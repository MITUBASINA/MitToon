// MitToon Shader - shading model: toon <-> PBR blend (pipeline independent)
#ifndef MITTOON_LIGHTING_INCLUDED
#define MITTOON_LIGHTING_INCLUDED

#include "MitToonBRDF.hlsl"
#include "MitToonSurface.hlsl"
#include "MitToonScreenSpace.hlsl"
#include "MitToonGI.hlsl"

struct LumiCtx
{
    float3 V;
    float  NoV;
    float3 toonDir;      // light direction used for toon shading (main light + SH)
    float3 litLight;     // limited light color for lit side
    float3 shadeLight;   // limited light color for shadow side
    float3 specLight;    // light color used for direct specular
    float  ssao;
    float3 aoColor;
    float  rampLit;      // main toon ramp (1 = lit)
    float  depthValidity;
};

static float2 lumiPixel = 0;     // set by the pass (dither patterns)
static float  lumiCurvature = 0; // debug view

// hard clamp or soft knee (no flat "clipped" look under strong lights)
float LumiCapLum(float l)
{
    float m = max(_LightMaxLimit, 1e-4);
    float hard = min(l, m);
    float soft = m * (1.0 - exp(-l / m));
    return lerp(hard, soft, _LightSoftLimit);
}
float3 LumiLimitLight(float3 c)
{
    float l = LumiLuminance(c);
    c = lerp(c, l.xxx, _MonochromeLighting);
    float lc = max(LumiCapLum(l), _LightMinLimit);
    lc *= 1.0 + _LightBoost * saturate(1.0 - lc * 2.0);   // lift dark worlds only
    lc = min(lc, max(_LightMaxLimit, _LightMinLimit));
    if (l <= 1e-4) return lc.xxx;
    // limiting keeps the colour, lifting adds neutral light (a dark blue world must not turn the avatar blue)
    float k = min(lc / l, 1.0);
    return c * k + (lc - l * k).xxx;
}
float3 LumiLimitMax(float3 c)
{
    float l = LumiLuminance(c);
    c = lerp(c, l.xxx, _MonochromeLighting);
    float lc = LumiCapLum(l);
    return l > 1e-4 ? c * (lc / l) : c;
}

// normal used for diffuse terms (spherical normal smooths faces)
float3 LumiDiffuseNormal(LumiSurface s, LumiInputData d)
{
#if defined(_LUMI_SPHERENORMAL)
    float3 center = LumiObjectToWorld(_SphereCenter.xyz);
    float3 up = normalize(LumiObjectToWorldDir(float3(0, 1, 0)));
    float3 sn = d.posWS - center;
    sn -= up * dot(sn, up) * _SphereNormalVertical;
    sn = dot(sn, sn) > 1e-10 ? normalize(sn) : s.N;
    return normalize(lerp(s.N, sn, _SphereNormalStrength));
#else
    return s.N;
#endif
}

// eye shadow guard: 1 where the eye must stay free of shadows
float LumiEyeGuard(float2 uv)
{
    return LUMI_SAMPLE(_EyeGuardMask, uv).r * step(0.5, _UseEyeGuard);
}

// ---- Toon ramp ------------------------------------------------------------
// a shadow colour is never brighter than the lit colour (a flat tint on a dark texture would glow otherwise).
// Scaled by luminance so a hue shifted shadow keeps its hue.
float3 LumiShadeNotBrighter(float3 c, float3 base)
{
    return c * min(1.0, LumiLuminance(base) / max(LumiLuminance(c), 1e-4));
}

// Soft cast shadows: the received shadow is not pushed through the (sharp) toon border, which turned the sub texel
// movement of a realtime shadow map into a hard edge jumping every frame. It is layered on top of the toon result as
// its own gradient instead. g = lit amount of the cast shadow, k = blend weight against the old crisp result.
float LumiCastG(float shadow)
{
    float sEff = lerp(1, shadow, _ReceiveShadowStrength);
    float w = 0.02 + 0.48 * _CastShadowSoftness;
    return smoothstep(0.5 - w, 0.5 + w, sEff);
}
float LumiCastK() { return saturate(_CastShadowSoftness * 4.0); }

// x = half lambert (0..1) already multiplied with received shadows, x0 = the same without them.
// returns shaded albedo, lit = 1 on lit side
float3 LumiToonShade(LumiSurface s, float x, float x0, float castG, out float lit)
{
    float3 base = s.diffuseColor;
    float3 col;
    float str = _ShadowStrength * s.shadowStrengthMask;
    if (_ShadowRampMode > 0.5)
    {
        float3 ramp = _ShadowRampTex.Sample(sampler_linear_clamp, float2(saturate(x), s.rampRow)).rgb;
        col = base * ramp;
        lit = saturate(LumiLuminance(ramp));
    }
    else
    {
        float3 c1 = LumiShadeNotBrighter(s.shadowFlat1 + base * s.shadowMul1, base);
        float3 c2 = LumiShadeNotBrighter(s.shadowFlat2 + base * s.shadowMul2, base);
        float dith = (LumiBayer4(lumiPixel) - 0.5) * _ShadowDither * max(_ShadowBlur, 0.05) * 2.0;
        x += dith;
        // the border is never thinner than a pixel (no stair steps / VR shimmer on hard cel shadows)
        float aa = fwidth(x) * _QToonAA;
        float r1 = LumiSmoothBorder(x, _ShadowBorder, max(_ShadowBlur, aa));
        float r2 = LumiSmoothBorder(x, _Shadow2ndBorder, max(_Shadow2ndBlur, aa));
        x0 += dith;
        float aa0 = fwidth(x0) * _QToonAA;   // outside the branch: no derivatives in flow control
        float k = LumiCastK();
        [branch] if (k > 0.001)
        {
            r1 = lerp(r1, LumiSmoothBorder(x0, _ShadowBorder, max(_ShadowBlur, aa0)) * castG, k);
            r2 = lerp(r2, LumiSmoothBorder(x0, _Shadow2ndBorder, max(_Shadow2ndBlur, aa0)) * castG, k);
            x = lerp(x, x0 * castG, k);   // border colour line follows the soft result too
        }
        if (_ShadowPosterize > 0.5)
        {
            r1 = floor(r1 * _ShadowPosterize + 0.5) / _ShadowPosterize;
            r2 = floor(r2 * _ShadowPosterize + 0.5) / _ShadowPosterize;
        }
        float3 sh = lerp(c1, c2, (1.0 - r2) * _Shadow2ndColor.a);
        col = lerp(sh, base, r1);
        if (_ShadowBorderRange > 0.001)
        {
            float bw = saturate(1.0 - abs(x - _ShadowBorder) / _ShadowBorderRange);
            col = lerp(col, base * _ShadowBorderColor.rgb, bw * bw * _ShadowBorderColor.a);
        }
        lit = r1;
    }
    lit = lerp(1, lit, str);
    return lerp(base, col, str);
}

// light map modes other than the toon border: gradient / lambert / no shading (keepToon = 1 keeps the toon result, e.g. face SDF)
void LumiLightMapOverride(LumiSurface s, float NoL, float shadow, float keepToon, inout float3 shaded, inout float lit)
{
    if (_LightMapMode < 0.5 || (_LightMapMode > 2.5 && _LightMapMode < 3.5)) return;
    float g = 1;
    if (_LightMapMode < 2.5) g = (_LightMapMode < 1.5 ? NoL * 0.5 + 0.5 : saturate(NoL)) * lerp(1, shadow, _ReceiveShadowStrength);
    float str = _ShadowStrength * s.shadowStrengthMask;
    float3 c1 = LumiShadeNotBrighter(s.shadowFlat1 + s.diffuseColor * s.shadowMul1, s.diffuseColor);
    float l2 = lerp(1, g, str);
    float3 sh2 = lerp(s.diffuseColor, lerp(c1, s.diffuseColor, g), str);
    shaded = lerp(sh2, shaded, keepToon);
    lit = lerp(l2, lit, keepToon);
}

float3 LumiRotateAxis(float3 v, float3 k, float a)
{
    float sn, cs; sincos(a, sn, cs);
    return v * cs + cross(k, v) * sn + k * dot(k, v) * (1.0 - cs);
}

// toon coordinate without received shadows
float LumiToonX0(LumiSurface s, float NoL)
{
    float x = lerp(NoL * 0.5 + 0.5, 1.0, _CastShadowOnly) + s.shadowOffset;
    return x * lerp(1, s.occlusion, _ShadowAOShift);
}
float LumiToonX(LumiSurface s, float NoL, float shadow)
{
    return LumiToonX0(s, NoL) * lerp(1, shadow, _ReceiveShadowStrength);
}

// ---- Direct specular (GGX / hair / sheen / clear coat) ---------------------
#if defined(_LUMI_RIM)
// light direction, shadow, back face and "lit side only" weighting shared by both rim lights
float LumiRimLightMask(float r, float3 Nr, float3 toonDir, float lightDir, float shadowMask, float backMask, float litSide, float litBlur, float lit, float facing)
{
    float NoL = dot(Nr, toonDir);
    r *= lerp(1, saturate(NoL * 0.5 + 0.5) * 1.5, lightDir);
    r *= lerp(1, smoothstep(-litBlur * 0.5, litBlur * 0.5, NoL), litSide);
    r *= lerp(1, lit, shadowMask);
    if (facing < 0) r *= 1.0 - backMask;
    return r;
}
// 0 add, 1 screen, 2 multiply, 3 replace
float3 LumiRimBlend(float3 col, float3 rc, float a, float mode)
{
    if (mode < 0.5) return col + rc * a;
    if (mode < 1.5) return col + rc * (1.0 - saturate(col)) * a;
    if (mode < 2.5) return lerp(col, col * rc, a);
    return lerp(col, rc, a);
}
#endif

