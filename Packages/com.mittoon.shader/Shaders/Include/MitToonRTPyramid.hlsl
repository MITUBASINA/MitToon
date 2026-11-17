// RayTrace shader: blurred copies of the screen (a mip chain: 1/8 ... 1/64 size), so the bounce light and rough
// reflections can read a whole area with one read. Without it a few reads per direction catch a thin bright thing (a
// neon tube) on one vertex and miss it on the next (blotches).
// Each level keeps five averages of the surfaces under it (the sky left out), in two planes side by side:
//   plane 0 (rgba): colour x coverage (r, g, b), coverage (how much of the area is a surface)
//   plane 1 (r):    coverage / eye depth
// so a read gets the colour of the surfaces only and can tell whether the area holds one surface or several at other
// depths (an outline, where it then keeps to the sharp colour).
// The chain is drawn over the lower left corner of the screen (level 3 along the bottom, the others in a row above it),
// grabbed, and the corner is then put back exactly as it was (colour and alpha) from the grab taken before.
// It is built ONCE per camera render, by the first RayTrace object, and shared by all the others (the copies of the
// screen and the reads over the whole screen were the biggest cost, once per object before). Named grabs are taken once
// per camera render (mirrors / other cameras take their own), at the first object that uses them. Order of the passes:
//   RT_TOKEN: the builder writes the token of this render (below) into three pixels of the corner
//   -> unnamed grab U (per object: the screen with this object drawn, read by the composite pass; the builder's has the
//      token) -> RT_PYRAMID: level 3 from U -> _MitToonRTPyr1 -> RT_PYRAMID2: levels 4..6 from level 3
//   -> _MitToonRTPyr (P): the chain for every object -> RT_ALPHA: the corner back from U -> composite pass
// The token: a 24 bit number of this camera render (time, camera, a few depth pixels). P holding the token of this
// render = built already, so RT_TOKEN writes nothing; only the builder then finds it in its own U and draws the rest.
// Putting the corner back matters for the alpha too: Unity draws the first pass of every object of a render queue
// before the rest of any of them, so the alpha there also holds the blur marks of the FX pass of objects not drawn yet.
// The passes draw one quad over the corner, made by the geometry shader from the first triangle of the mesh.
#ifndef MITTOON_RTPYRAMID_INCLUDED
#define MITTOON_RTPYRAMID_INCLUDED

struct LumiPyrIn { float4 vertex : POSITION; };
struct LumiPyrV { float4 pos : SV_POSITION; };
struct LumiPyrG { float4 pos : SV_POSITION; float2 u : TEXCOORD0; };

LumiPyrV vertPyr(LumiPyrIn v)
{
    LumiPyrV o;
    o.pos = v.vertex;
    return o;
}

bool LumiRTPyrWanted()
{
#if defined(LUMI_RT_PYRAMID)
    // (the same for every object of a camera render, not per material: the first RayTrace object builds the chain for
    // all, also when it does not read it itself)
    return UNITY_MATRIX_P._m33 == 0.0 && LumiDepthTextureAvailable();
#else
    return false;
#endif
}

#if defined(LUMI_RT_PYRAMID)
float _LumiRTSerial;   // (the MitToon editor script counts camera renders: the editor can render a camera twice per frame)
uint LumiHashF(uint h, float v) { return (h ^ asuint(v)) * 16777619u; }
uint LumiHashF4(uint h, float4 v) { return LumiHashF(LumiHashF(LumiHashF(LumiHashF(h, v.x), v.y), v.z), v.w); }
// this camera render as a 24 bit number (bit exact in every stage: only integer maths on the raw bits)
uint LumiRTTokenNow()
{
    uint h = 2166136261u;
    h = LumiHashF4(h, float4(_Time.y, _LumiRTSerial, _ScreenParams.xy));
    h = LumiHashF4(h, float4(_WorldSpaceCameraPos, _ProjectionParams.z));
    h = LumiHashF4(h, UNITY_MATRIX_V[0]); h = LumiHashF4(h, UNITY_MATRIX_V[1]); h = LumiHashF4(h, UNITY_MATRIX_V[2]);
    h = LumiHashF4(h, float4(UNITY_MATRIX_P._m00, UNITY_MATRIX_P._m11, UNITY_MATRIX_P._m02, UNITY_MATRIX_P._m12));
    // a few depth pixels: two cameras at the same place that see different things
    uint w, ht;
    _CameraDepthTexture.GetDimensions(w, ht);
    [unroll] for (int i = 0; i < 16; i += 4)
    {
        float4 z;
        [unroll] for (int c = 0; c < 4; c++)
        {
            float2 f = float2((i + c + 0.37) / 16.0, frac(((i + c) * 7 + 0.61) / 16.0));
            z[c] = _CameraDepthTexture.Load(int3(int2(f * float2(w, ht)), 0));
        }
        h = LumiHashF4(h, z);
    }
    h ^= h >> 15; h *= 0x2c1b3c6du; h ^= h >> 12;
    return h & 0xFFFFFFu;
}
uint LumiRTTokenIn(Texture2D t)
{
    float2 eye = LumiEyeSize();
    uint v = 0;
    [unroll] for (int j = 0; j < 3; j++)
    {
        float2 u = ((float2)(LumiRTTokenPx(eye) + int2(j, 0)) + 0.5) / eye;
        float a = t.SampleLevel(sampler_point_clamp, LumiGrabUV(LumiEyeFull(u)), 0).a;
        v |= ((uint)round(saturate(a) * 255.0)) << (8 * j);
    }
    return v;
}
// which level / plane a pixel of the corner holds (k = 0: none)
void LumiRTPyrWhere(float2 a, int first, out float k, out float pl, out float2 uk)
{
    k = 0; pl = 0; uk = 0;
    [unroll] for (int j = first; j <= LUMI_RT_PYR_LEVELS; j++)
    {
        float s = exp2(-j), x0 = LumiRTPyrX0(j), y0 = LumiRTPyrY0(j);
        if (a.y >= y0 && a.y < y0 + s && a.x >= x0 && a.x < x0 + 2.0 * s)
        {
            k = j;
            pl = min(floor((a.x - x0) / s), 1.0);
            uk = float2((a.x - x0 - pl * s) / s, (a.y - y0) / s);
        }
    }
}
#endif

