// MitToon Shader - "MitToon GI": global ilmittoontion with world robustness (pipeline independent)
// A typical forward renderer gathers SH + one reflection probe. VRChat worlds are often flat
// (single ambient color), missing probes, or have probes that do not match the lighting, so MitToon adds:
//  - hemisphere synthesis for flat ambient (keeps volume in any world)
//  - SH synthesised reflections when there is no probe (metal / gloss never turns grey or black)
//  - probe brightness normalisation against the SH irradiance
//  - a virtual key light taken from the SH dominant direction (highlights in worlds without directional light)
//  - multi-scatter energy compensation and multi-bounce AO
//  - auto lighting: ambient from the scenery (reflection probe), point lights steer the light direction,
//    key / fill balance in flat worlds, and ambient colour control (neutral in the dark)
#ifndef MITTOON_GI_INCLUDED
#define MITTOON_GI_INCLUDED

#include "MitToonBRDF.hlsl"

struct LumiGI
{
    float3 L0;          // average irradiance (SH blended with the scenery probe)
    float3 domDir;      // dominant light direction of the SH
    float3 domColor;    // color carried by the directional part
    float  flatness;    // 1 = ambient has no direction at all
    // v1.4 auto lighting
    float  probeW;      // weight of the probe based ambient
    float3 pL0, pL1r, pL1g, pL1b;
    float  chromaKeep;       // how much of the ambient color survives
    float  lightChromaKeep;  // same for direct lights
    float  ambScale;         // ambient energy left after moving some into the auto key
    float3 autoKey;          // auto key light color (added along the toon direction)
    float3 dirHint;          // unnormalised direction hint: SH / scenery / point lights / default key
    float  worldLum;
};

float3 LumiKeepChroma(float3 c, float keep)
{
    return lerp(LumiLuminance(c).xxx, c, keep);
}

// mainColor: directional light color. Analyses the SH, the reflection probe (scenery) and nearby point lights.
// Scenery probe reduced to L0 + L1 (6 taps at the blurriest mip). Computed per vertex; the pixel shader reads the statics.
static float  lumiProbeReady = 0;
static float3 lumiPL0 = 0, lumiPL1r = 0, lumiPL1g = 0, lumiPL1b = 0;
void LumiProbeSH(out float3 L0, out float3 L1r, out float3 L1g, out float3 L1b)
{
    L0 = 0; L1r = 0; L1g = 0; L1b = 0;
    UNITY_BRANCH
    if (_AutoLight * _AutoProbeAmbient > 0.001)
    {
        float3 px = LumiSampleProbeDiffuse(float3( 1, 0, 0)), nx = LumiSampleProbeDiffuse(float3(-1, 0, 0));
        float3 py = LumiSampleProbeDiffuse(float3( 0, 1, 0)), ny = LumiSampleProbeDiffuse(float3( 0,-1, 0));
        float3 pz = LumiSampleProbeDiffuse(float3( 0, 0, 1)), nz = LumiSampleProbeDiffuse(float3( 0, 0,-1));
        L0 = (px + nx + py + ny + pz + nz) / 6.0;
        // radiance gradient -> irradiance L1 (x 2/3 cosine lobe)
        float3 dx = (px - nx) / 3.0, dy = (py - ny) / 3.0, dz = (pz - nz) / 3.0;
        L1r = float3(dx.r, dy.r, dz.r); L1g = float3(dx.g, dy.g, dz.g); L1b = float3(dx.b, dy.b, dz.b);
    }
}

