// MitToon Shader - Built-in RP adapter.
// Everything pipeline specific lives here (and in the Pass files). To port to URP, write MitToonPlatformURP.hlsl
// providing the same functions (LumiGetMainLight / LumiSampleSH / LumiSampleEnvironment / LumiSampleSceneDepth ...)
#ifndef MITTOON_PLATFORM_BIRP_INCLUDED
#define MITTOON_PLATFORM_BIRP_INCLUDED

#include "UnityCG.cginc"
#include "UnityLightingCommon.cginc"
#include "AutoLight.cginc"
#include "MitToonInput.hlsl"

#define MITTOON_BIRP 1

struct LumiLight
{
    float3 direction;           // surface -> light
    float3 color;
    float  distanceAttenuation;
    float  shadowAttenuation;
};

// declared as a real texture object (not sampler2D) so its size can be queried with GetDimensions
#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    Texture2DArray<float> _CameraDepthTexture;
    #define LUMI_DEPTH_SAMPLE(uv) _CameraDepthTexture.SampleLevel(sampler_CameraDepthTexture, float3((uv), unity_StereoEyeIndex), 0)
#else
    Texture2D<float> _CameraDepthTexture;
    #define LUMI_DEPTH_SAMPLE(uv) _CameraDepthTexture.SampleLevel(sampler_CameraDepthTexture, (uv), 0)
#endif
SamplerState sampler_CameraDepthTexture;
float4 _CameraDepthTexture_TexelSize;

float3 LumiGetCameraPositionWS()
{
#if defined(USING_STEREO_MATRICES)
    return (unity_StereoWorldSpaceCameraPos[0] + unity_StereoWorldSpaceCameraPos[1]) * 0.5;
#else
    return _WorldSpaceCameraPos;
#endif
}
float3 LumiGetEyePositionWS() { return _WorldSpaceCameraPos; }

float3 LumiObjectToWorld(float3 p)   { return mul(unity_ObjectToWorld, float4(p, 1)).xyz; }
float3 LumiObjectToWorldDir(float3 d){ return UnityObjectToWorldDir(d); }
float3 LumiObjectToWorldNormal(float3 n) { return UnityObjectToWorldNormal(n); }
float4 LumiWorldToClip(float3 p)     { return UnityWorldToClipPos(p); }
float3 LumiWorldToViewDir(float3 d)  { return mul((float3x3)UNITY_MATRIX_V, d); }
float3 LumiViewToWorldDir(float3 d)  { return mul((float3x3)UNITY_MATRIX_I_V, d); }
float  LumiProjScaleY()             { return abs(UNITY_MATRIX_P._m11); }
float  LumiEyeDepth(float3 posWS)    { return -mul(UNITY_MATRIX_V, float4(posWS, 1)).z; }

float4 LumiComputeScreenPos(float4 posCS) { return ComputeScreenPos(posCS); }

// ---- Ambient --------------------------------------------------------------
// VRC Light Volumes: only compiled into the variant that enables it, so the package stays optional.
#if defined(_LUMI_LIGHTVOLUMES)
    #if defined(_LUMI_LV_LITE)
        // lite: per light shadows, cookies and area lights are compiled out (big saving in light heavy worlds)
        #define VRCLV_DISABLE_SHADOWS
        #define VRCLV_DISABLE_AREA_LIGHTS
        #define VRCLV_DISABLE_POINT_COOKIES
        #define VRCLV_DISABLE_SPOT_COOKIES
    #endif
    #include "Packages/red.sim.lightvolumes/Shaders/LightVolumes.cginc"
#endif
static float  lumiLVActive = 0;
static float3 lumiL0 = 0, lumiL1r = 0, lumiL1g = 0, lumiL1b = 0;
static float3 lumiLVSpec = 0;

#if defined(_LUMI_LIGHTVOLUMES)
void LumiLVScaleAdd(float k, float3 a0, float3 ar, float3 ag, float3 ab)
{
    lumiL0 += a0 * k; lumiL1r += ar * k; lumiL1g += ag * k; lumiL1b += ab * k;
}
#endif

