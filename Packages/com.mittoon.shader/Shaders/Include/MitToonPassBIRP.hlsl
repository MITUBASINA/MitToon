// MitToon Shader - Built-in RP passes (ForwardBase / ForwardAdd / Outline / ShadowCaster)
#ifndef MITTOON_PASS_BIRP_INCLUDED
#define MITTOON_PASS_BIRP_INCLUDED

#include "MitToonPlatformBIRP.hlsl"
#include "MitToonLighting.hlsl"

// PCSS soft shadows of shadowed spot lights (see LumiPCSS) and the shadow light (see fragShadowLight)
#if defined(SPOT) && defined(SHADOWS_DEPTH) && defined(SHADOWS_NATIVE) && !defined(SHADER_API_MOBILE)
#define LUMI_HAS_PCSS 1
#endif

struct appdata
{
    float4 vertex  : POSITION;
    float3 normal  : NORMAL;
    float4 tangent : TANGENT;
    float2 uv0     : TEXCOORD0;
    float2 uv1     : TEXCOORD1;
    float4 color   : COLOR;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float4 pos       : SV_POSITION;
    float4 uv01      : TEXCOORD0;
    float3 posWS     : TEXCOORD1;
    float3 normalWS  : TEXCOORD2;
    float4 tangentWS : TEXCOORD3;
    float4 color     : TEXCOORD4;
    float4 screenPos : TEXCOORD5;
    float4 posOS     : TEXCOORD6;    // w: the avatar's scale (LumiVertexScale)
    UNITY_SHADOW_COORDS(7)
    LUMI_FOG_COORDS(8)
#if defined(UNITY_PASS_FORWARDBASE)
    float4 probe0    : TEXCOORD9;    // scenery probe SH: L0.rgb, L1r.x
    float4 probe1    : TEXCOORD10;   // L1r.yz, L1g.xy
    float4 probe2    : TEXCOORD11;   // L1g.z, L1b.xyz
    // the 4 vertex lights, shaded per vertex. Always declared: VERTEXLIGHT_ON is a vertex stage only keyword, the
    // pixel shader never sees it, so the data has to come through the interpolators.
    float4 vlight    : TEXCOORD12;   // rgb: vertex light colour, a: their summed luminance (light direction hint)
    float3 vlightDir : TEXCOORD16;   // luminance weighted direction toward them
    #if defined(_LUMI_LIGHTVOLUMES)
    float4 lv0       : TEXCOORD13;   // light volume SH per vertex (see LumiLVVertex)
    float4 lv1       : TEXCOORD14;
    float4 lv2       : TEXCOORD15;
    #endif
#endif
#if defined(LUMI_RT_COMPOSITE)
    float4 rtgi0     : TEXCOORD17;   // ray traced bounce probe per vertex (see LumiRTGIVertex)
    float4 rtgi1     : TEXCOORD18;
    float4 rtgi2     : TEXCOORD19;
#endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

// ---------------------------------------------------------------------------
// FPS mode: coherent noise that only changes every 1/FPS seconds (hand drawn "boiling" at a low frame rate)
float LumiObjectScale() { return length(unity_ObjectToWorld._m00_m10_m20); }
// the avatar's scale. Skinned meshes are drawn with the scale of their bones baked into the vertices and a matrix
// without it, but their normals keep it (Unity does not normalise them again after skinning). The lengths given in
// m / cm (outline width, depth rim, depth shadow ...) follow it, so a resized avatar (VRChat avatar scaling, the small
// avatar of the menu preview) keeps its look.
float LumiVertexScale(float3 normalOS)
{
    float l = length(normalOS);
    float s = LumiObjectScale() * (l > 1e-4 ? l : 1.0);
    return lerp(1.0, clamp(s, 1e-3, 1e3), _AvatarScaleFollow);
}
float3 LumiFPSOffsetOS(float3 posOS, float3 normalOS)
{
#if defined(_LUMI_FPSMODE)
    float scale = max(LumiObjectScale(), 1e-4);
    float frame = floor(_Time.y * max(_FPSRate, 1.0));
    float3 p = posOS * scale * _FPSFreq;
    float3 n = float3(LumiValueNoise3(p + frame * 7.13), LumiValueNoise3(p + frame * 3.71 + 17.0), LumiValueNoise3(p + frame * 5.37 + 41.0)) - 0.5;
    float3 dir = lerp(n * 2.0, normalize(normalOS) * (n.x * 2.0), _FPSNormal);
    float3 o = posOS + dir * (_FPSAmp * 0.01 / scale);
    if (_FPSSnap > 0.0001)
    {
        float g = _FPSSnap * 0.01 / scale;
        o = round(o / g) * g;
    }
    return o - posOS;
#else
    return 0;
#endif
}
float LumiFPSWidthJitter(float3 posOS)
{
#if defined(_LUMI_FPSMODE)
    float frame = floor(_Time.y * max(_FPSRate, 1.0));
    float n = LumiValueNoise3(posOS * LumiObjectScale() * _FPSFreq * 0.5 + frame * 11.7);
    return 1.0 + (n - 0.5) * 2.0 * _FPSWidthJitter;
#else
    return 1;
#endif
}

// perspective removal: project around the center depth (orthographic like), strongest when close
// Off in VR (stereo rendering) and in VR mirrors (VRChat renders them per eye, _VRChatMirrorMode 1): each eye has
// an off-axis projection, so flattening per eye breaks the stereo pair (the face looks like a flat card at a wrong
// depth). VR has no close-up lens distortion to fix anyway. Desktop view, cameras and desktop mirrors keep it.
float4 LumiPerspectiveRemoval(float4 posCS)
{
#if defined(USING_STEREO_MATRICES)
    return posCS;
#else
    if (_PerspectiveRemoval <= 0.001 || abs(_VRChatMirrorMode - 1.0) < 0.5) return posCS;
    float3 cWS = LumiObjectToWorld(_PerspectiveCenter.xyz);
    float4 cCS = LumiWorldToClip(cWS);
    float dist = distance(cWS, LumiGetCameraPositionWS());
    float k = _PerspectiveRemoval * saturate(1.0 - dist / max(_PerspectiveRange, 0.01));
    if (k <= 0 || cCS.w <= 0.01) return posCS;
    float2 ndc = posCS.xy / posCS.w;
    float2 flat = posCS.xy / cCS.w;
    posCS.xy = lerp(ndc, flat, k) * posCS.w;
    return posCS;
#endif
}

// ink line: width follows the stroke direction on screen like a flat pen (swells and tapers)
float LumiInkWeight(float3 posOS, float3 normalOS)
{
#if defined(_LUMI_INKLINE)
    float3 posWS = LumiObjectToWorld(posOS);
    float3 N = normalize(LumiObjectToWorldNormal(normalOS));
    float3 V = normalize(LumiGetCameraPositionWS() - posWS);
    float3 R = cross(float3(0, 1, 0), V);
    R = dot(R, R) > 1e-4 ? normalize(R) : UNITY_MATRIX_V[0].xyz;
    float3 U = cross(V, R);
    float2 ln = float2(dot(N, R), dot(N, U));
    ln /= max(length(ln), 1e-4);
    float ang = radians(_InkAngle);
    float pen = abs(ln.x * cos(ang) + ln.y * sin(ang));
    pen = saturate((pen - _InkGap) / max(1.0 - _InkGap, 1e-3));
    float w = lerp(_InkMin, 1.0, pow(pen, _InkTaper));
    if (dot(_InkUnderDir.xyz, _InkUnderDir.xyz) > 1e-6) w *= lerp(1.0, 1.0 - dot(N, normalize(_InkUnderDir.xyz)), _InkUnder);
    if (_InkNoise > 0.001) w *= lerp(1.0, smoothstep(0.2, 0.7, LumiValueNoise3(posOS * LumiObjectScale() * _InkNoiseFreq)), _InkNoise);
    return lerp(1.0, w, _InkStrength) * _InkWidth;
#else
    return 1;
#endif
}

#define LUMI_NAN4 (float4(0, 0, -1, 1) * asfloat(0x7fc00000))
// mirror / camera / UV tile visibility: the vertex collapses, nothing is rasterised (all passes, incl. shadows)
bool LumiHidden(appdata v)
{
    bool mirror = _VRChatMirrorMode > 0.5;
    bool cam = _VRChatCameraMode > 0.5;
    if (_MirrorVisibility > 0.5 && (_MirrorVisibility < 1.5) != mirror) return true;
    if (_CameraVisibility > 0.5 && (_CameraVisibility < 1.5) == cam) return true;
    if (_UVTileHide > 0.5)
    {
        float2 t = floor(_UVTileUV < 0.5 ? v.uv0 : v.uv1);
        if (all(t >= 0) && all(t < 4))
            if (fmod(floor(_UVTileHide / exp2(t.x + t.y * 4)), 2) > 0.5) return true;
    }
    return false;
}
// soft sway (hair tips, ribbons, plants): relative to the object so walking does not change the wave
float3 LumiWobbleWS(float3 posWS, appdata v)
{
    if (_WobbleStrength <= 0.0001) return 0;
    float m = _WobbleMask.SampleLevel(sampler_trilinear_repeat, LUMI_TF(_WobbleMask, v.uv0), 0).r * lerp(1, v.color.r, _WobbleVertexColor);
    float3 dir = normalize(_WobbleDir.xyz + float3(1e-5, 0, 0));
    float3 p = posWS - unity_ObjectToWorld._m03_m13_m23;
    float t = _Time.y * _WobbleSpeed;
    float ph = (dot(p, dir) + p.y) * _WobbleFrequency * 6.2831853 - t;
    float w = sin(ph) + _WobbleGust * 0.6 * sin(ph * 2.37 + t * 0.61) * (0.6 + 0.4 * sin(t * 0.23));
    return dir * (w * m * _WobbleStrength * 0.01);
}

// the 4 vertex lights (unimportant point lights) shaded per vertex: diffuse only, toon border on the vertex normal.
// Per pixel they cost 4 full light evaluations.
float3 LumiVertexLights(float3 posWS, float3 N)
{
    float3 sum = 0;
#if defined(VERTEXLIGHT_ON)
    float bw = max(max(_ShadowBlur, _AddLightSoftness * 0.5), 0.05);
    [unroll] for (int k = 0; k < 4; k++)
    {
        float3 toL = float3(unity_4LightPosX0[k], unity_4LightPosY0[k], unity_4LightPosZ0[k]) - posWS;
        float d2 = max(dot(toL, toL), 1e-6);
        // matches Unity vertex light falloff, faded to 0 at range
        float range = 5.0 * rsqrt(max(unity_4LightAtten0[k], 1e-6));
        float atten = (1.0 / (1.0 + d2 * unity_4LightAtten0[k])) * saturate(1.0 - d2 / (range * range));
        float3 lc = LumiLimitMax(LumiKeepChroma(unity_LightColor[k].rgb * _VertexLightStrength, _LightColorStrength) * atten) * _AddLightStrength;
        lc = lerp(lc, LumiLuminance(lc).xxx, _AddLightMonochrome);
        lc *= min(1.0, _AddLightMaxLimit / max(LumiLuminance(lc), 1e-4));
        float NoL = dot(N, toL * rsqrt(d2));
        NoL = lerp(NoL, NoL * 0.5 + 0.5, _AddLightPassthrough);
        if (_LightMapMode > 2.5 && _LightMapMode < 3.5) NoL = 1;
        float lit = lerp(1.0, smoothstep(_ShadowBorder - bw, _ShadowBorder + bw, NoL * 0.5 + 0.5), _ShadowStrength);
        sum += lc * lerp(saturate(NoL), lit, _ToonAmount);
    }
#endif
    return sum;
}

#if defined(_LUMI_COMPAT)
// compatible shading: the vertex lights summed into one colour without direction, with the source shader's falloff curve;
// the base shading adds it to the main light colour before the light limits
float3 LumiCompatVertexLights(float3 posWS)
{
    float3 lc = 0;
#if defined(VERTEXLIGHT_ON)
    float4 tx = unity_4LightPosX0 - posWS.x, ty = unity_4LightPosY0 - posWS.y, tz = unity_4LightPosZ0 - posWS.z;
    float4 d2 = tx * tx + ty * ty + tz * tz + 0.000001;
    float4 at = saturate(saturate((25.0 - d2 * unity_4LightAtten0) * 0.111375) / (0.987725 + d2 * unity_4LightAtten0)) * _VertexLightStrength;
    lc = unity_LightColor[0].rgb * at.x + unity_LightColor[1].rgb * at.y + unity_LightColor[2].rgb * at.z + unity_LightColor[3].rgb * at.w;
#endif
    return lc;
}
#endif

v2f vert(appdata v)
{
    v2f o;
    UNITY_INITIALIZE_OUTPUT(v2f, o);
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
#if defined(_LUMI_FPSMODE)
    if (_FPSTarget > 0.5) v.vertex.xyz += LumiFPSOffsetOS(v.vertex.xyz, v.normal);
#endif
    o.posWS = LumiObjectToWorld(v.vertex.xyz);
    if (_WobbleStrength > 0.0001)
    {
        o.posWS += LumiWobbleWS(o.posWS, v);
        v.vertex.xyz = mul(unity_WorldToObject, float4(o.posWS, 1)).xyz;
    }
    o.normalWS = LumiObjectToWorldNormal(v.normal);
    o.posOS = float4(v.vertex.xyz, LumiVertexScale(v.normal));
    o.pos = LumiPerspectiveRemoval(UnityWorldToClipPos(o.posWS));
    if (LumiHidden(v)) o.pos = LUMI_NAN4;
    o.uv01 = float4(v.uv0, v.uv1);
    o.tangentWS = float4(LumiObjectToWorldDir(v.tangent.xyz), v.tangent.w * unity_WorldTransformParams.w);
    o.color = v.color;
    o.screenPos = ComputeScreenPos(o.pos);
    UNITY_TRANSFER_SHADOW(o, v.uv1);
    LUMI_TRANSFER_FOG(o, o.pos);
#if defined(UNITY_PASS_FORWARDBASE)
    {
        float3 p0, pr, pg, pb;
        LumiProbeSH(p0, pr, pg, pb);
        o.probe0 = float4(p0, pr.x);
        o.probe1 = float4(pr.yz, pg.xy);
        o.probe2 = float4(pg.z, pb);
    }
    #if defined(VERTEXLIGHT_ON)
    {
        float pl;
        o.vlightDir = LumiPointLightDirection(o.posWS, pl);
        o.vlight = float4(LumiVertexLights(o.posWS, normalize(o.normalWS)), pl);
#if defined(_LUMI_COMPAT)
        o.vlight.rgb = LumiCompatVertexLights(o.posWS);
#endif
    }
    #endif
    #if defined(_LUMI_LIGHTVOLUMES)
    LumiLVVertex(o.posWS, normalize(o.normalWS), o.lv0, o.lv1, o.lv2);
    #endif
#endif
#if defined(LUMI_RT_COMPOSITE)
    LumiRTGIVertex(o.posWS, o.normalWS, o.rtgi0, o.rtgi1, o.rtgi2);
#endif
    // passes that would draw nothing are not rasterised at all (no pixel runs): the FX pass with the blur off, the
    // RayTrace composite pass with nothing to add (ray tracing off, bounce and reflections off, see through surfaces
    // (not in the depth texture), no depth texture)
#if defined(LUMI_FX_WRITE)
    if (!LumiFXActive()) o.pos = LUMI_NAN4;
#endif
    // the shadow light (a shadowed spot of almost no brightness) is drawn by its own pass (fragShadowLight), only on
    // surfaces with PCSS that it can darken; every other light by the additive light pass
#if defined(UNITY_PASS_FORWARDADD)
    bool shadowLight = max(_LightColor0.r, max(_LightColor0.g, _LightColor0.b)) < 0.02;
  #if defined(LUMI_SHADOW_LIGHT_PASS)
    #if defined(LUMI_HAS_PCSS)
    if (!shadowLight || _UsePCSS < 0.5 || abs(_DstBlendAdd - 5) > 0.5) o.pos = LUMI_NAN4;
    #else
    o.pos = LUMI_NAN4;
    #endif
  #elif defined(LUMI_HAS_PCSS)
    if (shadowLight) o.pos = LUMI_NAN4;
  #endif
#endif
#if defined(LUMI_RT_COMPOSITE)
    #if !defined(_LUMI_RAYTRACE) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
    o.pos = LUMI_NAN4;
    #else
    if (_RTGIStrength + _RTGISpecular + _RTReflStrength <= 0.001 || !LumiDepthTextureAvailable()) o.pos = LUMI_NAN4;
    #endif
#endif
    return o;
}

LumiInputData LumiBuildInput(v2f i, float facing)
{
    LumiInputData d;
    d.uv0 = i.uv01.xy;
    d.uv1 = i.uv01.zw;
    d.posWS = i.posWS;
    d.posOS = i.posOS.xyz;
    lumiAvatarScale = i.posOS.w;
    d.normalWS = i.normalWS;
    d.tangentWS = i.tangentWS;
    d.viewDirWS = normalize(LumiGetEyePositionWS() - i.posWS);
    d.color = i.color;
    d.screenUV = i.screenPos.xy / i.screenPos.w;
    d.pixelPos = i.pos.xy;
    d.eyeDepth = LumiEyeDepth(i.posWS);
    d.facing = facing;
    return d;
}

float4 LumiOutputAlpha(float4 col)
{
#if defined(_ALPHAPREMULTIPLY_ON)
    col.rgb *= col.a;
#elif defined(_ALPHATEST_ON)
    col.a = _AlphaToMask > 0.5 ? saturate(col.a) : 1;   // coverage for Alpha To Coverage (see LumiCutoutClip)
#elif !defined(_ALPHABLEND_ON)
    col.a = 1;
#endif
    return col;
}

// ---------------------------------------------------------------------------
float4 fragBase(v2f i, float facing : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
#if defined(LUMI_RT_COMPOSITE)
    lumiRTGIV0 = i.rtgi0; lumiRTGIV1 = i.rtgi1; lumiRTGIV2 = i.rtgi2;
#endif
    LumiInputData d = LumiBuildInput(i, facing > 0 ? 1 : -1);
#if defined(LUMI_RT_COMPOSITE)
#if !defined(_LUMI_RAYTRACE)
    discard;   // (pseudo ray tracing off)
#endif
    // nothing to add (bounce and reflections off): the main pass drew it all
    if (_RTGIStrength + _RTGISpecular + _RTReflStrength <= 0.001) discard;
    bool aoHand = LumiRTAOHandoff();
#if defined(LUMI_RT_PYRAMID)
    [branch] if (aoHand)
    {
        // the main pass's AO from the alpha, but at the three pixels the token of the blurred screen is in
        float2 eye = LumiEyeSize();
        int2 q = int2(LumiEyeLocal(d.screenUV) * eye), t0 = LumiRTTokenPx(eye);
        if (q.y != t0.y || q.x < t0.x || q.x > t0.x + 2) lumiRTAOIn = LUMI_GRAB_SAMPLE4(LumiGrabUV(d.screenUV)).a;
    }
#endif
#endif
#if defined(LUMI_RT_COMPOSITE)
    [branch] if (LumiScreenSpaceValidity(d) * LumiRTFade(d.eyeDepth) <= 0.001)
    {
        // every term the pass adds is scaled by these: nothing to add
        if (!aoHand) discard;
        return float4(LUMI_GRAB_SAMPLE(LumiGrabUV(d.screenUV)), 1.0);   // (the alpha back to 1 after the AO)
    }
#endif
    LumiNearDither(d);
    LumiSurface s = LumiInitSurface(d);
    lumiPixel = d.pixelPos;
#if defined(LUMI_FX_WRITE)
    if (!LumiFXActive()) discard;   // blur off: the FX pass draws nothing
#endif
#if defined(LUMI_FX_READ)
    lumiFXUse = LumiFXActive();
    [branch] if (lumiFXUse) LumiFXRead(d.screenUV, d.eyeDepth, d.pixelPos);
#endif
#if defined(_LUMI_LIGHTVOLUMES) && defined(UNITY_PASS_FORWARDBASE)
    LumiSetupAmbient(i.lv0, i.lv1, i.lv2, s.N, d.viewDirWS, s.f0, 1.0 - s.perceptualRough, true);
#endif
#if defined(UNITY_PASS_FORWARDBASE)
    lumiPL0 = i.probe0.rgb;
    lumiPL1r = float3(i.probe0.w, i.probe1.xy);
    lumiPL1g = float3(i.probe1.zw, i.probe2.x);
    lumiPL1b = i.probe2.yzw;
    lumiProbeReady = 1;
    lumiPointDir = i.vlightDir;
    lumiPointLum = i.vlight.a;
    lumiPointReady = 1;
#if defined(_LUMI_COMPAT) && defined(VERTEXLIGHT_ON)
    lumiCompatVL = i.vlight.rgb;
#endif
#endif

    UNITY_LIGHT_ATTENUATION(atten, i, i.posWS);
#if defined(LUMI_RT_COMPOSITE)
    atten = 1;   // RayTrace composite pass: the shadow does not reach the reflections / bounce it draws
#else
    [branch] if (lumiFXUse) atten = lumiFX.z;   // blurred by the FX pass + grab
    else
    {
#if defined(LUMI_HAS_SCREEN_SHADOW) && !defined(_ALPHABLEND_ON) && !defined(_ALPHAPREMULTIPLY_ON)
    [branch] if (_ReceiveCastShadow > 0.5)
    {
        float soft;
        if (_QLodDistance > 0.01 && d.eyeDepth > _QLodDistance) soft = LumiSampleScreenShadow(d.screenUV);   // far: no blur taps
        else soft = LumiSoftScreenShadow(d.posWS, normalize(d.normalWS), _WorldSpaceLightPos0.xyz, d.screenUV, d.eyeDepth, d.pixelPos);
        float zDist = dot(_WorldSpaceCameraPos - i.posWS, UNITY_MATRIX_V[2].xyz);
        float fade = UnityComputeShadowFade(UnityComputeShadowFadeDistance(i.posWS, zDist));
        atten = saturate(soft + fade);
    }
#endif
#if defined(LUMI_HAS_SCREEN_SHADOW) && !defined(_ALPHABLEND_ON) && !defined(_ALPHAPREMULTIPLY_ON) && !defined(_LUMI_COMPAT)
    atten = LumiQuadSmooth(atten.xxxx, d.eyeDepth, d.pixelPos).x;   // dots of the soft shadow taps
#endif
    if (_ReceiveCastShadow < 0.5) atten = 1;   // cast shadows off: shading, contact / depth shadows and AO stay
    }
#endif
    lumiFXOut.z = atten;
#if defined(_LUMI_SOFTSHADOW)
    atten = LumiSmoothBorder(atten, 0.5, 0.5 * max(_ShadowSmoothness, 0.01) + 0.001) * step(0.001, _ShadowSmoothness) + atten * step(_ShadowSmoothness, 0.001);
#endif

    LumiLight mainLight = LumiGetMainLight();
    mainLight.shadowAttenuation = atten;

    LumiCtx c;
    float4 col = LumiShadeBase(s, d, mainLight, c);
#if defined(LUMI_FX_WRITE)
    // (+ a vanishing use of the base colour: keeps _MainTex, whose sampler the other textures share, in the program)
    return float4(lumiFXOut + s.albedo.r * 1e-9, LUMI_FX_MARK);
#endif

#if defined(LUMI_RT_COMPOSITE)
    // RayTrace shader, second pass: the screen with this surface already drawn + what the rays found
    float4 dr = float4(lumiRTDelta * i.fogFactor, 0);
    float3 dl = lerp(dr.rgb, LumiQuadSmooth(dr, d.eyeDepth, d.pixelPos).rgb, lumiRTReflSmooth);   // dots of rough reflections only
    if (!aoHand && dot(abs(dl), 1.0) < 1e-5) discard;   // (with the AO handed over every pixel puts the alpha back to 1)
    float4 gc = LUMI_GRAB_SAMPLE4(LumiGrabUV(d.screenUV));
    return float4(max(gc.rgb + dl, 0.0), aoHand ? 1.0 : 0.0);   // (alpha: back to 1 after the AO, or kept by the blend)
#endif

#if defined(UNITY_PASS_FORWARDBASE)
#if !defined(_LUMI_COMPAT)
    col.rgb += s.diffuseColor * i.vlight.rgb * (1.0 - _AsUnlit);
#endif
#endif

    col.rgb = LumiDistanceFade(col.rgb, d, false);
    col.rgb = LumiFinalGrade(col.rgb, false);
    LUMI_APPLY_FOG(i, col);
    col = LumiOutputAlpha(col);
#if defined(LUMI_RT_BASE)
    if (LumiRTAOHandoff()) col.a = lumiFXOut.x;   // the AO for the composite pass (it puts the alpha back to 1)
#endif
    return col;
}

// ---------------------------------------------------------------------------
// light falloff / cookie of the current additional light without its shadow (same terms as UNITY_LIGHT_ATTENUATION)
float LumiAddLightFalloff(float3 posWS)
{
#if defined(POINT)
    float3 lc = mul(unity_WorldToLight, float4(posWS, 1)).xyz;
    return tex2D(_LightTexture0, dot(lc, lc).rr).r;
#elif defined(SPOT)
    float4 lc = mul(unity_WorldToLight, float4(posWS, 1));
    return (lc.z > 0) * UnitySpotCookie(lc) * UnitySpotAttenuate(lc.xyz);
#elif defined(POINT_COOKIE)
    float3 lc = mul(unity_WorldToLight, float4(posWS, 1)).xyz;
    return tex2D(_LightTextureB0, dot(lc, lc).rr).r * texCUBE(_LightTexture0, lc).w;
#elif defined(DIRECTIONAL_COOKIE)
    float2 lc = mul(unity_WorldToLight, float4(posWS, 1)).xy;
    return tex2D(_LightTexture0, lc).w;
#else
    return 1;
#endif
}

// ---------------------------------------------------------------------------
// PCSS (percentage closer soft shadows) for shadowed spot lights: the blockers found around the pixel give how far the
// shadow is from what casts it, and the filter grows with that distance (sharp at contact, soft further away).
// Following the NVIDIA PCSS paper; the depths of the spot shadow map are linearised from unity_WorldToShadow itself.
#if defined(LUMI_HAS_PCSS)
float2 LumiVogel(int i, int n, float rot)
{
    float r = sqrt((i + 0.5) / n);
    float th = i * 2.39996323 + rot * 6.2831853;
    return r * float2(cos(th), sin(th));
}
float LumiPCSS(float3 posWS, float3 N, float2 pixel)
{
    posWS += N * (_PCSSReceiverBias * 0.01);   // receiver bias: lifts the sample off its own surface
    float4x4 M = unity_WorldToShadow[0];
    float4 sc = mul(M, float4(posWS, 1));
    float3 coord = sc.xyz / sc.w;
    float wR = sc.w;
    // z = a * w + b along the light axis (the z row only depends on the axial distance)
    float3 ax = M[3].xyz;
    float axL2 = max(dot(ax, ax), 1e-12);
    float a = dot(M[2].xyz, ax) / axL2;
    float b = M[2].w - a * M[3].w;
    float3 axN = ax * rsqrt(axL2);
    float k = 0.5 * (length(M[0].xyz - dot(M[0].xyz, axN) * axN) + length(M[1].xyz - dot(M[1].xyz, axN) * axN));
    float uvPerMeter = k / max(wR, 1e-5);
    float wTex, hTex; _ShadowMapTexture.GetDimensions(wTex, hTex);
    float texel = 1.0 / max(wTex, 1.0);

    // receiver plane depth bias: the depth slope of the surface in shadow map space (wide kernels would self shadow)
    float3 dx = ddx(coord), dy = ddy(coord);
    float det = dx.x * dy.y - dx.y * dy.x;
    float2 slope = abs(det) > 1e-12 ? float2(dy.y * dx.z - dx.y * dy.z, dx.x * dy.z - dy.x * dx.z) / det : 0;
    slope = clamp(slope, -1.0, 1.0);

    float rot = LumiSSNoise(pixel, posWS, max(_PCSSMaxBlur, _PCSSMinBlur) * 0.005, 0) * _PCSSJitter;
    float lightR = _PCSSLightSize * 0.01 * 0.5;
    int nF = (int)clamp(_PCSSSamples, 8, 64);
    int nB = (int)max(nF * 0.5, 6.0);

    // blocker search: blockers can sit anywhere between the light and the pixel; nearer ones reach further in the map
    float rS = clamp(lightR * uvPerMeter * 3.0 * _PCSSSearchScale, texel * 2.0, texel * 48.0 * _PCSSSearchScale);
    float sum = 0, cnt = 0;
    [loop] for (int i = 0; i < nB; i++)
    {
        float2 o = LumiVogel(i, nB, rot) * rS;
        float d = _ShadowMapTexture.SampleLevel(sampler_point_clamp, coord.xy + o, 0).r;
        float zr = coord.z + dot(o, slope);
#if defined(UNITY_REVERSED_Z)
        if (d > zr) { sum += d; cnt += 1; }
#else
        if (d < zr) { sum += d; cnt += 1; }
#endif
    }
    float sh = 0;
    [branch] if (cnt < 0.5)
    {
        // no blocker found by the search (lit, or a rare miss inside the umbra): one hard tap decides
        sh = _ShadowMapTexture.SampleCmpLevelZero(sampler_ShadowMapTexture, coord.xy, coord.z);
    }
    else
    {
        float den = sum / cnt - a;
        float wB = clamp(b / (abs(den) > 1e-9 ? den : 1e-9), 1e-4, wR);
        float pen = lightR * 2.0 * (wR - wB) / wB;          // penumbra width at the pixel, meters
        pen = clamp(pen, _PCSSMinBlur * 0.01, max(_PCSSMaxBlur, _PCSSMinBlur) * 0.01);
        // a sharp (anime) edge only needs where the half-shadow point is: a narrow filter keeps it from turning into noise
        float rF = clamp(pen * 0.5 * uvPerMeter * lerp(1.0, 0.08, _PCSSToon), texel * lerp(0.5, 1.5, _PCSSTexelFilter), texel * 64.0);
        [loop] for (int j = 0; j < nF; j++)
        {
            float2 o = LumiVogel(j, nF, rot + 0.37) * rF;
            sh += _ShadowMapTexture.SampleCmpLevelZero(sampler_ShadowMapTexture, coord.xy + o, coord.z + dot(o, slope));
        }
        sh /= nF;
    }
    float wEdge = lerp(0.5, 0.03, _PCSSToon);
    // the border moves the half-shadow point: right = the shadow spreads into the penumbra, left = it shrinks
    // (a power curve: full shadow and full light stay, the value at the border becomes the half point)
    sh = pow(saturate(sh), log(0.5) / log(clamp(_PCSSBorder, 0.02, 0.98)));
    sh = saturate((sh - 0.5) / max(2.0 * wEdge, fwidth(sh) * 0.75) + 0.5);    // linear at sharpness 0; at 1 about one pixel wide (antialiased)
    sh = lerp(_LightShadowData.r, 1.0, sh);
    // fade out at the shadow distance like Unity's own shadows
    float viewZ = dot(_WorldSpaceCameraPos - posWS, UNITY_MATRIX_V[2].xyz);
    return saturate(sh + UnityComputeShadowFade(UnityComputeShadowFadeDistance(posWS, viewZ)));
}
#endif

#if defined(LUMI_SHADOW_LIGHT_PASS)
// shadow light (MitToon ShadowLight: a shadowed spot of almost no brightness). It adds no light: its soft shadow
// multiplies what is already drawn (Blend DstColor Zero), so the shadow takes the world's own light and can never get
// brighter than the lit surface, in any world. The fill colours are shares of what was drawn (they used to be added in
// the scale of the scene's ambient setting, which in some worlds is far brighter than the real light: the shadows glowed).
float4 fragShadowLight(v2f i, float facing : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    LumiInputData d = LumiBuildInput(i, facing > 0 ? 1 : -1);
    LumiNearDither(d);
    LumiSurface s = LumiInitSurface(d);
    lumiPixel = d.pixelPos;
    float3 f = 1;
#if defined(LUMI_HAS_PCSS)
    float3 lDir = normalize(_WorldSpaceLightPos0.xyz - i.posWS * _WorldSpaceLightPos0.w);
    float4 lc = mul(unity_WorldToLight, float4(i.posWS, 1));
    float w = lc.z > 0 ? tex2D(_LightTexture0, lc.xy / lc.w + 0.5).w : 0;   // inside the cone
    w *= LUMI_SAMPLE(_PCSSReceiveMask, LUMI_TF(_PCSSReceiveMask, s.uvMain)).r;
    if (_PCSSDistanceFade > 0.01) w *= saturate(2.0 - 2.0 * d.eyeDepth / _PCSSDistanceFade);
    float3 N = normalize(lerp(normalize(d.normalWS), s.N, _PCSSNormalStrength));
    float NoL = dot(N, lDir);
    // the shadow map is a geometric thing: gate it with the mesh normal, and let it reach the terminator
    // (fading it out on the lit side left a bright band between the cast shadow and the shading)
    float3 Ng = normalize(d.normalWS);
    // with the shading on, the cast shadow runs up to the terminator (one shadow); without it, it fades
    // before the terminator so no second, hard terminator line appears
    float g0 = lerp(0.0, -0.25, saturate(_PCSSShading * 2.0));
    float fc = smoothstep(g0, g0 + lerp(0.3, 0.25, saturate(_PCSSShading * 2.0)), dot(Ng, lDir));
    [branch] if (w > 0.001)
    {
        float sh = fc > 0.001 ? LumiPCSS(i.posWS, Ng, d.pixelPos) : 1;
        // faces turned away from the light: optional shading (soft terminator) instead of nothing
        // (the border of that shading follows Sharpen Edge: soft lambert-like at 0, a toon line at 1)
        float aw = lerp(0.01, 0.6, _PCSSShadingBlur);
        float ac = 0.03 + (_PCSSShadingBorder - 0.5) * 1.2;   // right = the shading spreads to the lit side
        // (direction from the world's light: the main pass shades along it, the shadow light only casts)
        float away = _PCSSShading * (1 - smoothstep(ac - aw, ac + aw, NoL)) * (1 - _PCSSWorldLight);
        // eye shadow guard: no bang / lid shadow and no shading inside the eye
        float eyeG = LumiEyeGuard(s.uvMain);
        away *= 1 - eyeG * _EyeGuardShade;
        // one light: lit = (not turned away) x (not occluded), so the two shadows join without a seam
        float occ = 1 - (1 - away) * (1 - fc * (1 - sh) * (1 - eyeG * _EyeGuardShadow));
        float k = _PCSSShadowStrength * w * occ;
        // a real shadow keeps a part of the light around it
        float dark = 1 - k * (1 - saturate(_PCSSShadowKeep));
        // fill colour, and the colourful part of the base colour (minus its grey) deepening the shadow hue (skin goes
        // warm, not grey): per colour channel shares of what was drawn, at most back to the unshadowed colour
        float3 dc = max(s.diffuseColor, 0.0);
        float mn = min(dc.r, min(dc.g, dc.b));
        float3 tint = k * (_PCSSShadowColor.rgb * _PCSSShadowColorStrength + _PCSSAutoColor * (dc - mn) / max(dc, 1e-4));
        f = min(dark + tint, 1.0);
        // coloured border in the penumbra (toon look)
        float edge = fc * saturate(1 - abs(sh - 0.5) * 2.0 / max(_PCSSBorderWidth, 0.05));
        f += edge * w * _PCSSBorderColor.a * _PCSSBorderColor.rgb;
    }
#endif
    return float4(LumiQuadSmooth(float4(f, 0), d.eyeDepth, d.pixelPos).rgb, 1);   // (dots of the PCSS taps)
}
#endif

float4 fragAdd(v2f i, float facing : VFACE) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    LumiInputData d = LumiBuildInput(i, facing > 0 ? 1 : -1);
    LumiNearDither(d);
    LumiSurface s = LumiInitSurface(d);
    lumiPixel = d.pixelPos;

