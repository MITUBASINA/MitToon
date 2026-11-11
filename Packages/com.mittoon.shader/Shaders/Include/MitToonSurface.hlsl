// MitToon Shader - surface construction (pipeline independent, needs a Platform file included first)
#ifndef MITTOON_SURFACE_INCLUDED
#define MITTOON_SURFACE_INCLUDED

#include "MitToonCommon.hlsl"
#include "MitToonBRDF.hlsl"

struct LumiInputData
{
    float2 uv0;
    float2 uv1;
    float3 posWS;
    float3 posOS;
    float3 normalWS;     // interpolated, not normalized
    float4 tangentWS;    // w = sign
    float3 viewDirWS;    // normalized, surface -> camera
    float4 color;
    float2 screenUV;
    float2 pixelPos;
    float  eyeDepth;
    float  facing;       // 1 front / -1 back
};

struct LumiSurface
{
    float3 albedo;
    float  alpha;
    float3 N;            // shading normal
    float3 Ng;           // geometric normal
    float3 T;
    float3 B;
    float  metallic;
    float  perceptualRough;
    float  a2;           // GGX alpha^2 (after spec AA)
    float  occlusion;
    float3 diffuseColor;
    float3 f0;
    float  shadowStrengthMask;
    // shadow colour = shadowFlat + base colour * shadowMul (see the toon shadow inputs below)
    float3 shadowFlat1, shadowMul1;
    float3 shadowFlat2, shadowMul2;
    float  sssMask;
    float  thickness;
    float2 uvMain;
    float3 emission;
    float  specMask;
    float  shadowOffset;
    float  rampRow;
};

float2 LumiSelectUV(LumiInputData d, float ch) { return ch < 0.5 ? d.uv0 : d.uv1; }

static float3 lumiFlipEmis = 0;
// sprite sheet animation (texture sheet frames, auto or animator driven)
// Cutout alpha, always read from the full resolution mip. Smaller mips average the alpha with the transparent
// texels around it, so the cut out area would grow / shrink with distance and viewing angle. At mip 0 the
// clipped area is fixed on the texture: the same from any distance and angle, in every pass (color, outline, shadow).
float LumiCutoutAlpha(float2 uv)
{
    float a = _MainTex.SampleLevel(sampler_MainTex, uv, 0).a * _Color.a;
    float am = _AlphaMask.SampleLevel(sampler_MainTex, uv, 0).r;
    if (_AlphaMaskMode == 1) a = am;
    else if (_AlphaMaskMode == 2) a *= am;
    return saturate(a + _AlphaMaskValue);
}
// Cutout test. Alpha To Coverage on: the alpha is turned into a one pixel wide ramp around the cutoff
// ((a - cutoff) / fwidth(a) + 0.5) and written as coverage, so the edge is anti-aliased and only fully outside
// pixels are discarded. Off: a plain test against the cutoff. Returns the alpha to output.
float LumiCutoutClip(float2 uv)
{
    float a = LumiCutoutAlpha(uv);
    if (_AlphaToMask < 0.5)
    {
        clip(a - _Cutoff);
        return 1.0;
    }
    float cov = saturate((a - _Cutoff) / max(fwidth(a), 0.0001) + 0.5);
    if (cov <= 0.0) discard;
    return cov;
}

