// MitToon Shader - Tessellation (Tessellation shader variants only)
// Hull / domain stages wrapped around the normal vertex functions: the patch is subdivided in object space,
// smoothed with Phong tessellation, then every new vertex goes through vert / vertOutline / vertShadow as usual,
// so wobble, outline width and shadow bias all work on the finer mesh.
// The amount is controlled by an edge length on screen, a distance fade and a mask texture (R).
#ifndef MITTOON_TESSELLATION_INCLUDED
#define MITTOON_TESSELLATION_INCLUDED

#if defined(UNITY_INSTANCING_ENABLED) || defined(UNITY_PROCEDURAL_INSTANCING_ENABLED) || defined(UNITY_STEREO_INSTANCING_ENABLED)
    #define LUMI_TESS_INSTANCING 1
#endif

struct LumiTessCP
{
    float4 vertex  : INTERNALTESSPOS;
    float3 normal  : NORMAL;
    float4 tangent : TANGENT;
    float2 uv0     : TEXCOORD0;
    float2 uv1     : TEXCOORD1;
    float4 color   : COLOR;
    float2 mask    : TEXCOORD2;   // x: tessellation mask, y: locked (border vertex, see below)
#if defined(LUMI_TESS_INSTANCING)
    uint instID    : TEXCOORD3;
#endif
};

struct LumiTessFactors
{
    float edge[3] : SV_TessFactor;
    float inside  : SV_InsideTessFactor;
};