bool LumiLVOn()
{
#if defined(_LUMI_LIGHTVOLUMES)
    return LightVolumesEnabled() > 0.5 && LightVolumesVersion() >= VRCLV_MIN_SUPPORTED_VERSION;
#else
    return false;
#endif
}

// Light volume L0/L1 at a vertex (or at any point), packed into 3 float4 (L0.rgb L1r.x / L1r.yz L1g.xy / L1g.z L1b).
// Evaluated per vertex: the volumes are low resolution, and per pixel the lookup loops over every volume and
// every point light volume, which is far too heavy for an avatar.
void LumiLVVertex(float3 posWS, float3 N, out float4 p0, out float4 p1, out float4 p2)
{
    p0 = 0; p1 = 0; p2 = 0;
#if defined(_LUMI_LIGHTVOLUMES)
    [branch] if (LumiLVOn())
    {
        // sampling partly at the object centre keeps the body evenly lit (no blotches between voxels),
        // the normal offset keeps the sample out of walls the skin is touching
        float3 center = unity_ObjectToWorld._m03_m13_m23;
        float3 pV = lerp(posWS, center, _LVObjectCenter) + N * (_LVNormalOffset * (1.0 - _LVObjectCenter));
        lumiL0 = 0; lumiL1r = 0; lumiL1g = 0; lumiL1b = 0;
    #if VRCLV_VERSION == 3
        // regular / additive / point light volumes separately, each with its own strength
        float3 a0 = 0, ar = 0, ag = 0, ab = 0;
        LV_LightVolumeRegularSH(pV, a0, ar, ag, ab);
        LumiLVScaleAdd(_LVRegular, a0, ar, ag, ab);
        a0 = 0; ar = 0; ag = 0; ab = 0;
        LV_LightVolumeAdditiveSH(pV, a0, ar, ag, ab);
        LumiLVScaleAdd(_LVAdditive, a0, ar, ag, ab);
        [branch] if (_LVPointLights > 0.001)
        {
            a0 = 0; ar = 0; ag = 0; ab = 0;
            LV_PointLightVolumeSH(posWS, N, _LVPointShading, a0, ar, ag, ab);
            LumiLVScaleAdd(_LVPointLights, a0, ar, ag, ab);
        }
    #else
        // other package versions: public API only (one strength for everything)
        LightVolumeSH(posWS, lumiL0, lumiL1r, lumiL1g, lumiL1b, pV - posWS, N, _LVPointShading);
    #endif
        // saturation / minimum, then overall strength
        float lum = dot(lumiL0, float3(0.2126, 0.7152, 0.0722));
        lumiL0 = max(lerp(lum.xxx, lumiL0, _LVSaturation), 0);
        float3 l1l = lumiL1r * 0.2126 + lumiL1g * 0.7152 + lumiL1b * 0.0722;
        lumiL1r = lerp(l1l, lumiL1r, _LVSaturation); lumiL1g = lerp(l1l, lumiL1g, _LVSaturation); lumiL1b = lerp(l1l, lumiL1b, _LVSaturation);
        lumiL0 = max(lumiL0, _LVMinBrightness);
        p0 = float4(lumiL0, lumiL1r.x) * _LVStrength;
        p1 = float4(lumiL1r.yz, lumiL1g.xy) * _LVStrength;
        p2 = float4(lumiL1g.z, lumiL1b) * _LVStrength;
    }
#endif
}