#if defined(_LUMI_ANISO)
// highlight direction on the surface: tangent / bitangent, or radial / circular around a UV point, then rotated
float3 LumiAnisoDirection(float3 T, float3 B, float2 uv)
{
    float2 dir = _AnisoTangent < 0.5 ? float2(1, 0) : float2(0, 1);
    if (_AnisoTangent > 1.5)
    {
        float2 r = uv - _AnisoCenter.xy;
        r = dot(r, r) > 1e-10 ? normalize(r) : float2(1, 0);
        dir = _AnisoTangent < 2.5 ? r : float2(-r.y, r.x);
    }
    float sn, cs; sincos(radians(_AnisoAngle), sn, cs);
    dir = float2(dir.x * cs - dir.y * sn, dir.x * sn + dir.y * cs);
    return normalize(T * dir.x + B * dir.y);
}
#endif

#if defined(_LUMI_CLEARCOAT)
// coat normal: the base normal (or the geometry normal), then the coat's own normal map on top (orange peel, flakes)
float3 LumiCoatNormal(LumiSurface s, float2 uv)
{
    float3 Nc = _ClearCoatUseNormal > 0.5 ? s.N : s.Ng;
    [branch] if (_ClearCoatNormalScale > 0.001)
    {
        float3 n = LumiUnpackNormal(_ClearCoatNormalMap.Sample(sampler_trilinear_repeat, uv * _ClearCoatNormalMap_ST.xy + _ClearCoatNormalMap_ST.zw), _ClearCoatNormalScale);
        Nc = normalize(s.T * n.x + s.B * n.y + Nc * n.z);
    }
    return Nc;
}
float LumiCoatRoughness(float2 uv)
{
    return clamp(1.0 - _ClearCoatSmoothness * LUMI_SAMPLE(_ClearCoatSmoothnessMap, uv).r, 0.03, 1);
}
#endif

float3 LumiDirectSpecular(LumiSurface s, LumiCtx c, float3 L, float3 lightColor, float2 uv, out float coatAtten)
{
    coatAtten = 1;
    float3 N = s.N;
    float3 H = normalize(L + c.V);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float VoH = saturate(dot(c.V, H));
    float a = sqrt(s.a2);

    float  D = LumiD_GGX(NoH, s.a2);
    float  Vis = LumiV_SmithJointApprox(c.NoV, NoL, a);
    float3 F = LumiF_Schlick(s.f0, VoH);
    // minimal direct specular + multi-scatter compensation
    float3 spec = LumiDirectSpecularMin(s.f0, s.a2, NoH, VoH) * NoL * LumiEnergyCompensation(s.f0, s.perceptualRough, c.NoV);

    // toon highlight: normalised lobe shape thresholded
    float shape = saturate(D * LUMI_PI * s.a2);
    float3 toonSpec = LumiSmoothBorder(shape, _ToonSpecBorder, max(_ToonSpecBlur, fwidth(shape) * _QToonAA)) * F * step(0.0001, NoL);
    spec = lerp(spec, toonSpec, _SpecularToony);

#if defined(_LUMI_ANISO)
    {
        float mask = LUMI_SAMPLE(_AnisoMask, uv).r;
        float3 Th = LumiAnisoDirection(s.T, s.B, uv);
        float3 hairSpec;
        if (_AnisoMode < 0.5)
        {
            float shift = (_AnisoShiftMap.Sample(sampler_trilinear_repeat, uv * _AnisoShiftMap_ST.xy + _AnisoShiftMap_ST.zw).r - 0.5) * _AnisoShiftNoise;
            float3 T1 = normalize(Th + N * (_Aniso1Shift + shift));
            float3 T2 = normalize(Th + N * (_Aniso2Shift + shift));
            float wrapL = saturate(dot(N, L) * 0.5 + 0.5);
            float l1 = LumiStrandSpec(T1, H, _Aniso1Exponent), l2 = LumiStrandSpec(T2, H, _Aniso2Exponent);
            float tb = _AnisoToonBlur;
            l1 = lerp(l1, smoothstep(0.5 - tb, 0.5 + tb, l1), _AnisoToony);
            l2 = lerp(l2, smoothstep(0.5 - tb, 0.5 + tb, l2), _AnisoToony);
            hairSpec = (_Aniso1Color.rgb * l1 + _Aniso2Color.rgb * l2 * lerp(1.0.xxx, s.albedo, _Aniso2Albedo)) * wrapL;
        }
        else
        {
            float3 Bh = normalize(cross(N, Th));
            float at = max(a * (1.0 + _Anisotropy), 0.002);
            float ab = max(a * (1.0 - _Anisotropy), 0.002);
            float Da = LumiD_GGXAniso(dot(Th, H), dot(Bh, H), NoH, at, ab);
            hairSpec = Da * Vis * F * (LUMI_PI * NoL) * _Aniso1Color.rgb;
            // toon: the stretched lobe shape thresholded, like the toon highlight
            float shapeA = saturate(Da * LUMI_PI * at * ab);
            float3 toonA = LumiSmoothBorder(shapeA, 0.5, max(_AnisoToonBlur, fwidth(shapeA))) * F * step(0.0001, NoL) * _Aniso1Color.rgb;
            hairSpec = lerp(hairSpec, toonA, _AnisoToony);
        }
        hairSpec *= _AnisoStrength;
        spec = _AnisoBlend < 0.5 ? lerp(spec, hairSpec, mask) : spec + hairSpec * mask;
    }
#endif

    spec *= _SpecularStrength * _SpecularColor.rgb;

#if defined(_LUMI_SHEEN)
    {
        float3 sheen = _SheenColor.rgb * LUMI_SAMPLE(_SheenMap, uv).rgb * LUMI_SAMPLE(_SheenMask, uv).r;
        spec += sheen * LumiD_Sheen(NoH, max(_SheenRoughness, 0.05)) * LumiV_Sheen(c.NoV, NoL) * (LUMI_PI * NoL);
        // velvet edge: fuzz that glows toward the silhouette on the lit side
        spec += sheen * _SheenFuzz * pow(saturate(1.0 - c.NoV), _SheenFuzzPower) * saturate(dot(s.N, L) * 0.5 + 0.5);
    }
#endif

#if defined(_LUMI_CLEARCOAT)
    {
        float coat = _ClearCoat * LUMI_SAMPLE(_ClearCoatMask, uv).r;
        float3 Nc = LumiCoatNormal(s, uv);
        float NoLc = saturate(dot(Nc, L));
        float NoHc = saturate(dot(Nc, H));
        float NoVc = saturate(dot(Nc, c.V)) + 1e-4;
        float pr = LumiCoatRoughness(uv);
        float ac = pr * pr;
        float Fc = (_ClearCoatF0 + (1.0 - _ClearCoatF0) * LumiPow5(1.0 - VoH)) * coat;
        float Dc = LumiD_GGX(NoHc, ac * ac);
        float coatSpec = Dc * LumiV_SmithJointApprox(NoVc, NoLc, ac) * Fc * (LUMI_PI * NoLc);
        // toon: the coat lobe thresholded into a hard highlight
        float shapeC = saturate(Dc * LUMI_PI * ac * ac);
        float toonC = LumiSmoothBorder(shapeC, 0.5, max(_ClearCoatToonBlur, fwidth(shapeC))) * Fc * step(0.0001, NoLc);
        coatSpec = lerp(coatSpec, toonC, _ClearCoatToony);
        coatAtten = 1.0 - Fc;
        spec = spec * coatAtten + coatSpec * _ClearCoatSpecColor.rgb;
    }
#endif
    return spec * lightColor;
}

// ---- Transmission / backlight -------------------------------------------------
float3 LumiTransmission(LumiSurface s, LumiCtx c, float3 L, float3 lightColor, float2 uv)
{
    float3 o = 0;
#if defined(_LUMI_SSS)
    {
        float3 Lt = L + s.N * _TransmissionDistortion;
        float t = pow(saturate(dot(c.V, -Lt)), max(_TransmissionPower, 0.1)) * _TransmissionStrength;
        o += t * s.thickness * s.sssMask * _SSSColor.rgb * s.albedo * lightColor;
    }
#endif
#if defined(_LUMI_BACKLIGHT)
    {
        float3 Nb = normalize(lerp(s.Ng, s.N, _BacklightNormalStrength));
        float rim = 1.0 - saturate(dot(Nb, c.V));
        float viewF = lerp(1, saturate(dot(-L, c.V)), _BacklightViewStrength);
        float dirF = pow(saturate(-dot(Nb, L) * 0.5 + 0.5), max(_BacklightDirectivity, 0.01));
        float b = LumiSmoothBorder(rim, _BacklightBorder, _BacklightBlur) * dirF * viewF;
        float4 m = LUMI_SAMPLE(_BacklightMask, uv);
        o += _BacklightColor.rgb * m.rgb * lerp(1, s.albedo, _BacklightMainStrength) * lightColor * (b * _BacklightColor.a);
    }
#endif
    return o;
}

#if defined(_LUMI_COMPAT)
// ---- lilToon mode: lilToon (MIT) style light and shadow maths, so a material switched from lilToon keeps roughly its look
float LumiCompatToon(float v, float border, float blur, float range)
{
    float bMin = saturate(border - blur * 0.5 - range), bMax = saturate(border + blur * 0.5);
    return (v - bMin) / saturate(bMax - bMin + fwidth(v) * _QToonAA);
}

