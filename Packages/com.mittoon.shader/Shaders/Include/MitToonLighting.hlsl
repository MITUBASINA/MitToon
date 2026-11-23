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
    return l > 1e-4 ? c * (lc / max(l, 1e-4)) : c;   // (both sides run: the max keeps a black light from dividing by 0)
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
    return LUMI_SAMPLE(_EyeGuardMask, LUMI_TF(_EyeGuardMask, uv)).r * step(0.5, _UseEyeGuard);
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
static float lumiPCSSOn = 0;   // set by fragAdd when the PCSS soft shadow is used (it shapes its own edge)
float LumiCastG(float shadow)
{
    float sEff = lerp(1, shadow, max(_ReceiveShadowStrength, lumiPCSSOn));   // PCSS ignores the plain receive strength
    float w = lerp(0.02 + 0.48 * _CastShadowSoftness, 0.5, lumiPCSSOn);
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

// rim colour with the optional hue cycle (a white rim still cycles visibly)
float3 LumiRimHue(float3 c, float speed)
{
    if (speed < 0.0001) return c;
    float3 hsv = LumiRGB2HSV(c);
    hsv.x = frac(hsv.x + _Time.y * speed);
    hsv.y = max(hsv.y, 0.6);
    return LumiHSV2RGB(hsv);
}

// strength of the emissive part: emission strength times the optional blink
float LumiRimBlink(float strength, float4 blink)
{
    float b = sin(_Time.y * blink.y + blink.z) * 0.5 + 0.5;
    if (blink.w > 0.5) b = step(0.5, b);
    return strength * lerp(1, b, blink.x);
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
    return clamp(1.0 - _ClearCoatSmoothness * LUMI_SAMPLE(_ClearCoatSmoothnessMap, LUMI_TF(_ClearCoatSmoothnessMap, uv)).r, 0.03, 1);
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
        float mask = LUMI_SAMPLE(_AnisoMask, LUMI_TF(_AnisoMask, uv)).r;
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
        float3 sheen = _SheenColor.rgb * LUMI_SAMPLE(_SheenMap, LUMI_TF(_SheenMap, uv)).rgb * LUMI_SAMPLE(_SheenMask, LUMI_TF(_SheenMask, uv)).r;
        spec += sheen * LumiD_Sheen(NoH, max(_SheenRoughness, 0.05)) * LumiV_Sheen(c.NoV, NoL) * (LUMI_PI * NoL);
        // velvet edge: fuzz that glows toward the silhouette on the lit side
        spec += sheen * _SheenFuzz * pow(saturate(1.0 - c.NoV), _SheenFuzzPower) * saturate(dot(s.N, L) * 0.5 + 0.5);
    }
#endif

#if defined(_LUMI_CLEARCOAT)
    {
        float coat = _ClearCoat * LUMI_SAMPLE(_ClearCoatMask, LUMI_TF(_ClearCoatMask, uv)).r;
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
        float4 m = LUMI_SAMPLE(_BacklightMask, LUMI_TF(_BacklightMask, uv));
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
    float4 blurM = LUMI_SAMPLE(_ShadowBlurMask, LUMI_TF(_ShadowBlurMask, uv));
    float4 bm = LUMI_SAMPLE(_ShadowBorderMask, LUMI_TF(_ShadowBorderMask, uv));
    bm.r = saturate(bm.r * _CompatAOShift.x + _CompatAOShift.y);
    bm.g = saturate(bm.g * _CompatAOShift.z + _CompatAOShift.w);
    bm.b = saturate(bm.b * _ShadowAOShift2.x + _ShadowAOShift2.y);
    bool post = _ShadowPostAO > 0.5;
    lns.xyz = post ? lns.xyz : lns.xyz * bm.rgb;
    lns.w = lns.x;
    float3 lam = saturate(lns.xyz * 2.0 - 1.0);   // the same light as lambert (toon amount below 1 blends toward it)
    lns.x = LumiCompatToon(lns.x, _ShadowBorder, _ShadowBlur * blurM.r, 0);
    lns.y = LumiCompatToon(lns.y, _Shadow2ndBorder, _Shadow2ndBlur * blurM.g, 0);
    lns.w = LumiCompatToon(lns.w, _ShadowBorder, _ShadowBlur * blurM.r, _ShadowBorderRange);
    lns.z = LumiCompatToon(lns.z, _Shadow3rdBorder, _Shadow3rdBlur * blurM.b, 0);
    lns.xyz = lerp(lam, lns.xyz, _ToonAmount);
    lns = saturate(post ? lns * bm.rgbr : lns);
    lns *= d.facing < 0 ? 1.0 - _BackfaceForceShadow : 1.0;
    float mix = lns.x;
    lns.x = lerp(1.0, lns.x, _ShadowStrength * LUMI_SAMPLE(_ShadowMaskTex, LUMI_TF(_ShadowMaskTex, uv)).r);
    float4 t1 = LUMI_SAMPLE(_ShadowColorTex, LUMI_TF(_ShadowColorTex, uv)), t2 = LUMI_SAMPLE(_Shadow2ndColorTex, LUMI_TF(_Shadow2ndColorTex, uv)), t3 = LUMI_SAMPLE(_Shadow3rdColorTex, LUMI_TF(_Shadow3rdColorTex, uv));
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

float3 LumiCompatMatCap(float3 col, LumiSurface s, LumiInputData d, float3 N, float3 V, Texture2D tex, float4 st, Texture2D mask, float4 maskST, float4 color, float mode, float lod,
                     float el, float shMask, float ms, float bfMask, float3 lc, float mix)
{
    float2 muv = LumiCompatMatCapUV(normalize(N), V, st, _MatCapZRotCancel, _MatCapPerspective);
    float4 mc = color * tex.SampleLevel(sampler_trilinear_repeat, muv, lod);
    mc.rgb = lumiCompatFA > 0.5 ? (mode < 2.5 ? mc.rgb * lc * el : mc.rgb) : lerp(mc.rgb, mc.rgb * lc, el);
    mc.a = lerp(mc.a, mc.a * mix, shMask);
    mc.a = (d.facing < 0 && bfMask > 0.5) ? 0 : mc.a;
    float3 mk = LUMI_SAMPLE(mask, (s.uvMain) * maskST.xy + maskST.zw).rgb;
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
        r = saturate(LumiCompatToon(r, _RimShadeBorder, _RimShadeBlur, 0)) * _RimShadeColor.a * LUMI_SAMPLE(_RimShadeMask, LUMI_TF(_RimShadeMask, uv)).r;
        col = lerp(col, col * _RimShadeColor.rgb, r);
    }
    if (_UseBacklight > 0.5 && lumiCompatFA < 0.5)
    {
        float3 N = lerp(s.Ng, s.N, _BacklightNormalStrength);
        float4 bc = _BacklightColor * LUMI_SAMPLE(_BacklightMask, LUMI_TF(_BacklightMask, uv));
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
            float3 nb = LumiUnpackNormal(LUMI_SAMPLE(_MatCapBumpMap, LUMI_TF(_MatCapBumpMap, uv)), _MatCapBumpScale);
            N = normalize(s.T * nb.x + s.B * nb.y + s.Ng * nb.z);
        }
        col = LumiCompatMatCap(col, s, d, N, V, _MatCapTex, _MatCapTex_ST, _MatCapMask, _MatCapMask_ST, _MatCapColor, _MatCapBlend, _MatCapLod,
                            _MatCapEnableLighting, _MatCapShadowMask, _MatCapMainStrength, _MatCapBackfaceMask, lc, mix);
    }
    if (_UseMatCap2 > 0.5)
        col = LumiCompatMatCap(col, s, d, lerp(s.Ng, s.N, _MatCap2NormalStrength), V, _MatCap2Tex, _MatCap2Tex_ST, _MatCap2Mask, _MatCap2Mask_ST, _MatCap2Color, _MatCap2Blend, _MatCap2Lod,
                            _MatCap2EnableLighting, _MatCap2ShadowMask, 0, 0, lc, mix);
    if (_UseRim > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _RimNormalStrength, _RimFresnelPower, _RimBorder, _RimBlur, _RimBackfaceMask, _RimShadowMask,
                         _RimMainStrength, _RimEnableLighting, _RimColor, LUMI_SAMPLE(_RimTex, LUMI_TF(_RimTex, uv)), _RimBlendMode, _RimLightDir, 1);
    if (_UseRim2 > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _Rim2NormalStrength, _Rim2FresnelPower, _Rim2Border, _Rim2Blur, _Rim2BackfaceMask, _Rim2ShadowMask,
                         _Rim2MainStrength, _Rim2EnableLighting, _Rim2Color, LUMI_SAMPLE(_Rim2Tex, LUMI_TF(_Rim2Tex, uv)), _Rim2BlendMode, _Rim2LightDir, 0);
    if (_UseRim3 > 0.5)
        col = LumiCompatRim(col, s, d, V, L, lc, mix, _Rim3NormalStrength, _Rim3FresnelPower, _Rim3Border, _Rim3Blur, _Rim3BackfaceMask, _Rim3ShadowMask,
                         _Rim3MainStrength, _Rim3EnableLighting, _Rim3Color, LUMI_SAMPLE(_Rim3Tex, LUMI_TF(_Rim3Tex, uv)), _Rim3BlendMode, _Rim3LightDir, 0);
    return col;
}
#endif