void LumiApplyFlipbook(LumiInputData d, inout float4 col)
{
    if (_UseFlipbook < 0.5) return;
    float2 uvB = LumiSelectUV(d, _FlipbookUV) * _FlipbookTex_ST.xy + _FlipbookTex_ST.zw;
    float inside = _FlipbookClamp > 0.5 ? step(0, uvB.x) * step(uvB.x, 1) * step(0, uvB.y) * step(uvB.y, 1) : 1;
    float2 cuv = _FlipbookClamp > 0.5 ? saturate(uvB) : frac(uvB);
    float cols = max(1, floor(_FlipbookGrid.x)), rows = max(1, floor(_FlipbookGrid.y));
    float n = clamp(floor(_FlipbookGrid.z), 1, cols * rows);
    float f = _FlipbookFrame >= 0 ? _FlipbookFrame : _Time.y * _FlipbookGrid.w;
    float fi = floor(f), f0 = fi - floor((fi + 0.5) / n) * n, f1 = f0 + 1 >= n ? 0 : f0 + 1;   // whole numbers only, no fmod rounding
    float2 cell = float2(cols, rows);
    float2 dx = ddx(uvB) / cell, dy = ddy(uvB) / cell;
    // cell from the frame index with +0.5 so the GPU division (rcp * mul) never lands just below a whole row
    float r0 = floor((f0 + 0.5) / cols), r1 = floor((f1 + 0.5) / cols);
    float2 uv0 = (float2(f0 - r0 * cols, rows - 1 - r0) + cuv) / cell;
    float2 uv1 = (float2(f1 - r1 * cols, rows - 1 - r1) + cuv) / cell;
    float4 fb = _FlipbookTex.SampleGrad(sampler_MainTex, uv0, dx, dy);
    float4 fbN = _FlipbookTex.SampleGrad(sampler_MainTex, uv1, dx, dy);
    fb = lerp(fb, fbN, frac(f) * _FlipbookBlend) * _FlipbookColor;
    float a = fb.a * inside;
    if (_FlipbookMode < 0.5)      col.rgb = lerp(col.rgb, fb.rgb, a);
    else if (_FlipbookMode < 1.5) col.rgb *= lerp(1.0.xxx, fb.rgb, a);
    else if (_FlipbookMode < 2.5) col.rgb += fb.rgb * a;
    else                          lumiFlipEmis = fb.rgb * a;
}

// ---- Parallax ---------------------------------------------------------------
float2 LumiParallax(float2 uv, float3 viewTS)
{
    float2 res = uv;
#if defined(_LUMI_PARALLAX)
    viewTS = normalize(viewTS);
    [branch] if (_ParallaxMode < 0.5)
    {
        float h0 = LUMI_SAMPLE(_ParallaxMap, uv).g - 0.5;
        res = uv + h0 * _Parallax * viewTS.xy / (viewTS.z + 0.42);
    }
    else
    {
        // parallax occlusion mapping
        int steps = (int)clamp(_ParallaxSteps, 4, 64);
        float stepSize = 1.0 / steps;
        float2 delta = viewTS.xy / max(viewTS.z, 0.1) * _Parallax * stepSize;
        float2 cur = uv;
        float layer = 1.0;
        float h = LUMI_SAMPLE_LOD(_ParallaxMap, cur, 0).g;
        float prevH = h, prevLayer = layer;
        [loop] for (int i = 0; i < steps && h < layer; i++)
        {
            prevH = h; prevLayer = layer;
            cur += delta;
            layer -= stepSize;
            h = LUMI_SAMPLE_LOD(_ParallaxMap, cur, 0).g;
        }
        float a = h - layer, b = prevH - prevLayer;
        float w = a / min(a - b, -1e-5);
        res = lerp(cur, cur - delta, saturate(w));
    }
#endif
    return res;
}

// ---- Color layers -------------------------------------------------------------
float4 LumiSampleLayer(Texture2D tex, Texture2D mask, float4 st, float4 scroll, float decal, float2 uv)
{
    float2 luv = uv * st.xy + st.zw + scroll.xy * _Time.y;
    luv = LumiRotateUV(luv, scroll.z);
    float4 c = decal > 0.5 ? tex.Sample(sampler_linear_clamp, luv) : tex.Sample(sampler_trilinear_repeat, luv);
    if (decal > 0.5 && any(abs(luv - 0.5) > 0.5)) c.a = 0;
    c.a *= LUMI_SAMPLE(mask, uv).r;
    return c;
}