// a quad over the part of the corner the pass writes (LUMI_PYR_PASS 0: the token, 1: level 3, 2: levels 4..6, else the
// whole corner)
[maxvertexcount(4)]
void geomPyr(triangle LumiPyrV IN[3], uint pid : SV_PrimitiveID, inout TriangleStream<LumiPyrG> os)
{
#if defined(LUMI_RT_PYRAMID)
    // (the geometry shader runs for every triangle of the mesh: the rest only for the first one, real branches)
    [branch] if (pid != 0) return;
    [branch] if (!LumiRTPyrWanted()) return;
#if LUMI_PYR_PASS == 0
    [branch] if (LumiRTTokenIn(_MitToonRTPyr) == LumiRTTokenNow()) return;   // built already in this camera render
#else
    [branch] if (LumiRTTokenIn(_GrabTexture) != LumiRTTokenNow()) return;    // not the builder (no token in its own grab U)
#endif
    float s3 = exp2(-(float)LUMI_RT_PYR_FIRST);
#if LUMI_PYR_PASS == 0
    float2 eye = LumiEyeSize(), t0 = (float2)LumiRTTokenPx(eye);
    float2 lo = max(t0 - 1.0, 0.0) / eye, hi = (t0 + float2(3.0, 1.0)) / eye;   // (just the three token pixels)
#elif LUMI_PYR_PASS == 1
    float2 lo = 0, hi = float2(2.0 * s3, s3);
#elif LUMI_PYR_PASS == 2
    float2 lo = float2(0, s3), hi = float2(2.0 * s3, 1.5 * s3);
#else
    float2 lo = 0, hi = float2(2.0 * s3, 1.5 * s3);
#endif
    hi = min(hi + 2.0 / LumiEyeSize(), 1.0);   // (2 pixels of margin: the fragments check the exact edges)
    [unroll] for (int i = 0; i < 4; i++)
    {
        LumiPyrG g;
        // this eye's screen UV, the same way ComputeScreenPos makes it (before the stereo packing)
        g.u = float2((i & 1) ? hi.x : lo.x, (i & 2) ? hi.y : lo.y);
        g.pos = float4(g.u.x * 2.0 - 1.0, (g.u.y * 2.0 - 1.0) * _ProjectionParams.x, 0.5, 1.0);
        os.Append(g);
    }
#endif
}

// RT_TOKEN: the token of this camera render, one byte in the alpha of each of three pixels
float4 fragToken(LumiPyrG i) : SV_Target
{
#if defined(LUMI_RT_PYRAMID)
    float2 eye = LumiEyeSize();
    int2 q = int2(i.u * eye), t0 = LumiRTTokenPx(eye);
    int j = q.x - t0.x;
    if (q.y != t0.y || j < 0 || j > 2) discard;
    return ((float)((LumiRTTokenNow() >> (8 * j)) & 255u) / 255.0).xxxx;
#else
    discard;
    return 0;
#endif
}