LumiGI LumiGatherGI(float3 mainColor, float3 posWS)
{
    LumiGI gi = (LumiGI)0;
    gi.L0 = LumiSampleSHAverage();
    float3 r, g, b;
    LumiGetSHL1(r, g, b);

    // scenery: the reflection probe seen from the avatar (prepared per vertex, see LumiProbeSH)
    float autoW = _AutoLight;
    if (autoW * _AutoProbeAmbient > 0.001 && lumiProbeReady > 0.5)
    {
        float lp = LumiLuminance(lumiPL0);
        if (lp > 1e-4)
        {
            // keep the brightness of the light probes; the scenery only gives color and direction
            float scale = clamp(LumiLuminance(gi.L0) / lp, 0.25, 4.0);
            gi.pL0 = lumiPL0 * scale;
            gi.pL1r = lumiPL1r * scale; gi.pL1g = lumiPL1g * scale; gi.pL1b = lumiPL1b * scale;
            float shLen = length(r * 0.2126 + g * 0.7152 + b * 0.0722) / max(LumiLuminance(gi.L0), 1e-4);
            // light probes with a clear direction are trusted more than the probe
            gi.probeW = autoW * _AutoProbeAmbient * lerp(1.0, 0.35, saturate(shLen * 2.0));
            gi.L0 = lerp(gi.L0, gi.pL0, gi.probeW);
            r = lerp(r, gi.pL1r, gi.probeW); g = lerp(g, gi.pL1g, gi.probeW); b = lerp(b, gi.pL1b, gi.probeW);
        }
    }

    float3 l1 = r * 0.2126 + g * 0.7152 + b * 0.0722;
    float len = length(l1);
    gi.domDir = len > 1e-5 ? l1 / len : float3(0, 1, 0);
    gi.domColor = max(float3(dot(r, gi.domDir), dot(g, gi.domDir), dot(b, gi.domDir)), 0);
    gi.flatness = 1.0 - saturate(len / max(LumiLuminance(gi.L0) * 0.5, 1e-4));

    // nearby point lights (vertex lights) pull the light direction toward them
    float pointLum;
    float3 pointDir = LumiPointLightDirection(posWS, pointLum);

    float keyLum = LumiLuminance(mainColor);
    float ambLum = LumiLuminance(gi.L0);
    gi.worldLum = keyLum + ambLum + pointLum * 0.5;

    // colour of the environment: weaker overall and almost neutral in the dark
    float dark = 1.0 - smoothstep(0.0, max(_DarkColorThreshold, 1e-3), gi.worldLum);
    gi.chromaKeep = _EnvColorStrength * (1.0 - dark * _DarkColorReduce);
    gi.lightChromaKeep = _LightColorStrength * (1.0 - dark * _DarkColorReduce * 0.6);
    gi.domColor = LumiKeepChroma(gi.domColor, gi.chromaKeep);

    // key / fill balance: when almost everything is ambient, move part of it into a key light (front average preserved)
    float T = _AutoKeyRatio;
    float m = (T * (keyLum + ambLum) - keyLum) / max(ambLum * (2.0 - T), 1e-4);
    m = clamp(m, 0.0, 0.75) * autoW * step(1e-4, ambLum);
    gi.ambScale = 1.0 - m;
    gi.autoKey = LumiKeepChroma(gi.L0, gi.chromaKeep) * (2.0 * m);

    // direction hint. A world with no direction at all gets a camera relative upper front key.
    float3 viewKey = LumiViewToWorldDir(normalize(float3(-0.35, 0.55, 0.75)));
    gi.dirHint = l1 + pointDir * (_AutoPointLights * autoW)
               + viewKey * (ambLum * gi.flatness * saturate(1.0 - keyLum / max(ambLum, 1e-4)) * _AutoDefaultKey * autoW);
    return gi;
}

float3 LumiGISH(LumiGI gi, float3 N)
{
    float3 sh = LumiSampleSH(N);
    if (gi.probeW > 0.001)
        sh = lerp(sh, max(gi.pL0 + float3(dot(gi.pL1r, N), dot(gi.pL1g, N), dot(gi.pL1b, N)), 0), gi.probeW);
    return sh;
}

// Diffuse irradiance along N before colour control / key redistribution (N may be shortened to soften L1)
float3 LumiGIIrradianceRaw(LumiGI gi, float3 N)
{
    float3 sh = LumiGISH(gi, N);
    float k = gi.flatness * _AmbientShape;
    float3 sky    = gi.L0 * (1.0 + _AmbientShapeContrast * k) * lerp(1, _AmbientSkyTint.rgb, k);
    float3 ground = gi.L0 * (1.0 - _AmbientShapeContrast * k) * lerp(1, _AmbientGroundTint.rgb, k);
    float3 hemi = lerp(ground, sky, saturate(N.y * 0.5 + 0.5));
    float3 irr = lerp(sh, hemi, k);
    return max(lerp(irr, gi.L0, _AmbientFlatten), 0);   // even indirect light
}
// Ambient used for shading
float3 LumiGIIrradiance(LumiGI gi, float3 N)
{
    return LumiKeepChroma(LumiGIIrradianceRaw(gi, N), gi.chromaKeep) * gi.ambScale;
}