void LumiApplyDissolve(LumiInputData d, inout LumiSurface s)
{
#if defined(_LUMI_DISSOLVE)
    float v;
    if (_DissolveMode < 0.5)      v = _DissolveNoise.Sample(sampler_trilinear_repeat, d.uv0 * _DissolveNoise_ST.xy + _DissolveNoise_ST.zw).r;
    else if (_DissolveMode < 1.5) v = d.uv0.y;
    else                          v = LumiRemap(d.posOS.y, _DissolveHeightRange.x, _DissolveHeightRange.y);
    float t = _DissolveAmount * (1.0 + _DissolveEdgeWidth);
    if (_DissolveAmount > 0) clip(v - t);
    float edge = (t > 1e-4) ? 1.0 - saturate((v - t) / max(_DissolveEdgeWidth, 1e-4)) : 0;
    s.emission += edge * _DissolveEdgeColor.rgb;
#endif
}

// Rainbow: replaces the hue of the emission, keeping its brightness. rb = (amount, cycles per second, repeats, mode)
// mode 0 whole surface, 1 UV horizontal, 2 UV vertical, 3 object height, 4 rings from the UV centre
float3 LumiEmissionRainbow(float3 em, float4 rb, float2 uv, float3 posOS)
{
    [branch] if (rb.x > 0.001)
    {
        float m = rb.w;
        float coord = m < 0.5 ? 0.0 : m < 1.5 ? uv.x : m < 2.5 ? uv.y : m < 3.5 ? posOS.y : length(uv - 0.5) * 2.0;
        float3 rainbow = LumiHSV2RGB(float3(frac(_Time.y * rb.y + coord * rb.z), 1.0, 1.0));
        em = lerp(em, rainbow * max(em.r, max(em.g, em.b)), rb.x);
    }
    return em;
}

// AudioLink multiplier for one emission slot. al = (band, strength, minimum, delay); 1 without an AudioLink world
float LumiAudioLinkMul(float4 al, float2 uv0)
{
    float m = 1.0;
#if defined(_LUMI_AUDIOLINK)
    if (_AudioTexture_TexelSize.z > 16)
    {
        int x = (int)(saturate(uv0.x) * al.w * 127.0);
        float v = _AudioTexture.Load(int3(x, (int)al.x, 0)).r;
        m = lerp(al.z, 1.0, v) * al.y;
    }
#endif
    return m;
}

float3 LumiEmissionLayer(LumiInputData d, Texture2D map, Texture2D mask, float4 st, float4 color, float uvCh, float4 scroll, float4 blink, float4 rb)
{
    float2 uvBase = LumiSelectUV(d, uvCh);
    float2 uv = uvBase * st.xy + st.zw + scroll.xy * _Time.y;
    float4 em = map.Sample(sampler_trilinear_repeat, uv) * color;
    float blinkS = sin(_Time.y * blink.y + blink.z) * 0.5 + 0.5;
    if (blink.w > 0.5) blinkS = step(0.5, blinkS);
    em.rgb *= lerp(1, blinkS, blink.x) * LUMI_SAMPLE(mask, d.uv0).r;
    em.rgb = LumiEmissionRainbow(em.rgb, rb, uvBase, d.posOS);
    return em.rgb * em.a;
}