// ---- Shading of one extra light (ForwardAdd / vertex lights) -------------------
// ---- URP lighting ----------------------------------------------------------------
// The lighting of the Universal Render Pipeline's Lit shader: energy conserving lambert diffuse, URP's
// minimalist GGX specular, light probes along the normal and the reflection probe with its fresnel term.
// No toon, no light limits, no MitToon GI: what the scene's lights give is what the surface shows.
struct LumiURPBRDF
{
    float3 diffuse, specular;
    float  perceptualRough, rough2, rough2m1, norm, grazing;
};
LumiURPBRDF LumiURPInit(LumiSurface s)
{
    LumiURPBRDF b;
    float oneMinusRefl = 0.96 * (1.0 - s.metallic);          // dielectric reflectance 0.04
    b.diffuse = s.albedo * oneMinusRefl;
    b.specular = lerp(0.04.xxx, s.albedo, s.metallic);
    b.perceptualRough = s.perceptualRough;
    float r = max(s.perceptualRough * s.perceptualRough, 0.0078125);
    b.rough2 = max(r * r, 6.103515625e-5);
    b.rough2m1 = b.rough2 - 1.0;
    b.norm = r * 4.0 + 2.0;
    b.grazing = saturate((1.0 - s.perceptualRough) + (1.0 - oneMinusRefl));
    return b;
}
// toon amount in the URP / ray tracing models: N.L toward a cel step at the 1st border (0 = lambert, 1 = toon)
float LumiToonNoL(float NoL)
{
    float x = NoL * 0.5 + 0.5;
    float bw = max(_ShadowBlur, fwidth(x) * _QToonAA) + 1e-4;
    return lerp(saturate(NoL), smoothstep(_ShadowBorder - bw, _ShadowBorder + bw, x), _ToonAmount);
}
// the ambient along the normal flattened toward its even part (toon: less volume from the ambient)
float3 LumiToonSH(float3 N)
{
    float3 shN = LumiSampleSH(N);
    return _ToonAmount > 0.001 ? lerp(shN, 0.5 * (shN + LumiSampleSH(-N)), _ToonAmount * 0.6) : shN;
}
// one light: (diffuse + specular x BRDF) x light colour x attenuation x N.L
float3 LumiURPDirect(LumiURPBRDF b, float3 N, float3 V, float3 L, float3 radiance, float specMask)
{
    float3 H = normalize(L + V + float3(0, 1e-5, 0));
    float NoH = saturate(dot(N, H)), LoH = saturate(dot(L, H));
    float dd = NoH * NoH * b.rough2m1 + 1.00001;
    float spec = b.rough2 / ((dd * dd) * max(0.1, LoH * LoH) * b.norm);
    return (b.diffuse + b.specular * (spec * specMask)) * radiance;
}
// URP's specular lobe alone (times the specular colour), for mixing into the MitToon model
float3 LumiURPSpecularTerm(LumiURPBRDF b, float3 N, float3 V, float3 L)
{
    float3 H = normalize(L + V + float3(0, 1e-5, 0));
    float NoH = saturate(dot(N, H)), LoH = saturate(dot(L, H));
    float dd = NoH * NoH * b.rough2m1 + 1.00001;
    return b.specular * (b.rough2 / ((dd * dd) * max(0.1, LoH * LoH) * b.norm));
}
static float lumiRTValidity = 0;   // depth validity of this pixel, for the ray traced reflection in the URP model
static float3 lumiRTBounce = 0;    // ray traced colour bounce of this pixel
// ray tracing lighting: the light of the probes split into the sky's main direction (a light the rays can shadow,
// with a real lambert falloff) and the even rest
static float3 lumiSkyDir = float3(0, 1, 0), lumiSkyCol = 0;
static float lumiSkyShadow = 1;
// URP lighting with the pseudo ray tracing on: the probes' sky light is shadowed by rays (0 when the sky slider is 0)
bool LumiRTLighting()
{
#if defined(_LUMI_RAYTRACE)
    return LUMI_URP_MODEL && _RTSkyLight > 0.001;
#else
    return false;
#endif
}
void LumiRTSkySplit()
{
    float3 px = LumiSampleSH(float3(1, 0, 0)), nx = LumiSampleSH(float3(-1, 0, 0));
    float3 py = LumiSampleSH(float3(0, 1, 0)), ny = LumiSampleSH(float3(0, -1, 0));
    float3 pz = LumiSampleSH(float3(0, 0, 1)), nz = LumiSampleSH(float3(0, 0, -1));
    float3 A = (px + nx + py + ny + pz + nz) / 6.0;                  // L0 (the L2 terms cancel over the 6 axes)
    float3 Bx = (px - nx) * 0.5, By = (py - ny) * 0.5, Bz = (pz - nz) * 0.5;   // L1 per axis (x / y / z per channel)
    float3 lw = float3(0.2126, 0.7152, 0.0722);
    float3 bl = float3(dot(Bx, lw), dot(By, lw), dot(Bz, lw));
    float bln = length(bl);
    lumiSkyDir = bln > 1e-6 ? bl / bln : float3(0, 1, 0);
    // a light C from one direction is C (1/4 + n.d / 2) in the first two bands: C = 2 B along it, at most what keeps
    // the rest positive everywhere (4 L0). Taken as luminance, in the colour of the probes' average: per channel the
    // channels whose light comes from elsewhere (a warm floor below a green ceiling) dropped out of it, so the shadow
    // took away only green and left purple.
    float la = LumiLuminance(max(A, 0.0));
    float sl = min(2.0 * bln, 4.0 * la) * _RTSkyLight;
    lumiSkyCol = la > 1e-6 ? max(A, 0.0) * (sl / la) : 0.0;
}
float3 LumiRTSkySH(float3 N)
{
    float NoS = dot(N, lumiSkyDir);
    // the probes without the sky's part, in the probes' own colour there (no channel clamped away), + the sky's part
    // as a light the rays shadow
    float3 sh = LumiToonSH(N);
    float ls = LumiLuminance(sh);
    float3 rest = ls > 1e-6 ? sh * saturate(1.0 - LumiLuminance(lumiSkyCol * (0.25 + 0.5 * NoS)) / ls) : 0.0;
    return rest + lumiSkyCol * LumiToonNoL(NoS) * lumiSkyShadow;
}
float3 LumiURPShade(LumiSurface s, LumiInputData d, LumiLight ml, float3 aoIndirect, float3 aoDirect)
{
    LumiURPBRDF b = LumiURPInit(s);
    float3 N = s.N, V = d.viewDirWS;
    float NoV = saturate(dot(N, V));
    // global illumination: probes along the normal + the reflection probe (fresnel toward the grazing colour)
    float3 indirectDiffuse = (LumiRTLighting() ? LumiRTSkySH(N) : LumiToonSH(N)) * s.occlusion * aoIndirect;
    float3 R = reflect(-V, N);
    float3 reflP = LumiSampleEnvironment(R, d.posWS, b.perceptualRough, 0, 1);
    float3 refl = LumiRTReflection(reflP, d.posWS, N, V, b.perceptualRough, d.eyeDepth, d.pixelPos, lumiRTValidity);
    float fres = 1.0 - NoV; fres *= fres; fres *= fres;
    float3 kRefl = (lerp(b.specular, b.grazing.xxx, fres) / (b.rough2 + 1.0)) * s.specMask * s.occlusion * aoIndirect;
    float3 col = indirectDiffuse * b.diffuse + refl * kRefl;
    float3 giSpec = 0;
#if defined(LUMI_RAYTRACE_GRAB)
    LumiURPBRDF bg = b;   // the bounce light is an area: wider lobe
    bg.rough2 = saturate(b.rough2 + lumiRTGIA2); bg.rough2m1 = bg.rough2 - 1.0; bg.norm = sqrt(bg.rough2) * 4.0 + 2.0;
    giSpec = LumiURPSpecularTerm(bg, N, V, lumiRTGIDir) * lumiRTGICol * saturate(dot(N, lumiRTGIDir)) * s.specMask * aoIndirect;
#endif
    lumiRTDelta = (refl - reflP) * kRefl + b.diffuse * lumiRTBounce + giSpec;
    float NoL = LumiToonNoL(dot(N, ml.direction));
    col += LumiURPDirect(b, N, V, ml.direction, ml.color * (ml.distanceAttenuation * ml.shadowAttenuation * NoL), s.specMask) * aoDirect;
    col += b.diffuse * lumiRTBounce + giSpec;
    return col + s.emission;
}