// light direction (main light weighted by its brightness + SH), lit colour and the environment colour
void LumiCompatLight(LumiLight ml, float3 posWS, out float3 L, out float3 lc, out float3 ind)
{
    float4 Ar, Ag, Ab, Br, Bg, Bb; float3 Cc; float lv;
    LumiCompatSH(Ar, Ag, Ab, Br, Bg, Bb, Cc, lv);
    float3 mainDir = ml.direction * dot(ml.color, float3(0.0396819152, 0.458021790, 0.00609653955));
    float3 sh9 = (Ar.xyz + Ag.xyz + Ab.xyz) * 0.333333;
    L = normalize(float3(sh9.x, abs(sh9.y), sh9.z) + mainDir + float3(0, 0.002, 0));
    // the shared light direction override (W = blend) works here too
    L = normalize(lerp(L, normalize(_LightDirOverride.xyz + float3(0, 1e-4, 0)), _LightDirOverride.w));
    float3 dSH = sh9 + mainDir;
    dSH = dot(dSH, dSH) < 0.000001 ? 0 : normalize(dSH);
    float3 N = lv > 0.5 ? normalize(LumiGetCameraPositionWS() - posWS) : dSH;
    float4 vB = N.xyzz * N.yzzx;
    float3 res = float3(Ar.w, Ag.w, Ab.w) + float3(dot(Br, vB), dot(Bg, vB), dot(Bb, vB)) + Cc * (N.x * N.x - N.y * N.y);
    float3 shMax = res + float3(dot(Ar.xyz, N), dot(Ag.xyz, N), dot(Ab.xyz, N));
    float3 sum = Ar.xyz + Ag.xyz + Ab.xyz;
    float3 Nm = sum * rsqrt(max(dot(sum, sum), 1e-20));
    ind = dot(sum, sum) > 1e-20 ? res + float3(dot(Ar.xyz, Nm), dot(Ag.xyz, Nm), dot(Ab.xyz, Nm)) : 0;
    lc = clamp(ml.color + shMax + lumiCompatVL, _LightMinLimit, _LightMaxLimit);
    lc = lerp(lc, dot(lc, 1.0 / 3.0).xxx, _MonochromeLighting);
    lc = lerp(lc, 1.0, _AsUnlit);
}

// up to 3 shadow colours with their own borders, AO map, blur mask, received shadows and the environment light
float3 LumiCompatShading(LumiSurface s, LumiInputData d, float3 L, float3 origL, float3 lightCol, float3 indCol, float atten, bool isBase, out float shadowmix)
{
    float2 uv = s.uvMain;
    float3 albedo = s.albedo;
    float3 directCol = albedo * lightCol;
    float3 N1 = lerp(s.Ng, s.N, _ShadowNormalStrength), N2 = lerp(s.Ng, s.N, _Shadow2ndNormalStrength), N3 = lerp(s.Ng, s.N, _Shadow3rdNormalStrength);
    float4 lns = 1;
    lns.x = saturate(dot(L, N1) * 0.5 + 0.5);
    lns.y = saturate(dot(L, N2) * 0.5 + 0.5);
    lns.z = saturate(dot(L, N3) * 0.5 + 0.5);
    float cs = saturate(atten + distance(L, origL));
    lns.xyz *= lerp(1.0.xxx, cs.xxx, float3(_ShadowReceive, _Shadow2ndReceive, _Shadow3rdReceive));
    float4 blurM = LUMI_SAMPLE(_ShadowBlurMask, uv);
    float4 bm = LUMI_SAMPLE(_ShadowBorderMask, uv);
    bm.r = saturate(bm.r * _CompatAOShift.x + _CompatAOShift.y);
    bm.g = saturate(bm.g * _CompatAOShift.z + _CompatAOShift.w);
    bm.b = saturate(bm.b * _ShadowAOShift2.x + _ShadowAOShift2.y);
    bool post = _ShadowPostAO > 0.5;
    lns.xyz = post ? lns.xyz : lns.xyz * bm.rgb;
    lns.w = lns.x;
    lns.x = LumiCompatToon(lns.x, _ShadowBorder, _ShadowBlur * blurM.r, 0);
    lns.y = LumiCompatToon(lns.y, _Shadow2ndBorder, _Shadow2ndBlur * blurM.g, 0);
    lns.w = LumiCompatToon(lns.w, _ShadowBorder, _ShadowBlur * blurM.r, _ShadowBorderRange);
    lns.z = LumiCompatToon(lns.z, _Shadow3rdBorder, _Shadow3rdBlur * blurM.b, 0);
    lns = saturate(post ? lns * bm.rgbr : lns);
    lns *= d.facing < 0 ? 1.0 - _BackfaceForceShadow : 1.0;
    float mix = lns.x;
    lns.x = lerp(1.0, lns.x, _ShadowStrength * LUMI_SAMPLE(_ShadowMaskTex, uv).r);
    float4 t1 = LUMI_SAMPLE(_ShadowColorTex, uv), t2 = LUMI_SAMPLE(_Shadow2ndColorTex, uv), t3 = LUMI_SAMPLE(_Shadow3rdColorTex, uv);
    float3 ind = lerp(albedo, t1.rgb, t1.a) * _ShadowColor.rgb;
    ind = lerp(ind, lerp(albedo, t2.rgb, t2.a) * _Shadow2ndColor.rgb, _Shadow2ndColor.a - lns.y * _Shadow2ndColor.a);
    ind = lerp(ind, lerp(albedo, t3.rgb, t3.a) * _Shadow3rdColor.rgb, _Shadow3rdColor.a - lns.z * _Shadow3rdColor.a);
    ind = lerp(ind, ind * albedo, _ShadowMainStrength);
    ind *= lightCol;
    if (isBase) ind = lerp(ind, albedo, saturate(indCol * _ShadowEnvStrength));
    ind = min(ind, directCol);
    ind = lerp(ind, directCol, lns.w * _ShadowBorderColor.rgb);
    bool on = _ShadowStrength > 0.0;
    shadowmix = on ? mix : 1.0;
    return on ? lerp(ind, directCol, lns.x) : directCol;
}

// 0 normal, 1 add, 2 screen, 3 multiply
float3 LumiCompatBlend(float3 dst, float3 src, float3 a, float mode)
{
    float3 ad = dst + src, mu = dst * src;
    float3 o = mode < 0.5 ? src : (mode < 1.5 ? ad : (mode < 2.5 ? max(ad - mu, dst) : mu));
    return lerp(dst, o, a);
}

float2 LumiCompatMatCapUV(float3 N, float3 V, float4 st, float zRotCancel, float perspective)
{
    float3 nV = (perspective > 0.5 && unity_OrthoParams.w < 0.5) ? V : UNITY_MATRIX_V[2].xyz;
    float3 bV = zRotCancel > 0.5 ? float3(0, 1, 0) : UNITY_MATRIX_V[1].xyz;
    bV = normalize(bV - nV * dot(nV, bV));
    float3 tV = cross(nV, bV);
    float2 m = float2(dot(tV, N), dot(bV, N));
    return (m * st.xy + st.zw) * 0.5 + 0.5;
}

// rim light of one slot; mode is MitToon's (0 add, 1 screen, 2 multiply, 3 replace), the shadow side rim (indir) only on the first slot
float3 LumiCompatRim(float3 col, LumiSurface s, LumiInputData d, float3 V, float3 L, float3 lc, float mix, float ns, float fp, float border, float blur,
                  float bfMask, float shMask, float ms, float el, float4 color, float4 tex, float mode, float dirStr, float indir)
{
    float3 N = lerp(s.Ng, s.N, ns);
    float rim = pow(saturate(1.0 - abs(dot(N, V))), fp);
    rim *= d.facing < 0 ? 1.0 - bfMask : 1.0;
    float4 rc = color * tex;
    rc.rgb = lerp(rc.rgb, rc.rgb * s.albedo, ms);
    float4 ic = _RimIndirColor * tex;
    float lnRaw = dot(L, N) * 0.5 + 0.5;
    float lnDir = saturate((lnRaw + _RimDirRange) / (1.0 + _RimDirRange));
    float lnInd = saturate((1.0 - lnRaw + _RimIndirRange) / (1.0 + _RimIndirRange));
    float rDir = saturate(LumiCompatToon(lerp(rim, rim * lnDir, dirStr), border, blur, 0));
    float rInd = indir * saturate(LumiCompatToon(rim * lnInd * dirStr, _RimIndirBorder, _RimIndirBlur, 0));
    rDir = lerp(rDir, rDir * mix, shMask);
    rInd = lerp(rInd, rInd * mix, shMask);
    float m = mode > 2.5 ? 0 : mode + 1;
    // an extra light adds only its own part: multiply keeps the colour, the other modes take the light colour
    float3 lm = lumiCompatFA > 0.5 ? (m < 2.5 ? lc * el : 1.0.xxx) : lerp(1.0.xxx, lc, el);
    col = LumiCompatBlend(col, rc.rgb * lm, rDir * rc.a, m);
    return LumiCompatBlend(col, ic.rgb * lm, rInd * ic.a, m);
}

float3 LumiCompatMatCap(float3 col, LumiSurface s, LumiInputData d, float3 N, float3 V, Texture2D tex, float4 st, Texture2D mask, float4 color, float mode, float lod,
                     float el, float shMask, float ms, float bfMask, float3 lc, float mix)
{
    float2 muv = LumiCompatMatCapUV(normalize(N), V, st, _MatCapZRotCancel, _MatCapPerspective);
    float4 mc = color * tex.SampleLevel(sampler_trilinear_repeat, muv, lod);
    mc.rgb = lumiCompatFA > 0.5 ? (mode < 2.5 ? mc.rgb * lc * el : mc.rgb) : lerp(mc.rgb, mc.rgb * lc, el);
    mc.a = lerp(mc.a, mc.a * mix, shMask);
    mc.a = (d.facing < 0 && bfMask > 0.5) ? 0 : mc.a;
    float3 mk = LUMI_SAMPLE(mask, s.uvMain).rgb;
    mc.rgb = lerp(mc.rgb, mc.rgb * s.albedo, ms);
    return LumiCompatBlend(col, mc.rgb, mc.a * mk, mode);
}