    LumiLight l;
    l.direction = normalize(_WorldSpaceLightPos0.xyz - i.posWS * _WorldSpaceLightPos0.w);
    l.color = _LightColor0.rgb;
    if (_AddLightIgnoreDirectional > 0.5 && _WorldSpaceLightPos0.w < 0.5) l.color = 0;
    UNITY_LIGHT_ATTENUATION(atten, i, i.posWS);
    // split falloff and shadow: recompute shadow only
    float shadowOnly = UNITY_SHADOW_ATTENUATION(i, i.posWS);
    l.shadowAttenuation = shadowOnly;
    l.distanceAttenuation = atten / max(shadowOnly, 1e-4);
    if (shadowOnly < 1e-4) { l.distanceAttenuation = 1; l.shadowAttenuation = atten; }
#if defined(LUMI_HAS_PCSS)
    [branch] if (_UsePCSS > 0.5)   // also with the plain cast shadows turned off
    {
        l.shadowAttenuation = LumiQuadSmooth(LumiPCSS(i.posWS, normalize(d.normalWS), d.pixelPos).xxxx, d.eyeDepth, d.pixelPos).x;
        l.distanceAttenuation = LumiAddLightFalloff(i.posWS);
        lumiPCSSOn = 1;     // soft, so the coarse-map guard (_AddLightCastShadow) does not apply
    }
#endif
    if (_ReceiveCastShadow < 0.5 && lumiPCSSOn < 0.5) { l.shadowAttenuation = 1; l.distanceAttenuation = LumiAddLightFalloff(i.posWS); }
#if defined(POINT) || defined(POINT_COOKIE)
    {
        // the falloff texture cuts off hard at the light range: window it so the edge fades out smoothly
        float3 lp = mul(unity_WorldToLight, float4(i.posWS, 1)).xyz;
        float win = saturate(1.0 - dot(lp, lp));
        l.distanceAttenuation *= lerp(1.0, win * win, _AddLightSmoothFalloff);
    }
#endif