// edge tint: toward the silhouette the colour softly takes a tint (skin reddening at its edge, light scattered under it).
// A multiplier on the lit colour (not added light); only the optional glow adds, scaled by the light reaching the
// surface (the caller), so it never shines in the dark. lit = 1 on the lit side (base pass toon result)
// returns row 0 = the multiplier, row 1 = the glow (no out parameter: FXC then warns of uninitialized variables)
float2x3 LumiEdgeTint(LumiSurface s, LumiInputData d, float lit)
{
    float3 m = 1.0, glow = 0;
    if (_UseEdgeTint > 0.5 && d.facing > 0)
    {
        float3 n = normalize(lerp(s.Ng, s.N, _EdgeTintNormalMap));
        float edge = 1.0 - saturate(dot(n, d.viewDirWS));
        float w = _EdgeTintWidth;
        float f = smoothstep(1.0 - w, 1.0 - w * (1.0 - _EdgeTintSoftness) + 1e-3, edge);
        f = pow(f, _EdgeTintPower);
        f *= LUMI_SAMPLE(_EdgeTintMask, LUMI_TF(_EdgeTintMask, s.uvMain)).r;
        float ls = _EdgeTintLitSide;   // + toward the lit side, - toward the shadow side
        f *= ls >= 0.0 ? lerp(1.0, lit, ls) : lerp(1.0, 1.0 - lit, -ls);
        float4 tc = _EdgeTintUseShadowColor > 0.5 ? lerp(_EdgeTintShadowColor, _EdgeTintColor, lit) : _EdgeTintColor;
        // from the base colour: its own hue deepened (skin -> deeper red), at the tint colour's brightness
        float am = max(s.albedo.r, max(s.albedo.g, s.albedo.b));
        float3 deep = am > 1e-4 ? s.albedo / am : 1.0;
        tc.rgb = lerp(tc.rgb, deep * deep * max(tc.r, max(tc.g, tc.b)), _EdgeTintAlbedo);
        // keep brightness: the multiplier's luminance goes to 1, only the hue changes
        float3 tint = lerp(tc.rgb, tc.rgb / max(LumiLuminance(tc.rgb), 1e-3), _EdgeTintKeepBrightness);
        float a = saturate(f) * tc.a;
        m = lerp(1.0.xxx, tint, a);
        glow = tc.rgb * (a * _EdgeTintGlow);
    }
    return float2x3(m, glow);
}