// rim shade, backlight, matcaps and rim lights in the common toon order and maths
float3 LumiCompatEffects(float3 col, LumiSurface s, LumiInputData d, float3 V, float3 L, float3 origL, float3 lc, float mix, float atten)
{
    float2 uv = s.uvMain;
    if (_UseRimShade > 0.5)
    {
        float3 N = lerp(s.Ng, s.N, _RimShadeNormalStrength);
        float r = pow(saturate(1.0 - abs(dot(N, V))), _RimShadeFresnelPower);
        r = saturate(LumiCompatToon(r, _RimShadeBorder, _RimShadeBlur, 0)) * _RimShadeColor.a * LUMI_SAMPLE(_RimShadeMask, uv).r;
        col = lerp(col, col * _RimShadeColor.rgb, r);
    }
    if (_UseBacklight > 0.5 && lumiCompatFA < 0.5)
    {
        float3 N = lerp(s.Ng, s.N, _BacklightNormalStrength);
        float4 bc = _BacklightColor * LUMI_SAMPLE(_BacklightMask, uv);
        float f = pow(saturate(-dot(V, L) * 0.5 + 0.5), _BacklightDirectivity);
        float ln = dot(normalize(-V * _BacklightViewStrength + L), N) * 0.5 + 0.5;
        if (_BacklightReceiveShadow > 0.5) ln *= saturate(atten + distance(L, origL));
        ln = saturate(LumiCompatToon(ln, _BacklightBorder, _BacklightBlur, 0));
        float b = saturate(f * ln);
        b = (d.facing < 0 && _BacklightBackfaceMask > 0.5) ? 0 : b;
        bc.rgb = lerp(bc.rgb, bc.rgb * s.albedo, _BacklightMainStrength);
        col += b * bc.a * bc.rgb * lc;
    }
    if (_UseMatCap > 0.5)
    {
        float3 N = lerp(s.Ng, s.N, _MatCapNormalStrength);
        if (_UseMatCapBump > 0.5)
        {
            float3 nb = LumiUnpackNormal(LUMI_SAMPLE(_MatCapBumpMap, uv), _MatCapBumpScale);
            N = normalize(s.T * nb.x + s.B * nb.y + s.Ng * nb.z);
        }
        col = LumiCompatMatCap(col, s, d, N, V, _MatCapTex, _MatCapTex_ST, _MatCapMask, _MatCapColor, _MatCapBlend, _MatCapLod,
                            _MatCapEnableLighting, _MatCapShadowMask, _MatCapMainStrength, _MatCapBackfaceMask, lc, mix);
    }
    if (_UseMatCap2 > 0.5)
        col = LumiCompatMatCap(col, s, d, lerp(s.Ng, s.N, _MatCap2NormalStrength), V, _MatCap2Tex, _MatCap2Tex_ST, _MatCap2Mask, _MatCap2Color, _MatCap2Blend, _MatCap2Lod,
                            _MatCap2EnableLighting, _MatCap2ShadowMask, 0, 0, lc, mix);
    if (_UseRim > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _RimNormalStrength, _RimFresnelPower, _RimBorder, _RimBlur, _RimBackfaceMask, _RimShadowMask,
                         _RimMainStrength, _RimEnableLighting, _RimColor, LUMI_SAMPLE(_RimTex, uv), _RimBlendMode, _RimLightDir, 1);
    if (_UseRim2 > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _Rim2NormalStrength, _Rim2FresnelPower, _Rim2Border, _Rim2Blur, _Rim2BackfaceMask, _Rim2ShadowMask,
                         _Rim2MainStrength, _Rim2EnableLighting, _Rim2Color, LUMI_SAMPLE(_Rim2Tex, uv), _Rim2BlendMode, _Rim2LightDir, 0);
    if (_UseRim3 > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _Rim3NormalStrength, _Rim3FresnelPower, _Rim3Border, _Rim3Blur, _Rim3BackfaceMask, _Rim3ShadowMask,
                         _Rim3MainStrength, _Rim3EnableLighting, _Rim3Color, LUMI_SAMPLE(_Rim3Tex, uv), _Rim3BlendMode, _Rim3LightDir, 0);
    return col;
}
#endif

// ---- Shading of one extra light (ForwardAdd / vertex lights) -------------------
float3 LumiShadeAdditional(LumiSurface s, LumiInputData d, LumiCtx c, LumiLight light)
{
#if defined(_LUMI_COMPAT)
    {
        float at = light.distanceAttenuation * light.shadowAttenuation;
        float3 lcA = min(light.color * at, _LightMaxLimit);
        lcA = lerp(lcA, dot(lcA, 1.0 / 3.0).xxx, _MonochromeLighting);
        lcA = lerp(lcA, 0, _AsUnlit);
        float mixA;
        float3 colA = LumiCompatShading(s, d, light.direction, light.direction, lcA, 0, at, false, mixA);
        lumiCompatFA = 1;
        colA = LumiCompatEffects(colA, s, d, c.V, light.direction, light.direction, lcA, mixA, at);
        lumiCompatFA = 0;
        return colA;
    }
#endif
    float3 L = light.direction;
    float atten = light.distanceAttenuation * light.shadowAttenuation;
    float3 lc = LumiLimitMax(LumiKeepChroma(light.color, _LightColorStrength) * light.distanceAttenuation) * _AddLightStrength;
    lc = lerp(lc, LumiLuminance(lc).xxx, _AddLightMonochrome);
    lc *= min(1.0, _AddLightMaxLimit / max(LumiLuminance(lc), 1e-4));     // one close point light cannot blow out the avatar
    float NoL = dot(LumiDiffuseNormal(s, d), L);
    NoL = lerp(NoL, NoL * 0.5 + 0.5, _AddLightPassthrough);
    float eyeG = LumiEyeGuard(s.uvMain);
    NoL = lerp(NoL, 1.0, eyeG * _EyeGuardShade);
    light.shadowAttenuation = lerp(light.shadowAttenuation, 1.0, eyeG * _EyeGuardShadow);
    // point / spot shadow cube maps are coarse: their blocks would be cut out sharply by the toon border
    light.shadowAttenuation = lerp(1.0, light.shadowAttenuation, _AddLightCastShadow);

    // toon: an additional light only adds light where it reaches. The far side gets nothing (no tinted shadow colour
    // multiplied by the light colour, which made hard coloured patches), and the border is soft.
    if (_LightMapMode > 2.5 && _LightMapMode < 3.5) NoL = 1;
    float x0 = LumiToonX0(s, NoL);
    float x = x0 * lerp(1, light.shadowAttenuation, _ReceiveShadowStrength);
    float bw = max(max(_ShadowBlur, _AddLightSoftness * 0.5), fwidth(x) * _QToonAA);
    float bw0 = max(max(_ShadowBlur, _AddLightSoftness * 0.5), fwidth(x0) * _QToonAA);
    float tl = lerp(smoothstep(_ShadowBorder - bw, _ShadowBorder + bw, x),
                    smoothstep(_ShadowBorder - bw0, _ShadowBorder + bw0, x0) * LumiCastG(light.shadowAttenuation), LumiCastK());
    float lit = lerp(1.0, tl, _ShadowStrength * s.shadowStrengthMask);
    float3 shaded = s.diffuseColor;
    LumiLightMapOverride(s, NoL, light.shadowAttenuation, 0, shaded, lit);
    float3 toon = s.diffuseColor * lc * lit;
    // pbr
    float3 diffTerm = saturate(NoL).xxx;
#if defined(_LUMI_SSS)
    float3 w = _SSSWrap * _SSSColor.rgb;
    diffTerm = lerp(diffTerm, saturate((NoL + w) / (1.0 + w)) / (1.0 + w), s.sssMask);
#endif
    float3 pbr = s.diffuseColor * diffTerm * lc * light.shadowAttenuation;
    float coatAtten;
    float3 spec = LumiDirectSpecular(s, c, L, lc * light.shadowAttenuation, s.uvMain, coatAtten);
    float3 col = lerp(pbr, toon, _ToonAmount) * coatAtten + spec;
    col += LumiTransmission(s, c, L, lc, s.uvMain);
    return lerp(col, 0, _AsUnlit);
}

// ---- MatCap -------------------------------------------------------------------
float2 LumiMatCapUV(float3 N, float3 V, float3 posWS, float perspective, float zRotCancel)
{
    float3 camUp = normalize(UNITY_MATRIX_V[1].xyz);
    float3 viewZ = normalize(lerp(-UNITY_MATRIX_V[2].xyz, V, perspective));
    float3 up = normalize(lerp(camUp, float3(0, 1, 0), zRotCancel));
    float3 x = normalize(cross(up, viewZ));
    float3 y = cross(viewZ, x);
    return float2(dot(N, x), dot(N, y)) * 0.495 + 0.5;
}
float3 LumiApplyMatCap(float3 col, Texture2D tex, Texture2D mask, float4 color, float blend, float lod, float lighting, float shadowMask,
                       float mainStr, float2 uvMain, float2 mcuv, float3 albedo, float3 light, float lit)
{
    float4 m = tex.SampleLevel(sampler_trilinear_clamp, mcuv, lod) * color;
    m.rgb *= lerp(1, albedo, mainStr);
    m.rgb *= lerp(1, light, lighting);
    float a = m.a * LUMI_SAMPLE(mask, uvMain).r * lerp(1, lit, shadowMask);
    return LumiBlend(col, m.rgb, a, blend);
}

