// MitToon - mask paint tool (editor only). Draws the mesh in UV space into the mask render texture.
Shader "Hidden/MitToon/MaskPaint"
{
    Properties
    {
        _MainTex ("Tex", 2D) = "white" {}
        _Cov ("Coverage", 2D) = "black" {}
    }
    CGINCLUDE
    #include "UnityCG.cginc"
    float4 _Brush, _Brush2, _BrushDir, _BrushDir2;   // xyz world centre, w radius (0 = off) / dir: xyz view dir, w back face test
    float _Hardness, _Strength, _Value, _FlipY;
    sampler2D _MainTex, _Cov;
    float4 _MainTex_TexelSize;

    struct appdataP { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; };
    struct v2fP { float4 pos : SV_POSITION; float3 posWS : TEXCOORD0; float3 nWS : TEXCOORD1; };
    v2fP vertUV(appdataP v)
    {
        v2fP o;
        o.pos = float4(v.uv * 2 - 1, 0.5, 1);
        o.pos.y *= _FlipY;
        o.posWS = v.vertex.xyz;   // the tool feeds a mesh already in world space
        o.nWS = v.normal;
        return o;
    }
    float BrushA(float4 b, float3 p)
    {
        if (b.w <= 0) return 0;
        float d = distance(p, b.xyz) / b.w;
        return 1 - smoothstep(saturate(_Hardness) * 0.999, 1, d);
    }
    float4 fragBrush(v2fP i) : SV_Target
    {
        float3 n = normalize(i.nWS);
        float a1 = BrushA(_Brush, i.posWS), a2 = BrushA(_Brush2, i.posWS);
        if (_BrushDir.w > 0.5 && dot(n, _BrushDir.xyz) > 0.1) a1 = 0;     // skip faces turned away
        if (_BrushDir.w > 0.5 && dot(n, _BrushDir2.xyz) > 0.1) a2 = 0;
        float a = max(a1, a2);
        return float4(_Value.xxx, a * _Strength);
    }
    float4 fragFill(v2fP i) : SV_Target { return float4(_Value.xxx, _Strength); }
    float4 fragCov(v2fP i) : SV_Target { return 1; }

    // seam padding: uncovered texels take the average of covered neighbours
    float4 fragDilate(v2f_img i) : SV_Target
    {
        float4 c = tex2D(_MainTex, i.uv);
        if (tex2D(_Cov, i.uv).r > 0.5) return c;
        float4 sum = 0; float n = 0;
        [unroll] for (int y = -1; y <= 1; y++)
        [unroll] for (int x = -1; x <= 1; x++)
        {
            float2 uv = i.uv + float2(x, y) * _MainTex_TexelSize.xy;
            float w = tex2D(_Cov, uv).r > 0.5 ? 1 : 0;
            sum += tex2D(_MainTex, uv) * w; n += w;
        }
        return n > 0 ? sum / n : c;
    }
    float4 fragDilateCov(v2f_img i) : SV_Target
    {
        float m = 0;
        [unroll] for (int y = -1; y <= 1; y++)
        [unroll] for (int x = -1; x <= 1; x++)
            m = max(m, tex2D(_MainTex, i.uv + float2(x, y) * _MainTex_TexelSize.xy).r);
        return m;
    }
    float4 fragInvert(v2f_img i) : SV_Target { float4 c = tex2D(_MainTex, i.uv); return float4(1 - c.rgb, c.a); }
    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass { Blend SrcAlpha OneMinusSrcAlpha ColorMask RGB
               CGPROGRAM
               #pragma vertex vertUV
               #pragma fragment fragBrush
               ENDCG }
        Pass { Blend SrcAlpha OneMinusSrcAlpha ColorMask RGB
               CGPROGRAM
               #pragma vertex vertUV
               #pragma fragment fragFill
               ENDCG }
        Pass { CGPROGRAM
               #pragma vertex vertUV
               #pragma fragment fragCov
               ENDCG }
        Pass { CGPROGRAM
               #pragma vertex vert_img
               #pragma fragment fragDilate
               ENDCG }
        Pass { CGPROGRAM
               #pragma vertex vert_img
               #pragma fragment fragDilateCov
               ENDCG }
        Pass { CGPROGRAM
               #pragma vertex vert_img
               #pragma fragment fragInvert
               ENDCG }
    }
}