float3 LumiShadeAdditional(LumiSurface s, LumiInputData d, LumiCtx c, LumiLight light)
{
    [branch] if (LUMI_URP_MODEL)
    {
        LumiURPBRDF b = LumiURPInit(s);
        float NoL = LumiToonNoL(dot(s.N, light.direction));
#if defined(_LUMI_RAYTRACE) && defined(UNITY_PASS_FORWARDADD)
        // ray tracing lighting: point / spot lights cast ray traced shadows too (they rarely have a shadow map)
        [branch] if (_RTShadowStrength > 0.001)
            light.shadowAttenuation *= LumiQuadSmooth(LumiRTShadow(d.posWS, s.Ng, light.direction, d.eyeDepth, d.pixelPos, lumiRTValidity).xxxx, d.eyeDepth, d.pixelPos).x;
#endif
        light.shadowAttenuation = lerp(light.shadowAttenuation, 1.0, LumiEyeGuard(s.uvMain) * _EyeGuardShadow);
        return LumiURPDirect(b, s.N, c.V, light.direction, light.color * (light.distanceAttenuation * light.shadowAttenuation * NoL), s.specMask);
    }
#if defined(_LUMI_COMPAT)
    {
        light.shadowAttenuation = lerp(light.shadowAttenuation, 1.0, LumiEyeGuard(s.uvMain) * _EyeGuardShadow);
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
    light.shadowAttenuation = lerp(1.0, light.shadowAttenuation, max(_AddLightCastShadow, lumiPCSSOn));

    // toon: an additional light only adds light where it reaches. The far side gets nothing (no tinted shadow colour
    // multiplied by the light colour, which made hard coloured patches), and the border is soft.
    if (_LightMapMode > 2.5 && _LightMapMode < 3.5) NoL = 1;
    float x0 = LumiToonX0(s, NoL);
    float x = x0 * lerp(1, light.shadowAttenuation, max(_ReceiveShadowStrength, lumiPCSSOn));
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
    float3 diffA = lerp(pbr, toon, _ToonAmount);
    [branch] if (_URPMixDiffuse + _URPMixSpecular > 0.001)
    {
        LumiURPBRDF ub = LumiURPInit(s);
        float3 radU = lc * light.shadowAttenuation * saturate(dot(s.N, L));
        diffA = lerp(diffA, ub.diffuse * radU, _URPMixDiffuse);
        spec = lerp(spec, LumiURPSpecularTerm(ub, s.N, c.V, L) * radU, _URPMixSpecular);
    }
    float3 col = diffA * coatAtten + spec;
    col += LumiTransmission(s, c, L, lc, s.uvMain);
    float2x3 et = LumiEdgeTint(s, d, 1.0);
    col = col * et[0] + et[1] * lc * (light.shadowAttenuation * saturate(dot(s.N, L) * 0.5 + 0.5));
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
float3 LumiApplyMatCap(float3 col, Texture2D tex, Texture2D mask, float4 maskST, float4 color, float blend, float lod, float lighting, float shadowMask,
                       float mainStr, float2 uvMain, float2 mcuv, float3 albedo, float3 light, float lit)
{
    float4 m = tex.SampleLevel(sampler_trilinear_clamp, mcuv, lod) * color;
    m.rgb *= lerp(1, albedo, mainStr);
    m.rgb *= lerp(1, light, lighting);
    float a = m.a * LUMI_SAMPLE(mask, (uvMain) * maskST.xy + maskST.zw).r * lerp(1, lit, shadowMask);
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
    float3 col = acc * _GlitterColor.rgb * _GlitterColor.a * LUMI_SAMPLE(_GlitterMask, LUMI_TF(_GlitterMask, s.uvMain)).r;
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

// light reaching a rim: the ambient (SH / Light Volumes) along the rim normal plus the lights on that side,
// so a rim brightens and takes the colour of the side the environment light comes from
float3 LumiRimEnvLight(LumiGI gi, LumiCtx c, float3 mainColor, float3 N, float amount)
{
    if (amount <= 0.0) return c.litLight;
    float w = saturate(dot(N, c.toonDir) * 0.5 + 0.5);
    float3 l = LumiLimitLight((mainColor + gi.autoKey) * w + LumiGIIrradiance(gi, N));
    return lerp(c.litLight, l, amount);
}

// rim lights 1 / 2 / 3 and the offset rim, shared by the MitToon model and the URP / ray tracing models
// (lit: 1 on the lit side, for the shadow masks; *Emis: the emissive part, added with the emission)
float3 LumiRimLayers(float3 col, LumiSurface s, LumiInputData d, LumiCtx c, LumiGI gi, float3 mainColor, float lit, out float3 rimEmis)
{
    float2 uv = s.uvMain;
    // ---- Rim lights 1 / 2 / 3 (one keyword, each with its own switch)
    // the emissive part of each rim is collected here and added with the emission (glows the same in any world)
    rimEmis = 0;
#if defined(_LUMI_RIM) && !defined(_LUMI_COMPAT)
    [branch] if (_UseRim > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _RimNormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _RimFresnelPower), _RimBorder, _RimBlur);
        if (_RimMode > 0.5 && c.depthValidity > 0.5)
            r = LumiDepthRim(Nr, d.screenUV, d.eyeDepth, _RimDepthWidth, _RimDepthThreshold) * lerp(1, r, 0.25);
        r = LumiRimLightMask(r, Nr, c.toonDir, _RimLightDir, _RimShadowMask, _RimBackfaceMask, _RimLitSideOnly, _RimLitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_RimTex, LUMI_TF(_RimTex, uv));
        float3 rb = LumiRimHue(_RimColor.rgb, _RimHueSpeed) * rt.rgb * lerp(1, s.albedo, _RimMainStrength);
        float ra = saturate(r) * _RimColor.a * rt.a;
        col = LumiRimBlend(col, rb * lerp(1, LumiRimEnvLight(gi, c, mainColor, Nr, _RimEnvLight), _RimEnableLighting), ra * (1.0 - _RimEmission), _RimBlendMode);
        rimEmis += rb * (ra * _RimEmission * LumiRimBlink(_RimEmissionStrength, _RimBlink));
    }
    [branch] if (_UseRim2 > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _Rim2NormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _Rim2FresnelPower), _Rim2Border, _Rim2Blur);
        r = LumiRimLightMask(r, Nr, c.toonDir, _Rim2LightDir, _Rim2ShadowMask, _Rim2BackfaceMask, _Rim2LitSideOnly, _Rim2LitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_Rim2Tex, LUMI_TF(_Rim2Tex, uv));
        float3 rb = LumiRimHue(_Rim2Color.rgb, _Rim2HueSpeed) * rt.rgb * lerp(1, s.albedo, _Rim2MainStrength);
        float ra = saturate(r) * _Rim2Color.a * rt.a;
        col = LumiRimBlend(col, rb * lerp(1, LumiRimEnvLight(gi, c, mainColor, Nr, _Rim2EnvLight), _Rim2EnableLighting), ra * (1.0 - _Rim2Emission), _Rim2BlendMode);
        rimEmis += rb * (ra * _Rim2Emission * LumiRimBlink(_Rim2EmissionStrength, _Rim2Blink));
    }
    [branch] if (_UseRim3 > 0.5)
    {
        float3 Nr = normalize(lerp(s.Ng, s.N, _Rim3NormalStrength));
        float r = LumiSmoothBorder(pow(saturate(1.0 - dot(Nr, c.V)), _Rim3FresnelPower), _Rim3Border, _Rim3Blur);
        r = LumiRimLightMask(r, Nr, c.toonDir, _Rim3LightDir, _Rim3ShadowMask, _Rim3BackfaceMask, _Rim3LitSideOnly, _Rim3LitSideBlur, lit, d.facing);
        float4 rt = LUMI_SAMPLE(_Rim3Tex, LUMI_TF(_Rim3Tex, uv));
        float3 rb = LumiRimHue(_Rim3Color.rgb, _Rim3HueSpeed) * rt.rgb * lerp(1, s.albedo, _Rim3MainStrength);
        float ra = saturate(r) * _Rim3Color.a * rt.a;
        col = LumiRimBlend(col, rb * lerp(1, LumiRimEnvLight(gi, c, mainColor, Nr, _Rim3EnvLight), _Rim3EnableLighting), ra * (1.0 - _Rim3Emission), _Rim3BlendMode);
        rimEmis += rb * (ra * _Rim3Emission * LumiRimBlink(_Rim3EmissionStrength, _Rim3Blink));
    }