// ---- Glitter ------------------------------------------------------------------
float3 LumiGlitter(LumiSurface s, LumiInputData d, LumiCtx c, float3 H)
{
    float2 guv = (_GlitterUV < 0.5 ? d.uv0 : d.uv1) * _GlitterDensity;
    float2 cell = floor(guv);
    float3 acc = 0;
    [unroll] for (int y = -1; y <= 1; y++)
    [unroll] for (int x = -1; x <= 1; x++)
    {
        float2 cc = cell + float2(x, y);
        float3 rnd = LumiHash32(cc);
        float2 center = cc + 0.5 + (rnd.xy - 0.5) * 0.8;
        float dist = length(guv - center);
        float shape = saturate(1.0 - dist / max(_GlitterSize, 0.01));
        float3 rn = normalize(rnd * 2.0 - 1.0);
        float facing = saturate(dot(normalize(s.N + rn * 0.6), H));
        float twinkle = sin(_Time.y * _GlitterSpeed + rnd.z * 6.2831853) * 0.5 + 0.5;
        float g = shape * shape * pow(facing, _GlitterSensitivity) * lerp(1, twinkle, step(0.001, _GlitterSpeed));
        float3 rc = lerp(1, LumiHSV2RGB(float3(rnd.z, 0.8, 1)), _GlitterRandomColor);
        acc += g * rc;
    }
    float3 col = acc * _GlitterColor.rgb * _GlitterColor.a * LUMI_SAMPLE(_GlitterMask, s.uvMain).r;
    col *= lerp(1, c.litLight, _GlitterEnableLighting);
    col *= lerp(1, c.rampLit, _GlitterShadowMask);
    return col;
}

// ---- Main (ForwardBase) shading -----------------------------------------------
// 1 when the screen space effects may read the depth texture for this pixel
float LumiScreenSpaceValidity(LumiInputData d)
{
    float v = LumiDepthValidity(d.screenUV, d.eyeDepth);
    if (_QLodDistance > 0.01 && d.eyeDepth > _QLodDistance) v = 0;   // far away: skip the screen space work
#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
    v = 0;   // a blended surface is not in the depth texture (SSAO / contact / depth rim would read what is behind it)
#endif
    return v;
}