    LumiCtx c = (LumiCtx)0;
    c.V = d.viewDirWS;
    c.NoV = saturate(dot(s.N, c.V)) + 1e-4;
    c.litLight = l.color;
#if defined(_LUMI_RAYTRACE)
    lumiRTValidity = LUMI_URP_MODEL && _RTShadowStrength > 0.001 ? LumiScreenSpaceValidity(d) : 0;
#endif
    c.rampLit = 1;

    float4 col = float4(LumiShadeAdditional(s, d, c, l), s.alpha);
    col.rgb = LumiDistanceFade(col.rgb, d, true);
    col.rgb = LumiFinalGrade(col.rgb, true);
    LUMI_APPLY_FOG_BLACK(i, col);
    col = LumiOutputAlpha(col);
#if defined(_ALPHATEST_ON)
    // Alpha To Coverage reads the alpha as coverage: 0 would drop every added light on cutout surfaces
    col.a = _AlphaToMask > 0.5 ? col.a : 0;
#elif !defined(_ALPHABLEND_ON) && !defined(_ALPHAPREMULTIPLY_ON)
    col.a = 0;
#endif
    if (abs(_DstBlendAdd - 5) < 0.5) col.a = 1;   // Blend One SrcAlpha (shadow light support): plain add
    return col;
}