// Crack free borders: the NDMF pass writes TEXCOORD6 = (shared uv, locked, 1) into the mesh.
// Split vertices (UV seams) all read the masks at the same shared uv, so both sides of an edge get the same factor.
// Locked vertices sit on a border (open edge, other material, hard normal): an edge between two of them is never
// subdivided and Phong smoothing fades out there, so it stays on the neighbour's straight edge.
struct LumiTessIn
{
    float4 vertex   : POSITION;
    float3 normal   : NORMAL;
    float4 tangent  : TANGENT;
    float2 uv0      : TEXCOORD0;
    float2 uv1      : TEXCOORD1;
    float4 color    : COLOR;
    float4 tessData : TEXCOORD6;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

LumiTessCP tessVert(LumiTessIn v)
{
    LumiTessCP o;
    float baked = step(0.5, v.tessData.w);
    float2 muv = baked > 0 ? v.tessData.xy : v.uv0;
    o.vertex = v.vertex;
    o.normal = v.normal;
    o.tangent = v.tangent;
    o.uv0 = v.uv0;
    o.uv1 = v.uv1;
    o.color = v.color;
    o.mask.x = _TessMask.SampleLevel(sampler_trilinear_repeat, muv, 0).r;
    o.mask.y = baked * step(0.5, v.tessData.z);
#if defined(LUMI_TESS_INSTANCING)
    o.instID = v.instanceID;
#endif
    return o;
}

// subdivisions needed so the edge is about _TessEdgeLength pixels on screen
float LumiTessEdgeFactor(float3 p0, float3 p1)
{
    float3 mid = (p0 + p1) * 0.5;
    float dist = max(distance(mid, LumiGetCameraPositionWS()), 0.01);
    float px = distance(p0, p1) * _ScreenParams.y * abs(UNITY_MATRIX_P[1][1]) * 0.5 / dist;
    float f = px / max(_TessEdgeLength, 1.0);
    // distance fade: full amount before FadeStart, back to 1 at FadeEnd
    float fade = 1.0 - saturate((dist - _TessFadeStart) / max(_TessFadeEnd - _TessFadeStart, 0.01));
    return lerp(1.0, f, fade);
}

bool LumiTessCull(float3 p0, float3 p1, float3 p2, float margin)
{
    // patch completely outside one frustum plane (with room for displacement / outline width)
    float4 c0 = UnityWorldToClipPos(p0), c1 = UnityWorldToClipPos(p1), c2 = UnityWorldToClipPos(p2);
    float3 m = float3(c0.w, c1.w, c2.w) * margin + margin;
    bool3 l = float3(c0.x, c1.x, c2.x) < -float3(c0.w, c1.w, c2.w) - m;
    bool3 r = float3(c0.x, c1.x, c2.x) >  float3(c0.w, c1.w, c2.w) + m;
    bool3 b = float3(c0.y, c1.y, c2.y) < -float3(c0.w, c1.w, c2.w) - m;
    bool3 t = float3(c0.y, c1.y, c2.y) >  float3(c0.w, c1.w, c2.w) + m;
    bool3 n = float3(c0.w, c1.w, c2.w) < -m;
    return all(l) || all(r) || all(b) || all(t) || all(n);
}

LumiTessFactors tessConst(InputPatch<LumiTessCP, 3> p)
{
    LumiTessFactors f;
#if defined(LUMI_TESS_INSTANCING)
    appdata iv = (appdata)0;
    iv.instanceID = p[0].instID;
    UNITY_SETUP_INSTANCE_ID(iv);
#endif
    float3 w0 = LumiObjectToWorld(p[0].vertex.xyz);
    float3 w1 = LumiObjectToWorld(p[1].vertex.xyz);
    float3 w2 = LumiObjectToWorld(p[2].vertex.xyz);
#if !defined(UNITY_PASS_SHADOWCASTER)
    // shadow maps use the light's view: never cull there
    if (LumiTessCull(w0, w1, w2, 0.1))
    {
        f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
        return f;
    }
#endif
    float3 W[3] = { w0, w1, w2 };
    float tessMax = max(_TessMax, 1.0);
    [unroll] for (int e = 0; e < 3; e++)
    {
        // edge e is opposite vertex e
        int a = (e + 1) % 3, b = (e + 2) % 3;
        float base = LumiTessEdgeFactor(W[a], W[b]);
        float m = (p[a].mask.x + p[b].mask.x) * 0.5;
        float fe = lerp(1.0, min(base, tessMax), m);
        if (p[a].mask.y > 0.5 && p[b].mask.y > 0.5) fe = 1.0;   // border edge: match the neighbour
        f.edge[e] = clamp(fe, 1.0, 64.0);
    }
    f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0;
    return f;
}

[domain("tri")]
[partitioning("fractional_odd")]
[outputtopology("triangle_cw")]
[patchconstantfunc("tessConst")]
[outputcontrolpoints(3)]
LumiTessCP tessHull(InputPatch<LumiTessCP, 3> p, uint id : SV_OutputControlPointID)
{
    return p[id];
}

appdata LumiTessInterpolate(const OutputPatch<LumiTessCP, 3> p, float3 bc)
{
    appdata v = (appdata)0;
    #define LUMI_TESS_BARY(f) (p[0].f * bc.x + p[1].f * bc.y + p[2].f * bc.z)
    float3 pos = LUMI_TESS_BARY(vertex.xyz);
    v.normal = normalize(LUMI_TESS_BARY(normal));
    float4 t = LUMI_TESS_BARY(tangent);
    v.tangent = float4(normalize(t.xyz + 1e-6), p[0].tangent.w);
    v.uv0 = LUMI_TESS_BARY(uv0);
    v.uv1 = LUMI_TESS_BARY(uv1);
    v.color = LUMI_TESS_BARY(color);
    // Phong tessellation: project onto each corner's tangent plane and blend, rounding the silhouette
    if (_TessPhong > 0.001)
    {
        float3 q0 = pos - dot(pos - p[0].vertex.xyz, p[0].normal) * p[0].normal;
        float3 q1 = pos - dot(pos - p[1].vertex.xyz, p[1].normal) * p[1].normal;
        float3 q2 = pos - dot(pos - p[2].vertex.xyz, p[2].normal) * p[2].normal;
        float3 phong = q0 * bc.x + q1 * bc.y + q2 * bc.z;
        float3 w = float3(p[0].mask.x * (1 - p[0].mask.y), p[1].mask.x * (1 - p[1].mask.y), p[2].mask.x * (1 - p[2].mask.y));
        float m = dot(w, bc);
        pos = lerp(pos, phong, _TessPhong * m);
    }
    #undef LUMI_TESS_BARY
    v.vertex = float4(pos, 1);
#if defined(LUMI_TESS_INSTANCING)
    v.instanceID = p[0].instID;
#endif
    return v;
}

#define LUMI_TESS_DOMAIN(name, outType, vfunc) \
    [domain("tri")] \
    outType name(LumiTessFactors f, const OutputPatch<LumiTessCP, 3> p, float3 bc : SV_DomainLocation) \
    { return vfunc(LumiTessInterpolate(p, bc)); }

LUMI_TESS_DOMAIN(tessDom_vert, v2f, vert)
LUMI_TESS_DOMAIN(tessDom_vertOutline, v2fOutline, vertOutline)
LUMI_TESS_DOMAIN(tessDom_vertOutline2, v2fOutline, vertOutline2)
LUMI_TESS_DOMAIN(tessDom_vertShadow, v2fShadow, vertShadow)

#endif