float4 LumiShadeBase(LumiSurface s, LumiInputData d, LumiLight mainLight, out LumiCtx c)
{
    c = (LumiCtx)0;
    c.V = d.viewDirWS;
    c.NoV = saturate(dot(s.N, c.V)) + 1e-4;
    float2 uv = s.uvMain;

    // light direction & colors (main light + ambient / scenery / point lights, then limited)
    LumiGI gi = LumiGatherGI(mainLight.color, d.posWS);
    float3 mainColor = LumiKeepChroma(mainLight.color, gi.lightChromaKeep);
    float mainLum = LumiLuminance(mainColor);
    // ambient direction kept above the horizon: floor bounce never lights the face from below
    float3 hint = gi.dirHint;
    hint.y = lerp(hint.y, abs(hint.y), _LightDirKeepUp);
    float3 dir = mainLight.direction * mainLum + hint + float3(0, 0.001, 0);
    if (_LightDirMode > 0.5 && _LightDirMode < 1.5 && mainLum > 1e-3) dir = mainLight.direction;
    float3 ovr = normalize(_LightDirOverride.xyz + float3(0, 1e-4, 0));
    if (_LightDirMode > 1.5 && _LightDirMode < 4.5)
    {
        // fixed light: world / camera relative (always lit from the front-ish) / object local
        dir = _LightDirMode < 2.5 ? ovr : (_LightDirMode < 3.5 ? LumiViewToWorldDir(ovr) : LumiObjectToWorldDir(ovr));
        c.toonDir = normalize(dir);
    }
    else if (_LightDirMode > 4.5 && _LightDirMode < 5.5)
    {
        // the real light when there is one, otherwise from the camera, slightly above
        float3 camDef = normalize(UNITY_MATRIX_V[2].xyz + UNITY_MATRIX_V[1].xyz);
        c.toonDir = mainLum > 1e-3 ? mainLight.direction : camDef;
    }
    else if (_LightDirMode > 5.5)
    {
        // light follows the viewer: from the camera position with an angle offset (mirrored in mirrors)
        float m = _VRChatMirrorMode > 0.5 ? -1.0 : 1.0;
        float3 toCam = normalize(LumiGetCameraPositionWS() - unity_ObjectToWorld._m03_m13_m23 + float3(0, 1e-4, 0));
        float3 upV = UNITY_MATRIX_V[1].xyz, rightV = UNITY_MATRIX_V[0].xyz;
        toCam = LumiRotateAxis(toCam, upV, radians(-_LightViewYaw * m));
        c.toonDir = normalize(LumiRotateAxis(toCam, rightV, radians(_LightViewPitch * m)));
    }
    else c.toonDir = normalize(lerp(normalize(dir), ovr, _LightDirOverride.w));
    float3 shAvg = LumiKeepChroma(gi.L0, gi.chromaKeep);
    float3 shLit = LumiGIIrradiance(gi, c.toonDir * _SHSoftness);
    float3 shShade = LumiGIIrradiance(gi, -c.toonDir * _SHSoftness);
    float3 Nd = LumiDiffuseNormal(s, d);
    float3 irrN = LumiGIIrradiance(gi, Nd);   // ambient along the normal, shared by every path below
    float3 litRaw = mainColor + gi.autoKey + shLit, shadeRaw = shShade;
    if (_LightColorMode > 0.5 && _LightColorMode < 1.5)
    {
        // standard: direct light + ambient along the normal; without a light the ambient alone shapes the avatar
        bool hasLight = mainLum > 1e-3;
        litRaw = hasLight ? mainColor + irrN : irrN * 1.2;
        shadeRaw = irrN;
    }
    else if (_LightColorMode > 1.5 && _LightColorMode < 2.5)
    {
        // always visible: the ambient never drops below a floor, the light never darker than the ambient
        float3 ind = saturate(max(0.05 * _UnlitIntensity, max(shAvg, LumiGIIrradiance(gi, float3(0, -1, 0))) * _UnlitIntensity));
        litRaw = max(ind, mainColor + ind * 0.5);
        shadeRaw = ind;
    }
    else if (_LightColorMode > 2.5 && _LightColorMode < 3.5)
    {
        // SH lit / shade: the bright and the dark side of the light probe along the light direction (classic toon)
        litRaw = mainColor + LumiGIIrradiance(gi, c.toonDir * 0.666666);
        shadeRaw = LumiGIIrradiance(gi, -c.toonDir * 0.666666);
    }
    else if (_LightColorMode > 3.5)
    {
        // flat: one colour everywhere, shadows only come from the shadow colours
        litRaw = mainColor + shAvg;
        shadeRaw = litRaw;
    }
    c.litLight = LumiLimitLight(litRaw);
    c.shadeLight = lerp(c.litLight, LumiLimitLight(shadeRaw), _ShadowEnvStrength);
#if defined(_LUMI_COMPAT)
    float3 compatInd;
    LumiCompatLight(mainLight, d.posWS, c.toonDir, c.litLight, compatInd);
    c.shadeLight = c.litLight;
#endif

    // occlusion terms
    c.depthValidity = LumiScreenSpaceValidity(d);
    float aoMask = 1;
#if defined(_LUMI_SSAO)
    aoMask = LUMI_SAMPLE(_SSAOMask, uv).r;
#endif
    // normal map detail: sample around the bumped normal so small creases of the normal map also occlude
    float3 aoN = normalize(lerp(s.Ng, s.N, _SSAONormalStrength));
    c.ssao = LumiSSAO(d.posWS, aoN, d.eyeDepth, d.pixelPos, c.depthValidity, aoMask);
    c.ssao = lerp(1.0, c.ssao, lerp(1.0, saturate(s.alpha), _SSAOAlphaInfluence));   // thin / see through parts occlude less
    // occlusion colour, optionally carrying the hue of the base colour (painted look)
    float3 hueA = min(s.albedo / max(dot(s.albedo, float3(0.2126, 0.7152, 0.0722)), 0.04), 3.0);
    float3 occCol = _SSAOColor.rgb * lerp(1.0.xxx, hueA, _SSAOAlbedoTint);
    c.aoColor = lerp(occCol, 1, c.ssao);
    float csMask = 1;
#if defined(_LUMI_CONTACTSHADOW)
    csMask = LUMI_SAMPLE(_ContactShadowMask, uv).r;
#endif
    float contact = LumiContactShadow(d.posWS, s.Ng, c.toonDir, d.eyeDepth, d.pixelPos, c.depthValidity, csMask);
    float castSh = mainLight.shadowAttenuation;
    if (_ShadowTerminatorFade > 0.001)
        castSh = lerp(1.0, castSh, smoothstep(0.0, _ShadowTerminatorFade, dot(s.Ng, mainLight.direction)));
    float shadow = castSh * contact * LumiDepthTexShadow(c.toonDir, d.screenUV, d.eyeDepth, c.depthValidity);
    // eye shadow guard: eyelid / bang shadows, light angle shading and AO do not reach the inside of the eye
    float eyeG = LumiEyeGuard(uv);
    shadow = lerp(shadow, 1.0, eyeG * _EyeGuardShadow);
    c.ssao = lerp(c.ssao, 1.0, eyeG * _EyeGuardAO);
    c.aoColor = lerp(c.aoColor, 1.0, eyeG * _EyeGuardAO);
    s.occlusion = lerp(s.occlusion, 1.0, eyeG * _EyeGuardAO);
    {
        // micro shadows: AO and normal map detail also block direct light (cavities stop glowing in the sun)
        float ao2 = s.occlusion * c.ssao;
        float ms = saturate(abs(dot(s.N, c.toonDir)) + 2.0 * ao2 * ao2 - 1.0);
        shadow *= lerp(1.0, saturate(ms), _QMicroShadow);
    }
    float vk = LumiVirtualKeyWeight(gi, mainLum);
    c.specLight = LumiLimitMax(mainColor + gi.autoKey + gi.domColor * vk + max(shLit - shAvg, 0) * (1.0 - vk)) * shadow;

    float NoL = dot(Nd, c.toonDir);
    NoL = lerp(NoL, 1.0, eyeG * _EyeGuardShade);
    if (_LightMapMode > 2.5 && _LightMapMode < 3.5) NoL = 1;   // cast shadows only

    // ---- Toon diffuse
    float toonX0 = LumiToonX0(s, NoL);
    float toonX = toonX0 * lerp(1, shadow, _ReceiveShadowStrength);
    float castG = LumiCastG(shadow);
    float faceMask = 0, faceLit = 1;
#if defined(_LUMI_FACESDF)
    {
        // SDF face shadow (game / VTuber style). Object axes follow the head when the face renderer's root bone is the head.
        float3 up = normalize(LumiObjectToWorldDir(_FaceUp.xyz));
        float3 fwd = normalize(LumiObjectToWorldDir(_FaceForward.xyz));
        fwd = normalize(fwd - up * dot(fwd, up));
        float3 right = cross(up, fwd);
        float3 Lh = c.toonDir - up * dot(c.toonDir, up);
        Lh = dot(Lh, Lh) > 1e-6 ? normalize(Lh) : fwd;
        float2 suv = d.uv0;
        if ((dot(right, Lh) > 0) != (_FaceSDFFlip > 0.5)) suv.x = 1.0 - suv.x;
        float sdf = _FaceSDFTex.Sample(sampler_linear_clamp, suv).r;
        float th = 1.0 - (dot(fwd, Lh) * 0.5 + 0.5);
        faceLit = LumiSmoothBorder(sdf, th, _FaceSDFBlur);
        faceMask = LUMI_SAMPLE(_FaceSDFMask, uv).r;
        float xShade = max(_Shadow2ndBorder + _Shadow2ndBlur, _ShadowBorder - _ShadowBlur) + 0.01;
        float xFace0 = lerp(xShade, 1.0, faceLit);
        toonX = lerp(toonX, xFace0 * lerp(1, shadow, _ReceiveShadowStrength), faceMask);
        toonX0 = lerp(toonX0, xFace0, faceMask);
    }
#endif
    float lit;
    float3 shaded = LumiToonShade(s, toonX, toonX0, castG, lit);
    LumiLightMapOverride(s, NoL, shadow, faceMask, shaded, lit);
    c.rampLit = lit;
    float3 toonDiff = shaded * lerp(c.shadeLight, c.litLight, lit);
    float hyb = _HybridAmount * (1.0 - faceMask * 0.7);
    if (hyb > 0.001)
    {
        // Toon + real material: the cel border stays where it is, but light behaves physically inside each tone.
        // lit side: soft falloff toward the border + a little ambient bounce colour
        float3 litL = c.litLight * lerp(1.0, 0.62 + 0.38 * saturate(NoL), _HybridLitGradient * hyb);
        litL += LumiLimitMax(irrN) * (_HybridEnvTint * hyb * 0.5);
        // shadow side: ambient per normal (real volume) with multi-bounce AO instead of one flat colour
        float3 shadeN = lerp(c.litLight, LumiLimitLight(LumiGIIrradiance(gi, Nd * _SHSoftness)), _ShadowEnvStrength);
        float3 shadeL = lerp(c.shadeLight, shadeN, _HybridShadeVolume * hyb);
        shadeL *= lerp(1.0.xxx, LumiMultiBounceAO(s.occlusion, s.diffuseColor), _HybridShadeVolume * hyb);
        toonDiff = shaded * lerp(shadeL, litL, lit);
    }
    // SSAO influence: ambient (shadow side) and direct (lit side) separately
    float3 aoAmb = lerp(1.0.xxx, c.aoColor, _SSAOAmbient), aoDir = lerp(1.0.xxx, c.aoColor, _SSAODirect);
    toonDiff *= lerp(aoAmb, aoDir, lit);

    // ---- PBR diffuse
    float3 L = c.toonDir;
    float3 H = normalize(L + c.V);
    float NoLs = saturate(NoL);
    float3 pbrDiff = 0;
    if (_ToonAmount < 0.999)   // full toon skips the whole PBR diffuse
    {
    float wrapNoL = saturate((NoL + _RichWrap) / (1.0 + _RichWrap)) / (1.0 + _RichWrap * 0.5);
    float3 diffTerm = lerp(NoLs, wrapNoL, _RichWrap > 0 ? 1 : 0).xxx * LumiDiffuseRetro(c.NoV, NoLs, saturate(dot(L, H)), s.perceptualRough);
    // detail contrast: exaggerate how the normal map turns toward / away from the light
    diffTerm *= clamp(1.0 + _RichMicroContrast * 2.0 * (dot(s.N, L) - dot(s.Ng, L)), 0.4, 1.6);
    diffTerm = lerp(diffTerm, (faceLit * 0.8 + 0.2).xxx, faceMask);
#if defined(_LUMI_SSS)
    {
        float3 w = _SSSWrap * _SSSColor.rgb;
        float curv = saturate(length(fwidth(s.Ng)) / max(length(fwidth(d.posWS)), 1e-5) * 0.02);
        w *= lerp(1, curv, _SSSCurvature);
        float3 wrapT = saturate((NoL + w) / (1.0 + w)) / (1.0 + w);
        diffTerm = lerp(diffTerm, wrapT, s.sssMask);
    }
#endif
    float3 mainDirect = LumiLimitMax(mainColor + gi.autoKey) * shadow;
    float3 ambient = max(irrN, _LightMinLimit.xxx) * _EnvLightStrength;
    ambient = LumiLimitMax(ambient);
    float3 aoMB = LumiMultiBounceAO(s.occlusion, s.diffuseColor) * aoAmb;   // baked AO multi-bounce x colored SSAO
    pbrDiff = s.diffuseColor * (diffTerm * mainDirect * aoDir + ambient * aoMB);
    {
        // warm scattering band at the light terminator (skin / cloth look instead of a grey falloff)
        float band = saturate(1.0 - abs(NoL) / _RichTerminatorWidth);
        pbrDiff += s.diffuseColor * _RichTerminatorColor.rgb * (_RichTerminatorColor.a * band * band) * mainDirect;
    }
    }

    float3 diffuse = lerp(pbrDiff, toonDiff, _ToonAmount);
    {
        // richness in the shade: deeper own color, more saturation, hue shift (shadow HSV)
        float shadeF = 1.0 - saturate(lerp(NoLs * shadow, lit, _ToonAmount));
        float3 chroma = s.albedo / max(max(s.albedo.r, max(s.albedo.g, s.albedo.b)), 1e-3);
        diffuse *= lerp(1, chroma, _RichColorDepth * shadeF);
        diffuse = max(diffuse, 0);
        [branch] if (abs(_RichShadowHue) > 1e-4)
        {
            float3 hsv = LumiRGB2HSV(diffuse);
            hsv.x = frac(hsv.x + _RichShadowHue * shadeF);
            diffuse = LumiHSV2RGB(hsv);
        }
        // HSV saturation x k without the HSV round trip: keep the max channel (value), scale the distance to it
        float vmax = max(diffuse.r, max(diffuse.g, diffuse.b));
        diffuse = max(vmax - (vmax - diffuse) * (1.0 + _RichShadowSaturation * shadeF), 0);
        // painterly shade: shadows lean toward the complement of the light colour (cool under white / warm light)
        float3 lc = c.litLight / max(max(c.litLight.r, max(c.litLight.g, c.litLight.b)), 1e-4);
        float lsat = 1.0 - min(lc.r, min(lc.g, lc.b));
        float3 comp = 1.0 - (lc - min(lc.r, min(lc.g, lc.b))) * 0.35;   // complement of the light hue, low saturation
        float3 tint = lerp(_QShadowCoolColor.rgb, comp, saturate(lsat * 3.0));
        diffuse *= lerp(1.0.xxx, tint, _QShadowComplement * shadeF);
    }
    diffuse *= lerp(1.0, _EyeGuardBrightness, eyeG);
    diffuse = lerp(diffuse, s.albedo, _AsUnlit);

    // ---- Specular
    float coatAtten;
    float3 specDirect = LumiDirectSpecular(s, c, L, c.specLight, uv, coatAtten);
    if (_RichSoftSpec > 0.001)
    {
        // broad second lobe: satin like gloss that a single lobe lacks
        float pr2 = max(s.perceptualRough, _RichSoftSpecRoughness);
        float a2b = pr2 * pr2; a2b *= a2b;
        float NoLb = saturate(dot(s.N, L));
        specDirect += LumiDirectSpecularMin(max(s.f0, 0.04), a2b, saturate(dot(s.N, H)), saturate(dot(L, H))) * NoLb * c.specLight * _RichSoftSpec;
    }
    if (_QSpecClamp < 15.9)
    {
        // soft limit relative to the light: no single pixel sparkle on sharp normals (flicker in VR)
        float sl = LumiLuminance(specDirect);
        float lim = max(LumiLuminance(c.specLight), 1e-3) * _QSpecClamp;
        specDirect *= sl > 1e-5 ? lim * (1.0 - exp(-sl / lim)) / sl : 1.0;
    }
    float3 R = reflect(-c.V, s.N);
    float specOcc = lerp(1, LumiSpecularOcclusion(c.NoV, s.occlusion * lerp(1.0, c.ssao, _SSAOSpecular), s.perceptualRough), _SpecOcclusionStrength)
                  * lerp(1, LumiHorizonOcclusion(R, s.Ng), _HorizonOcclusionStrength);
    float3 env = LumiGIReflection(gi, R, d.posWS, s.perceptualRough);
    env = LumiLimitMax(env);
    float3 envBRDF = LumiEnvironmentBRDFMin(s.f0, s.metallic, s.perceptualRough, s.a2, c.NoV) * LumiEnergyCompensation(s.f0, s.perceptualRough, c.NoV);
    float fresG = 1.0 - c.NoV; fresG *= fresG * fresG;
    envBRDF *= 1.0 + _RichGloss * 2.0 * fresG * (1.0 - s.perceptualRough * 0.7);   // edge gloss
    float3 specEnv = env * envBRDF * specOcc * _EnvReflStrength;
    specEnv += LumiLightVolumeSpecular(s.f0, 1.0 - s.perceptualRough, s.N, c.V) * specOcc * _LVSpecular;
#if defined(_LUMI_IRIDESCENCE)
    // thin film interference approximation (cosine spectrum over film thickness * view angle)
    float3 irid = 0.5 + 0.5 * cos(6.2831853 * (c.NoV * _IridScale + _IridOffset + float3(0.0, 0.333, 0.667)));
    irid = lerp(1.0, irid, _IridSaturation);
    float iridF = pow(saturate(1.0 - c.NoV), _IridFresnel);
    float3 iridSpec = lerp(1.0, irid * _IridSpecBoost, saturate(_IridStrength) * _IridSpecOnly);
    specDirect *= iridSpec;
    specEnv *= iridSpec;
#endif
#if defined(_LUMI_CLEARCOAT)
    {
        float coat = _ClearCoat * LUMI_SAMPLE(_ClearCoatMask, uv).r;
        float3 Nc = LumiCoatNormal(s, uv);
        float pr = LumiCoatRoughness(uv);
        float NoVc = saturate(dot(Nc, c.V));
        float Fc = (_ClearCoatF0 + (1.0 - _ClearCoatF0) * LumiPow5(1.0 - NoVc)) * coat;
        float3 envC = LumiLimitMax(LumiGIReflection(gi, reflect(-c.V, Nc), d.posWS, pr));
        specEnv = specEnv * (1.0 - Fc) * lerp(1, _ClearCoatColor.rgb, coat) + envC * Fc * specOcc * _EnvReflStrength * _ClearCoatReflStrength * _ClearCoatSpecColor.rgb;
        diffuse *= (1.0 - Fc) * lerp(1, _ClearCoatColor.rgb, coat);   // coat absorption tint
    }
#endif
    float3 col = diffuse * coatAtten + (specDirect + specEnv) * s.specMask * (1.0 - _AsUnlit);
    col += LumiTransmission(s, c, L, c.litLight, uv);
    // ambient rim: the environment wraps around the silhouette
    {
        float rimA = LumiPow5(1.0 - c.NoV) * 2.0;
        [branch] if (_RichAmbientRimMode > 0.5 && _RichAmbientRim > 0.001)
        {
            // toon: a flat band only on the real silhouette (background behind), none on inner edges such as a muzzle
            rimA = smoothstep(0.55, 0.7, 1.0 - c.NoV) * LumiSilhouetteMask(s.Ng, d.screenUV, d.eyeDepth, c.depthValidity);
        }
        col += irrN * lerp(s.albedo, 1, 0.35) * (rimA * _RichAmbientRim) * s.occlusion * c.ssao * (1.0 - _AsUnlit);
    }

#if defined(_LUMI_COMPAT)
    // compatible shading: its own diffuse replaces the toon / PBR mix, the specular and the extras above
    col = LumiCompatShading(s, d, c.toonDir, mainLight.direction, c.litLight, compatInd, mainLight.shadowAttenuation, true, lit);
    col = min(col, s.albedo * _LightMaxLimit);
    col = LumiCompatEffects(col, s, d, c.V, c.toonDir, mainLight.direction, c.litLight, lit, mainLight.shadowAttenuation);
    c.rampLit = lit;
#endif

    // ---- Procedural extras (no textures)
#if defined(_LUMI_CURVATURE)
    {
        float3 dpx = ddx(d.posWS), dpy = ddy(d.posWS);
        float k = (dot(ddx(s.Ng), dpx) + dot(ddy(s.Ng), dpy)) / max(dot(dpx, dpx) + dot(dpy, dpy), 1e-12);
        k *= _CurvScale * 0.02;
        lumiCurvature = k;
        float pw = lerp(2.0, 0.4, _CurvSharpness);
        float edge = pow(saturate(k), pw), cavity = pow(saturate(-k), pw);
        col *= lerp(1, _CurvCavityColor.rgb, cavity * _CurvCavityColor.a);
        col += _CurvEdgeColor.rgb * edge * _CurvEdgeColor.a * lerp(1, c.litLight, _CurvLightInfluence) * lerp(0.5, 1, lit);
    }
#endif
#if defined(_LUMI_IRIDESCENCE)
    col += irid * iridF * _IridStrength * (1.0 - _IridSpecOnly) * c.litLight * 0.5 * (1.0 - _AsUnlit);
#endif
#if defined(_LUMI_BOUNCE)
    {
        float3 up = float3(0, 1, 0);
        float down = pow(saturate(-dot(Nd, up) * 0.5 + 0.5), _BouncePower);
        float hgt = d.posWS.y - LumiObjectToWorld(float3(0, 0, 0)).y;
        float fade = saturate((_BounceHeight - hgt) / max(_BounceHeight, 1e-3));
        float3 bc = _BounceColor.rgb * lerp(1, LumiKeepChroma(LumiGISH(gi, -up), gi.chromaKeep) * _BounceGroundIntensity, _BounceGroundMatch);
        bc *= lerp(1, LumiLuminance(c.litLight), _BounceLightInfluence);
        col += s.diffuseColor * bc * (down * fade * _BounceStrength) * c.aoColor * s.occlusion;
    }
#endif
#if defined(_LUMI_FILLLIGHT)
    {
        float3 Lf = normalize(LumiViewToWorldDir(_FillDir.xyz) + 1e-5);
        float f = LumiSmoothBorder(dot(Nd, Lf) * 0.5 + 0.5, _FillBorder, _FillBlur);
        f *= lerp(1, 1.0 - lit, _FillShadowOnly);
        col += s.diffuseColor * _FillColor.rgb * (f * _FillStrength) * c.aoColor;
    }
#endif
#if defined(_LUMI_HATCH)
    {
        float dark = 1.0 - lerp(lit, saturate(toonX), 0.5);
        float2 p = _HatchSpace < 0.5 ? d.pixelPos / _ScreenParams.y : d.uv0;
        p *= _HatchDensity;
        float2 pr = LumiRotateUV(p, radians(_HatchAngle));
        float2 pc = LumiRotateUV(p, radians(_HatchAngle + 90.0));
        float jit = _HatchNoise * 0.35;
        float l1 = abs(frac(pr.x + sin(pr.y * 0.37) * jit) - 0.5) * 2.0;
        float l2 = abs(frac(pc.x + sin(pc.y * 0.41) * jit) - 0.5) * 2.0;
        float w1 = _HatchWidth * saturate((dark - _HatchThreshold) / max(1.0 - _HatchThreshold, 1e-3));
        float th2 = lerp(_HatchThreshold, 1.0, _Hatch2ndThreshold);
        float w2 = _HatchWidth * saturate((dark - th2) / max(1.0 - th2, 1e-3)) * _HatchCross;
        float aa1 = fwidth(pr.x) * 2.0, aa2 = fwidth(pc.x) * 2.0;
        float m1 = (1.0 - smoothstep(w1 - aa1, w1 + aa1, l1)) * step(1e-4, w1);
        float m2 = (1.0 - smoothstep(w2 - aa2, w2 + aa2, l2)) * step(1e-4, w2);
        float m = max(m1, m2);
        col = lerp(col, col * _HatchColor.rgb, saturate(m) * _HatchColor.a);
    }
#endif

    // ---- MatCap
#if defined(_LUMI_MATCAP) && !defined(_LUMI_COMPAT)
    {
        float3 Nm = s.N;
        if (_UseMatCapBump > 0.5)
        {
            float3 nb = LumiUnpackNormal(LUMI_SAMPLE(_MatCapBumpMap, uv), _MatCapBumpScale);
            Nm = normalize(s.T * nb.x + s.B * nb.y + s.N * nb.z);
        }
        float3 N1 = normalize(lerp(s.Ng, Nm, _MatCapNormalStrength));
        col = LumiApplyMatCap(col, _MatCapTex, _MatCapMask, _MatCapColor, _MatCapBlend, _MatCapLod, _MatCapEnableLighting, _MatCapShadowMask,
                              _MatCapMainStrength, uv, LumiMatCapUV(N1, c.V, d.posWS, _MatCapPerspective, _MatCapZRotCancel), s.albedo, c.litLight, lit);
        if (_UseMatCap2 > 0.5)
        {
            float3 N2 = normalize(lerp(s.Ng, Nm, _MatCap2NormalStrength));
            col = LumiApplyMatCap(col, _MatCap2Tex, _MatCap2Mask, _MatCap2Color, _MatCap2Blend, _MatCap2Lod, _MatCap2EnableLighting, _MatCap2ShadowMask,
                                  0, uv, LumiMatCapUV(N2, c.V, d.posWS, _MatCapPerspective, _MatCapZRotCancel), s.albedo, c.litLight, lit);
        }
    }
#endif

    // ---- Rim lights 1 / 2 / 3 (one keyword, each with its own switch)
#if defined(_LUMI_RIM) && !defined(_LUMI_COMPAT)
    [branch] if (_UseRim > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _RimNormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _RimFresnelPower), _RimBorder, _RimBlur);
        if (_RimMode > 0.5 && c.depthValidity > 0.5)
            r = LumiDepthRim(Nr, d.screenUV, d.eyeDepth, _RimDepthWidth, _RimDepthThreshold) * lerp(1, r, 0.25);
        r = LumiRimLightMask(r, Nr, c.toonDir, _RimLightDir, _RimShadowMask, _RimBackfaceMask, _RimLitSideOnly, _RimLitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_RimTex, uv);
        float3 rc = _RimColor.rgb * rt.rgb * lerp(1, s.albedo, _RimMainStrength) * lerp(1, c.litLight, _RimEnableLighting);
        col = LumiRimBlend(col, rc, saturate(r) * _RimColor.a * rt.a, _RimBlendMode);
    }
    [branch] if (_UseRim2 > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _Rim2NormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _Rim2FresnelPower), _Rim2Border, _Rim2Blur);
        r = LumiRimLightMask(r, Nr, c.toonDir, _Rim2LightDir, _Rim2ShadowMask, _Rim2BackfaceMask, _Rim2LitSideOnly, _Rim2LitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_Rim2Tex, uv);
        float3 rc = _Rim2Color.rgb * rt.rgb * lerp(1, s.albedo, _Rim2MainStrength) * lerp(1, c.litLight, _Rim2EnableLighting);
        col = LumiRimBlend(col, rc, saturate(r) * _Rim2Color.a * rt.a, _Rim2BlendMode);
    }
    [branch] if (_UseRim3 > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _Rim3NormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _Rim3FresnelPower), _Rim3Border, _Rim3Blur);
        r = LumiRimLightMask(r, Nr, c.toonDir, _Rim3LightDir, _Rim3ShadowMask, _Rim3BackfaceMask, _Rim3LitSideOnly, _Rim3LitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_Rim3Tex, uv);
        float3 rc = _Rim3Color.rgb * rt.rgb * lerp(1, s.albedo, _Rim3MainStrength) * lerp(1, c.litLight, _Rim3EnableLighting);
        col = LumiRimBlend(col, rc, saturate(r) * _Rim3Color.a * rt.a, _Rim3BlendMode);
    }