// Reflection with fallbacks. pr = perceptual roughness
float3 LumiGIReflection(LumiGI gi, float3 R, float3 posWS, float pr)
{
    float3 env = LumiSampleEnvironment(R, posWS, pr, _ReflCubeMode, _ReflCubeIntensity);
    float3 shR = LumiGIIrradianceRaw(gi, R);
    bool probeMode = _ReflCubeMode < 0.5 || (_ReflCubeMode > 1.5 && _ReflCubeMode < 2.5) || _ReflCubeMode > 3.5;
    if (_ReflCubeMode < 0.5 && dot(env, 1) < 0.002)
    {
        // no probe: synthesise from SH. sharp lobe of the dominant light acts as the "sky highlight"
        float3 synth = lerp(shR, gi.L0, pr * pr * _SynthReflBlur);
        float sp = exp2(lerp(10.0, 1.5, pr));
        synth += gi.domColor * pow(saturate(dot(R, gi.domDir)), sp) * ((sp + 2.0) / 8.0) * _SynthReflHighlight;
        env = synth * _ReflCubeIntensity;
    }
    else if (probeMode && _EnvNormalize > 0.001)
    {
        // match the probe to the light the avatar actually receives (probes baked in other lighting / too bright)
        float probeLum = LumiLuminance(LumiSampleProbeDiffuse(R));
        float ratio = clamp(LumiLuminance(shR) / max(probeLum, 1e-3), 1.0 / _EnvNormalizeRange, _EnvNormalizeRange);
        env *= lerp(1.0, ratio, _EnvNormalize);
    }
    // reflections keep a bit more colour than diffuse ambient (metals should still read the scene)
    return LumiKeepChroma(env, lerp(gi.chromaKeep, 1.0, 0.4));
}

// Weight of the virtual key light: full when the world has no (or a very weak) directional light
float LumiVirtualKeyWeight(LumiGI gi, float mainLum)
{
    return _VirtualKeyLight * saturate(1.0 - mainLum / max(LumiLuminance(gi.L0) * 2.0, 1e-4));
}

// ---- Minimal BRDF -----------------------------------------------------------------------------
// Minimalist Cook-Torrance specular with an explicit Schlick term.
float3 LumiDirectSpecularMin(float3 f0, float a2, float NoH, float LoH)
{
    float r2 = max(a2, 6.1e-5);
    float d = NoH * NoH * (r2 - 1.0) + 1.00001;
    float norm = sqrt(r2) * 4.0 + 2.0;
    float term = r2 / ((d * d) * max(0.1, LoH * LoH) * norm);
    return term * LumiF_Schlick(f0, LoH);
}
// Environment BRDF: surfaceReduction * lerp(specular, grazingTerm, fresnelTerm)
float3 LumiEnvironmentBRDFMin(float3 f0, float metallic, float perceptualRough, float a2, float NoV)
{
    float reflectivity = 1.0 - 0.96 * (1.0 - metallic);
    float grazing = saturate((1.0 - perceptualRough) + reflectivity);
    float fresnel = 1.0 - NoV; fresnel *= fresnel; fresnel *= fresnel;
    float surfaceReduction = 1.0 / (a2 + 1.0);
    return surfaceReduction * lerp(f0, grazing.xxx, fresnel);
}
// Multi-scatter energy compensation (rough metals keep their brightness)
float3 LumiEnergyCompensation(float3 f0, float perceptualRough, float NoV)
{
    float E = LumiEnvBRDFApprox(1.0.xxx, perceptualRough, NoV).x;
    return 1.0 + f0 * (1.0 / max(E, 0.05) - 1.0) * _SpecEnergyComp;
}
// Multi-bounce AO: occluded areas keep the albedo colour instead of turning grey
float3 LumiMultiBounceAO(float ao, float3 albedo)
{
    float3 a = 2.0404 * albedo - 0.3324;
    float3 b = -4.7951 * albedo + 0.6417;
    float3 c = 2.7552 * albedo + 0.6903;
    return max(ao.xxx, ((ao * a + b) * ao + c) * ao);
}

#endif