// Call once per pixel before shading with the interpolated light volume SH from LumiLVVertex.
// wantSpec: also evaluate the light volume specular (base pass) for the given f0 / smoothness.
void LumiSetupAmbient(float4 p0, float4 p1, float4 p2, float3 N, float3 V, float3 f0, float smoothness, bool wantSpec)
{
#if defined(_LUMI_LIGHTVOLUMES)
    if (LumiLVOn())
    {
        lumiL0 = p0.rgb; lumiL1r = float3(p0.w, p1.xy); lumiL1g = float3(p1.zw, p2.x); lumiL1b = p2.yzw;
        lumiLVSpec = 0;
        [branch] if (wantSpec && _LVSpecularMode < 1.5 && _LVSpecular > 0.001)
        {
            lumiLVSpec = _LVSpecularMode < 0.5 ? LightVolumeSpecular(f0, smoothness, N, V, lumiL0, lumiL1r, lumiL1g, lumiL1b)
                                               : LightVolumeSpecularDominant(f0, smoothness, N, V, lumiL0, lumiL1r, lumiL1g, lumiL1b);
        }
        lumiLVActive = 1;
    }
#endif
}
// SH for the compatible shading light. Light volumes replace L0 / L1 and drop L2 (lv = 1 then).
void LumiCompatSH(out float4 Ar, out float4 Ag, out float4 Ab, out float4 Br, out float4 Bg, out float4 Bb, out float3 Cc, out float lv)
{
    Ar = unity_SHAr; Ag = unity_SHAg; Ab = unity_SHAb; Br = unity_SHBr; Bg = unity_SHBg; Bb = unity_SHBb; Cc = unity_SHC.rgb;
    lv = lumiLVActive;
    if (lumiLVActive > 0.5)
    {
        Ar = float4(lumiL1r, lumiL0.r); Ag = float4(lumiL1g, lumiL0.g); Ab = float4(lumiL1b, lumiL0.b);
        Br = 0; Bg = 0; Bb = 0; Cc = 0;
    }
}
float3 LumiEvalL1(float3 n) { return lumiL0 + float3(dot(lumiL1r, n), dot(lumiL1g, n), dot(lumiL1b, n)); }
float3 LumiSampleSH(float3 n)
{
    if (lumiLVActive > 0.5) return max(LumiEvalL1(n), 0);
    return max(ShadeSH9(float4(n, 1)), 0);
}
float3 LumiSampleSHAverage()
{
    if (lumiLVActive > 0.5) return max(lumiL0, 0);
    return max(float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w) + float3(unity_SHBr.z, unity_SHBg.z, unity_SHBb.z) / 3.0, 0);
}
float3 LumiSHDominantDirection()
{
    if (lumiLVActive > 0.5) return (lumiL1r + lumiL1g + lumiL1b) * 0.333333;
    return unity_SHAr.xyz * 0.333333 + unity_SHAg.xyz * 0.333333 + unity_SHAb.xyz * 0.333333;
}
void LumiGetSHL1(out float3 r, out float3 g, out float3 b)
{
    if (lumiLVActive > 0.5) { r = lumiL1r; g = lumiL1g; b = lumiL1b; return; }
    r = unity_SHAr.xyz; g = unity_SHAg.xyz; b = unity_SHAb.xyz;
}
// Blurred probe radiance (mip 6) used to match reflection brightness with the world's diffuse light
float3 LumiSampleProbeDiffuse(float3 R)
{
    return DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, R, 6.0), unity_SpecCube0_HDR);
}
// Extra specular from light volume SH (L1 dominant direction highlight)
float3 LumiLightVolumeSpecular(float3 f0, float smoothness, float3 N, float3 V)
{
    return lumiLVActive > 0.5 ? lumiLVSpec : 0;
}