// four independent emission slots; the keyword is on when any of them is
float3 LumiSampleEmission(LumiInputData d, LumiSurface s)
{
    float3 e = 0;
#if defined(_LUMI_EMISSION)
    [branch] if (_UseEmission > 0.5)
    {
        float2 uv = d.uv0 * _EmissionMap_ST.xy + _EmissionMap_ST.zw + _EmissionScroll.xy * _Time.y;
        float4 em = _EmissionMap.Sample(sampler_trilinear_repeat, uv) * _EmissionColor;
        float blinkS = sin(_Time.y * _EmissionBlink.y + _EmissionBlink.z) * 0.5 + 0.5;
        if (_EmissionBlink.w > 0.5) blinkS = step(0.5, blinkS);
        em.rgb *= lerp(1, blinkS, _EmissionBlink.x) * LUMI_SAMPLE(_EmissionMask, d.uv0).r;
        em.rgb *= lerp(1, s.albedo, _EmissionMainStrength);
        em.rgb = LumiEmissionRainbow(em.rgb, float4(_EmissionRainbow, _EmissionRainbowSpeed, _EmissionRainbowScale, _EmissionRainbowMode), d.uv0, d.posOS);
        float3 e1 = em.rgb * em.a;
        if (_UseAudioLink > 0.5) e1 *= LumiAudioLinkMul(float4(_AudioLinkBand, _AudioLinkStrength, _AudioLinkMin, _AudioLinkDelay), d.uv0);
        e += e1;
    }
    [branch] if (_UseEmission2 > 0.5)
    {
        float3 e2 = LumiEmissionLayer(d, _Emission2Map, _Emission2Mask, _Emission2Map_ST, _Emission2Color, _Emission2UV, _Emission2Scroll, _Emission2Blink,
                                      float4(_Emission2Rainbow, _Emission2RainbowSpeed, _Emission2RainbowScale, _Emission2RainbowMode));
        if (_Emission2AudioLink > 0.5) e2 *= LumiAudioLinkMul(float4(_Emission2ALBand, _Emission2ALStrength, _Emission2ALMin, _Emission2ALDelay), d.uv0);
        e += e2;
    }
    [branch] if (_UseEmission3 > 0.5)
    {
        float3 e3 = LumiEmissionLayer(d, _Emission3Map, _Emission3Mask, _Emission3Map_ST, _Emission3Color, _Emission3UV, _Emission3Scroll, _Emission3Blink,
                                      float4(_Emission3Rainbow, _Emission3RainbowSpeed, _Emission3RainbowScale, _Emission3RainbowMode));
        if (_Emission3AudioLink > 0.5) e3 *= LumiAudioLinkMul(float4(_Emission3ALBand, _Emission3ALStrength, _Emission3ALMin, _Emission3ALDelay), d.uv0);
        e += e3;
    }
    [branch] if (_UseEmission4 > 0.5)
    {
        float3 e4 = LumiEmissionLayer(d, _Emission4Map, _Emission4Mask, _Emission4Map_ST, _Emission4Color, _Emission4UV, _Emission4Scroll, _Emission4Blink,
                                      float4(_Emission4Rainbow, _Emission4RainbowSpeed, _Emission4RainbowScale, _Emission4RainbowMode));
        if (_Emission4AudioLink > 0.5) e4 *= LumiAudioLinkMul(float4(_Emission4ALBand, _Emission4ALStrength, _Emission4ALMin, _Emission4ALDelay), d.uv0);
        e += e4;
    }
#endif
    return e;
}