// ---------------------------------------------------------------------------
// Outline (inverted hull)
struct v2fOutline
{
    float4 pos      : SV_POSITION;
    float2 uv0      : TEXCOORD0;
    float3 posWS    : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    float4 screenPos: TEXCOORD3;
    LUMI_FOG_COORDS(4)
    float3 light    : TEXCOORD5;   // outline lighting, per vertex
    float3 lightDir : TEXCOORD6;   // main light + ambient direction (highlight)
    UNITY_SHADOW_COORDS(7)
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

v2fOutline LumiOutlineVertex(appdata v, float widthCm, float zBiasCm, float behind)
{
    v2fOutline o;
    UNITY_INITIALIZE_OUTPUT(v2fOutline, o);
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

#if defined(_LUMI_FPSMODE)
    v.vertex.xyz += LumiFPSOffsetOS(v.vertex.xyz, v.normal);
    widthCm *= LumiFPSWidthJitter(v.vertex.xyz);
#endif
    widthCm *= LumiInkWeight(v.vertex.xyz, v.normal);
    float sc = LumiVertexScale(v.normal);
    float width = widthCm * 0.01 * sc; // cm -> m, at the avatar's scale
    // the smooth normal bake also stores mask x vertex color width, averaged over vertices on one position:
    // sampled per UV, a mask tears the outline at UV seams (the two sides read different texels)
    if (_OutlineWidthBaked > 0.5 && _OutlineNormalSource > 0.5) width *= v.color.a;
    else
    {
        width *= _OutlineWidthMask.SampleLevel(sampler_trilinear_repeat, LUMI_TF(_OutlineWidthMask, v.uv0), 0).r;
        width *= lerp(1, v.color.a, _OutlineVertexColorWidth);
    }
    float3 posWS = LumiObjectToWorld(v.vertex.xyz);
    posWS += LumiWobbleWS(posWS, v);
    float3 nOS = v.normal;
    if (_OutlineNormalSource > 1.5)
    {
        // smoothed normal baked in vertex color RGB, tangent space (survives skinning)
        // (unit vectors: skinned ones carry the avatar's scale)
        float3 ts = v.color.rgb * 2.0 - 1.0;
        float3 n0 = normalize(v.normal), t0 = normalize(v.tangent.xyz + 1e-6);
        float3 bt = cross(n0, t0) * v.tangent.w;
        nOS = normalize(t0 * ts.x + bt * ts.y + n0 * ts.z);
    }
    else if (_OutlineNormalSource > 0.5) nOS = v.tangent.xyz;
    float3 nWS = LumiObjectToWorldNormal(nOS);
    float camDist = distance(posWS, LumiGetCameraPositionWS());
    width *= lerp(1, min(camDist / sc, _OutlineFixDistance), _OutlineFixWidth);   // keep screen width when far away (distance at the avatar's scale)
    width *= lerp(1, clamp(1.7320508 / max(LumiProjScaleY(), 1e-3), 0.5, 2.0), _OutlineFOVCompensate);   // same look at any FOV
    float3 basePosWS = posWS;
    posWS += nWS * width;
    float3 toCam = normalize(LumiGetCameraPositionWS() - posWS);
    // behind: pushed away along the view ray by its own width (same place on screen). In hollows (eyes, between muscles,
    // clothing folds) a wide shell's back faces come out in front of the surface: as deep as it is wide at most
    posWS -= toCam * (zBiasCm * 0.01 * sc + width * behind);
    o.posWS = posWS;
    o.pos = LumiPerspectiveRemoval(UnityWorldToClipPos(posWS));
    if (width <= 0 || LumiHidden(v)) o.pos = LUMI_NAN4; // degenerate: no outline
    o.uv0 = v.uv0;
    o.normalWS = nWS;
    o.screenPos = ComputeScreenPos(o.pos);
    LUMI_TRANSFER_FOG(o, o.pos);
    {
        // lighting per vertex: the outline is thin, per pixel it repeated the whole ambient analysis
        float4 p0, p1, p2;
        LumiLVVertex(posWS, nWS, p0, p1, p2);
        LumiSetupAmbient(p0, p1, p2, nWS, 0, 0, 0, false);
        LumiLight ml = LumiGetMainLight();
        LumiGI gi = LumiGatherGI(ml.color, posWS);
        float3 mc = LumiKeepChroma(ml.color, gi.lightChromaKeep);
        float3 dir = ml.direction * LumiLuminance(mc) + gi.dirHint + float3(0, 0.001, 0);
        o.light = LumiLimitLight(mc + gi.autoKey + LumiGIIrradiance(gi, normalize(dir) * _SHSoftness));
        o.lightDir = dir;
    }
    UNITY_TRANSFER_SHADOW(o, v.uv1);
#if defined(SHADOWS_SCREEN) && !defined(UNITY_NO_SCREENSPACE_SHADOWS)
    // the outline lies outside the body, where the screen space shadow belongs to the background: read it on the body edge
    o._ShadowCoord = ComputeScreenPos(LumiPerspectiveRemoval(UnityWorldToClipPos(basePosWS - nWS * 0.002)));
#endif
    return o;
}
v2fOutline vertOutline(appdata v)  { return LumiOutlineVertex(v, _OutlineWidth, _OutlineZBias, 0.0); }
// 2nd (outer) outline: drawn outside the 1st one (white + dark double line, glow edge ...)
// "only outside the body" hides it with the stencil: the 1st outline's Z bias would only push it behind nearby objects (gaps), so only its own applies
v2fOutline vertOutline2(appdata v) { return LumiOutlineVertex(v, _Outline2Width > 0 ? _OutlineWidth + _Outline2Width : 0, _OutlineZBias * (1.0 - _Outline2Silhouette) + _Outline2ZBias, 1.0); }

float4 LumiOutlineColor(v2fOutline i, float4 color, float mainBlend, float lighting, bool highlight)
{
    float2 uv = i.uv0 * _MainTex_ST.xy + _MainTex_ST.zw;
    float4 main = LUMI_SAMPLE(_MainTex, uv) * _Color;
#if defined(_ALPHATEST_ON)
    float cutA = LumiCutoutClip(uv);
#else
    float cutA = 1.0;
#endif
    float4 col = color;
    col.rgb = lerp(col.rgb, col.rgb * main.rgb, mainBlend);

    // highlight on the lit side (lilToon outline "Lit"): light and normal compared on the screen plane
    if (highlight && _OutlineLitColor.a > 0)
    {
        float2 n2 = LumiWorldToViewDir(i.normalWS).xy;
        float2 l2 = LumiWorldToViewDir(i.lightDir).xy;
        float ndl = dot(n2 * rsqrt(max(dot(n2, n2), 1e-8)), l2 * rsqrt(max(dot(l2, l2), 1e-8))) * 0.5 + 0.5;
        float f = saturate(ndl * _OutlineLitScale + _OutlineLitOffset) * _OutlineLitColor.a;
        if (_OutlineLitShadowReceive > 0.5) { UNITY_LIGHT_ATTENUATION(atten, i, i.posWS); f *= atten; }
        float3 litCol = _OutlineLitApplyTex > 0.5 ? main.rgb * _OutlineLitColor.rgb : _OutlineLitColor.rgb;
        col.rgb = lerp(col.rgb, litCol, f);
    }

    col.rgb *= lerp(1, i.light, lighting);

    col.rgb = LumiFinalGrade(col.rgb, false);
    LUMI_APPLY_FOG(i, col);
    col.a = cutA;
    return col;
}
// standalone AudioLink on the outline (a uniform branch: no keyword in the outline passes)
float3 LumiALOutline(float2 uv)
{
    float3 g = 0;
    [branch] if (_UseALSolo > 0.5 && _ALOutline > 0.001) g = LumiALSoloGlow(uv) * _ALOutline;
    return g;
}
float4 fragOutline(v2fOutline i) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    float2 uv = i.uv0 * _MainTex_ST.xy + _MainTex_ST.zw;
    float4 col = LumiOutlineColor(i, _OutlineColor * LUMI_SAMPLE(_OutlineTex, LUMI_TF(_OutlineTex, uv)), _OutlineMainBlend, _OutlineEnableLighting, true);
    col.rgb += LumiALOutline(i.uv0);
    return col;
}
float4 fragOutline2(v2fOutline i) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    float4 col = LumiOutlineColor(i, _Outline2Color, _Outline2MainBlend, _Outline2EnableLighting, false);
    col.rgb += LumiALOutline(i.uv0);
    return col;
}