#endif
    return col;
}
float3 LumiOffsetRimLayer(float3 col, LumiSurface s, LumiInputData d, LumiCtx c, LumiGI gi, float3 mainColor, float3 mainLightColor, float lit, out float3 offRimEmis)
{
    offRimEmis = 0;
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
        // lit rim: lit by what reaches its side (lights + ambient SH / Light Volumes along the normal), split into
        // brightness (strongest channel) and hue, so the rim keeps its own brightness when only the colour is taken over
        float3 rc = baseC * _OffsetRimStrength * lerp(1, s.albedo, _OffsetRimAlbedo);
        float3 rl = LumiRimEnvLight(gi, c, mainColor, s.N, 1.0);
        float peak = max(rl.r, max(rl.g, rl.b));
        // the hue comes from the light before the body's colour reduction (dark worlds wash the ambient out for the
        // shading, a rim should still pick up the world's colour); near black it fades to white instead of noise
        float3 raw = mainLightColor * saturate(dot(s.N, c.toonDir) * 0.5 + 0.5) + LumiGIIrradianceRaw(gi, s.N);
        float rawPeak = max(raw.r, max(raw.g, raw.b));
        float3 hue = lerp(1.0, raw / max(rawPeak, 1e-4), saturate(rawPeak * 20.0));
        rc *= lerp(1, peak, _OffsetRimLightInfluence) * lerp(1, hue, _OffsetRimEnvInfluence);
        col += rc * (r * lerp(1, lit, _OffsetRimShadowMask) * _OffsetRimColor.a * (1.0 - _OffsetRimEmission));
        // emissive rim: glows the same in any world (added after world adaptation, like emission)
        float blink = sin(_Time.y * _OffsetRimBlink.y + _OffsetRimBlink.z) * 0.5 + 0.5;
        if (_OffsetRimBlink.w > 0.5) blink = step(0.5, blink);
        offRimEmis = baseC * lerp(1, s.albedo, _OffsetRimEmissionAlbedo) * (_OffsetRimEmissionStrength * r * _OffsetRimColor.a * _OffsetRimEmission)
                   * lerp(1, blink, _OffsetRimBlink.x);
    }
#endif
    return col;
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
    {
        // the world's light for shadows: the real light, else where the probes / scenery / point lights bring the most
        // light from (never the camera relative default key: a shadow must not turn with the view)
        float3 wh = gi.worldHint;
        wh.y = lerp(wh.y, abs(wh.y), _LightDirKeepUp);
        float3 wl = mainLight.direction * mainLum + wh;
        float wlen = length(wl);
        lumiWorldL = wlen > 1e-5 ? wl / wlen : float3(0, 1, 0);
        // how clearly it has a direction: 1 under a lamp or the sun, 0 under an even overcast
        lumiWorldConf = saturate(wlen / max(mainLum + LumiLuminance(gi.L0) * 0.5, 1e-4));
        lumiWorldMain = wlen > 1e-5 ? saturate(mainLum / wlen) : 0;
    }
    [branch] if (LumiRTLighting()) LumiRTSkySplit();
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
    aoMask = LUMI_SAMPLE(_SSAOMask, LUMI_TF(_SSAOMask, uv)).r;
