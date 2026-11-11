// MitToon - fake shadow: a copy of the hair drawn shifted along the light and multiplied onto the face.
// The face writes a stencil value, this pass only draws where that value is (so the shadow stays on the face).
// Property names follow the common fake shadow layout, so a material switched to this shader keeps its values.
Shader "MitToon/Optional/FakeShadow"
{
    Properties
    {
        [ToggleUI] _Invisible ("非表示|Invisible", Float) = 0
        _Color ("影の色|Shadow Color", Color) = (0.925, 0.7, 0.74, 1)
        _MainTex ("テクスチャ|Texture", 2D) = "white" {}
        _FakeShadowVector ("ずらす向き (XYZ) / 距離 (W)|Offset Direction (XYZ) / Distance (W)", Vector) = (0, 0, 0, 0.05)

        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("カリング|Cull", Float) = 2
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 2
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlendAlpha ("Src Blend Alpha", Float) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlendAlpha ("Dst Blend Alpha", Float) = 1
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("Blend Op", Float) = 0
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpAlpha ("Blend Op Alpha", Float) = 0
        [ToggleUI] _ZClip ("ZClip", Float) = 1
        [ToggleUI] _ZWrite ("ZWrite", Float) = 1
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
        _StencilRef ("ステンシル参照値|Stencil Ref", Range(0, 255)) = 51
        _StencilReadMask ("ステンシル読込マスク|Stencil Read Mask", Range(0, 255)) = 255
        _StencilWriteMask ("ステンシル書込マスク|Stencil Write Mask", Range(0, 255)) = 255
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("ステンシル比較|Stencil Compare", Float) = 3
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilPass ("ステンシル Pass|Stencil Pass", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFail ("ステンシル Fail|Stencil Fail", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilZFail ("ステンシル ZFail|Stencil ZFail", Float) = 0
        _OffsetFactor ("Offset Factor", Float) = 0
        _OffsetUnits ("Offset Units", Float) = 0
        _ColorMask ("Color Mask", Float) = 15
        [ToggleUI] _AlphaToMask ("Alpha To Mask", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "AlphaTest+55" }
        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }
            Stencil
            {
                Ref [_StencilRef]
                ReadMask [_StencilReadMask]
                WriteMask [_StencilWriteMask]
                Comp [_StencilComp]
                Pass [_StencilPass]
                Fail [_StencilFail]
                ZFail [_StencilZFail]
            }
            Cull [_Cull]
            ZClip [_ZClip]
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            ColorMask [_ColorMask]
            Offset [_OffsetFactor], [_OffsetUnits]
            BlendOp [_BlendOp], [_BlendOpAlpha]
            Blend [_SrcBlend] [_DstBlend], [_SrcBlendAlpha] [_DstBlendAlpha]
            AlphaToMask [_AlphaToMask]

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma target 3.5
            #include "UnityCG.cginc"

            float4 _LightColor0;
            sampler2D _MainTex;
            float4 _MainTex_ST, _Color, _FakeShadowVector;
            float _Invisible;

            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; UNITY_FOG_COORDS(1) UNITY_VERTEX_OUTPUT_STEREO };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                if (_Invisible > 0.5) return o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                // light direction: main light weighted by its brightness + the SH direction, plus the material's own offset
                float3 mainDir = _WorldSpaceLightPos0.xyz * dot(_LightColor0.rgb, float3(0.0396819152, 0.458021790, 0.00609653955));
                float3 shDir = (unity_SHAr.xyz + unity_SHAg.xyz + unity_SHAb.xyz) * 0.333333;
                float3 custom = mul((float3x3)unity_ObjectToWorld, _FakeShadowVector.xyz);
                custom = dot(custom, custom) > 1e-12 ? length(_FakeShadowVector.xyz) * normalize(custom) : 0;
                float3 L = normalize(normalize(mainDir + shDir + float3(0.001, 0.002, 0.001)) + custom);
                float3 posWS = mul(unity_ObjectToWorld, float4(v.vertex.xyz, 1)).xyz;
                o.pos = UnityWorldToClipPos(posWS);
                o.pos -= mul(UNITY_MATRIX_VP, float4(L * _FakeShadowVector.w, 0));
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float4 col = tex2D(_MainTex, i.uv) * _Color;
                UNITY_APPLY_FOG_COLOR(i.fogCoord, col, float4(1, 1, 1, 1));   // multiplied onto the face: fog fades it to white
                return col;
            }
            ENDCG
        }
    }
    Fallback Off
    CustomEditor "MitToon.Editor.MitToonShaderGUI"
}