float4 fragPyr(LumiPyrG i) : SV_Target
{
#if defined(LUMI_RT_PYRAMID)
    float2 a = i.u;
    float2 px = float2(abs(ddx(a.x)), abs(ddy(a.y)));   // one screen pixel in this eye's UV
    float k, pl; float2 uk;
    LumiRTPyrWhere(a, LUMI_RT_PYR_FIRST, k, pl, uk);
    if (k != (float)LUMI_RT_PYR_FIRST) discard;   // (the coarser levels: RT_PYRAMID2)
    // the 2^k x 2^k screen pixels under it, read on the corners between pixels (4 pixels per read). The loops are
    // unrolled and free of branches inside, so all reads go out at once (with a branch per read they wait one by one).
    const int N = 1 << (LUMI_RT_PYR_FIRST - 1);
    float2 start = uk - px * N;
    float far = _ProjectionParams.z * 0.95;
    float w[N * N];
    float iz = 0; bool clean = true;
    [unroll] for (int t = 0; t < N * N; t++)
    {
        float2 su = LumiEyeFull(saturate(start + px * (float2(t % N, t / N) * 2.0 + 1.0)));
        float dz = LumiSampleSceneEyeDepthSmooth(su);
        float cov = saturate((far - dz) / (far * 0.05));   // the sky / background is no surface
        // an object of the same queue not drawn yet holds the data of its FX pass there (marked in the alpha), not
        // its colour: left out like the sky
        float mw = dot(step(0.0008, abs(_GrabTexture.GatherAlpha(sampler_linear_clamp, LumiGrabUV(su)) - LUMI_FX_MARK)), 0.25);
        clean = clean && mw > 0.999;
        w[t] = cov * mw;
        iz += cov / max(dz, 0.05) * mw;
    }
    if (pl > 0.5) return float4(iz / (N * N), 0, 0, 0);
    float4 v = 0;
    [branch] if (clean)
    {
        // (no marks: each read is the bilinear mean of its four pixels)
        [unroll] for (int t = 0; t < N * N; t++)
        {
            float2 gu = LumiGrabUV(LumiEyeFull(saturate(start + px * (float2(t % N, t / N) * 2.0 + 1.0))));
            v += float4(LumiRTBright(_GrabTexture.SampleLevel(sampler_linear_clamp, gu, 0).rgb), 1.0) * w[t];
        }
    }
    else
    {
        // the marked pixels left out of each read's four
        [loop] for (int t = 0; t < N * N; t++)
        {
            float2 su = LumiEyeFull(saturate(start + px * (float2(t % N, t / N) * 2.0 + 1.0)));
            float2 gu = LumiGrabUV(su);
            float dz = LumiSampleSceneEyeDepthSmooth(su);
            float cov = saturate((far - dz) / (far * 0.05));
            float4 mk = step(0.0008, abs(_GrabTexture.GatherAlpha(sampler_linear_clamp, gu) - LUMI_FX_MARK));
            float mw = dot(mk, 0.25);
            float4 m4 = mk / max(mw * 4.0, 1e-4);
            float3 c = float3(dot(_GrabTexture.GatherRed(sampler_linear_clamp, gu), m4), dot(_GrabTexture.GatherGreen(sampler_linear_clamp, gu), m4), dot(_GrabTexture.GatherBlue(sampler_linear_clamp, gu), m4));
            v += float4(LumiRTBright(c), 1.0) * (cov * mw);
        }
    }
    return v / (N * N);
#else
    discard;
    return 0;
#endif
}

// levels 4..6 from level 3 (same plane): a level k texel is the average of 2^(k-3) x 2^(k-3) level 3 texels, read with
// bilinear taps on the corners between them
float4 fragPyr2(LumiPyrG i) : SV_Target
{
#if defined(LUMI_RT_PYRAMID)
    float2 a = i.u;
    float2 px = float2(abs(ddx(a.x)), abs(ddy(a.y)));   // one screen pixel in this eye's UV
    float k, pl; float2 uk;
    LumiRTPyrWhere(a, LUMI_RT_PYR_FIRST + 1, k, pl, uk);
    if (k < 0.5) discard;
    float f = (float)LUMI_RT_PYR_FIRST, s3 = exp2(-f);
    float2 t3 = px / s3;                      // one level 3 texel in its plane's 0..1 UV
    int n = (int)exp2(k - f - 1.0);           // taps per axis (each reads 2 x 2 level 3 texels)
    float2 start = uk - t3 * n;
    float2 o3 = float2(LumiRTPyrX0(f) + pl * s3, LumiRTPyrY0(f));
    float4 v = 0;
    [loop] for (int y = 0; y < n; y++)
        [loop] for (int x = 0; x < n; x++)
        {
            float2 ul = clamp(start + t3 * (float2(x, y) * 2.0 + 1.0), t3, 1.0 - t3);   // (inside the plane)
            v += _MitToonRTPyr1.SampleLevel(sampler_linear_clamp, LumiGrabUV(LumiEyeFull(o3 + ul * s3)), 0);
        }
    return v / (n * n);
#else
    discard;
    return 0;
#endif
}

// RT_ALPHA: the corner back as it was (U: taken before the chain was drawn), the token pixels to an opaque alpha
float4 fragAlpha(LumiPyrG i) : SV_Target
{
#if defined(LUMI_RT_PYRAMID)
    // (the whole quad, its margin too: where the edge of a level falls inside a pixel the passes before can write one
    // pixel past it, and U is the screen as it was there anyway)
    float4 c = _GrabTexture.SampleLevel(sampler_point_clamp, LumiGrabUV(LumiEyeFull(i.u)), 0);
    float2 eye = LumiEyeSize();
    int2 q = int2(i.u * eye), t0 = LumiRTTokenPx(eye);
    if (q.y == t0.y && q.x >= t0.x && q.x <= t0.x + 2) c.a = 1.0;
    return c;
#else
    discard;
    return 1;
#endif
}

#endif