// Luminance weighted direction toward nearby point lights (vertex lights). lum = summed received luminance
// The pixel shader gets the per vertex result (VERTEXLIGHT_ON only exists in the vertex stage).
static float  lumiPointReady = 0;
static float3 lumiPointDir = 0;
static float  lumiPointLum = 0;
static float3 lumiCompatVL = 0;    // compatible shading: vertex lights, added to the main light colour
static float  lumiCompatFA = 0;    // compatible shading: 1 while shading an extra (ForwardAdd) light
float3 LumiPointLightDirection(float3 posWS, out float lum)
{
    float3 acc = 0; lum = 0;
    if (lumiPointReady > 0.5) { lum = lumiPointLum; return lumiPointDir; }
#if defined(VERTEXLIGHT_ON)
    [unroll] for (int k = 0; k < 4; k++)
    {
        float3 toL = float3(unity_4LightPosX0[k], unity_4LightPosY0[k], unity_4LightPosZ0[k]) - posWS;
        float d2 = max(dot(toL, toL), 1e-6);
        float range = 5.0 * rsqrt(max(unity_4LightAtten0[k], 1e-6));
        float a = (1.0 / (1.0 + d2 * unity_4LightAtten0[k])) * saturate(1.0 - d2 / (range * range));
        float l = dot(unity_LightColor[k].rgb, float3(0.2126, 0.7152, 0.0722)) * a * _VertexLightStrength;   // strength 0 = ignored entirely
        acc += toL * rsqrt(d2) * l;
        lum += l;
    }
#endif
    return acc;
}

// ---- Main light -----------------------------------------------------------
LumiLight LumiGetMainLight()
{
    LumiLight l;
    l.direction = _WorldSpaceLightPos0.xyz;
    l.color = _LightColor0.rgb;
    l.distanceAttenuation = 1;
    l.shadowAttenuation = 1;
    return l;
}

// ---- Reflection probes ----------------------------------------------------
float3 LumiBoxProject(float3 dir, float3 posWS, float4 probePos, float4 boxMin, float4 boxMax)
{
    UNITY_BRANCH
    if (probePos.w > 0)
    {
        float3 nrdir = dir;
        float3 rbmax = (boxMax.xyz - posWS) / nrdir;
        float3 rbmin = (boxMin.xyz - posWS) / nrdir;
        float3 rbminmax = (nrdir > 0.0f) ? rbmax : rbmin;
        float fa = min(min(rbminmax.x, rbminmax.y), rbminmax.z);
        dir = posWS - probePos.xyz + nrdir * fa;
    }
    return dir;
}
float3 LumiSampleEnvironment(float3 R, float3 posWS, float perceptualRough, float cubeMode, float cubeIntensity)
{
    float mip = perceptualRough * (1.7 - 0.7 * perceptualRough) * 6.0;
    float3 env = 0;
    if (cubeMode > 2.5)
    {
        // Procedural sky: no cubemap needed. Gradient + sun lobe from the main light, blurred by roughness.
        float y = R.y;
        float3 sky = lerp(_SkyHorizonColor.rgb, _SkyTopColor.rgb, saturate(y * (1.5 - perceptualRough)));
        sky = lerp(sky, _SkyGroundColor.rgb, smoothstep(0.0, -0.08 - perceptualRough * 0.4, y));
        float sp = exp2(lerp(9.0, 1.0, perceptualRough));
        float sun = pow(saturate(dot(R, _WorldSpaceLightPos0.xyz)), sp) * (sp + 2.0) / 8.0;
        return (sky + _LightColor0.rgb * sun) * cubeIntensity;
    }
    if (cubeMode != 1)
    {
        float3 r0 = LumiBoxProject(R, posWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
        float4 e0 = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, r0, mip);
        env = DecodeHDR(e0, unity_SpecCube0_HDR);
        UNITY_BRANCH
        if (unity_SpecCube0_BoxMin.w < 0.99999)
        {
            float3 r1 = LumiBoxProject(R, posWS, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);
            float4 e1 = UNITY_SAMPLE_TEXCUBE_SAMPLER_LOD(unity_SpecCube1, unity_SpecCube0, r1, mip);
            env = lerp(DecodeHDR(e1, unity_SpecCube1_HDR), env, unity_SpecCube0_BoxMin.w);
        }
    }
    // Fallback cubemap: always (mode 1) or when the world has no usable probe (mode 4). Mode 0 is resolved by MitToonGI (SH synthesis)
    if (cubeMode == 1 || (cubeMode > 3.5 && dot(env, 1) < 0.002))
    {
        float4 c = _ReflCube.SampleLevel(sampler_trilinear_repeat, R, mip);
        env = DecodeHDR(c, _ReflCube_HDR) * cubeIntensity;
    }
    return env;
}