// ---------------------------------------------------------------------------
// Shadow caster / depth prepass with adjustable bias (removes shadow acne stripes)
struct v2fShadow
{
    V2F_SHADOW_CASTER;
    float2 uv0   : TEXCOORD1;
    float3 posOS : TEXCOORD2;
    UNITY_VERTEX_OUTPUT_STEREO
};

v2fShadow vertShadow(appdata v)
{
    v2fShadow o;
    UNITY_INITIALIZE_OUTPUT(v2fShadow, o);
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
#if defined(_LUMI_FPSMODE)
    if (_FPSTarget > 0.5) v.vertex.xyz += LumiFPSOffsetOS(v.vertex.xyz, v.normal);
#endif
    float3 posWS = LumiObjectToWorld(v.vertex.xyz);
    posWS += LumiWobbleWS(posWS, v);
    float3 nWS = LumiObjectToWorldNormal(v.normal);
    if (unity_LightShadowBias.x != 0.0 || unity_LightShadowBias.z != 0.0) // only while rendering a shadow map (camera depth has no bias)
    {
        float3 L = normalize(UnityWorldSpaceLightDir(posWS));
        float shadowCos = dot(nWS, L);
        float shadowSine = sqrt(1 - shadowCos * shadowCos);
        float sc = LumiVertexScale(v.normal);   // (the biases in cm at the avatar's scale)
        posWS -= nWS * (_ShadowCasterNormalBias * 0.01 * sc * shadowSine);
        // push the caster away from the light: small shapes (nose, bangs, folds) stop shadowing the avatar itself,
        // which also removes most of the frame to frame shimmer of those small shadows. Stronger when the light
        // comes from the camera side (front light: self shadows there look the most wrong), none from behind.
        float bias = _ShadowCasterBias * 0.01 * sc;
        float facing = saturate(dot(L, normalize(_WorldSpaceCameraPos - posWS)) * 2.0 + 1.0);
        bias *= lerp(1.0, facing, _ShadowCasterBiasView);
    #if defined(SHADOWS_DEPTH)
        if (UNITY_MATRIX_P._m33 == 0.0) bias = 0;   // spot light: perspective shadow map, keep it exact
    #endif
        posWS -= L * bias;
    }
    v.vertex.xyz = mul(unity_WorldToObject, float4(posWS, 1)).xyz;
    TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
    if (unity_LightShadowBias.z == 0.0) o.pos = LumiPerspectiveRemoval(o.pos);   // camera depth pass must match the color pass
    if (LumiHidden(v)) o.pos = LUMI_NAN4;
    o.uv0 = v.uv0;
    o.posOS = v.vertex.xyz;
    return o;
}

