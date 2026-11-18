// MitToon Shader - per pixel screen space effects using the camera depth texture (no post process needed)
// Requires: LumiSampleSceneEyeDepth, LumiDepthTextureAvailable, LumiWorldToClip, LumiComputeScreenPos (Platform file)
#ifndef MITTOON_SCREENSPACE_INCLUDED
#define MITTOON_SCREENSPACE_INCLUDED

#include "MitToonCommon.hlsl"

// ---- Sample rotation (2x2 quad) ---------------------------------------------------------------------------------
// The screen space effects take few samples per pixel. The 4 pixels of each 2x2 quad turn their samples by 4 evenly
// spaced amounts and the results are averaged over the quad through the fine screen derivatives: 4 times the samples
// for free, and no random dots (the same pattern everywhere, a continuous result). Neighbours at another depth are left
// out (no halo). The Blur setting smooths the rest. (posWS / radiusM / seed: kept for the call sites, unused.)
float LumiSSNoise(float2 pixel, float3 posWS, float radiusM, float seed)
{
    float2 p = fmod(floor(pixel), 2.0);
    return frac(0.5 + p.x * 0.25 + p.y * 0.5);
}
#if defined(SHADER_API_D3D11) || defined(SHADER_API_VULKAN) || defined(SHADER_API_METAL) || defined(SHADER_API_GLCORE)
    #define LUMI_DDX(v) ddx_fine(v)
    #define LUMI_DDY(v) ddy_fine(v)
#else
    #define LUMI_DDX(v) ddx(v)
    #define LUMI_DDY(v) ddy(v)
#endif
// call in uniform control flow (not inside a per pixel branch)
float4 LumiQuadSmooth(float4 v, float z, float2 pixel)
{
    float2 sg = 1.0 - 2.0 * fmod(floor(pixel), 2.0);   // +1: the quad neighbour is right / below, -1: left / above
    float tol = 0.004 + z * 0.015;
    float4 vx = v + LUMI_DDX(v) * sg.x;
    float wx = saturate(1.0 - abs(LUMI_DDX(z)) / tol);
    float4 h = (v + vx * wx) / (1.0 + wx);
    float4 hy = h + LUMI_DDY(h) * sg.y;
    float wy = saturate(1.0 - abs(LUMI_DDY(z)) / tol);
    float4 a = (h + hy * wy) / (1.0 + wy);
    return a;
}

// 1 when a depth texture is bound. The depth of this very pixel is NOT compared with our own depth: in the VRChat
// main view and in mirrors the depth texture can be rendered at another resolution / with another camera setup, so
// such a check switched the effects off there although the depth was usable.
// 1 when the depth texture really belongs to this camera: it must hold our own surface at our pixel.
// Cameras that do not make one (VRChat avatar previews, some mirrors / stream cameras) can still see the depth texture
// of another camera; reading it would put rims, AO and contact shadows in random places (white wash, colored fringes).
float LumiDepthValidity(float2 screenUV, float eyeDepth)
{
    if (!LumiDepthTextureAvailable()) return 0;
    float tol = 0.03 * lumiAvatarScale + eyeDepth * 0.03;
    return 1.0 - smoothstep(tol, tol * 2.0, abs(LumiSampleSceneEyeDepth(screenUV) - eyeDepth));
}

// Eye depth our own flat surface (normal nV, view space) would have at another screen UV: exact ray / plane
// intersection, so slopes are not mistaken for depth jumps. Works with asymmetric (VR) and oblique (mirror) frustums.
float LumiPlaneDepth(float3 nV, float2 uv0, float D0, float2 uvS)
{
    float4x4 P = UNITY_MATRIX_P;
    if (P._m33 != 0.0) return D0;   // orthographic
    float2 n0 = float2(uv0.x * 2.0 - 1.0, (uv0.y * 2.0 - 1.0) * _ProjectionParams.x);
    float2 nS = float2(uvS.x * 2.0 - 1.0, (uvS.y * 2.0 - 1.0) * _ProjectionParams.x);
    float3 P0 = float3((n0.x + P._m02) / P._m00, (n0.y + P._m12) / P._m11, -1.0) * D0;
    float3 dir = float3((nS.x + P._m02) / P._m00, (nS.y + P._m12) / P._m11, -1.0);
    float den = dot(nV, dir);
    if (abs(den) < 0.05) return D0;
    float D = dot(nV, P0) / den;
    return D > 0.0 ? D : D0;
}

float2 LumiWorldToScreenUV(float3 posWS, out float eyeDepth)
{
    float4 cs = LumiWorldToClip(posWS);
    float4 sp = LumiComputeScreenPos(cs);
    eyeDepth = cs.w;
    return sp.xy / sp.w;
}

// Normal oriented hemisphere SSAO. returns visibility (1 = unoccluded)
// returns visibility (1 = unoccluded). mask = SSAO mask value (1 = full effect).
// With the default settings this is exactly the original hemisphere SSAO; every extra setting is neutral at its default.
float LumiSSAOPass(float3 posWS, float3 N, float3 t, float3 b, float2 uv0, float3 nV, float eyeDepth,
                   float R, float noise, int n, float softD, float softH, float pixPerM)
{
    float rot = noise * 6.2831853;
    float fall = 1.0 / max(1.0 - _SSAOFalloff, 1e-3);
    float occ = 0, cnt = 0;
    [loop] for (int i = 0; i < n; i++)
    {
        float fi = (i + 0.5) / n;
        float phi = i * 2.3999632 + rot;
        float r = sqrt(fi);
        float h = sqrt(1.0 - fi);
        float s, c; sincos(phi, s, c);
        float len = frac(fi * 7.31 + noise);
        len = lerp(0.1, 1.0, len * len);
        float o;
        [branch] if (_SSAOMethod < 0.5)
        {
            // horizon: scene depth against our own tangent plane, height over screen distance = horizon slope
            float rp = max(len * R * 0.6 * pixPerM, 1.0);
            float2 uvS = uv0 + float2(c, s) * rp / _ScreenParams.xy;
            if (any(uvS < 0) || any(uvS > 1)) continue;   // off screen: unknown, left out
            float hh = LumiPlaneDepth(nV, uv0, eyeDepth, uvS) - LumiSampleSceneEyeDepth(uvS) - _SSAOBias;
            o = smoothstep(0.1, softH, hh * pixPerM / rp) * saturate((2.0 * R * _SSAOThickness - hh) / R);
        }
        else
        {
            float3 dir = t * (c * r) + b * (s * r) + N * h;
            float3 p = posWS + N * _SSAOBias + dir * (R * len);
            float sDepth;
            float2 uv = LumiWorldToScreenUV(p, sDepth);
            if (any(uv < 0) || any(uv > 1)) continue;
            float scene = LumiSampleSceneEyeDepth(uv);
            float diff = sDepth - scene;
            float range = saturate(R * _SSAOThickness / max(abs(eyeDepth - scene), 1e-4));
            o = smoothstep(0.002, 0.002 + softD, diff) * range;
        }
        occ += o * (1.0 - saturate((len - _SSAOFalloff) * fall));   // falloff 1 = no falloff
        cnt += 1.0;
    }
    return occ / max(cnt, n * 0.5);   // (near the border: the samples on screen, at least half the weight)
}