#endif

#if defined(_LUMI_GLITTER)
    col += LumiGlitter(s, d, c, normalize(c.toonDir + c.V));
#endif

#if defined(_LUMI_ANGELRING)
    {
        // procedural hair highlight ring: band of view space normal Y, broken up along UV.x
        float3 nV = LumiWorldToViewDir(s.N);
        float band = smoothstep(_AngelWidth, _AngelWidth * (1.0 - _AngelBlur), abs(nV.y - _AngelHeight));
        band *= saturate(nV.z * 2.0);
        float br = sin(d.uv0.x * _AngelFrequency * 6.2831853) * 0.5 + 0.5;
        br = lerp(br, LumiHash12(floor(d.uv0.x * _AngelFrequency).xx), 0.5);
        band *= lerp(1, smoothstep(0.25, 0.75, br), _AngelBreakup);
        col += _AngelColor.rgb * (_AngelColor.a * band) * lerp(1, c.litLight, _AngelLightInfluence) * lerp(1, lit, _AngelShadowMask) * s.specMask;
    }
#endif

    float3 offRimEmis = 0;
#if defined(_LUMI_OFFSETRIM)
    {
        float r = LumiOffsetRim(s.N, c.toonDir, d.screenUV, d.eyeDepth, c.NoV, c.depthValidity);
        r *= lerp(1, saturate((1.0 - c.NoV) * 2.0), _OffsetRimFacing);
        r *= saturate(1.0 - d.eyeDepth / max(_OffsetRimFadeEnd, 0.01));
        if (d.facing < 0) r = 0;
        float3 baseC = _OffsetRimColor.rgb;
        if (_OffsetRimHueSpeed > 0.0001)
        {
            float3 hsv = LumiRGB2HSV(baseC);
            hsv.x = frac(hsv.x + _Time.y * _OffsetRimHueSpeed);
            hsv.y = max(hsv.y, 0.6);   // a white rim still cycles visibly
            baseC = LumiHSV2RGB(hsv);
        }
        // lit rim: follows the light, the ambient and the shadows
        float3 rc = baseC * _OffsetRimStrength * lerp(1, s.albedo, _OffsetRimAlbedo);
        rc *= lerp(1, c.litLight, _OffsetRimLightInfluence) * lerp(1, LumiLimitLight(shAvg) * 2.0, _OffsetRimEnvInfluence);
        col += rc * (r * lerp(1, lit, _OffsetRimShadowMask) * _OffsetRimColor.a * (1.0 - _OffsetRimEmission));
        // emissive rim: glows the same in any world (added after world adaptation, like emission)
        float blink = sin(_Time.y * _OffsetRimBlink.y + _OffsetRimBlink.z) * 0.5 + 0.5;
        if (_OffsetRimBlink.w > 0.5) blink = step(0.5, blink);
        offRimEmis = baseC * lerp(1, s.albedo, _OffsetRimEmissionAlbedo) * (_OffsetRimEmissionStrength * r * _OffsetRimColor.a * _OffsetRimEmission)
                   * lerp(1, blink, _OffsetRimBlink.x);
    }