LumiSurface LumiInitSurface(LumiInputData d)
{
    LumiSurface s = (LumiSurface)0;

    // back faces turn the normal toward the camera unless "Flip Backface Normal" is off (then they keep the front's normal)
    float nf = (d.facing < 0 && _BackfaceFlipNormal > 0.5) ? -1 : 1;
    float3 Ng = normalize(d.normalWS) * nf;
    float3 T = normalize(d.tangentWS.xyz - Ng * dot(Ng, d.tangentWS.xyz));
    float3 B = cross(Ng, T) * d.tangentWS.w * nf;
    if (any(isnan(T)) || dot(d.tangentWS.xyz, d.tangentWS.xyz) < 1e-6)
    {
        T = normalize(cross(Ng, abs(Ng.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
        B = cross(Ng, T);
    }

    // ---- UV / parallax
    float2 uv = d.uv0 * _MainTex_ST.xy + _MainTex_ST.zw + _MainScroll.xy * _Time.y;
    uv = LumiRotateUV(uv, _MainScroll.z);
#if defined(_LUMI_PARALLAX)
    float3 viewTS = float3(dot(d.viewDirWS, T), dot(d.viewDirWS, B), dot(d.viewDirWS, Ng));
    uv = LumiParallax(uv, viewTS);
#endif
    if (_EyeParallax > 0.0001 && _UseEyeGuard > 0.5)
    {
        // iris depth: the pupil / iris sits behind the cornea, so it shifts against the view like a real eye
        float3 vts = float3(dot(d.viewDirWS, T), dot(d.viewDirWS, B), dot(d.viewDirWS, Ng));
        float em = LUMI_SAMPLE(_EyeParallaxMask, uv).r;
        uv -= vts.xy / max(vts.z, 0.25) * (_EyeParallax * em);
    }
    s.uvMain = uv;

    // ---- Base color
#if defined(_LUMI_COMPAT)
    // compatible: tone correction on the texture before the colour, with the source shader's formula
    float4 col = _MainTex.SampleBias(sampler_MainTex, uv, _QMipBias);
    col.rgb = lerp(col.rgb, LumiCompatTone(col.rgb, _MainTexHSVG), LUMI_SAMPLE(_MainColorAdjustMask, uv).r);
    col *= _Color;
#else
    float4 col = _MainTex.SampleBias(sampler_MainTex, uv, _QMipBias) * _Color;   // slight negative bias: sharper in VR
#endif
    if (_QSharpen > 0.001)
    {
        // local contrast: difference to a blurred (higher mip) version brings out painted detail without halos
        float3 blurC = _MainTex.SampleBias(sampler_MainTex, uv, _QMipBias + 2.0).rgb * _Color.rgb;
        col.rgb = max(col.rgb + (col.rgb - blurC) * (_QSharpen * 1.5), 0);
    }
#if !defined(_LUMI_COMPAT)
    col.rgb = lerp(col.rgb, LumiApplyHSVG(col.rgb, _MainTexHSVG), LUMI_SAMPLE(_MainColorAdjustMask, uv).r);
#endif
    if (_UseVertexColor > 0.5) col *= d.color;
#if !defined(_LUMI_COMPAT)   // compatible mode: applied over the lit colour instead
    if (_BackfaceColor.a > 0.001)
    {
        // inside of skirts / sleeves / hair: own colour or texture on back faces
        float3 bf = LUMI_SAMPLE(_BackfaceTex, uv).rgb * _BackfaceColor.rgb * lerp(1.0.xxx, col.rgb, _BackfaceMainBlend);
        col.rgb = lerp(col.rgb, bf, _BackfaceColor.a * step(d.facing, 0));
    }
#endif
    LumiApplyFlipbook(d, col);

#if defined(_LUMI_LAYER)
    if (_UseMain2 > 0.5)
    {
        float4 l = LumiSampleLayer(_Main2Tex, _Main2Mask, _Main2Tex_ST, _Main2Scroll, _Main2Decal, LumiSelectUV(d, _Main2UV)) * _Main2Color;
        col.rgb = LumiBlend(col.rgb, l.rgb, l.a, _Main2Blend);
    }
    if (_UseMain3 > 0.5)
    {
        float4 l = LumiSampleLayer(_Main3Tex, _Main3Mask, _Main3Tex_ST, _Main3Scroll, _Main3Decal, LumiSelectUV(d, _Main3UV)) * _Main3Color;
        col.rgb = LumiBlend(col.rgb, l.rgb, l.a, _Main3Blend);
    }
#endif

#if defined(_LUMI_DETAIL)
    float detailMask = LUMI_SAMPLE(_DetailMask, uv).r;
    float2 duv = LumiSelectUV(d, _DetailUV) * _DetailAlbedoMap_ST.xy + _DetailAlbedoMap_ST.zw;
    float3 detailAlbedo = _DetailAlbedoMap.Sample(sampler_trilinear_repeat, duv).rgb * 2.0; // 0.5 grey = neutral
    col.rgb *= lerp(1, detailAlbedo, detailMask * _DetailAlbedoScale);
#endif

#if defined(_LUMI_GRADIENT)
    {
        // height gradient + view dependent hue shift (no textures)
        float h = _GradSpace < 0.5 ? d.posOS.y : (_GradSpace < 1.5 ? d.posWS.y : d.uv0.y);
        float t = LumiRemap(h, _GradRange.x, _GradRange.y);
        float4 g = lerp(_GradBottom, _GradTop, t);
        col.rgb = LumiBlend(col.rgb, g.rgb, g.a * _GradStrength, _GradBlend);
        if (abs(_ViewHueShift) > 1e-4)
        {
            float3 hsv = LumiRGB2HSV(col.rgb);
            float f = 1.0 - saturate(dot(normalize(d.normalWS), d.viewDirWS));
            hsv.x = frac(hsv.x + _ViewHueShift * f * f);
            col.rgb = LumiHSV2RGB(hsv);
        }
    }
#endif

    // ---- Alpha
    float am = LUMI_SAMPLE(_AlphaMask, uv).r;
    if (_AlphaMaskMode == 1) col.a = am;
    else if (_AlphaMaskMode == 2) col.a *= am;
    col.a = saturate(col.a + _AlphaMaskValue);
#if defined(_ALPHATEST_ON)
    col.a = LumiCutoutClip(uv);
#endif
    s.albedo = col.rgb;
    s.alpha = col.a;

    // ---- Normal
    float3 nTS = float3(0, 0, 1);
#if defined(_LUMI_NORMALMAP)
    nTS = LumiUnpackNormal(_BumpMap.SampleBias(sampler_MainTex, uv, _QMipBias), _BumpScale * LUMI_SAMPLE(_BumpMask, d.uv0).r);
    if (_UseBump2 > 0.5)
    {
        float3 n2 = LumiUnpackNormal(_Bump2Map.Sample(sampler_trilinear_repeat, d.uv0 * _Bump2Map_ST.xy + _Bump2Map_ST.zw), _Bump2Scale * LUMI_SAMPLE(_Bump2Mask, uv).r);
        nTS = LumiBlendNormalRNM(nTS, n2);
    }
#endif
#if defined(_LUMI_DETAIL)
    float3 dn = LumiUnpackNormal(_DetailNormalMap.Sample(sampler_trilinear_repeat, duv), _DetailNormalScale * detailMask);
    nTS = LumiBlendNormalRNM(nTS, dn);
#endif
    if (_QNormalFadeDist > 0.01)
    {
        // far away the normal map turns into shimmering noise: fade it out
        float nf = 1.0 - saturate((d.eyeDepth - _QNormalFadeDist) / _QNormalFadeDist);
        nTS = normalize(lerp(float3(0, 0, 1), nTS, nf));
    }
    s.N = normalize(T * nTS.x + B * nTS.y + Ng * nTS.z);
    s.Ng = Ng;
    s.T = normalize(T - s.N * dot(T, s.N));
    s.B = cross(s.N, s.T) * (d.tangentWS.w < 0 ? -1 : 1);

    // ---- PBR maps
    float metallic = _Metallic, smooth = _Smoothness, ao = 1;
    if (_PBRMapMode < 0.5)
    {
        metallic *= LUMI_SAMPLE(_MetallicMap, uv).r;
        float sm = LUMI_SAMPLE(_SmoothnessMap, uv).r;
        smooth *= _SmoothnessIsRoughness > 0.5 ? 1.0 - sm : sm;
        ao = LUMI_SAMPLE(_OcclusionMap, uv).g;
    }
    else
    {
        float4 m = LUMI_SAMPLE(_MaskMap, uv);
        if (_PBRMapMode < 1.5) { metallic *= m.r; ao = m.g; smooth *= m.a; }       // mask map (MAOS)
        else                   { ao = m.r; smooth *= 1.0 - m.g; metallic *= m.b; } // packed ORM
    }
    // wetness: porous darkening + glossier surface
    float wet = _Wetness * LUMI_SAMPLE(_WetnessMask, uv).r;
    s.albedo *= lerp(1.0, 0.55 + 0.25 * s.albedo, wet * (1.0 - saturate(metallic)));
    smooth = lerp(smooth, max(smooth, 0.93), wet);
    ao = lerp(ao, 1.0, wet * 0.3);
    s.metallic = saturate(metallic);
    s.perceptualRough = clamp(1.0 - smooth, 0.02, 1.0);
    float a = s.perceptualRough * s.perceptualRough;
    s.a2 = LumiSpecularAA(s.N, max(a * a, 1e-4), _SpecAA, _SpecAAThreshold);
    s.occlusion = lerp(1, ao, _OcclusionStrength);

    float dielectricF0 = 0.16 * _Reflectance * _Reflectance;
    s.f0 = lerp(dielectricF0.xxx, s.albedo, s.metallic);
    s.diffuseColor = s.albedo * (1.0 - s.metallic);

    // ILM / light map (game style): R spec intensity, G shadow threshold (0.5 neutral), B spec mask, A ramp row
    s.specMask = LUMI_SAMPLE(_SpecularMask, uv).r;
    s.shadowOffset = 0;
    s.rampRow = _ShadowRampRow;
    if (_UseILM > 0.5)
    {
        float4 ilm = LUMI_SAMPLE(_ILMMap, uv);
        s.specMask *= ilm.b * (ilm.r * 2.0);
        s.shadowOffset = ilm.g - 0.5;
        s.rampRow = ilm.a;
    }

    // ---- Toon shadow inputs
    s.shadowStrengthMask = LUMI_SAMPLE(_ShadowMaskTex, uv).r;
    // Shadow textures: transparent / unset (default black, A=0) = the main texture colour times the shadow colour,
    // so the shadow always follows the texture. Painted (A=1) = the painted colour, multiplied with the main
    // texture by Main Strength. Same as the common toon convention, so switched materials keep their look.
    float4 st1 = LUMI_SAMPLE(_ShadowColorTex, uv);
    float4 st2 = LUMI_SAMPLE(_Shadow2ndColorTex, uv);
    s.shadowFlat1 = _ShadowColor.rgb * st1.rgb * st1.a * (1.0 - _ShadowMainStrength);
    s.shadowMul1  = _ShadowColor.rgb * ((1.0 - st1.a) + st1.rgb * st1.a * _ShadowMainStrength);
    s.shadowFlat2 = _Shadow2ndColor.rgb * st2.rgb * st2.a * (1.0 - _ShadowMainStrength);
    s.shadowMul2  = _Shadow2ndColor.rgb * ((1.0 - st2.a) + st2.rgb * st2.a * _ShadowMainStrength);
    if (_AutoShadowColor > 0.001)
    {
        // painter's shadow colour from the albedo: hue leans red on warm colours (skin keeps its blood colour) and
        // toward violet on cool / neutral ones, saturation rises, value drops. No shadow colour texture needed.
        float3 hsv = LumiRGB2HSV(s.albedo);
        float warm = (hsv.x < 0.14 || hsv.x > 0.92) ? 1.0 : 0.0;
        float target = warm > 0.5 ? 0.0 : 0.72;
        float dh = frac(target - hsv.x + 0.5) - 0.5;
        float3 t1 = float3(frac(hsv.x + clamp(dh, -_AutoShadowHue, _AutoShadowHue)), saturate(hsv.y * 1.25 + 0.06), hsv.z * _AutoShadowDarkness);
        float3 t2 = float3(frac(hsv.x + clamp(dh, -_AutoShadowHue * 1.6, _AutoShadowHue * 1.6)), saturate(hsv.y * 1.4 + 0.1), hsv.z * _AutoShadowDarkness * _AutoShadowDarkness);
        float3 a1 = LumiHSV2RGB(t1), a2 = LumiHSV2RGB(t2);
        // the picked colours are final shadow colours (flat part, no extra multiply)
        s.shadowFlat1 = lerp(s.shadowFlat1, a1, _AutoShadowColor); s.shadowMul1 *= 1.0 - _AutoShadowColor;
        s.shadowFlat2 = lerp(s.shadowFlat2, a2, _AutoShadowColor); s.shadowMul2 *= 1.0 - _AutoShadowColor;
    }

#if defined(_LUMI_SSS)
    float2 sssm = LUMI_SAMPLE(_SSSMap, uv).rg;
    s.sssMask = sssm.r * _SSSStrength;
    s.thickness = sssm.g;
#endif

    s.emission = LumiSampleEmission(d, s) + lumiFlipEmis;
    LumiApplyDissolve(d, s);
    return s;
}

#endif