float LumiSSAO(float3 posWS, float3 N, float eyeDepth, float2 pixel, float validity, float mask)
{
#if defined(_LUMI_SSAO)
    float fade = 1.0 - LumiRemap(eyeDepth, _SSAOMaxDistance * min(_SSAOFadeStart, 0.999), _SSAOMaxDistance);
    float amount = validity * saturate(fade) * lerp(1.0, mask, _SSAOMaskStrength);
    if (amount <= 0.001) return 1;

    float R = _SSAORadius * lumiAvatarScale * lerp(1.0, max(eyeDepth, 0.25), _SSAODistanceScale);
    bool multi = _SSAOFarWeight > 0.001;
    bool mid = _SSAOMidWeight > 0.001;
    float d0;
    float2 uv0 = LumiWorldToScreenUV(posWS, d0);
    float3 nV = normalize(LumiWorldToViewDir(N));
    float pixPerM = _ScreenParams.y * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05);
    {
        // early out: 4 depth reads around the pixel. When nothing there is in front of our own surface plane
        // (open, flat areas: most of the screen) no sample can be occluded either.
        float rPix = R * max(multi ? max(_SSAOFarScale, 1.0) : 1.0, mid ? max(_SSAOMidScale, 1.0) : 1.0) * 0.6 * pixPerM;
        float2 o = max(rPix, 1.0) / _ScreenParams.xy;
        const float2 offs[4] = { float2(1, 0.7), float2(-1, -0.7), float2(-0.7, 1), float2(0.7, -1) };
        float occl = 0;
        [unroll] for (int k = 0; k < 4; k++)
        {
            float2 uvS = saturate(uv0 + o * offs[k]);
            occl = max(occl, LumiPlaneDepth(nV, uv0, eyeDepth, uvS) - LumiSampleSceneEyeDepth(uvS));
        }
        [branch] if (occl < 0.004 * lumiAvatarScale) return 1;
    }
    float3 t = normalize(cross(N, abs(N.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(N, t);
    float noise = lerp(0.5, LumiSSNoise(pixel, posWS, R, 0), _SSAOJitter);
    int n = (int)clamp(_SSAOSamples, 4, 8);   // capped: every sample is a depth read per pixel
    float softD = max(0.01 * _SSAOSoftness / 0.35, 0.001) * lumiAvatarScale;   // 0.35 = 1 cm, the original range
    float softH = 0.1 + lerp(0.1, 1.5, _SSAOSoftness);
    // multi scale: near (the base radius), mid and far passes, each weighted; the wider ones only cost when used
    float o = _SSAONearWeight * LumiSSAOPass(posWS, N, t, b, uv0, nV, eyeDepth, R, noise, n, softD, softH, pixPerM);
    [branch] if (mid)
        o += _SSAOMidWeight * LumiSSAOPass(posWS, N, t, b, uv0, nV, eyeDepth, R * _SSAOMidScale, frac(noise + 0.25), n, softD, softH, pixPerM);
    [branch] if (multi)
        o += _SSAOFarWeight * LumiSSAOPass(posWS, N, t, b, uv0, nV, eyeDepth, R * _SSAOFarScale, frac(noise + 0.5), n, softD, softH, pixPerM);
    // view angle correction: surfaces seen edge on catch their own neighbours as occluders and turn too dark
    o *= lerp(1.0, smoothstep(0.0, 0.45, saturate(nV.z)), _SSAOViewFix);

    // shaping: neutral at the defaults (power 1, contrast 1, minimum 0)
    float vis = saturate(1.0 - o * _SSAOStrength * amount);
    vis = pow(vis, _SSAOPower);
    float va = pow(vis, _SSAOContrast), vb = pow(1.0 - vis, _SSAOContrast);
    vis = va / max(va + vb, 1e-5);   // S curve, 0 and 1 stay fixed
    return lerp(_SSAOMin * amount, 1.0, vis);
#else
    return 1;
#endif
}

// Short screen space ray toward the light (hair onto face, collar onto neck ...). returns visibility
// mask = receive mask value (1 = full effect). With the default settings this is exactly the original contact shadow.
float LumiContactShadow(float3 posWS, float3 N, float3 L, float eyeDepth, float2 pixel, float validity, float mask)
{
#if defined(_LUMI_CONTACTSHADOW)
    float amount = validity * lerp(1.0, mask, _ContactShadowMaskStrength);
    if (_ContactShadowMaxDistance > 0.01)
        amount *= 1.0 - LumiRemap(eyeDepth, _ContactShadowMaxDistance * 0.7, _ContactShadowMaxDistance);
    if (amount <= 0.001) return 1;
    float scale = lerp(1.0, max(eyeDepth, 0.25), _ContactShadowDistanceScale) * lumiAvatarScale;
    float len = _ContactShadowLength * scale, thick = _ContactShadowThickness * scale;
    int steps = (int)clamp(_ContactShadowSteps, 4, 8);
    float jitter = lerp(0.5, LumiSSNoise(pixel, posWS, len, 17), _ContactShadowJitter);
    float3 start = posWS + N * (_ContactShadowBias * lumiAvatarScale);
    float minD = _ContactShadowMinDelta * lumiAvatarScale, soft = _ContactShadowSoftness * lumiAvatarScale;
    float occ = 0;
    [loop] for (int i = 0; i < steps; i++)
    {
        float t = (i + jitter) / steps;
        float3 p = start + L * (t * len);
        float rayDepth;
        float2 uv = LumiWorldToScreenUV(p, rayDepth);
        if (any(uv < 0) || any(uv > 1)) break;
        float delta = rayDepth - LumiSampleSceneEyeDepth(uv);
        if (delta > minD && delta < thick)
        {
            float w = _ContactShadowSoftness > 0.0001 ? smoothstep(minD, minD + soft, delta) : 1.0;
            occ = w * lerp(1.0, 1.0 - t * t, _ContactShadowEndFade);   // soften toward the end of the ray
            break;
        }
    }
    return 1.0 - occ * _ContactShadowStrength * amount;
#else
    return 1;
#endif
}

// Screen space depth rim (game style): constant width rim where the depth behind the silhouette jumps
float LumiDepthRim(float3 N, float2 screenUV, float eyeDepth, float widthCm, float threshold)
{
    float3 nV = LumiWorldToViewDir(N);
    float2 dir = nV.xy;
    dir = dot(dir, dir) > 1e-6 ? normalize(dir) : float2(0, 1);
    float k = widthCm * 0.01 * lumiAvatarScale * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05);
    float2 offs = dir * k * float2(_ScreenParams.y / _ScreenParams.x, 1.0);
    float2 uv = saturate(screenUV + offs);
    float scene = LumiSampleSceneEyeDepth(uv);
    threshold *= lumiAvatarScale;
    return smoothstep(threshold * 0.5, threshold, scene - eyeDepth);
}

// offset rim: shift the screen UV toward a direction (normal / light / vector) and light the pixel
// when the depth behind that offset jumps away. Falls back to a directional fresnel rim without a depth texture.
// 1 where the background lies far behind just outside this pixel (the real silhouette), 0 on inner edges
// (a muzzle side, a cheek over the neck ...). Used by the toon mode of the ambient rim.
float LumiSilhouetteMask(float3 N, float2 screenUV, float eyeDepth, float validity)
{
    if (validity <= 0.001) return 0;
    float3 nV = LumiWorldToViewDir(N);
    float2 dn = dot(nV.xy, nV.xy) > 1e-6 ? normalize(nV.xy) : float2(0, 1);
    float px = clamp(0.006 * lumiAvatarScale * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y, 1.0, 12.0);
    float2 uv = saturate(screenUV + dn * px / _ScreenParams.xy);
    float diff = LumiSampleSceneEyeDepth(uv) - LumiPlaneDepth(normalize(nV), screenUV, eyeDepth, uv);
    return smoothstep(0.1, 0.25, diff / lumiAvatarScale) * validity;
}

float LumiOffsetRim(float3 N, float3 L, float2 screenUV, float eyeDepth, float NoV, float validity)
{
    float3 nV = LumiWorldToViewDir(N);
    float3 lV = LumiWorldToViewDir(L);
    float2 dn = dot(nV.xy, nV.xy) > 1e-6 ? normalize(nV.xy) : float2(0, 1);
    float2 dl = dot(lV.xy, lV.xy) > 1e-6 ? normalize(lV.xy) : float2(0, 1);
    float2 dv = dot(_OffsetRimVector.xy, _OffsetRimVector.xy) > 1e-6 ? normalize(_OffsetRimVector.xy) : float2(0, 1);
    float2 dir; float facing;
    if (_OffsetRimDirMode < 0.5)      { dir = dn; facing = 1; }
    else if (_OffsetRimDirMode < 1.5) { dir = dl; facing = 1; }
    else if (_OffsetRimDirMode < 2.5) { dir = dv; facing = 1; }
    else                              { dir = dn; facing = saturate(dot(dn, dl) * 0.75 + 0.5); }

    float r;
    if (validity > 0.5)
    {
        float px = _OffsetRimWidth * 0.01 * lumiAvatarScale * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y;
        px = min(px, _OffsetRimMaxPx);
        float2 uv = saturate(screenUV + dir * px / _ScreenParams.xy);
        float diff = LumiSampleSceneEyeDepth(uv) - LumiPlaneDepth(normalize(nV), screenUV, eyeDepth, uv);
        float th = _OffsetRimThreshold * lumiAvatarScale;
        r = smoothstep(th * (1.0 - _OffsetRimSoftness * 0.9), th, diff);
    }
    else
    {
        float fr = saturate(1.0 - NoV);
        r = smoothstep(0.55, 0.85, fr) * saturate(dot(dn, dir) * 2.0) * _OffsetRimFallback;
    }
    return r * facing;
}

// depth texture shadow: step toward the light in screen space; if something is clearly in front of
// us there (hair over the face, collar over the neck) this pixel is shadowed. Gives the 2D "hair shadow" look.
float LumiDepthTexShadow(float3 L, float2 screenUV, float eyeDepth, float validity)
{
#if defined(_LUMI_DEPTHSHADOW)
    if (validity <= 0.5) return 1;
    float3 lV = LumiWorldToViewDir(L);
    float2 dir = dot(lV.xy, lV.xy) > 1e-6 ? normalize(lV.xy) : float2(0, 1);
    float px = _DepthShadowWidth * 0.01 * lumiAvatarScale * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y;
    px = min(px, _DepthShadowMaxPx);
    float2 uv = saturate(screenUV + dir * px / _ScreenParams.xy);
    float diff = eyeDepth - LumiSampleSceneEyeDepth(uv);
    float th = _DepthShadowThreshold * lumiAvatarScale;
    float sh = smoothstep(th * (1.0 - _DepthShadowSoftness * 0.9), th, diff);
    sh *= saturate(1.0 - diff / (0.5 * lumiAvatarScale));   // ignore far occluders (other objects)
    return 1.0 - sh * _DepthShadowStrength;
#else
    return 1;
#endif
}

// ---- Pseudo ray tracing ---------------------------------------------------------------------------------
// Rays marched through the depth texture: shadows toward the light, ambient occlusion over the hemisphere and, in the
// RayTrace shader (screen colour grabbed), reflections and colour bounce from what the rays hit.
// The RayTrace shader draws the surface first, then grabs the screen (per object, so the object itself and everything
// drawn before it are in the image) and a second pass adds what the rays found: hits on the own mesh read its real
// colour instead of whatever is behind it.
static float lumiRTReflSmooth = 0;   // how much the reflection needs its 2x2 dots smoothed (rough: jittered rays)
static float3 lumiRTDelta = 0;   // what the reflections / colour bounce add to this pixel (composite pass)
#if defined(LUMI_RAYTRACE_GRAB) || defined(LUMI_FX_READ)
    #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
        Texture2DArray _GrabTexture;
        #define LUMI_GRAB_SAMPLE(uv) _GrabTexture.SampleLevel(sampler_GrabTexture, float3((uv), unity_StereoEyeIndex), 0).rgb
        #define LUMI_GRAB_SAMPLE4(uv) _GrabTexture.SampleLevel(sampler_GrabTexture, float3((uv), unity_StereoEyeIndex), 0)
        #define LUMI_GRAB_SAMPLE_LIN(uv) _GrabTexture.SampleLevel(sampler_linear_clamp, float3((uv), unity_StereoEyeIndex), 0)
    #else
        Texture2D _GrabTexture;
        #define LUMI_GRAB_SAMPLE(uv) _GrabTexture.SampleLevel(sampler_GrabTexture, (uv), 0).rgb
        #define LUMI_GRAB_SAMPLE4(uv) _GrabTexture.SampleLevel(sampler_GrabTexture, (uv), 0)
        #define LUMI_GRAB_SAMPLE_LIN(uv) _GrabTexture.SampleLevel(sampler_linear_clamp, (uv), 0)   // always bilinear
    #endif
    SamplerState sampler_GrabTexture;
    // the grabbed image is stored top down: flip when the screen UV runs bottom up
    float2 LumiGrabUV(float2 uv)
    {
    #if UNITY_UV_STARTS_AT_TOP
        if (_ProjectionParams.x > 0) uv.y = 1.0 - uv.y;
    #endif
        return uv;
    }
#endif
#if defined(LUMI_RAYTRACE_GRAB) && !defined(UNITY_STEREO_INSTANCING_ENABLED) && !defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    // blurred copies of the screen in a corner of a grab (see MitToonRTPyramid.hlsl): levels 3..6, each as two planes
    // side by side (rgba: colour x coverage, coverage; r: coverage / depth); level 3 along the bottom of the screen,
    // the others in a second row above it
    #define LUMI_RT_PYRAMID 1
    // shared by every RayTrace object of a camera render (named grabs, see MitToonRTPyramid.hlsl): level 3, and the
    // whole chain
    Texture2D _MitToonRTPyr1;
    Texture2D _MitToonRTPyr;
    #define LUMI_PYR_SAMPLE(uv) _MitToonRTPyr.SampleLevel(sampler_linear_clamp, (uv), 0)
    #define LUMI_RT_PYR_FIRST 3
    #define LUMI_RT_PYR_LEVELS 6
    float LumiRTPyrX0(float k) { return k < (float)LUMI_RT_PYR_FIRST + 0.5 ? 0.0 : 2.0 * (exp2(-(float)LUMI_RT_PYR_FIRST) - exp2(1.0 - k)); }   // left edge of level k
    float LumiRTPyrY0(float k) { return k < (float)LUMI_RT_PYR_FIRST + 0.5 ? 0.0 : exp2(-(float)LUMI_RT_PYR_FIRST); }   // bottom edge
    // screen UV (stereo packed, as ComputeScreenPos gives it) <-> this eye's own 0..1 UV
    float2 LumiEyeLocal(float2 uv)
    {
    #if defined(UNITY_SINGLE_PASS_STEREO)
        float4 so = unity_StereoScaleOffset[unity_StereoEyeIndex];
        return (uv - so.zw) / so.xy;
    #else
        return uv;
    #endif
    }
    float2 LumiEyeFull(float2 u)
    {
    #if defined(UNITY_SINGLE_PASS_STEREO)
        float4 so = unity_StereoScaleOffset[unity_StereoEyeIndex];
        return u * so.xy + so.zw;
    #else
        return u;
    #endif
    }
    float2 LumiEyeSize()
    {
        float2 sz = LumiDepthTexSize();   // (the screen's size: the same in every pass, the grabs as well)
    #if defined(UNITY_SINGLE_PASS_STEREO)
        sz *= unity_StereoScaleOffset[unity_StereoEyeIndex].xy;
    #endif
        return sz;
    }
    // the three pixels that hold the token of the chain's camera render (MitToonRTPyramid.hlsl), in this eye's pixels:
    // in the row of levels 4..6, right of level 6
    int2 LumiRTTokenPx(float2 eye)
    {
        return int2((int)(eye.x * 0.23), (int)(eye.y * exp2(-(float)LUMI_RT_PYR_FIRST) * 1.25));
    }
#endif

// ---- Clean blur (FX pass + GrabPass) ------------------------------------------------------------------------------
// The FX pass draws the surface with the noisy terms instead of the colour (AO, contact x ray traced shadow, cast
// shadow; alpha = a mark), the grab copies them and the main pass reads them back blurred over a disk of _NoiseBlur
// pixels with gaussian weights. Taps on other objects (no mark, or another depth) are left out, so nothing bleeds
// across silhouettes. The main pass then skips computing those terms itself.
static float4 lumiFX = float4(1, 1, 1, 0);   // x = AO, y = contact * ray traced shadow, z = cast shadow
static float3 lumiFXOut = 1;                  // this pixel's terms (FX pass)
// RayTrace shader, opaque: the main pass leaves its AO in the alpha of the screen and the composite pass reads it back
// from its grab (exactly the same value, without tracing the AO rays a second time). Not in the lower left corner, where
// the blurred screen overwrites the alpha (there the composite pass traces them itself).
static float lumiRTAOIn = -1;
bool LumiRTAOHandoff()
{
#if defined(_LUMI_RAYTRACE) && !defined(_ALPHATEST_ON) && !defined(_ALPHABLEND_ON) && !defined(_ALPHAPREMULTIPLY_ON) && !defined(UNITY_STEREO_INSTANCING_ENABLED) && !defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    return _RTAlphaDst < 0.5 && _RTGIStrength + _RTGISpecular + _RTReflStrength > 0.001;
#else
    return false;
#endif
}
static bool lumiFXUse = false;               // the main pass uses lumiFX instead of computing the terms
#define LUMI_FX_MARK 0.5019608               // 128 / 255: exact in 8 bit and half float targets
bool LumiFXActive()
{
#if defined(_LUMI_COMPAT) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
    return false;   // lilToon mode / see through: no blur pass
#else
    return _NoiseBlur > 0.5;
#endif
}
#if defined(LUMI_FX_READ)
void LumiFXRead(float2 screenUV, float eyeDepth, float2 pixel)
{
    float R = _NoiseBlur;
    float2 px = 1.0 / _ScreenParams.xy;
    bool depthOK = LumiDepthTextureAvailable();
    float tol = 0.02 + eyeDepth * 0.02;
    // the 4 pixels of a quad take the disk turned by a quarter each; their average (below) = 4 x the taps
    float2 p = fmod(floor(pixel), 2.0);
    float rot = (p.x * 0.25 + p.y * 0.5) * 6.2831853;
    float4 g0 = LUMI_GRAB_SAMPLE4(LumiGrabUV(screenUV));
    float w0 = step(abs(g0.a - LUMI_FX_MARK), 0.02);
    float3 sum = g0.rgb * w0; float wsum = w0;
    const int N = 16;
    [unroll] for (int k = 0; k < N; k++)
    {
        float f = (k + 0.5) / N;
        float th = k * 2.3999632 + rot;
        float2 o = sqrt(f) * float2(cos(th), sin(th)) * R;
        float2 uv = screenUV + o * px;
        float4 g = LUMI_GRAB_SAMPLE4(LumiGrabUV(uv));
        float w = exp(-2.0 * f) * step(abs(g.a - LUMI_FX_MARK), 0.02);
        if (depthOK) w *= saturate(1.0 - abs(LumiSampleSceneEyeDepth(uv) - eyeDepth) / tol);
        sum += g.rgb * w; wsum += w;
    }
    float3 v = wsum > 1e-3 ? sum / wsum : 1.0;
    lumiFX = float4(LumiQuadSmooth(float4(v, 0), eyeDepth, pixel).xyz, 1);
}
#endif

float LumiRTFade(float eyeDepth) { return 1.0 - LumiRemap(eyeDepth, _RTMaxDistance * 0.7, _RTMaxDistance); }
// shadow / AO rays (k > 0): how much of the ray was tested before it left the screen (1: all of it, or it hit)
static float lumiRTMarchCover = 1;

// marches posWS + dir * t (t up to maxDist, denser near the start). Returns the hit weight (0 = nothing hit) with the
// screen UV and distance of the hit; a binary search between the last two steps puts the hit on the surface.
// soft (k > 0): how close the ray passed in front of a surface, relative to k * t (a cone of slope k around the ray):
// a near miss counts partly, so the edge of a shadow / AO runs as a gradient instead of flipping per pixel.
float LumiRTMarch(float3 posWS, float3 dir, float maxDist, int steps, float thick, float jitter, float k, out float2 hitUV, out float hitT, out float soft)
{
    hitUV = 0; hitT = maxDist; soft = 0;
    lumiRTMarchCover = 1;
    float prevT = 0, prevDelta = -1, prevScene = 0;
    // screen position (homogeneous) along the ray: linear in t, so p(t) = c0 + cd * t gives the same as projecting
    // posWS + dir * t at every step
    float4 c0 = LumiComputeScreenPos(LumiWorldToClip(posWS));
    float4 cd = LumiComputeScreenPos(LumiWorldToClip(posWS + dir)) - c0;
    [loop] for (int i = 0; i < steps; i++)
    {
        // reflection: the last step lands on maxDist (the hit fade toward the end of the ray then runs out smoothly
        // instead of the ray stopping short at a jittered point)
        float f = k <= 0.0 ? min((i + jitter) / (steps - 1.0), 1.0) : (i + jitter) / steps;
        float t = maxDist * f * f;
        float4 cp = c0 + cd * t;
        float rd = cp.w;
        float2 uv = cp.xy / cp.w;
        bool lastStep = false;
        float ew = 1.0;
        if (any(uv < 0) || any(uv > 1) || rd < 0.01)
        {
            if (k > 0.0)
            {
                // shadow / AO: the step is off screen. Close to the border the surface there is taken to go on out of
                // view (the floor under a foot, a body leaving the bottom of the picture), trusted less the farther
                // out the step is; farther out it is unknown (the caller weighs the ray by the part it tested)
                float2 uc = saturate(uv);
                float od = length(uv - uc);
                if (rd < 0.01 || od > 0.15) { lumiRTMarchCover = prevT / maxDist; return 0; }
                ew = 1.0 - od / 0.15;
                uv = uc;
            }
            else
            {
            if (i == 0) return 0;
            // reflection: the step left the screen; test the stretch up to the screen border too, else a floor met just
            // before the border is found or not by where the steps happen to fall (a ragged edge in the reflection)
            float a = prevT, b = t;
            [unroll] for (int bi = 0; bi < 5; bi++)
            {
                float m = (a + b) * 0.5;
                float4 cm = c0 + cd * m;
                float rm = cm.w;
                float2 um = cm.xy / cm.w;
                if (any(um < 0) || any(um > 1) || rm < 0.01) b = m; else a = m;
            }
            t = a; { float4 ca = c0 + cd * t; rd = ca.w; uv = ca.xy / ca.w; }
            lastStep = true;
            }
        }
        float sceneD = LumiSampleSceneEyeDepth(uv);
        float delta = rd - sceneD;
        if (k > 0.0 && delta <= 0.003 && delta > -(thick + t * 0.15))
            soft = max(soft, (1.0 - saturate((0.003 - delta) / (k * t + 0.002))) * smoothstep(0.02, 0.06, t) * ew);
        float th = thick + t * 0.15;
        // reflection only (k = 0): a ray that was in front of a surface at the last step and jumped deep behind it in one
        // long step (a floor seen at a grazing angle) also counts; the binary search below then tells a real crossing
        // from a ray that only passed behind something in front
        bool grazing = k <= 0.0 && delta >= th && prevDelta <= 0.003;
        if (delta > 0.003 && (delta < th || grazing))
        {
            float a = prevT, b = t, db = delta;
            [unroll] for (int bi = 0; bi < 5; bi++)
            {
                float m = (a + b) * 0.5;
                float4 cm = c0 + cd * m;
                float rm = cm.w;
                float2 um = cm.xy / cm.w;
                float dm = rm - LumiSampleSceneEyeDepth(saturate(um));   // (saturate: shadow / AO steps past the border)
                if (dm > 0.003) { b = m; uv = um; db = dm; } else a = m;
            }
            if (!grazing || db < thick + b * 0.15)
            {
                hitUV = uv; hitT = b;
                // reflections fade out at the screen border (what they show is cut there); shadows / AO keep their hit
                // (the occluder is right there; a fade there took the AO off near the border)
                float2 e = saturate(min(uv, 1.0 - uv) * 12.0);
                float hw = k > 0.0 ? ew : e.x * e.y;
                soft = hw;
                return hw;
            }
        }
        // reflection only: the ray was hidden behind something in front and comes out already below the surface beyond
        // it (the floor behind a body): it met that surface where we cannot see it; the visible surface next to the
        // hidden part stands in for it (instead of a ragged hole showing the probe)
        else if (k <= 0.0 && delta >= th && prevDelta >= thick + prevT * 0.15 && sceneD > prevScene + th)
        {
            hitUV = uv; hitT = t;
            float2 e = saturate(min(uv, 1.0 - uv) * 12.0);
            soft = e.x * e.y;
            return e.x * e.y;
        }
        if (lastStep) return 0;
        prevT = t; prevDelta = delta; prevScene = sceneD;
    }
    return 0;
}

// LumiRTMarch for the reflection (k = 0), with the depths of four steps read at once (where a step lands does not depend
// on what the steps before found), then the steps tested in order: the reads do not wait for each other. (Shadows / AO
// keep LumiRTMarch: their rays are short and many, and there the larger code was slower.)
float LumiRTMarchRefl(float3 posWS, float3 dir, float maxDist, int steps, float thick, float jitter, out float2 hitUV, out float hitT)
{
    hitUV = 0; hitT = maxDist;
    float prevT = 0, prevDelta = -1, prevScene = 0;
    float4 c0 = LumiComputeScreenPos(LumiWorldToClip(posWS));
    float4 cd = LumiComputeScreenPos(LumiWorldToClip(posWS + dir)) - c0;
    [loop] for (int i0 = 0; i0 < steps; i0 += 4)
    {
        float4 sdq;
        [unroll] for (int jq = 0; jq < 4; jq++)
        {
            float fq = min((i0 + jq + jitter) / (steps - 1.0), 1.0);
            float4 cq = c0 + cd * (maxDist * fq * fq);
            sdq[jq] = LumiSampleSceneEyeDepth(saturate(cq.xy / cq.w));
        }
        [loop] for (int jt = 0; jt < 4; jt++)
        {
            int i = i0 + jt;
            if (i >= steps) break;
            // the last step lands on maxDist (the hit fade toward the end of the ray then runs out smoothly instead of
            // the ray stopping short at a jittered point)
            float f = min((i + jitter) / (steps - 1.0), 1.0);
            float t = maxDist * f * f;
            float4 cp = c0 + cd * t;
            float rd = cp.w;
            float2 uv = cp.xy / cp.w;
            bool lastStep = false;
            float sceneD = sdq[jt];
            if (any(uv < 0) || any(uv > 1) || rd < 0.01)
            {
                if (i == 0) return 0;
                // the step left the screen; test the stretch up to the screen border too, else a floor met just before
                // the border is found or not by where the steps happen to fall (a ragged edge in the reflection)
                float a = prevT, b = t;
                [unroll] for (int bi = 0; bi < 5; bi++)
                {
                    float m = (a + b) * 0.5;
                    float4 cm = c0 + cd * m;
                    float rm = cm.w;
                    float2 um = cm.xy / cm.w;
                    if (any(um < 0) || any(um > 1) || rm < 0.01) b = m; else a = m;
                }
                t = a; { float4 ca = c0 + cd * t; rd = ca.w; uv = ca.xy / ca.w; }
                sceneD = LumiSampleSceneEyeDepth(uv);
                lastStep = true;
            }
            float delta = rd - sceneD;
            float th = thick + t * 0.15;
            // a ray that was in front of a surface at the last step and jumped deep behind it in one long step (a floor
            // seen at a grazing angle) also counts; the binary search below then tells a real crossing from a ray that
            // only passed behind something in front
            bool grazing = delta >= th && prevDelta <= 0.003;
            if (delta > 0.003 && (delta < th || grazing))
            {
                float a = prevT, b = t, db = delta;
                [unroll] for (int bi = 0; bi < 5; bi++)
                {
                    float m = (a + b) * 0.5;
                    float4 cm = c0 + cd * m;
                    float rm = cm.w;
                    float2 um = cm.xy / cm.w;
                    float dm = rm - LumiSampleSceneEyeDepth(saturate(um));
                    if (dm > 0.003) { b = m; uv = um; db = dm; } else a = m;
                }
                if (!grazing || db < thick + b * 0.15)
                {
                    hitUV = uv; hitT = b;
                    // faded out at the screen border (what the reflection shows is cut there)
                    float2 e = saturate(min(uv, 1.0 - uv) * 12.0);
                    return e.x * e.y;
                }
            }
            // the ray was hidden behind something in front and comes out already below the surface beyond it (the
            // floor behind a body): it met that surface where we cannot see it; the visible surface next to the hidden
            // part stands in for it (instead of a ragged hole showing the probe)
            else if (delta >= th && prevDelta >= thick + prevT * 0.15 && sceneD > prevScene + th)
            {
                hitUV = uv; hitT = t;
                float2 e = saturate(min(uv, 1.0 - uv) * 12.0);
                return e.x * e.y;
            }
            if (lastStep) return 0;
            prevT = t; prevDelta = delta; prevScene = sceneD;
        }
    }
    return 0;
}

// ray traced shadow toward the light: several rays inside the cone of the light's angular size (soft, grows with distance)
float LumiRTShadow(float3 posWS, float3 N, float3 L, float eyeDepth, float2 pixel, float validity)
{
#if defined(_LUMI_RAYTRACE)
    float amount = validity * _RTShadowStrength * LumiRTFade(eyeDepth);
    if (amount <= 0.001 || dot(L, L) < 0.5) return 1;
    float3 t = normalize(cross(L, abs(L.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(L, t);
    int rays = (int)clamp(_RTShadowRays, 1, 4), steps = (int)clamp(_RTShadowSteps, 4, 24);
    float cone = tan(radians(_RTShadowSoftness));
    float noise = LumiSSNoise(pixel, posWS, _RTShadowLength * max(cone, 0.05), 31);
    float3 start = posWS + N * _RTShadowBias;
    float vis = 0;
    [loop] for (int r = 0; r < rays; r++)
    {
        float s, c; sincos((r * 2.3999632 + noise) * 6.2831853, s, c);
        float3 dir = normalize(L + (t * c + b * s) * (sqrt((r + 0.5) / rays) * cone));
        float2 huv; float ht, sft;
        LumiRTMarch(start, dir, _RTShadowLength, steps, _RTShadowThickness, frac(noise + r * 0.618034), max(cone, 0.03), huv, ht, sft);
        vis += 1.0 - sft;
    }
    return lerp(1.0, vis / rays, amount);
#else
    return 1;
#endif
}

// shadow along the world's light (estimated per pixel from the real light / the probes / the scenery / point lights),
// for the soft shadows (PCSS) module: the shadow light's shadow map is fixed to the avatar, this one turns with the
// world. Rays through the depth texture inside the cone of the light's size. conf: how clearly the light has a direction
static float3 lumiWorldL = float3(0, 1, 0);
static float lumiWorldConf = 0;
static float lumiWorldMain = 0;   // share of the real light in it
float LumiWorldShadow(float3 posWS, float3 N, float eyeDepth, float2 pixel, float validity)
{
    float3 L = lumiWorldL;
    float amount = validity * lumiWorldConf * _PCSSWorldShadowStrength;
    // the part of the light that already casts a shadow of its own (shadow map / ray traced shadow along the real
    // light) gets no second one
    float covered = 0;
#if defined(SHADOWS_SCREEN)
    covered = step(0.5, _ReceiveCastShadow);
#endif
#if defined(_LUMI_RAYTRACE)
    covered = max(covered, saturate(_RTShadowStrength));
#endif
    amount *= 1.0 - lumiWorldMain * covered;
    if (_PCSSDistanceFade > 0.01) amount *= saturate(2.0 - 2.0 * eyeDepth / _PCSSDistanceFade);
    if (amount <= 0.001 || UNITY_MATRIX_P._m33 != 0.0 || dot(N, L) <= -0.1) return 1;
    float3 t = normalize(cross(L, abs(L.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(L, t);
    float cone = tan(radians(_PCSSWorldShadowSoftness));
    float noise = LumiSSNoise(pixel, posWS, _PCSSWorldShadowLength * max(cone, 0.05), 37);
    float3 start = posWS + N * 0.01;
    float vis = 0;
    [unroll] for (int r = 0; r < 2; r++)
    {
        float sn, cs; sincos((r * 0.5 + noise) * 6.2831853, sn, cs);
        float3 dir = normalize(L + (t * cs + b * sn) * (sqrt((r + 0.5) / 2.0) * cone));
        float2 huv; float ht, sft;
        LumiRTMarch(start, dir, _PCSSWorldShadowLength, 12, 0.2, frac(noise + r * 0.618034), max(cone, 0.03), huv, ht, sft);
        vis += 1.0 - sft;
    }
    return lerp(1.0, vis * 0.5, amount);
}

// ray traced ambient occlusion over the cosine weighted hemisphere (bounce: always 0, the bounce has its own rays: LumiRTGI)
float LumiRTAO(float3 posWS, float3 N, float eyeDepth, float2 pixel, float validity, out float3 bounce)
{
    bounce = 0;
#if defined(_LUMI_RAYTRACE)
    float amount = validity * LumiRTFade(eyeDepth);
    if (amount <= 0.001) return 1;
    float3 t = normalize(cross(N, abs(N.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(N, t);
    int rays = (int)clamp(_RTAORays, 2, 8), steps = (int)clamp(_RTAOSteps, 2, 8);
    float noise = LumiSSNoise(pixel, posWS, _RTAORadius, 5);
    float occ = 0, wsum = 0;
    [loop] for (int r = 0; r < rays; r++)
    {
        float fi = (r + 0.5) / rays;
        float s, c; sincos(r * 2.3999632 + noise * 6.2831853, s, c);
        float rr = sqrt(fi), h = sqrt(1.0 - fi);
        float3 dir = t * (c * rr) + b * (s * rr) + N * h;
        float2 huv; float ht, sft;
        float hit = LumiRTMarch(posWS + N * 0.005, dir, _RTAORadius, steps, _RTAOThickness, frac(noise * 1.7 + r * 0.618034), 0.1, huv, ht, sft);
        float near = 1.0 - 0.5 * ht / _RTAORadius;   // close occluders count more
        occ += sft * near;
        wsum += max(lumiRTMarchCover, sft);
    }
    // near the screen border rays pointing off screen do not dilute the others (at least half the rays' weight, so a
    // pixel with almost all of them off screen stays open)
    return saturate(1.0 - occ / max(wsum, rays * 0.5) * _RTAOStrength * amount);
#else
    return 1;
#endif
}

// grabbed colour, glowing things kept up to _RTGIMaxBright (a soft limit: emission lights its surroundings, but a sun
// spot in the background does not flood them)
float3 LumiRTBright(float3 c)
{
    float l = max(c.r, max(c.g, c.b)), m = max(_RTGIMaxBright, 1.0);
    return l > 1.0 ? c * ((1.0 + (m - 1.0) * (1.0 - exp(-(l - 1.0) / (m - 1.0)))) / l) : c;
}
#if defined(LUMI_RAYTRACE_GRAB)
// the grabbed colour at a UV (bilinear) for the bounce / reflections, a = 1; a = 0 (and no colour) where one of the four
// pixels under the read belongs to an object of the same queue not drawn yet: its FX pass data is there (AO, contact
// shadow, cast shadow as rgb: magenta in a contact shadow), not its colour
float4 LumiRTGrabClean(float2 g)
{
#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    float4 a4 = _GrabTexture.GatherAlpha(sampler_GrabTexture, float3(g, unity_StereoEyeIndex));
#else
    float4 a4 = _GrabTexture.GatherAlpha(sampler_GrabTexture, g);
#endif
    float clean = all(abs(a4 - LUMI_FX_MARK) >= 0.0008) ? 1.0 : 0.0;
    return float4(LUMI_GRAB_SAMPLE(g) * clean, clean);
}
#endif
#if defined(LUMI_RT_PYRAMID)
// one level of the blurred screen at a screen UV (level k: 2^k pixels per texel): colour x coverage (rgb), coverage (a)
// and coverage / depth (d), read from its two planes
float4 LumiRTPyrLevel(float2 uv, float k, float2 eye, out float d)
{
    float s = exp2(-k);
    float2 tx = exp2(k) / eye;                         // one texel of this level, in the eye's UV
    float2 u = clamp(LumiEyeLocal(uv), tx, 1.0 - tx);   // (a texel of margin: no bleed from the next plane)
    float2 p = float2(LumiRTPyrX0(k) + u.x * s, LumiRTPyrY0(k) + u.y * s);
    d = LUMI_PYR_SAMPLE(LumiGrabUV(LumiEyeFull(p + float2(s, 0)))).r;
    return LUMI_PYR_SAMPLE(LumiGrabUV(LumiEyeFull(p)));
}
// LumiRTPyr for many reads with the same lod, without branches (all its reads go out at once; the same result)
struct LumiRTPyrSpan { float fb, lA, lB, f; float2 eye; };
LumiRTPyrSpan LumiRTPyrSpanOf(float lod)
{
    LumiRTPyrSpan p;
    float first = (float)LUMI_RT_PYR_FIRST;
    lod = clamp(lod, 0.0, (float)LUMI_RT_PYR_LEVELS);
    p.fb = saturate(lod - (first - 1.0));
    p.eye = LumiEyeSize();
    float l0 = max(floor(lod), first);
    float f = smoothstep(0.2, 0.8, saturate(lod - l0));
    p.lA = l0 + (f >= 0.999 ? 1.0 : 0.0);
    p.lB = min(l0 + 1.0, (float)LUMI_RT_PYR_LEVELS);
    p.f = (f > 0.001 && f < 0.999 && l0 < (float)LUMI_RT_PYR_LEVELS) ? f : 0.0;
    return p;
}
float3 LumiRTPyrIn(LumiRTPyrSpan p, float2 uv, float depth)
{
    float4 sc = LumiRTGrabClean(LumiGrabUV(uv));
    float3 sharp = LumiRTBright(sc.rgb);
    float d0, d1;
    float4 B0 = LumiRTPyrLevel(uv, p.lA, p.eye, d0);
    float4 B1 = LumiRTPyrLevel(uv, p.lB, p.eye, d1);
    float4 B = p.f > 0.0 ? lerp(B0, B1, p.f) : B0;
    float dm = p.f > 0.0 ? lerp(d0, d1, p.f) : d0;
    float rel = abs(dm / max(B.a, 1e-4) * max(depth, 0.05) - 1.0);
    float w = p.fb * saturate(B.a * 4.0) * (1.0 - smoothstep(0.08, 0.25, rel));
    float3 blur = B.rgb / max(B.a, 1e-4);
    w = sc.a > 0.5 ? w : saturate(B.a * 4.0);   // (no sharp colour there: the blurred one, which leaves such pixels out)
    float3 r = w >= 0.999 ? blur : lerp(sharp, blur, w);
    return p.fb <= 0.001 && sc.a > 0.5 ? sharp : r;
}
// the screen's light at a UV, averaged over about 2^lod pixels of the surfaces there (the sky left out), blended between
// levels (below level 3: the sharp screen, blended into level 3 between 2 and 3). depth: of the surface the read is
// for; where the area around holds things at other depths (an outline: something in front or behind) the read keeps
// to the sharp colour, so nothing from another surface leaks in.
float3 LumiRTPyr(float2 uv, float lod, float depth)
{
    float first = (float)LUMI_RT_PYR_FIRST;
    lod = clamp(lod, 0.0, (float)LUMI_RT_PYR_LEVELS);
    float fb = saturate(lod - (first - 1.0));
    [branch] if (fb <= 0.001) return LumiRTBright(LUMI_GRAB_SAMPLE(LumiGrabUV(uv)));
    float2 eye = LumiEyeSize();
    float l0 = max(floor(lod), first);
    // between two levels: blended over the middle of the step only (one level read near either end, still continuous)
    float f = smoothstep(0.2, 0.8, saturate(lod - l0));
    float d0, d1 = 0;
    float4 B = LumiRTPyrLevel(uv, l0 + (f >= 0.999 ? 1.0 : 0.0), eye, d0);
    [branch] if (f > 0.001 && f < 0.999 && l0 < (float)LUMI_RT_PYR_LEVELS)
        B = lerp(B, LumiRTPyrLevel(uv, l0 + 1.0, eye, d1), f);
    else f = 0;
    float dm = lerp(d0, d1, f);
    // the area's mean 1 / depth (exact for a flat surface, also when tilted) against the surface's own
    float rel = abs(dm / max(B.a, 1e-4) * max(depth, 0.05) - 1.0);
    float w = fb * saturate(B.a * 4.0) * (1.0 - smoothstep(0.08, 0.25, rel));
    float3 blur = B.rgb / max(B.a, 1e-4);
    [branch] if (w >= 0.999) return blur;   // (the sharp colour is not needed)
    return lerp(LumiRTBright(LUMI_GRAB_SAMPLE(LumiGrabUV(uv))), blur, w);
}
// the blurred screen at a UV as it is stored: colour x coverage (rgb), coverage (a), coverage / depth (invz), averaged
// over about 2^lod pixels (below level 3 the sharp screen)
float4 LumiRTPyrRaw(float2 uv, float lod, out float invz)
{
    float first = (float)LUMI_RT_PYR_FIRST;
    lod = clamp(lod, 0.0, (float)LUMI_RT_PYR_LEVELS);
    float fb = saturate(lod - (first - 1.0));
    float4 S = 0; float si = 0;
    [branch] if (fb < 0.999)
    {
        float z = LumiSampleSceneEyeDepth(uv);
        float4 gc = LumiRTGrabClean(LumiGrabUV(uv));
        float cov = saturate((_ProjectionParams.z * 0.95 - z) / (_ProjectionParams.z * 0.0475)) * gc.a;   // (not drawn yet: like the sky)
        S = float4(LumiRTBright(gc.rgb) * cov, cov);
        si = cov / max(z, 0.05);
    }
    invz = si;
    [branch] if (fb <= 0.001) return S;
    float2 eye = LumiEyeSize();
    float l0 = max(floor(lod), first);
    float f = smoothstep(0.2, 0.8, saturate(lod - l0));   // (see LumiRTPyr)
    float d0, d1 = 0;
    float4 B = LumiRTPyrLevel(uv, l0 + (f >= 0.999 ? 1.0 : 0.0), eye, d0);
    [branch] if (f > 0.001 && f < 0.999 && l0 < (float)LUMI_RT_PYR_LEVELS)
        B = lerp(B, LumiRTPyrLevel(uv, l0 + 1.0, eye, d1), f);
    else f = 0;
    invz = lerp(si, lerp(d0, d1, f), fb);
    return lerp(S, B, fb);
}
// near bounce: what lies within this radius of a surface lights it from a few cm away, with a fall off finer than the
// vertices are apart. Where the radius covers enough pixels the pixels gather it themselves (LumiRTGINear) and the
// vertices leave it out (their first layer).
float LumiRTNearRadius() { return _RTGILength * 0.25; }
float LumiRTNearAmount(float eyeDepth, float kpx)   // kpx: pixels per meter at 1 m
{
    return smoothstep(6.0, 20.0, LumiRTNearRadius() * kpx / max(eyeDepth, 0.05));
}
#endif

// bounce light (RayTrace shader): each vertex sends rays in a fixed set of world directions (the half facing out of the
// surface) through the depth texture and reads the lit colour (grab) where they hit. The light found is kept as a
// small directional probe (L0 + L1 spherical harmonics, per colour) that the pixels read with their own normal.
// Directions fixed in the world + per vertex: when the view turns or moves, a vertex keeps looking at the same spots of
// the surroundings, so the bounce does not shimmer over patterned floors or blink around small bright things, and the
// pixels between the vertices blend smoothly (no grain). Only the light above what the probes already bring from that
// side is added (ordinary surroundings do not wash the shading out). The probe also gives a "bounce light" (direction +
// colour) for the highlight it puts on glossy parts.
static float3 lumiRTGIDir = 0, lumiRTGICol = 0;
// how wide the bounce light comes in (GGX alpha^2 added to the highlight): light from all around makes a broad sheen,
// one small glowing thing a tighter spot, never the pin point of a lamp (it is an area, not a point)
static float lumiRTGIA2 = 0.5;
static float4 lumiRTGIV0 = 0, lumiRTGIV1 = 0, lumiRTGIV2 = 0;   // the vertex probe, interpolated (set by the pass)
// depth read with linear filtering (Unity's built in linear clamp sampler): between two texels the depth runs over
// instead of stepping, so what is judged from it changes smoothly as the view moves (sampler from MitToonInput)
float LumiSampleSceneEyeDepthSmooth(float2 uv)
{
#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    float raw = _CameraDepthTexture.SampleLevel(sampler_linear_clamp, float3(uv, unity_StereoEyeIndex), 0);
#else
    float raw = _CameraDepthTexture.SampleLevel(sampler_linear_clamp, uv, 0);
#endif
    return LumiRawToEyeDepth(raw, uv);
}
void LumiRTGIVertex(float3 posWS, float3 N, out float4 o0, out float4 o1, out float4 o2)
{
    o0 = 0; o1 = 0; o2 = 0;
#if defined(_LUMI_RAYTRACE) && defined(LUMI_RAYTRACE_GRAB)
    float d0;
    LumiWorldToScreenUV(posWS, d0);
    float amount = LumiRTFade(d0);
    if (amount <= 0.001 || _RTGIStrength + _RTGISpecular <= 0.001 || UNITY_MATRIX_P._m33 != 0.0 || !LumiDepthTextureAvailable()) return;
    N = normalize(N);
    // a vertex facing well away from the camera only belongs to back faces, which are not drawn (Cull Back)
    if (_Cull > 1.5 && dot(N, normalize(LumiGetEyePositionWS() - posWS)) < -0.6) return;
    float2 dsz = LumiDepthTexSize();
    {
        // hidden behind something in front (a body under its clothes): no pixel around it is drawn in the end, so
        // nothing reads its probe. Tested at the vertex and 3 cm (at least 6 pixels) around it, about a triangle's
        // size: a triangle partly behind the edge of something in front keeps its vertices, a thin strap over a vertex
        // does not hide it. (A depth texture of another camera turns the bounce off per pixel anyway.)
        float dv;
        float2 uvv = LumiWorldToScreenUV(posWS, dv);
        float tol = 0.01 + dv * 0.01;
        float2 o6 = max(6.0, 0.03 * dsz.y * 0.5 * abs(UNITY_MATRIX_P._m11) / max(dv, 0.05)) / dsz;
        float vis = 0;
        [unroll] for (int k = 0; k < 5; k++)
        {
            float2 ou = k == 0 ? 0 : float2(k == 1 ? 1 : (k == 2 ? -1 : 0), k == 3 ? 1 : (k == 4 ? -1 : 0)) * o6;
            float2 su = uvv + ou;
            if (any(su < 0) || any(su > 1)) { vis = 1; break; }   // (partly off screen: kept)
            vis = max(vis, step(dv - tol, LumiSampleSceneEyeDepth(su)));
        }
        if (vis < 0.5) return;
    }
    float kpx = dsz.y * 0.5 * abs(UNITY_MATRIX_P._m11);   // depth texels per meter at 1 m
    int n = (int)clamp(_RTGIRays, 1, 8) * 4;
    // each direction stands for a cone of 4 pi / n of the sphere: its points are read over the whole width of that cone
    // (cones that leave gaps miss thin bright things such as neon tubes on one vertex and catch them on the next:
    // blotches)
    float coneR = 2.2 / sqrt((float)n);
    float maxPx = dsz.y * 0.3;
#if defined(LUMI_RT_PYRAMID)
    float nearV = LumiRTNearAmount(d0, kpx);   // the pixels gather the near bounce themselves
#else
    float nearV = 0;
#endif
    float3 a = 0, br = 0, bg = 0, bb = 0;
    [loop] for (int i = 0; i < n; i++)
    {
        // fibonacci sphere: evenly spread, the same in every frame and for every vertex
        float z = 1.0 - (i + 0.5) * 2.0 / n, r = sqrt(saturate(1.0 - z * z)), ph = i * 2.3999632;
        float3 dir = float3(cos(ph) * r, z, sin(ph) * r);
        float cosN = dot(dir, N);
        if (cosN <= 0.05) continue;
        // points along the direction at fixed distances (fixed in the world): how surely a surface sits at each point
        // is a smooth function of the depth difference there (no hit / miss), and the points are laid over each other
        // near to far like layers of fog, so the colour seen in this direction changes smoothly from vertex to vertex
        // and from frame to frame
        float3 Ld = 0; float T = 1.0;
        // (3 points: a 4th at fr = 1 would have fade 0)
        [loop] for (int j = 0; j < 3; j++)
        {
            float fr = (j + 1) / 4.0, t = _RTGILength * fr * fr, sg = max(0.4 * t, 0.03);
            float rd;
            float2 uv = LumiWorldToScreenUV(posWS + N * 0.02 + dir * t, rd);
            if (any(uv < 0.002) || any(uv > 0.998) || rd < 0.05) break;
            // the point is the cross section of the cone there (radius coneR t): 13 reads over it (centre, inner and outer
            // ring, turned per direction), each judged by how surely a surface sits at that depth and averaged. When the
            // outline of something passes over it (the view moves), the value slides over in small steps.
            float fpPx = min(coneR * t * kpx / rd, maxPx);
            float2 fp = fpPx / dsz;   // cross section radius in UV
            float lodq = log2(max(0.55 * fpPx, 1.0));   // each read averages the area up to its neighbours (blurred screen)
            // (the reads are unrolled and free of branches inside, so they all go out at once instead of one after the
            // other: the depths first, then, unless no read found a surface, the colours)
            float occ = 0, wsum = 0; float3 cs = 0;
            float2 quvs[13]; float sds[13], oqs[13];
            [unroll] for (int q = 0; q < 13; q++)
            {
                float qa = q * 1.0471976 + (q > 6 ? 0.5236 : 0.0) + ph;   // rings of 6, the outer one offset by 30 degrees
                float qr = q == 0 ? 0.0 : (q <= 6 ? 0.5 : 1.0);
                float2 quv = uv + float2(cos(qa), sin(qa)) * fp * qr;
                float inb = all(quv == saturate(quv)) ? 1.0 : 0.0;   // off screen: not read
                float sd = LumiSampleSceneEyeDepthSmooth(quv);
                float dq = rd - sd;   // > 0: the point is behind the visible surface
                float oq = smoothstep(-sg, 0.0, dq) * (1.0 - smoothstep(sg, 2.0 * sg + 0.1, dq));
                oq *= inb;
                occ += oq; wsum += inb;
                quvs[q] = saturate(quv); sds[q] = sd; oqs[q] = oq > 0.002 ? oq : 0.0;   // colour only where a surface is
            }
            [branch] if (occ > 0.002)
            {
            #if defined(LUMI_RT_PYRAMID)
                LumiRTPyrSpan sp = LumiRTPyrSpanOf(lodq);
                [unroll] for (int q = 0; q < 13; q++) cs += oqs[q] * LumiRTPyrIn(sp, quvs[q], sds[q]);
            #else
                [unroll] for (int q = 0; q < 13; q++) cs += oqs[q] * LumiRTBright(LumiRTGrabClean(LumiGrabUV(quvs[q])).rgb);
            #endif
            }
            occ /= max(wsum, 1.0); cs /= max(wsum, 1.0);
            // fade where the point reaches the screen border (it is not read past it), over its cross section but at most
            // 2 % of the screen (a wide band dimmed light from things near the border); taps off screen are left out above
            float2 e = saturate(min(uv, 1.0 - uv) * dsz / clamp(fpPx, 4.0, dsz.y * 0.02));
            float fade = e.x * e.y * (1.0 - smoothstep(0.6, 1.0, fr * fr));
            occ *= fade;
            Ld += T * cs * (fade * (j == 0 ? 1.0 - nearV : 1.0));
            T *= 1.0 - occ;
            if (T < 0.02) break;
        }
        float3 L = max(Ld - (1.0 - T) * LumiSampleSH(dir), 0.0) * smoothstep(0.05, 0.25, cosN);
        a += L; br += L.r * dir; bg += L.g * dir; bb += L.b * dir;
    }
    // irradiance / pi toward a normal m: a + b.m (L0 + L1, clamped cosine), each ray standing for 4 pi / n of the sphere
    float s0 = amount / n, s1 = 3.0 * amount / n;
    a *= s0; br *= s1; bg *= s1; bb *= s1;
    o0 = float4(a, br.x); o1 = float4(br.yz, bg.xy); o2 = float4(bg.z, bb);
#endif
}
#if defined(LUMI_RT_PYRAMID)
// near bounce gathered per pixel: rings of reads around the pixel on screen (6 per ring, 4 rings doubling in radius out
// to the near radius), each read the blurred screen over its share of the disc, so together they cover it with no gaps.
// Each area lights the pixel as a small patch of light: its colour x its area x the cosine at the surface / distance^2
// (irradiance / pi, the same as the vertex probe). Areas behind the surface's own plane (the surface itself, a convex
// body) give nothing; only the light above what the probes already bring from that side is added.
float3 LumiRTGINear(float3 posWS, float3 N, float validity)
{
    float z0;
    float2 uv0 = LumiWorldToScreenUV(posWS, z0);
    float2 eye = LumiEyeSize();
    float kpx = eye.y * 0.5 * abs(UNITY_MATRIX_P._m11);
    float nf = LumiRTNearAmount(z0, kpx) * validity * LumiRTFade(z0);
    if (nf <= 0.001) return 0;
    float R = LumiRTNearRadius();
    float rpx = min(R * kpx / z0, eye.y * 0.35);
    float4x4 P = UNITY_MATRIX_P;
    float2 lu0 = LumiEyeLocal(uv0);
    float2 n0 = float2(lu0.x * 2.0 - 1.0, (lu0.y * 2.0 - 1.0) * _ProjectionParams.x);
    float3 pV = float3((n0.x + P._m02) / P._m00, (n0.y + P._m12) / P._m11, -1.0) * z0;
    float3 nV = normalize(mul((float3x3)UNITY_MATRIX_V, N));
    float3 E = 0;
    [loop] for (int ring = 0; ring < 4; ring++)
    {
        float rho = rpx * exp2(ring - 3.0);
        // the innermost ring reads wide enough to cover the middle of the disc too
        float lod = log2(max(rho * (ring == 0 ? 2.0 : 0.9), 1.0));
        float apx = ring == 0 ? 1.047 * rho * rho : 0.785 * rho * rho;   // screen pixels each read stands for
        [loop] for (int k = 0; k < 6; k++)
        {
            float ang = (k + ring * 0.5) * 1.0471976;
            float2 lu = lu0 + float2(cos(ang), sin(ang)) * rho / eye;
            // off screen: the edge is read instead, fading out over half the ring's radius (no step when a read
            // crosses the edge as the view moves)
            float2 lc = saturate(lu);
            float edge = 1.0 - saturate(length((lu - lc) * eye) / (0.5 * rho));
            if (edge <= 0.0) continue;
            lu = lc;
            float iz;
            float4 B = LumiRTPyrRaw(LumiEyeFull(lu), lod, iz);
            if (B.a < 0.01) continue;
            float zs = B.a / max(iz, 1e-5);   // the area's depth (from its mean 1 / depth)
            float2 nd = float2(lu.x * 2.0 - 1.0, (lu.y * 2.0 - 1.0) * _ProjectionParams.x);
            float3 v = float3((nd.x + P._m02) / P._m00, (nd.y + P._m12) / P._m11, -1.0) * zs - pV;
            float d2 = dot(v, v), d = sqrt(d2);
            float cr = dot(nV, v) / max(d, 1e-4);
            if (cr <= 0.0) continue;
            float mpp = zs / kpx;   // meters per pixel there
            float A = apx * B.a * mpp * mpp;   // its area (as the camera sees it)
            float w = (1.0 - smoothstep(0.6 * R, R, d)) * edge;
            float3 vW = mul(v, (float3x3)UNITY_MATRIX_V) / max(d, 1e-4);
            float3 C = max(B.rgb / B.a - LumiSampleSH(vW), 0.0);
            E += C * (cr * A * w / (3.14159265 * max(d2, 4.0 * A + 1e-4)));
        }
    }
    return E * nf;
}
#endif
void LumiRTGI(float3 posWS, float3 N, float eyeDepth, float2 pixel, float validity, out float3 diffuse, out float3 lightDir, out float3 lightCol)
{
    diffuse = 0; lightDir = N; lightCol = 0;
#if defined(_LUMI_RAYTRACE) && defined(LUMI_RAYTRACE_GRAB)
    float3 a = lumiRTGIV0.rgb;
    float3 br = float3(lumiRTGIV0.a, lumiRTGIV1.xy), bg = float3(lumiRTGIV1.zw, lumiRTGIV2.x), bb = lumiRTGIV2.yzw;
    float3 E = max(a + float3(dot(br, N), dot(bg, N), dot(bb, N)), 0.0) * validity;
#if defined(LUMI_RT_PYRAMID)
    E += LumiRTGINear(posWS, N, 1.0) * validity;
#endif
    diffuse = E * _RTGIStrength;
    float3 bl = br * 0.2126 + bg * 0.7152 + bb * 0.0722;   // luminance weighted direction
    float al = LumiLuminance(a), bln = length(bl);
    lightDir = bln > 1e-6 ? bl / bln : N;
    lightCol = max(a + float3(dot(br, lightDir), dot(bg, lightDir), dot(bb, lightDir)), 0.0) * validity * _RTGISpecular;
    float coh = al > 1e-8 ? saturate(bln / (3.0 * al)) : 0.0;   // 1: all from one direction
    lumiRTGIA2 = 0.02 + 0.8 * (1.0 - coh) * (1.0 - coh);   // (squared: a small source seen by a few neighbouring cones stays a small source)
#endif
}

// ray traced reflection: the reflected ray (spread by the roughness) marched through the depth texture; where it hits
// something on screen the grabbed colour replaces the reflection probe
float3 LumiRTReflection(float3 env, float3 posWS, float3 N, float3 V, float perceptualRough, float eyeDepth, float2 pixel, float validity)
{
#if defined(_LUMI_RAYTRACE) && defined(LUMI_RAYTRACE_GRAB)
    float amount = validity * _RTReflStrength * LumiRTFade(eyeDepth) * (1.0 - smoothstep(_RTReflRoughCut * 0.6, _RTReflRoughCut, perceptualRough));
    if (amount <= 0.001) return env;
    // smooth surfaces: one sharp ray per pixel, drawn at full resolution; rough ones jitter and get smoothed
#if defined(LUMI_RT_PYRAMID)
    lumiRTReflSmooth = 0;   // one ray along the reflection, the roughness comes from the blurred screen: no noise
#else
    lumiRTReflSmooth = smoothstep(0.15, 0.5, perceptualRough);
#endif
    float noise = LumiSSNoise(pixel, posWS, _RTReflLength * max(perceptualRough * perceptualRough * 0.6, 0.02), 11);
    float3 R = reflect(-V, N);
    float3 t = normalize(cross(R, abs(R.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(R, t);
    float s, c; sincos(noise * 6.2831853, s, c);
#if defined(LUMI_RT_PYRAMID)
    float3 dir = R;
#else
    float3 dir = normalize(R + (t * c + b * s) * (sqrt(frac(noise * 7.13)) * perceptualRough * perceptualRough * 0.6));
#endif
    if (dot(dir, N) < 0.02) dir = R;
    float2 huv; float ht;
    float hit = LumiRTMarchRefl(posWS + N * 0.01, dir, _RTReflLength, (int)clamp(_RTReflSteps, 8, 48), _RTReflThickness, noise, huv, ht);
    if (hit <= 0.001) return env;
    float2 g = LumiGrabUV(huv);
    // an object of the same queue not drawn yet: the data of its FX pass is there (marked in the alpha), not its colour.
    // Any of the four pixels of the bilinear read: at its edge a read half on it had a mixed alpha and passed as a colour
    // (magenta glints in the eyes from a contact shadow there)
    float4 sc4 = LumiRTGrabClean(g);
    if (sc4.a < 0.5) return env;
    float3 sc = sc4.rgb;
    sc = LumiRTBright(sc);   // bright / glowing things stay bright in the reflection
    // glossy blur that grows with the distance to what is reflected (the cone of the rough reflection): sharp where
    // the reflected thing touches the surface, blurrier the farther it is, like a real glossy floor
    float a = perceptualRough * perceptualRough;
    float hd = LumiSampleSceneEyeDepth(huv);
    float ppm = _ScreenParams.y * 0.5 * abs(UNITY_MATRIX_P._m11) / max(hd, 0.05);
#if defined(LUMI_RT_PYRAMID)
    // the cone of the rough reflection at the distance of the hit, read from the blurred screen
    float rpx = ht * a * 0.9 * ppm;
    [branch] if (rpx > 0.75) sc = LumiRTPyr(huv, log2(rpx), hd);
#else
    float rpx = min(ht * a * 0.7 * ppm, 48.0);
    [branch] if (rpx > 0.75)
    {
        float2 bo = rpx / _ScreenParams.xy;
        float3 acc = sc * 2.0; float wsum = 2.0;
        [unroll] for (int k = 0; k < 6; k++)
        {
            float ang = k * 1.0471976 + noise * 6.2831853;
            float rr = (k & 1) ? 1.0 : 0.55;
            float4 ck = LumiRTGrabClean(g + float2(cos(ang), sin(ang)) * bo * rr);
            acc += LumiRTBright(ck.rgb);
            wsum += ck.a;
        }
        sc = acc / wsum;
    }
#endif
    hit *= 1.0 - smoothstep(0.7, 1.0, ht / _RTReflLength);
    return lerp(env, sc, hit * amount);
#else
    return env;
#endif
}

// Depth aware poisson blur of the screen space directional shadow mask = soft shadows without the shadow map stair steps
#if defined(LUMI_HAS_SCREEN_SHADOW)
float LumiSoftScreenShadow(float3 posWS, float3 N, float3 L, float2 screenUV, float eyeDepth, float2 pixel)
{
    float sum = LumiSampleScreenShadow(screenUV);
#if defined(_LUMI_SOFTSHADOW)
    float wsum = 1;
    float pixelsPerMeter = _ScreenParams.y * 0.5 * abs(UNITY_MATRIX_P._m11) / max(eyeDepth, 0.01);
    float rPix = clamp(_SoftShadowRadius * pixelsPerMeter, 0, 48);
    float2 texel = 1.0 / _ScreenParams.xy;
    bool edge;
    // early out: the blur only matters near a shadow edge. 4 reads at the full radius; when they and the centre
    // agree (fully lit / fully shadowed, most of the screen) the blur would return the same value.
    {
        float2 r = rPix * texel;
        float4 q = float4(LumiSampleScreenShadow(screenUV + float2(r.x, 0)), LumiSampleScreenShadow(screenUV - float2(r.x, 0)),
                          LumiSampleScreenShadow(screenUV + float2(0, r.y)), LumiSampleScreenShadow(screenUV - float2(0, r.y)));
        float lo = min(min(min(q.x, q.y), min(q.z, q.w)), sum), hi = max(max(max(q.x, q.y), max(q.z, q.w)), sum);
        edge = hi - lo >= 0.01;
    }
    [branch] if (edge)
    {
        #if defined(_LUMI_COMPAT)
    float rot = LumiIGN(pixel) * 6.2831853;   // lilToon mode: no quad average of the cast shadow (see fragBase)
#else
    float rot = LumiSSNoise(pixel, posWS, _SoftShadowRadius, 0) * 6.2831853;
#endif
        int n = (int)clamp(_SoftShadowSamples, 4, 8);   // capped: 2 reads per sample per pixel
        bool depthOK = LumiDepthValidity(screenUV, eyeDepth) > 0.5;
        [loop] for (int i = 0; i < n; i++)
        {
            float fi = (i + 0.5) / n;
            float s, c; sincos(i * 2.3999632 + rot, s, c);
            float2 uv = screenUV + float2(c, s) * (sqrt(fi) * rPix) * texel;
            float sh = LumiSampleScreenShadow(uv);
            float w = 1;
            if (depthOK)
            {
                float d = LumiSampleSceneEyeDepth(uv);
                w = saturate(1.0 - abs(d - eyeDepth) / (0.03 + eyeDepth * 0.03));
            }
            sum += sh * w;
            wsum += w;
        }
        sum /= wsum;
    }
#endif
    return sum;
}
#endif

#endif