#endif
    // normal map detail: sample around the bumped normal so small creases of the normal map also occlude
    float3 aoN = normalize(lerp(s.Ng, s.N, _SSAONormalStrength));
    lumiRTValidity = c.depthValidity;
    [branch] if (lumiFXUse)
    {
        c.ssao = lumiFX.x;   // blurred by the FX pass + grab
        lumiRTBounce = 0;
    }
    else
    {
        float aoIn = lumiRTAOIn;
        [branch] if (aoIn < 0.0)
        {
            c.ssao = LumiSSAO(d.posWS, aoN, d.eyeDepth, d.pixelPos, c.depthValidity, aoMask);
            // pseudo ray tracing: ray traced AO joins the SSAO
            float3 rtB;
            c.ssao *= LumiRTAO(d.posWS, aoN, d.eyeDepth, d.pixelPos, c.depthValidity, rtB);
        }
        else c.ssao = aoIn;   // (RayTrace composite pass: the main pass's AO, see LumiRTAOHandoff)
        {
            // the colour of what the rays hit bounces back (RayTrace shader)
        #if defined(LUMI_RAYTRACE_GRAB)
            float3 giD, giL, giC;
            LumiRTGI(d.posWS, aoN, d.eyeDepth, d.pixelPos, c.depthValidity, giD, giL, giC);
            lumiRTBounce = giD * (1.0 - _AsUnlit);
            lumiRTGIDir = giL;
            lumiRTGICol = giC * (1.0 - _AsUnlit);
        #endif
        }
        {
            // dots of the AO (the bounce comes smooth from the vertices: kept at full resolution; an AO handed over is
            // smoothed already)
            float aoSm = LumiQuadSmooth(c.ssao.xxxx, d.eyeDepth, d.pixelPos).x;
            c.ssao = aoIn < 0.0 ? aoSm : c.ssao;
        }
    }
    lumiFXOut.x = c.ssao;
    c.ssao = lerp(1.0, c.ssao, lerp(1.0, saturate(s.alpha), _SSAOAlphaInfluence));   // thin / see through parts occlude less
    // occlusion colour, optionally carrying the hue of the base colour (painted look)
    float3 hueA = min(s.albedo / max(dot(s.albedo, float3(0.2126, 0.7152, 0.0722)), 0.04), 3.0);
    float3 occCol = _SSAOColor.rgb * lerp(1.0.xxx, hueA, _SSAOAlbedoTint);
    c.aoColor = lerp(occCol, 1, c.ssao);
#if defined(_LUMI_RAYTRACE)
    {
        // pseudo ray tracing: occlusion the way light does it. In a gap the light still bounces between the walls, so
        // bright surfaces darken less and the occlusion takes their colour instead of grey (multi-bounce AO fit,
        // Jimenez et al. 2016)
        float3 alb = saturate(s.albedo);
        float3 ma = 2.0404 * alb - 0.3324, mb = -4.7951 * alb + 0.6417, mc = 2.7552 * alb + 0.6903;
        float ao = c.ssao;
        c.aoColor = lerp(c.aoColor, saturate(max(ao, ((ao * ma + mb) * ao + mc) * ao)), _RTAOMultiBounce);
    }
#endif
    float csMask = 1;
#if defined(_LUMI_CONTACTSHADOW)
    csMask = LUMI_SAMPLE(_ContactShadowMask, LUMI_TF(_ContactShadowMask, uv)).r;
#endif
    float contact = 1, rtSh = 1;
    // ray traced shadow along the real light (the toon light direction when the world has none)
    // (auto light direction: the world's light, so the shadow does not turn with the view like the default key can)
    // (ray tracing lighting without a real light: along the sky's main direction, which it shadows)
    float3 rtL = LumiLuminance(mainLight.color) > 1e-3 ? mainLight.direction
               : (LumiRTLighting() ? lumiSkyDir : (_LightDirMode < 0.5 ? lumiWorldL : c.toonDir));
#if !defined(LUMI_RT_COMPOSITE)   // (RayTrace composite pass: only the reflections / bounce are drawn, no shadow rays)
    [branch] if (lumiFXUse) contact = lumiFX.y;   // contact x ray traced shadow, blurred
    else
    {
        contact = LumiContactShadow(d.posWS, s.Ng, c.toonDir, d.eyeDepth, d.pixelPos, c.depthValidity, csMask);
        rtSh = LumiRTShadow(d.posWS, s.Ng, rtL, d.eyeDepth, d.pixelPos, c.depthValidity);
        // soft shadows module: shadow along the world's light (the shadow light cannot follow the world's light)
        [branch] if (_UsePCSS > 0.5 && _PCSSWorldLight > 0.5) rtSh *= LumiWorldShadow(d.posWS, s.Ng, d.eyeDepth, d.pixelPos, c.depthValidity);
        float2 q = LumiQuadSmooth(float4(contact, rtSh, 0, 0), d.eyeDepth, d.pixelPos).xy;
        contact = q.x; rtSh = q.y;
    }
#endif
    lumiFXOut.y = contact * rtSh;
#if defined(LUMI_FX_WRITE)
    return 0;   // FX pass: the terms are all it needs