float4 fragShadow(v2fShadow i) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
#if defined(_ALPHATEST_ON) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON) || defined(_LUMI_DISSOLVE)
    float2 uv = i.uv0 * _MainTex_ST.xy + _MainTex_ST.zw;
    float a = LUMI_SAMPLE(_MainTex, uv).a * _Color.a;
    float am = LUMI_SAMPLE(_AlphaMask, LUMI_TF(_AlphaMask, uv)).r;
    if (_AlphaMaskMode == 1) a = am; else if (_AlphaMaskMode == 2) a *= am;
    a = saturate(a + _AlphaMaskValue);
    #if defined(_ALPHATEST_ON)
        clip(LumiCutoutAlpha(uv) - _Cutoff);
    #elif defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
        clip(a - LumiBayer4(i.pos.xy));   // dithered shadows for transparent
    #endif
    #if defined(_LUMI_DISSOLVE)
        float v;
        if (_DissolveMode < 0.5)      v = _DissolveNoise.Sample(sampler_trilinear_repeat, i.uv0 * _DissolveNoise_ST.xy + _DissolveNoise_ST.zw).r;
        else if (_DissolveMode < 1.5) v = i.uv0.y;
        else                          v = LumiRemap(i.posOS.y, _DissolveHeightRange.x, _DissolveHeightRange.y);
        if (_DissolveAmount > 0) clip(v - _DissolveAmount * (1.0 + _DissolveEdgeWidth));
    #endif
#endif
    SHADOW_CASTER_FRAGMENT(i)
}

#endif

