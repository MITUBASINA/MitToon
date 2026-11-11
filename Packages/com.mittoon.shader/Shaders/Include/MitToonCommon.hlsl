// MitToon Shader - common math / color utilities (pipeline independent)
#ifndef MITTOON_COMMON_INCLUDED
#define MITTOON_COMMON_INCLUDED

#define LUMI_PI      3.14159265359
#define LUMI_INV_PI  0.31830988618
#define LUMI_EPS     1e-5

float  LumiPow5(float x) { float x2 = x * x; return x2 * x2 * x; }
float  LumiLuminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
float  LumiRemap(float x, float a, float b) { return saturate((x - a) / max(b - a, LUMI_EPS)); }
float  LumiSmoothBorder(float x, float border, float blur)
{
    blur = max(blur, 0.001);
    return smoothstep(border - blur, border + blur, x);
}
float2 LumiRotateUV(float2 uv, float angle)
{
    float s, c; sincos(angle, s, c);
    uv -= 0.5;
    return float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + 0.5;
}

// ---- Color --------------------------------------------------------------
float3 LumiRGB2HSV(float3 c)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
float3 LumiHSV2RGB(float3 c)
{
    float3 p = abs(frac(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * lerp(1.0, saturate(p - 1.0), c.y);
}
// hsvg = (hue shift, saturation mul, value mul, gamma)
float3 LumiApplyHSVG(float3 col, float4 hsvg)
{
    if (all(hsvg == float4(0, 1, 1, 1))) return col;
    float3 hsv = LumiRGB2HSV(saturate(col));
    hsv.x = frac(hsv.x + hsvg.x);
    hsv.y = saturate(hsv.y * hsvg.y);
    hsv.z = hsv.z * hsvg.z;
    return pow(max(LumiHSV2RGB(hsv), 0), hsvg.w);
}

// tone correction of the compatible mode: gamma first, then hue / saturation / value with the value clamped to 1
float3 LumiCompatTone(float3 c, float4 hsvg)
{
    c = pow(abs(c), hsvg.w);
    float4 p = (c.b > c.g) ? float4(c.bg, -1.0, 2.0 / 3.0) : float4(c.gb, 0.0, -1.0 / 3.0);
    float4 q = (p.x > c.r) ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float d = q.x - min(q.w, q.y);
    float3 hsv = float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
    hsv = float3(hsv.x + hsvg.x, saturate(hsv.y * hsvg.y), saturate(hsv.z * hsvg.z));
    return hsv.z - hsv.z * hsv.y + hsv.z * hsv.y * saturate(abs(frac(hsv.x + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
}

float3 LumiBlend(float3 dst, float3 src, float a, float mode)
{
    // 0:Normal 1:Add 2:Screen 3:Multiply
    float3 r = src;
    if (mode == 1) r = dst + src;
    else if (mode == 2) r = 1 - (1 - dst) * (1 - src);
    else if (mode == 3) r = dst * src;
    return lerp(dst, r, a);
}

// ---- Noise --------------------------------------------------------------
float LumiIGN(float2 pixel) { return frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715)))); }
float LumiHash12(float2 p) { float3 p3 = frac(float3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return frac((p3.x + p3.y) * p3.z); }
float3 LumiHash32(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return frac((p3.xxy + p3.yzz) * p3.zyx);
}
float LumiHash31(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}
// smooth 3D value noise, 0..1
float LumiValueNoise3(float3 p)
{
    float3 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = lerp(LumiHash31(i), LumiHash31(i + float3(1, 0, 0)), f.x);
    float b = lerp(LumiHash31(i + float3(0, 1, 0)), LumiHash31(i + float3(1, 1, 0)), f.x);
    float c = lerp(LumiHash31(i + float3(0, 0, 1)), LumiHash31(i + float3(1, 0, 1)), f.x);
    float d = lerp(LumiHash31(i + float3(0, 1, 1)), LumiHash31(i + float3(1, 1, 1)), f.x);
    return lerp(lerp(a, b, f.y), lerp(c, d, f.y), f.z);
}
float LumiBayer4(float2 pixel)
{
    uint2 p = (uint2)fmod(pixel, 4.0);
    const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    return (m[p.y * 4 + p.x] + 0.5) / 16.0;
}

// ---- Tonemapping / grading (filmic look without post processing) --
float3 LumiFilmicContrast(float3 x)
{
    // fitted filmic curve (contrast)
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}
float3 LumiNeutral(float3 x)
{
    // soft filmic curve, white point 6
    const float A = 0.22, B = 0.30, C = 0.10, D = 0.20, E = 0.01, F = 0.30, W = 6.0;
    float3 c = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
    float w = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
    return saturate(c / w);
}
// Natural: polynomial fit, hue preserving roll off, keeps skin from burning to yellow.
float3 LumiNatural(float3 x, float punchy)
{
    const float3x3 agxIn = float3x3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                                    0.0784335999999992, 0.878468636469772, 0.0784336,
                                    0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const float3x3 agxOut = float3x3(1.19687900512017, -0.0528968517574562, -0.0529716355144438,
                                     -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
                                     -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
    const float minEv = -12.47393, maxEv = 4.026069;
    x = mul(max(x, 1e-10), agxIn);
    x = (clamp(log2(x), minEv, maxEv) - minEv) / (maxEv - minEv);
    float3 x2 = x * x, x4 = x2 * x2;
    x = 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
    if (punchy > 0.5)
    {
        float l = LumiLuminance(x);
        x = pow(max(x, 0), 1.35);
        x = l + 1.4 * (x - l);
    }
    x = mul(x, agxOut);
    return pow(max(x, 0), 2.2);
}
// Neutral: keeps authored albedo / skin hue, only compresses highlights
float3 LumiNeutralHighlight(float3 c)
{
    const float start = 0.76, desat = 0.15;
    float x = min(c.r, min(c.g, c.b));
    c -= x < 0.08 ? x - 6.25 * x * x : 0.04;
    float peak = max(c.r, max(c.g, c.b));
    if (peak < start) return c;
    const float d = 1.0 - start;
    float newPeak = 1.0 - d * d / (peak + d - start);
    c *= newPeak / peak;
    float g = 1.0 - 1.0 / (desat * (peak - newPeak) + 1.0);
    return lerp(c, newPeak.xxx, g);
}
float3 LumiWhiteBalance(float3 col, float temperature, float tint)
{
    // simple warm/cool + green/magenta shift in linear space
    float3 shift = float3(temperature * 0.1 - tint * 0.05, tint * 0.1, -temperature * 0.1 - tint * 0.05);
    return col * max(1.0 + shift, 0.0);
}
// Vibrance that leaves already saturated colors and skin hues (orange, hue 0.0-0.12) mostly alone
float3 LumiSmartVibrance(float3 col, float vibrance)
{
    float mx = max(col.r, max(col.g, col.b)), mn = min(col.r, min(col.g, col.b));
    float sat = (mx - mn) / max(mx, 1e-4);
    float3 hsv = LumiRGB2HSV(saturate(col));
    float skin = smoothstep(0.16, 0.10, hsv.x) * smoothstep(-0.02, 0.02, hsv.x) * smoothstep(0.05, 0.2, hsv.y);
    float amount = vibrance * (1.0 - sat) * (1.0 - skin * 0.8);
    float l = LumiLuminance(col);
    return lerp(l.xxx, col, 1.0 + amount);
}
// mode: 0 none 1 filmic contrast 2 filmic soft 3 natural 4 natural punchy 5 neutral 6 simple
float3 LumiColorGrade(float3 col, float exposure, float mode, float contrast, float saturation, float temperature, float tint,
                      float vibrance, float3 shadowTint, float3 highlightTint)
{
    col *= exp2(exposure);
    col = LumiWhiteBalance(col, temperature, tint);
    if (mode == 1) col = LumiFilmicContrast(col);
    else if (mode == 2) col = LumiNeutral(col);
    else if (mode == 3) col = LumiNatural(col, 0);
    else if (mode == 4) col = LumiNatural(col, 1);
    else if (mode == 5) col = LumiNeutralHighlight(col);
    else if (mode == 6) col = col / (1.0 + LumiLuminance(col));
    // contrast around mid grey 0.18 in log space (filmic S without crushing)
    float3 lg = log2(max(col, 1e-5)) - log2(0.18);
    col = exp2(lg * contrast + log2(0.18));
    float l = LumiLuminance(col);
    col = lerp(l.xxx, col, saturation);
    col = LumiSmartVibrance(col, vibrance);
    // color balance: tint shadows / highlights
    float t = smoothstep(0.0, 1.0, saturate(LumiLuminance(col)));
    col *= lerp(shadowTint, highlightTint, t);
    return max(col, 0);
}

// ---- Normal helpers -----------------------------------------------------
float3 LumiUnpackNormal(float4 packed, float scale)
{
    float3 n;
    // supports both DXT5nm (AG) and plain RGB normal maps
    packed.x *= packed.w;
    n.xy = (packed.xy * 2.0 - 1.0) * scale;
    n.z = sqrt(saturate(1.0 - dot(n.xy, n.xy)));
    return n;
}
float3 LumiUnpackNormalRGB(float4 packed, float scale)
{
    float3 n = packed.xyz * 2.0 - 1.0;
    n.xy *= scale;
    return normalize(n);
}
float3 LumiBlendNormalRNM(float3 n1, float3 n2)
{
    // Reoriented normal mapping
    n1.z += 1.0; n2.xy = -n2.xy;
    return normalize(n1 * dot(n1, n2) / n1.z - n2);
}

#endif