#endif
    float castSh = mainLight.shadowAttenuation;
    if (_ShadowTerminatorFade > 0.001)
        castSh = lerp(1.0, castSh, smoothstep(0.0, _ShadowTerminatorFade, dot(s.Ng, mainLight.direction)));
    float extraSh = contact * LumiDepthTexShadow(c.toonDir, d.screenUV, d.eyeDepth, c.depthValidity) * rtSh;
    float shadow = castSh * extraSh;
    // eye shadow guard: eyelid / bang shadows, light angle shading and AO do not reach the inside of the eye
    float eyeG = LumiEyeGuard(uv);
    shadow = lerp(shadow, 1.0, eyeG * _EyeGuardShadow);
    // the cast shadow with contact / depth shadows and the eye guard, without MitToon's own terminator fade and
    // micro shadows: what the lilToon and URP shading models receive
    float shadowPlain = lerp(mainLight.shadowAttenuation * extraSh, 1.0, eyeG * _EyeGuardShadow);
    c.ssao = lerp(c.ssao, 1.0, eyeG * _EyeGuardAO);
    c.aoColor = lerp(c.aoColor, 1.0, eyeG * _EyeGuardAO);
    s.occlusion = lerp(s.occlusion, 1.0, eyeG * _EyeGuardAO);
    [branch] if (LUMI_URP_MODEL)
    {
        // URP shading model with MitToon's shadow extras: contact / depth shadows (along the real light),
        // the eye guard, the received shadow strength and SSAO
        LumiLight ml = mainLight;
        float cU = 1;
#if !defined(LUMI_RT_COMPOSITE)
        [branch] if (lumiFXUse) cU = lumiFX.y;
        else cU = LumiQuadSmooth(LumiContactShadow(d.posWS, s.Ng, ml.direction, d.eyeDepth, d.pixelPos, c.depthValidity, csMask).xxxx, d.eyeDepth, d.pixelPos).x;
#endif
        float exU = cU * LumiDepthTexShadow(ml.direction, d.screenUV, d.eyeDepth, c.depthValidity) * rtSh;
        ml.shadowAttenuation = lerp(1.0, lerp(ml.shadowAttenuation * exU, 1.0, eyeG * _EyeGuardShadow), _ReceiveShadowStrength);
        // ray tracing lighting: the sky's light is shadowed by the rays when there is no real light (they go along it)
        lumiSkyShadow = LumiLuminance(mainLight.color) > 1e-3 ? 1.0 : lerp(1.0, lerp(rtSh, 1.0, eyeG * _EyeGuardShadow), _ReceiveShadowStrength);
        c.litLight = ml.color; c.shadeLight = c.litLight; c.rampLit = 1;
        float3 urp = LumiURPShade(s, d, ml, lerp(1.0.xxx, c.aoColor, _SSAOAmbient), lerp(1.0.xxx, c.aoColor, _SSAODirect));
        {
            // rim lights and the offset rim on top (lit side: the light's step x its shadow)
            float bwU = max(_ShadowBlur, 0.02);
            float litU = smoothstep(_ShadowBorder - bwU, _ShadowBorder + bwU, dot(s.N, c.toonDir) * 0.5 + 0.5)
                       * (LumiLuminance(mainLight.color) > 1e-3 ? ml.shadowAttenuation : lumiSkyShadow);
            float3 rE, oE;
            urp = LumiRimLayers(urp, s, d, c, gi, mainColor, litU, rE);
            urp = LumiOffsetRimLayer(urp, s, d, c, gi, mainColor, mainLight.color, litU, oE);
            urp += rE + oE;
        }
        return float4(urp, s.alpha);
    }
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
        faceMask = LUMI_SAMPLE(_FaceSDFMask, LUMI_TF(_FaceSDFMask, uv)).r;
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
        // HSV saturation x k without the HSV round trip: keep the max channel (value), scale the distance to it. Done
        // on the colour as it is shown (gamma), like a paint tool: in linear values a colour that is already vivid
        // (blush, lips) has a far larger distance to its max channel and went almost pure red in the shade
        [branch] if (_RichShadowSaturation * shadeF > 1e-4)
        {
            float vmax = max(diffuse.r, max(diffuse.g, diffuse.b));
            float3 n = diffuse / max(vmax, 1e-6);
        #if !defined(UNITY_COLORSPACE_GAMMA)
            n = pow(saturate(n), 1.0 / 2.2);
        #endif
            n = saturate(1.0 - (1.0 - n) * (1.0 + _RichShadowSaturation * shadeF));
        #if !defined(UNITY_COLORSPACE_GAMMA)
            n = pow(n, 2.2);
        #endif
            diffuse = n * vmax;
        }
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
    float3 envP = LumiGIReflection(gi, R, d.posWS, s.perceptualRough);
    float3 env = LumiRTReflection(LumiLimitMax(envP), d.posWS, s.N, c.V, s.perceptualRough, d.eyeDepth, d.pixelPos, c.depthValidity);   // probe limited, ray hits up to _RTGIMaxBright
    float3 envBRDF = LumiEnvironmentBRDFMin(s.f0, s.metallic, s.perceptualRough, s.a2, c.NoV) * LumiEnergyCompensation(s.f0, s.perceptualRough, c.NoV);
    float fresG = 1.0 - c.NoV; fresG *= fresG * fresG;
    envBRDF *= 1.0 + _RichGloss * 2.0 * fresG * (1.0 - s.perceptualRough * 0.7);   // edge gloss
    float3 specEnv = env * envBRDF * specOcc * _EnvReflStrength;
    float3 giSpec = 0;
#if defined(LUMI_RAYTRACE_GRAB)
    {
        // highlight from the bounce light (bright / glowing things around): the same GGX as the main light
        float3 Lg = lumiRTGIDir, Hg = normalize(Lg + c.V);
        giSpec = LumiDirectSpecularMin(max(s.f0, 0.04), saturate(s.a2 + lumiRTGIA2), saturate(dot(s.N, Hg)), saturate(dot(Lg, Hg))) * saturate(dot(s.N, Lg)) * lumiRTGICol * specOcc;
    }