#endif

#if defined(_LUMI_HOLOGRAM)
    {
        float y = d.posWS.y * _HoloLineDensity + _Time.y * _HoloLineSpeed;
        float scan = sin(y * 6.2831853) * 0.5 + 0.5;
        float fres = pow(saturate(1.0 - c.NoV), _HoloFresnel);
        float flick = lerp(1, 0.65 + 0.35 * sin(_Time.y * _HoloFlickerSpeed + sin(_Time.y * _HoloFlickerSpeed * 0.3) * 3.0), _HoloFlicker);
        float h = saturate(fres + scan * 0.5) * flick;
        col += _HoloColor.rgb * h * _HoloStrength;
        s.alpha = lerp(s.alpha, s.alpha * saturate(h + 0.15), _HoloAlpha);
    }
#endif

    // ---- World adaptation (keeps the avatar readable in very dark / very bright worlds)
    {
        float worldLum = gi.worldLum;
        float adapt = clamp(_WorldAdaptTarget / max(worldLum, 1e-3), 1.0 / _WorldAdaptRange, _WorldAdaptRange);
        col *= lerp(1, adapt, _WorldAdapt);
    }

    // ---- Fresnel alpha (glass / soft edges)
    {
        float fr = LumiPow5(1.0 - saturate(c.NoV)) * 0.7 + (1.0 - c.NoV) * 0.3;
        s.alpha = _FresnelAlpha >= 0 ? lerp(s.alpha, 1.0, fr * _FresnelAlpha) : s.alpha * (1.0 - fr * -_FresnelAlpha);
    }

    // ---- Fake refraction (gems / glass / eyes): the environment seen through the surface, no grab pass needed
    if (_RefractStrength > 0.001)
    {
        float3 env = LumiGIReflection(gi, refract(-c.V, s.N, 1.0 / _RefractIOR), d.posWS, _RefractRoughness);
        if (_RefractDispersion > 0.001)
        {
            env.r = LumiGIReflection(gi, refract(-c.V, s.N, 1.0 / max(_RefractIOR - _RefractDispersion, 1.0)), d.posWS, _RefractRoughness).r;
            env.b = LumiGIReflection(gi, refract(-c.V, s.N, 1.0 / (_RefractIOR + _RefractDispersion)), d.posWS, _RefractRoughness).b;
        }
        float3 body = env * _RefractColor.rgb * lerp(1.0.xxx, s.albedo, _RefractColor.a);
        float fr = LumiPow5(1.0 - saturate(c.NoV));
        col = lerp(col, body,_RefractStrength * (1.0 - fr));
    }

    col += s.emission + offRimEmis;

#if defined(_LUMI_COMPAT)
    col = d.facing < 0 ? lerp(col, _BackfaceColor.rgb * c.litLight, _BackfaceColor.a) : col;
#endif

    // ---- Debug views
    if (_DebugView > 0.5)
    {
        int dv = (int)_DebugView;
        if (dv == 1) col = s.albedo;
        else if (dv == 2) col = s.N * 0.5 + 0.5;
        else if (dv == 3) col = lerp(c.shadeLight, c.litLight, lit);
        else if (dv == 4) col = (lit * shadow).xxx;
        else if (dv == 5) col = (c.ssao * s.occlusion).xxx;
        else if (dv == 6) col = c.depthValidity.xxx;
        else if (dv == 7) col = float3(saturate(lumiCurvature), 0.2, saturate(-lumiCurvature));
        else if (dv == 9) col = lumiLVActive > 0.5 ? max(LumiEvalL1(s.N), 0) : float3(0.25, 0.0, 0.25);   // purple: no light volume here
        else col = LumiGIIrradiance(gi, s.N);
    }
    return float4(col, s.alpha);
}

// ---- Final touches shared by passes ------------------------------------------
float3 LumiDistanceFade(float3 col, LumiInputData d, bool additive)
{
#if defined(_LUMI_DISTFADE)
    float dist = distance(d.posWS, LumiGetCameraPositionWS());
    float f = (1.0 - LumiRemap(dist, _DistanceFadeStart, _DistanceFadeEnd)) * _DistanceFadeStrength;
    col = lerp(col, additive ? 0 : _DistanceFadeColor.rgb, f);
#endif
    return col;
}
void LumiNearDither(LumiInputData d)
{
#if defined(_LUMI_DISTFADE)
    if (_NearDither > 0.5)
    {
        float dist = distance(d.posWS, LumiGetCameraPositionWS());
        clip(dist / max(_NearDitherDistance, 1e-3) - LumiBayer4(d.pixelPos));
    }
#endif
}
// per character controls (keep identical on every material of the avatar)
float3 LumiCharacterColor(float3 col, bool additive)
{
    col *= _CharTint.rgb * _CharBrightness;
    col = lerp(col, LumiLuminance(col).xxx, _CharDesaturate);
    col = lerp(col, additive ? 0 : _CharLerpColor.rgb, _CharLerpColor.a);
    return col;
}
// triangular dither of about one 8 bit step (in sRGB terms) to hide banding in dark smooth gradients
float3 LumiDeband(float3 col)
{
    float n = LumiHash12(lumiPixel) + LumiHash12(lumiPixel.yx + 17.13) - 1.0;
    float3 step8 = 2.2 * pow(max(col, 1e-4), 0.5455) / 255.0;   // d(linear)/d(sRGB) * 1/255
    return max(col + n * step8 * _QDeband, 0);
}
float3 LumiFinalGrade(float3 col, bool additive)
{
    col = LumiCharacterColor(col, additive);
#if defined(_LUMI_TONEMAP)
    if (additive) return LumiWhiteBalance(col * exp2(_Exposure), _Temperature, _Tint);
    col = LumiColorGrade(col, _Exposure, _TonemapMode, _Contrast, _Saturation, _Temperature, _Tint,
                         _Vibrance, _ShadowTint.rgb, _HighlightTint.rgb);
#endif
    if (!additive && _QDeband > 0.001) col = LumiDeband(col);
    return col;
}

#endif