// ---- Screen textures ------------------------------------------------------
// Real size of the bound depth texture. _CameraDepthTexture_TexelSize is not reliable in VRChat (the main view and
// mirrors can leave it unset or from another camera), so the texture itself is asked. Unity binds a tiny default
// texture when there is no depth, so "bigger than 16 px" means a real depth texture.
float2 LumiDepthTexSize()
{
    uint w, h;
#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    uint e;
    _CameraDepthTexture.GetDimensions(w, h, e);
#else
    _CameraDepthTexture.GetDimensions(w, h);
#endif
    return float2(w, h);
}
bool LumiDepthTextureAvailable() { float2 s = LumiDepthTexSize(); return s.x > 16 && s.y > 16; }

// Linear eye depth of a raw depth value at a screen UV. Mirrors use an oblique near plane, which changes the z row of
// the projection and breaks the _ZBufferParams formula, so the depth is solved from the projection matrix itself:
// view point (a d, b d, -d) with a, b from the screen position, and clip z / clip w = raw.
float LumiRawToEyeDepth(float raw, float2 uv)
{
    float4x4 P = UNITY_MATRIX_P;
    if (P._m33 != 0.0 || (P._m20 == 0.0 && P._m21 == 0.0)) return LinearEyeDepth(raw);
    float2 ndc = float2(uv.x * 2.0 - 1.0, (uv.y * 2.0 - 1.0) * _ProjectionParams.x);
    float z = UNITY_NEAR_CLIP_VALUE < 0.0 ? raw * 2.0 - 1.0 : raw;
    float a = (ndc.x + P._m02) / P._m00;
    float b = (ndc.y + P._m12) / P._m11;
    return P._m23 / max(z - P._m20 * a - P._m21 * b + P._m22, 1e-7);
}
float LumiSampleSceneEyeDepth(float2 uv)
{
    float raw = LUMI_DEPTH_SAMPLE(uv);
    return LumiRawToEyeDepth(raw, uv);
}

float2 LumiScreenTexelSize()     { return _ScreenParams.zw - 1.0; }

#if defined(SHADOWS_SCREEN) && !defined(UNITY_NO_SCREENSPACE_SHADOWS)
    #define LUMI_HAS_SCREEN_SHADOW 1
    // explicit LOD: also used inside the soft shadow loop, where gradient instructions are undefined
    #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
    float LumiSampleScreenShadow(float2 uv) { return UNITY_SAMPLE_TEX2DARRAY_LOD(_ShadowMapTexture, float3(uv, (float)unity_StereoEyeIndex), 0).r; }
    #else
    float LumiSampleScreenShadow(float2 uv) { return tex2Dlod(_ShadowMapTexture, float4(uv, 0, 0)).r; }
    #endif
#endif

// ---- Fog --------------------------------------------------------------------
// The fog factor is computed per vertex and the fragment always blends with it (1 = no fog). The fog keywords
// are vertex (or domain) only, so the heavy fragment shader is not compiled 4 times (upload time).
float LumiFogFactor(float4 posCS)
{
#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    UNITY_CALC_FOG_FACTOR(posCS.z);
    return saturate(unityFogFactor);
#else
    return 1.0;
#endif
}
#define LUMI_FOG_COORDS(n)            float fogFactor : TEXCOORD##n;
#define LUMI_TRANSFER_FOG(o, pos)     o.fogFactor = LumiFogFactor(pos)
// additive render mode (4) fades to black, or the fog colour would be added on top of the scene
#define LUMI_APPLY_FOG(i, col)        col.rgb = lerp(unity_FogColor.rgb * (abs(_RenderMode - 4.0) < 0.5 ? 0.0 : 1.0), col.rgb, i.fogFactor)
#define LUMI_APPLY_FOG_BLACK(i, col)  col.rgb *= i.fogFactor

#endif