#endif
    lumiRTDelta = ((env - LumiLimitMax(envP)) * envBRDF * specOcc * _EnvReflStrength + giSpec) * s.specMask * (1.0 - _AsUnlit)
                + s.diffuseColor * lumiRTBounce;
    specEnv += LumiLightVolumeSpecular(s.f0, 1.0 - s.perceptualRough, s.N, c.V) * specOcc * _LVSpecular;
    [branch] if (_URPMixDiffuse + _URPMixSpecular > 0.001)
    {
        // the good parts of URP inside the MitToon model: lambert along the light + ambient along the normal (volume
        // that follows the shape), URP's energy conserving diffuse, its GGX highlight and its fresnel reflection.
        // Light colours stay MitToon's (limited, auto key light, MitToon GI), so nothing blows out.
        LumiURPBRDF ub = LumiURPInit(s);
        float3 dirU = LumiLimitMax(mainColor + gi.autoKey) * shadow * saturate(dot(s.N, L));
        float3 ambU = LumiLimitMax(max(irrN, _LightMinLimit.xxx) * _EnvLightStrength) * LumiMultiBounceAO(s.occlusion, ub.diffuse);
        float3 diffU = ub.diffuse * (dirU * aoDir + ambU * aoAmb);
        diffuse = lerp(diffuse, diffU * lerp(1.0, _EyeGuardBrightness, eyeG), _URPMixDiffuse);
        float fresU = 1.0 - c.NoV; fresU *= fresU; fresU *= fresU;
        float3 specU = LumiURPSpecularTerm(ub, s.N, c.V, L) * dirU;
        // the reflection probe as it is (URP), still under the light limit
        float3 envRaw = lerp(env, LumiLimitMax(LumiSampleEnvironment(R, d.posWS, s.perceptualRough, 0, 1)), _URPMixSpecular);
        float3 envU = envRaw * (lerp(ub.specular, ub.grazing.xxx, fresU) / (ub.rough2 + 1.0)) * specOcc * _EnvReflStrength;
        specDirect = lerp(specDirect, specU, _URPMixSpecular);
        specEnv = lerp(specEnv, envU, _URPMixSpecular);
    }
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
        float coat = _ClearCoat * LUMI_SAMPLE(_ClearCoatMask, LUMI_TF(_ClearCoatMask, uv)).r;
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
    col += s.diffuseColor * lumiRTBounce + giSpec * s.specMask * (1.0 - _AsUnlit);   // ray traced bounce light
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
    // (cast shadow with contact / depth shadows and the eye guard; SSAO like the MitToon model)
    col = LumiCompatShading(s, d, c.toonDir, mainLight.direction, c.litLight, compatInd, shadowPlain, true, lit);
    col = min(col, s.albedo * _LightMaxLimit);
    col *= lerp(aoAmb, aoDir, lit);
    col += s.albedo * LumiLimitMax(lumiRTBounce);
    lumiRTDelta = s.albedo * LumiLimitMax(lumiRTBounce);
    col = LumiCompatEffects(col, s, d, c.V, c.toonDir, mainLight.direction, c.litLight, lit, shadowPlain);
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
            float3 nb = LumiUnpackNormal(LUMI_SAMPLE(_MatCapBumpMap, LUMI_TF(_MatCapBumpMap, uv)), _MatCapBumpScale);
            Nm = normalize(s.T * nb.x + s.B * nb.y + s.N * nb.z);
        }
        float3 N1 = normalize(lerp(s.Ng, Nm, _MatCapNormalStrength));
        col = LumiApplyMatCap(col, _MatCapTex, _MatCapMask, _MatCapMask_ST, _MatCapColor, _MatCapBlend, _MatCapLod, _MatCapEnableLighting, _MatCapShadowMask,
                              _MatCapMainStrength, uv, LumiMatCapUV(N1, c.V, d.posWS, _MatCapPerspective, _MatCapZRotCancel), s.albedo, c.litLight, lit);
        if (_UseMatCap2 > 0.5)
        {
            float3 N2 = normalize(lerp(s.Ng, Nm, _MatCap2NormalStrength));
            col = LumiApplyMatCap(col, _MatCap2Tex, _MatCap2Mask, _MatCap2Mask_ST, _MatCap2Color, _MatCap2Blend, _MatCap2Lod, _MatCap2EnableLighting, _MatCap2ShadowMask,
                                  0, uv, LumiMatCapUV(N2, c.V, d.posWS, _MatCapPerspective, _MatCapZRotCancel), s.albedo, c.litLight, lit);
        }
    }
#endif

    // ---- Rim lights 1 / 2 / 3 (one keyword, each with its own switch)
    float3 rimEmis;
    col = LumiRimLayers(col, s, d, c, gi, mainColor, lit, rimEmis);

#if defined(_LUMI_GLITTER)
    col += LumiGlitter(s, d, c, normalize(c.toonDir + c.V));
#endif

#if defined(_LUMI_ANGELRING)
    {
        // procedural hair highlight ring: band of the normal's height (how much it points up), broken up along UV.x.
        // Measured against the world's up so the ring stays on the hair wherever the camera is; "view follow" blends
        // toward the camera's up (1 = the old view space ring, which slid over the hair as the camera moved / tilted)
        float3 nV = LumiWorldToViewDir(s.N);
        float3 upV = normalize(lerp(float3(0, 1, 0), UNITY_MATRIX_V[1].xyz, _AngelViewFollow) + float3(0, 1e-4, 0));
        float band = smoothstep(_AngelWidth, _AngelWidth * (1.0 - _AngelBlur), abs(dot(s.N, upV) - _AngelHeight));
        band *= saturate(nV.z * 2.0);
        float br = sin(d.uv0.x * _AngelFrequency * 6.2831853) * 0.5 + 0.5;
        br = lerp(br, LumiHash12(floor(d.uv0.x * _AngelFrequency).xx), 0.5);
        band *= lerp(1, smoothstep(0.25, 0.75, br), _AngelBreakup);
        col += _AngelColor.rgb * (_AngelColor.a * band) * lerp(1, c.litLight, _AngelLightInfluence) * lerp(1, lit, _AngelShadowMask) * s.specMask;
    }
#endif

    float3 offRimEmis;
    col = LumiOffsetRimLayer(col, s, d, c, gi, mainColor, mainLight.color, lit, offRimEmis);
    float2x3 et = LumiEdgeTint(s, d, lit);
    col = col * et[0] + et[1] * lerp(c.shadeLight, c.litLight, lit);   // glow: as much as the light reaching it

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

    col += s.emission + offRimEmis + rimEmis;

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
        else if (dv == 10)
        {
            // offset rim check (VR: compare the eyes): red = the depth texture does not match this surface (the rim
            // falls back to fresnel), green = the depth step the rim finds, blue tint = right eye
            float rr = 0;
#if defined(_LUMI_OFFSETRIM)
            rr = LumiOffsetRim(s.N, c.toonDir, d.screenUV, d.eyeDepth, c.NoV, 1.0);
#endif
#if defined(USING_STEREO_MATRICES)
            float eye = (float)unity_StereoEyeIndex;
#else
            float eye = 0;
#endif
            col = float3(1.0 - c.depthValidity, saturate(rr), 0.35 * eye);
        }
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
