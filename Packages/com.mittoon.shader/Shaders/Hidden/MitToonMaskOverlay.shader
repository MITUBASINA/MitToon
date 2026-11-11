// MitToon - mask paint tool overlay (editor only): shows the mask on the mesh in the Scene view.
Shader "Hidden/MitToon/MaskOverlay"
{
    Properties { _MaskTex ("Mask", 2D) = "white" {} }
    SubShader
    {
        Tags { "Queue" = "Overlay" }
        Cull Off ZWrite Off ZTest LEqual
        Offset -1, -1
        Blend SrcAlpha OneMinusSrcAlpha
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MaskTex;
            float _Opacity;
            struct a2v { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert(a2v v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.uv; return o; }
            float4 frag(v2f i) : SV_Target
            {
                float m = tex2D(_MaskTex, i.uv).r;
                // black = blue, white = pink
                return float4(lerp(float3(0.1, 0.25, 0.9), float3(1.0, 0.35, 0.65), m), _Opacity);
            }
            ENDCG
        }
    }
}
