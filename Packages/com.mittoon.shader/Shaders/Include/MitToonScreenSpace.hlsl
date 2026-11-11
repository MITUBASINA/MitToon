// MitToon Shader - per pixel screen space effects using the camera depth texture (no post process needed)
// Requires: LumiSampleSceneEyeDepth, LumiDepthTextureAvailable, LumiWorldToClip, LumiComputeScreenPos (Platform file)
#ifndef MITTOON_SCREENSPACE_INCLUDED
#define MITTOON_SCREENSPACE_INCLUDED

#include "MitToonCommon.hlsl"

// 1 when a depth texture is bound. The depth of this very pixel is NOT compared with our own depth: in the VRChat
// main view and in mirrors the depth texture can be rendered at another resolution / with another camera setup, so
// such a check switched the effects off there although the depth was usable.
// 1 when the depth texture really belongs to this camera: it must hold our own surface at our pixel.
// Cameras that do not make one (VRChat avatar previews, some mirrors / stream cameras) can still see the depth texture
// of another camera; reading it would put rims, AO and contact shadows in random places (white wash, colored fringes).
float LumiDepthValidity(float2 screenUV, float eyeDepth)
{
    if (!LumiDepthTextureAvailable()) return 0;
    float tol = 0.03 + eyeDepth * 0.03;
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
    float occ = 0;
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
            float2 uvS = saturate(uv0 + float2(c, s) * rp / _ScreenParams.xy);
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
    }
    return occ / n;
}

float LumiSSAO(float3 posWS, float3 N, float eyeDepth, float2 pixel, float validity, float mask)
{
#if defined(_LUMI_SSAO)
    float fade = 1.0 - LumiRemap(eyeDepth, _SSAOMaxDistance * min(_SSAOFadeStart, 0.999), _SSAOMaxDistance);
    float amount = validity * saturate(fade) * lerp(1.0, mask, _SSAOMaskStrength);
    if (amount <= 0.001) return 1;

    float R = _SSAORadius * lerp(1.0, max(eyeDepth, 0.25), _SSAODistanceScale);
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
        [branch] if (occl < 0.004) return 1;
    }
    float3 t = normalize(cross(N, abs(N.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 b = cross(N, t);
    float noise = lerp(0.5, LumiIGN(pixel), _SSAOJitter);
    int n = (int)clamp(_SSAOSamples, 4, 8);   // capped: every sample is a depth read per pixel
    float softD = max(0.01 * _SSAOSoftness / 0.35, 0.001);   // 0.35 = 1 cm, the original range
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
    float scale = lerp(1.0, max(eyeDepth, 0.25), _ContactShadowDistanceScale);
    float len = _ContactShadowLength * scale, thick = _ContactShadowThickness * scale;
    int steps = (int)clamp(_ContactShadowSteps, 4, 8);
    float jitter = lerp(0.5, LumiIGN(pixel + 17.0), _ContactShadowJitter);
    float3 start = posWS + N * _ContactShadowBias;
    float minD = _ContactShadowMinDelta;
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
            float w = _ContactShadowSoftness > 0.0001 ? smoothstep(minD, minD + _ContactShadowSoftness, delta) : 1.0;
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
    float k = widthCm * 0.01 * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05);
    float2 offs = dir * k * float2(_ScreenParams.y / _ScreenParams.x, 1.0);
    float2 uv = saturate(screenUV + offs);
    float scene = LumiSampleSceneEyeDepth(uv);
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
    float px = clamp(0.006 * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y, 1.0, 12.0);
    float2 uv = saturate(screenUV + dn * px / _ScreenParams.xy);
    float diff = LumiSampleSceneEyeDepth(uv) - LumiPlaneDepth(normalize(nV), screenUV, eyeDepth, uv);
    return smoothstep(0.1, 0.25, diff) * validity;
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
        float px = _OffsetRimWidth * 0.01 * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y;
        px = min(px, _OffsetRimMaxPx);
        float2 uv = saturate(screenUV + dir * px / _ScreenParams.xy);
        float diff = LumiSampleSceneEyeDepth(uv) - LumiPlaneDepth(normalize(nV), screenUV, eyeDepth, uv);
        r = smoothstep(_OffsetRimThreshold * (1.0 - _OffsetRimSoftness * 0.9), _OffsetRimThreshold, diff);
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
    float px = _DepthShadowWidth * 0.01 * 0.5 * LumiProjScaleY() / max(eyeDepth, 0.05) * _ScreenParams.y;
    px = min(px, _DepthShadowMaxPx);
    float2 uv = saturate(screenUV + dir * px / _ScreenParams.xy);
    float diff = eyeDepth - LumiSampleSceneEyeDepth(uv);
    float sh = smoothstep(_DepthShadowThreshold * (1.0 - _DepthShadowSoftness * 0.9), _DepthShadowThreshold, diff);
    sh *= saturate(1.0 - diff / 0.5);   // ignore far occluders (other objects)
    return 1.0 - sh * _DepthShadowStrength;
#else
    return 1;
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
        float rot = LumiIGN(pixel) * 6.2831853;
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

