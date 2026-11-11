// MitToon Shader - BRDF terms (pipeline independent)
#ifndef MITTOON_BRDF_INCLUDED
#define MITTOON_BRDF_INCLUDED

#include "MitToonCommon.hlsl"

float  LumiD_GGX(float NoH, float a2)
{
    float d = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (LUMI_PI * d * d + 1e-7);
}
float  LumiV_SmithJointApprox(float NoV, float NoL, float a)
{
    float v = NoL * (NoV * (1.0 - a) + a);
    float l = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / max(v + l, 1e-5);
}
float3 LumiF_Schlick(float3 f0, float VoH) { return f0 + (1.0 - f0) * LumiPow5(1.0 - VoH); }
float3 LumiF_SchlickRough(float3 f0, float NoV, float rough)
{
    return f0 + (max((1.0 - rough).xxx, f0) - f0) * LumiPow5(1.0 - NoV);
}

// Retro reflective diffuse (energy normalised so that it stays comparable with Lambert)
float LumiDiffuseRetro(float NoV, float NoL, float LoH, float perceptualRough)
{
    float fd90 = 0.5 + 2.0 * LoH * LoH * perceptualRough;
    float lightScatter = 1.0 + (fd90 - 1.0) * LumiPow5(1.0 - NoL);
    float viewScatter  = 1.0 + (fd90 - 1.0) * LumiPow5(1.0 - NoV);
    return lightScatter * viewScatter;
}

// Sheen distribution (cloth / velvet)
float LumiD_Sheen(float NoH, float rough)
{
    float invR = 1.0 / max(rough, 0.02);
    float sin2h = max(1.0 - NoH * NoH, 0.0078125);
    return (2.0 + invR) * pow(sin2h, invR * 0.5) / (2.0 * LUMI_PI);
}
float LumiV_Sheen(float NoV, float NoL) { return saturate(1.0 / (4.0 * (NoL + NoV - NoL * NoV) + 1e-5)); }

// Strand specular (hair)
float LumiStrandSpec(float3 T, float3 H, float exponent)
{
    float ToH = dot(T, H);
    float sinTH = sqrt(saturate(1.0 - ToH * ToH));
    float dirAtten = smoothstep(-1.0, 0.0, ToH);
    return dirAtten * pow(sinTH, exponent);
}

// Anisotropic GGX
float LumiD_GGXAniso(float ToH, float BoH, float NoH, float at, float ab)
{
    float a2 = at * ab;
    float3 v = float3(ab * ToH, at * BoH, a2 * NoH);
    float v2 = dot(v, v);
    float w2 = a2 / max(v2, 1e-7);
    return a2 * w2 * w2 * LUMI_INV_PI;
}

// Analytic environment BRDF approximation
float3 LumiEnvBRDFApprox(float3 specColor, float rough, float NoV)
{
    const float4 c0 = float4(-1, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1, 0.0425, 1.04, -0.04);
    float4 r = rough * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    float2 AB = float2(-1.04, 1.04) * a004 + r.zw;
    return specColor * AB.x + AB.y;
}

// Specular occlusion
float LumiSpecularOcclusion(float NoV, float ao, float rough)
{
    return saturate(pow(abs(NoV + ao), exp2(-16.0 * rough - 1.0)) - 1.0 + ao);
}
// Horizon occlusion for normal mapped reflections
float LumiHorizonOcclusion(float3 R, float3 geomN)
{
    float h = saturate(1.0 + 1.1 * dot(R, geomN));
    return h * h;
}

// Geometric specular anti aliasing. returns modified roughness^2
float LumiSpecularAA(float3 N, float a2, float variance, float threshold)
{
    float3 dx = ddx(N), dy = ddy(N);
    float kernel = variance * (dot(dx, dx) + dot(dy, dy));
    return saturate(a2 + min(2.0 * kernel, threshold));
}

#endif
