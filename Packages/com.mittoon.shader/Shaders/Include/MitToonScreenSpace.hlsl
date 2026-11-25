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

// ---- Screen grab (clean blur) ----
#if defined(LUMI_FX_READ)
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

// ---- Clean blur (FX pass + GrabPass) ------------------------------------------------------------------------------
// The FX pass draws the surface with the noisy terms instead of the colour (AO, contact x world shadow, cast
// shadow; alpha = a mark), the grab copies them and the main pass reads them back blurred over a disk of _NoiseBlur
// pixels with gaussian weights. Taps on other objects (no mark, or another depth) are left out, so nothing bleeds
// across silhouettes. The main pass then skips computing those terms itself.
static float4 lumiFX = float4(1, 1, 1, 0);   // x = AO, y = contact * world shadow, z = cast shadow
static float3 lumiFXOut = 1;                  // this pixel's terms (FX pass)
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

// shadow ray through the depth texture (the soft shadows module's world shadow): marches posWS + dir * t (t up to
// maxDist, denser near the start) and returns how much of the light it blocks. A near miss within a cone of slope k
// around the ray counts partly, so the edge of the shadow runs as a gradient instead of flipping per pixel.
float LumiDepthMarch(float3 posWS, float3 dir, float maxDist, int steps, float thick, float jitter, float k)
{
    float soft = 0;
    // screen position (homogeneous) along the ray: linear in t, so p(t) = c0 + cd * t gives the same as projecting
    // posWS + dir * t at every step
    float4 c0 = LumiComputeScreenPos(LumiWorldToClip(posWS));
    float4 cd = LumiComputeScreenPos(LumiWorldToClip(posWS + dir)) - c0;
    [loop] for (int i = 0; i < steps; i++)
    {
        float f = (i + jitter) / steps;
        float t = maxDist * f * f;
        float4 cp = c0 + cd * t;
        float rd = cp.w;
        float2 uv = cp.xy / cp.w;
        float ew = 1.0;
        if (any(uv < 0) || any(uv > 1) || rd < 0.01)
        {
            // the step is off screen. Close to the border the surface there is taken to go on out of view (the floor
            // under a foot, a body leaving the bottom of the picture), trusted less the farther out the step is;
            // farther out it is unknown
            float2 uc = saturate(uv);
            float od = length(uv - uc);
            if (rd < 0.01 || od > 0.15) return soft;
            ew = 1.0 - od / 0.15;
            uv = uc;
        }
        float delta = rd - LumiSampleSceneEyeDepth(uv);
        float th = thick + t * 0.15;
        if (delta <= 0.003 && delta > -th)
            soft = max(soft, (1.0 - saturate((0.003 - delta) / (k * t + 0.002))) * smoothstep(0.02, 0.06, t) * ew);
        if (delta > 0.003 && delta < th) return ew;   // hit
    }
    return soft;
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
    // the part of the light that already casts a shadow of its own (shadow map along the real light) gets no second one
    float covered = 0;
#if defined(SHADOWS_SCREEN)
    covered = step(0.5, _ReceiveCastShadow);
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
        vis += 1.0 - LumiDepthMarch(start, dir, _PCSSWorldShadowLength, 12, 0.2, frac(noise + r * 0.618034), max(cone, 0.03));
    }
    return lerp(1.0, vis * 0.5, amount);
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

