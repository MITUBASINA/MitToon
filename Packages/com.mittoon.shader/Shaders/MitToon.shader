// MitToon Shader (Built-in Render Pipeline)
// Toon <-> PBR hybrid avatar shader. Shading code is in Include/*.hlsl; only MitToonPlatformBIRP / MitToonPassBIRP are BIRP specific.
Shader "MitToon/MitToon"
{
    Properties
    {
        // ---------- Rendering ----------
        [HideInInspector] _RenderMode ("描画モード|Render Mode", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("カリング|Cull", Float) = 2
        [HideInInspector] _SrcBlend ("Src Blend", Float) = 1
        [HideInInspector] _DstBlend ("Dst Blend", Float) = 0
        [HideInInspector] _SrcBlendAdd ("Src Blend Add", Float) = 1
        [HideInInspector] _DstBlendAdd ("Dst Blend Add", Float) = 1
        [HideInInspector] _BlendOpAdd ("Blend Op Add", Float) = 0
        [Enum(Off,0,On,1)] _ZWrite ("深度書き込み|ZWrite", Float) = 1
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("深度テスト|ZTest", Float) = 4
        [Enum(Off,0,On,1)] _AlphaToMask ("Alpha To Coverage", Float) = 0
        _OffsetFactor ("深度オフセット係数|Offset Factor", Float) = 0
        _OffsetUnits ("深度オフセット単位|Offset Units", Float) = 0
        _StencilRef ("ステンシル参照値|Stencil Ref", Range(0, 255)) = 0
        _StencilReadMask ("ステンシル読込マスク|Stencil Read Mask", Range(0, 255)) = 255
        _StencilWriteMask ("ステンシル書込マスク|Stencil Write Mask", Range(0, 255)) = 255
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("ステンシル比較|Stencil Compare", Float) = 8
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilPass ("ステンシル Pass|Stencil Pass", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilFail ("ステンシル Fail|Stencil Fail", Float) = 0
        [Enum(UnityEngine.Rendering.StencilOp)] _StencilZFail ("ステンシル ZFail|Stencil ZFail", Float) = 0

        // ---------- Main ----------
        _Color ("メインカラー|Main Color", Color) = (1,1,1,1)
        _MainTex ("メインテクスチャ|Main Texture", 2D) = "white" {}
        _MainTexHSVG ("色相/彩度/明度/ガンマ|Hue/Sat/Value/Gamma", Vector) = (0,1,1,1)
        _MainColorAdjustMask ("色調補正マスク|Color Adjust Mask", 2D) = "white" {}
        _MainScroll ("スクロール(XY) 回転(Z)|Scroll XY / Rotate Z", Vector) = (0,0,0,0)
        [Enum(None,0,Replace,1,Multiply,2)] _AlphaMaskMode ("アルファマスク モード|Alpha Mask Mode", Float) = 0
        _AlphaMask ("アルファマスク|Alpha Mask", 2D) = "white" {}
        _AlphaMaskValue ("アルファ補正|Alpha Offset", Range(-1, 1)) = 0
        _Cutoff ("カットオフ|Cutoff", Range(0, 1)) = 0.5
        [Toggle] _UseVertexColor ("頂点カラーを乗算|Multiply Vertex Color", Float) = 0

        // ---------- Layers ----------
        [Toggle(_LUMI_LAYER)] _UseLayer ("カラーレイヤー|Color Layers", Float) = 0
        [Toggle] _UseMain2 ("2nd レイヤー|2nd Layer", Float) = 0
        _Main2Color ("色|Color", Color) = (1,1,1,1)
        _Main2Tex ("テクスチャ|Texture", 2D) = "white" {}
        _Main2Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(Normal,0,Add,1,Screen,2,Multiply,3)] _Main2Blend ("合成モード|Blend Mode", Float) = 0
        [Enum(UV0,0,UV1,1)] _Main2UV ("UV", Float) = 0
        [Toggle] _Main2Decal ("デカール (繰り返さない)|Decal (clamp)", Float) = 0
        _Main2Scroll ("スクロール(XY) 回転(Z)|Scroll XY / Rotate Z", Vector) = (0,0,0,0)
        [Toggle] _UseMain3 ("3rd レイヤー|3rd Layer", Float) = 0
        _Main3Color ("色|Color", Color) = (1,1,1,1)
        _Main3Tex ("テクスチャ|Texture", 2D) = "white" {}
        _Main3Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(Normal,0,Add,1,Screen,2,Multiply,3)] _Main3Blend ("合成モード|Blend Mode", Float) = 0
        [Enum(UV0,0,UV1,1)] _Main3UV ("UV", Float) = 0
        [Toggle] _Main3Decal ("デカール (繰り返さない)|Decal (clamp)", Float) = 0
        _Main3Scroll ("スクロール(XY) 回転(Z)|Scroll XY / Rotate Z", Vector) = (0,0,0,0)

        // ---------- Normal / Detail / Parallax ----------
        [Toggle(_LUMI_NORMALMAP)] _UseBumpMap ("ノーマルマップ|Normal Map", Float) = 0
        [Normal] _BumpMap ("ノーマルマップ|Normal Map", 2D) = "bump" {}
        _BumpScale ("強度|Scale", Range(-10, 10)) = 1
        _BumpMask ("マスク|Mask", 2D) = "white" {}
        [Toggle] _UseBump2 ("2nd ノーマルマップ|2nd Normal Map", Float) = 0
        [Normal] _Bump2Map ("2nd ノーマルマップ|2nd Normal Map", 2D) = "bump" {}
        _Bump2Scale ("強度|Scale", Range(-10, 10)) = 1
        _Bump2Mask ("マスク|Mask", 2D) = "white" {}
        [Toggle(_LUMI_DETAIL)] _UseDetail ("ディテール|Detail Maps", Float) = 0
        _DetailMask ("ディテールマスク|Detail Mask", 2D) = "white" {}
        _DetailAlbedoMap ("ディテール色 (0.5=無変化)|Detail Albedo x2", 2D) = "grey" {}
        _DetailAlbedoScale ("色の強度|Albedo Strength", Range(0, 1)) = 1
        [Normal] _DetailNormalMap ("ディテールノーマル|Detail Normal", 2D) = "bump" {}
        _DetailNormalScale ("ノーマル強度|Normal Scale", Range(-4, 4)) = 1
        [Enum(UV0,0,UV1,1)] _DetailUV ("UV", Float) = 0
        [Toggle(_LUMI_PARALLAX)] _UseParallax ("視差 (ハイト)|Parallax (Height)", Float) = 0
        _ParallaxMap ("ハイトマップ (G)|Height Map (G)", 2D) = "grey" {}
        _Parallax ("高さ|Height", Range(0, 0.1)) = 0.02
        [Enum(Offset,0,Occlusion,1)] _ParallaxMode ("方式|Mode", Float) = 1
        [IntRange] _ParallaxSteps ("ステップ数 (POM)|Steps (POM)", Range(4, 64)) = 16

        // ---------- PBR / Reflection ----------
        _ToonAmount ("トゥーン度 (0=リアル 1=トゥーン)|Toon Amount (0 PBR - 1 Toon)", Range(0, 1)) = 0.7
        [Enum(Separate,0,Mask MAOS,1,Packed ORM,2)] _PBRMapMode ("PBR マップ形式|PBR Map Layout", Float) = 0
        _MaskMap ("パックマップ|Packed Mask Map", 2D) = "white" {}
        _MetallicMap ("メタリック (R)|Metallic (R)", 2D) = "white" {}
        _Metallic ("メタリック|Metallic", Range(0, 1)) = 0
        _SmoothnessMap ("スムースネス (R)|Smoothness (R)", 2D) = "white" {}
        [Toggle] _SmoothnessIsRoughness ("ラフネスとして扱う|Map is Roughness", Float) = 0
        _Smoothness ("スムースネス|Smoothness", Range(0, 1)) = 0.5
        _OcclusionMap ("AO マップ (G)|Occlusion (G)", 2D) = "white" {}
        _OcclusionStrength ("AO 強度|Occlusion Strength", Range(0, 1)) = 1
        _Reflectance ("反射率 (誘電体)|Reflectance (Dielectric)", Range(0, 1)) = 0.5
        [HDR] _SpecularColor ("スペキュラ色|Specular Tint", Color) = (1,1,1,1)
        _SpecularStrength ("スペキュラ強度|Specular Strength", Range(0, 4)) = 1
        _SpecularToony ("スペキュラのトゥーン化|Toon Specular", Range(0, 1)) = 0
        _SpecularMask ("スペキュラマスク (R)|Specular Mask (R)", 2D) = "white" {}
        _Wetness ("濡れ|Wetness", Range(0, 1)) = 0
        _WetnessMask ("濡れマスク (R)|Wetness Mask (R)", 2D) = "white" {}
        _EnvReflStrength ("環境反射の強度|Environment Reflection", Range(0, 2)) = 1
        _EnvLightStrength ("環境光の強度 (PBR)|Ambient Strength (PBR)", Range(0, 2)) = 1
        [Enum(Auto SH Synthesis,0,Always Cubemap,1,Probe Only,2,Procedural Sky,3,Auto Fallback Cubemap,4)] _ReflCubeMode ("キューブマップ|Cubemap Mode", Float) = 0
        _ReflCube ("フォールバック キューブマップ|Fallback Cubemap", Cube) = "" {}
        _ReflCubeIntensity ("キューブマップ明るさ|Cubemap Intensity", Range(0, 4)) = 1
        _SpecAA ("スペキュラ AA 分散|Specular AA Variance", Range(0, 1)) = 0.25
        _SpecAAThreshold ("スペキュラ AA 上限|Specular AA Threshold", Range(0, 1)) = 0.2

        // ---------- Toon Shadow ----------
        _ShadowStrength ("影の強さ|Shadow Strength", Range(0, 1)) = 1
        _ShadowMaskTex ("影の強さマスク (R)|Strength Mask (R)", 2D) = "white" {}
        [Enum(Color Steps,0,Ramp Texture,1)] _ShadowRampMode ("影の方式|Shadow Mode", Float) = 0
        [NoScaleOffset] _ShadowRampTex ("ランプ (トゥーン)|Ramp (Toon)", 2D) = "white" {}
        _ShadowRampRow ("ランプの行 (V)|Ramp Row (V)", Range(0, 1)) = 0.5
        [Toggle] _UseILM ("ILM マップを使う|Use ILM Map", Float) = 0
        _ILMMap ("ILM (R=スペキュラ G=影しきい値 B=スペキュラマスク A=ランプ行)|ILM (R spec, G threshold, B spec mask, A ramp row)", 2D) = "white" {}
        [Toggle(_LUMI_FACESDF)] _UseFaceSDF ("顔 SDF 影|Face SDF Shadow", Float) = 0
        [NoScaleOffset] _FaceSDFTex ("SDF 影テクスチャ|Face SDF Texture", 2D) = "white" {}
        _FaceSDFMask ("適用マスク (R)|Apply Mask (R)", 2D) = "white" {}
        _FaceSDFBlur ("境界のぼかし|Edge Blur", Range(0.001, 0.2)) = 0.02
        [Toggle] _FaceSDFFlip ("左右反転|Flip Sides", Float) = 0
        _FaceForward ("顔の正面 (オブジェクト空間)|Face Forward (object space)", Vector) = (0, 0, 1, 0)
        _FaceUp ("顔の上方向 (オブジェクト空間)|Face Up (object space)", Vector) = (0, 1, 0, 0)
        _ShadowColor ("1影の色|1st Shadow Color", Color) = (0.82, 0.76, 0.85, 1)
        _ShadowColorTex ("1影テクスチャ|1st Shadow Texture", 2D) = "black" {}
        _ShadowBorder ("1影の境界|1st Border", Range(0, 1)) = 0.5
        _ShadowBlur ("1影のぼかし|1st Blur", Range(0, 1)) = 0.1
        _Shadow2ndColor ("2影の色 (A=強度)|2nd Shadow Color (A=strength)", Color) = (0.68, 0.66, 0.79, 1)
        _Shadow2ndColorTex ("2影テクスチャ|2nd Shadow Texture", 2D) = "black" {}
        _Shadow2ndBorder ("2影の境界|2nd Border", Range(0, 1)) = 0.15
        _Shadow2ndBlur ("2影のぼかし|2nd Blur", Range(0, 1)) = 0.1
        _ShadowMainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 1
        [HDR] _ShadowBorderColor ("境界色 (A=強度)|Border Color (A=strength)", Color) = (1, 0.35, 0.25, 0.6)
        _ShadowBorderRange ("境界色の幅|Border Color Range", Range(0, 0.5)) = 0.08
        _ShadowEnvStrength ("影側に環境光を使う|Environment Light in Shadow", Range(0, 1)) = 0.3
        _ShadowAOShift ("AO で影の境界を動かす|AO Shifts Border", Range(0, 1)) = 0.5
        // ---------- lilToon mode ----------
        [Toggle(_LUMI_COMPAT)] _CompatShading ("lilToon モード|lilToon Mode", Float) = 0
        _Shadow3rdColor ("3影の色|3rd Shadow Color", Color) = (0, 0, 0, 0)
        _Shadow3rdColorTex ("3影テクスチャ|3rd Shadow Texture", 2D) = "black" {}
        _Shadow3rdBorder ("3影の境界|3rd Border", Range(0, 1)) = 0.25
        _Shadow3rdBlur ("3影のぼかし|3rd Blur", Range(0, 1)) = 0.1
        _ShadowNormalStrength ("1影のノーマルマップ強度|1st Normal Map Strength", Range(0, 1)) = 1
        _Shadow2ndNormalStrength ("2影のノーマルマップ強度|2nd Normal Map Strength", Range(0, 1)) = 1
        _Shadow3rdNormalStrength ("3影のノーマルマップ強度|3rd Normal Map Strength", Range(0, 1)) = 1
        _ShadowReceive ("1影で落ち影を受ける|1st Receive Shadow", Range(0, 1)) = 0
        _Shadow2ndReceive ("2影で落ち影を受ける|2nd Receive Shadow", Range(0, 1)) = 0
        _Shadow3rdReceive ("3影で落ち影を受ける|3rd Receive Shadow", Range(0, 1)) = 0
        _ShadowBorderMask ("AO マップ|AO Map", 2D) = "white" {}
        _CompatAOShift ("AO の調整 1影 2影|AO Remap 1st 2nd", Vector) = (1, 0, 1, 0)
        _ShadowAOShift2 ("AO の調整 3影|AO Remap 3rd", Vector) = (1, 0, 1, 0)
        [ToggleUI] _ShadowPostAO ("AO を境界の後に掛ける|Apply AO After Border", Float) = 0
        _ShadowBlurMask ("ぼかし量マスク|Blur Mask", 2D) = "white" {}
        _BackfaceForceShadow ("裏面を影にする|Backface Force Shadow", Range(0, 1)) = 0
        _RimDirRange ("リム 光側の広さ|Rim Lit Side Range", Range(-1, 1)) = 0
        _RimIndirRange ("リム 影側の広さ|Rim Shadow Side Range", Range(-1, 1)) = 0
        [HDR] _RimIndirColor ("リム 影側の色|Rim Shadow Side Color", Color) = (1, 1, 1, 1)
        _RimIndirBorder ("リム 影側の境界|Rim Shadow Side Border", Range(0, 1)) = 0.5
        _RimIndirBlur ("リム 影側のぼかし|Rim Shadow Side Blur", Range(0, 1)) = 0.1
        [ToggleUI] _UseRimShade ("リムシェード|Rim Shade", Float) = 0
        _RimShadeColor ("リムシェードの色|Rim Shade Color", Color) = (0.5, 0.5, 0.5, 1)
        _RimShadeMask ("リムシェードのマスク|Rim Shade Mask", 2D) = "white" {}
        _RimShadeNormalStrength ("リムシェードのノーマルマップ強度|Rim Shade Normal Map Strength", Range(0, 1)) = 1
        _RimShadeBorder ("リムシェードの境界|Rim Shade Border", Range(0, 1)) = 0.5
        _RimShadeBlur ("リムシェードのぼかし|Rim Shade Blur", Range(0, 1)) = 1
        _RimShadeFresnelPower ("リムシェードのフレネル|Rim Shade Fresnel Power", Range(0.01, 50)) = 1
        [ToggleUI] _BacklightReceiveShadow ("逆光で落ち影を受ける|Backlight Receive Shadow", Float) = 1
        [ToggleUI] _BacklightBackfaceMask ("逆光を裏面で消す|Backlight Backface Mask", Float) = 1
        [ToggleUI] _MatCapBackfaceMask ("マットキャップを裏面で消す|MatCap Backface Mask", Float) = 0
        _ReceiveShadowStrength ("落ち影を受ける|Receive Shadows", Range(0, 1)) = 1
        [ToggleUI] _ReceiveCastShadow ("落ち影を受け取る (オフでも陰影や他の影は残る)|Receive Cast Shadows (off keeps shading and other shadows)", Float) = 1
        _CastShadowSoftness ("落ち影の縁のやわらかさ|Cast Shadow Edge Softness", Range(0, 1)) = 0.3

        // ---------- Lighting ----------
        _LightMinLimit ("明るさ下限|Min Brightness", Range(0, 1)) = 0.05
        _LightMaxLimit ("明るさ上限|Max Brightness", Range(0, 10)) = 1
        _MonochromeLighting ("ライトの単色化|Monochrome Lighting", Range(0, 1)) = 0
        _AsUnlit ("Unlit 化|As Unlit", Range(0, 1)) = 0
        _VertexLightStrength ("頂点ライトの強度|Vertex Light Strength", Range(0, 1)) = 1
        _AddLightMaxLimit ("追加ライト 1 灯の明るさ上限|Max Brightness per Additional Light", Range(0, 10)) = 1.5
        _AddLightSoftness ("追加ライトの明暗のなめらかさ|Additional Light Softness", Range(0, 1)) = 0.5
        _AddLightCastShadow ("追加ライトの落ち影|Additional Light Cast Shadows", Range(0, 1)) = 0
        _AddLightPassthrough ("追加ライトを影側にも通す|Additional Light Passthrough", Range(0, 1)) = 0
        _AddLightMonochrome ("追加ライトの単色化|Additional Light Monochrome", Range(0, 1)) = 0
        _AddLightSmoothFalloff ("ポイントライトの端をなめらかに|Smooth Point Light Edge", Range(0, 1)) = 1
        [Toggle] _AddLightIgnoreDirectional ("追加のディレクショナルライトを無視|Ignore Extra Directional Lights", Float) = 0
        [Enum(MitToon Auto,0,Standard (direct and ambient),1,Always Visible,2,SH Lit and Shade,3,Flat,4)] _LightColorMode ("ライトの色の方式|Light Color Mode", Float) = 0
        [Enum(Toon Border,0,Half Lambert Gradient,1,Lambert,2,Cast Shadows Only,3,No Shading,4)] _LightMapMode ("明暗の付け方|Light Map Mode", Float) = 0
        _UnlitIntensity ("ライトが無い時の明るさ|Brightness Without Lights", Range(0.001, 4)) = 1
        _LightViewYaw ("カメラ基準の左右角度|Camera Light Yaw", Range(-90, 90)) = 0
        _LightViewPitch ("カメラ基準の上下角度|Camera Light Pitch", Range(-90, 90)) = 0
        _AutoShadowColor ("影色の自動生成|Auto Shadow Color", Range(0, 1)) = 0
        _AutoShadowHue ("影の色相シフト|Shadow Hue Shift", Range(0, 0.2)) = 0.06
        _AutoShadowDarkness ("自動影色の明るさ|Auto Shadow Brightness", Range(0.2, 1)) = 0.72
        _QLodDistance ("遠距離で軽量化 (m, 0=無効)|Distance LOD (m, 0 = off)", Range(0, 30)) = 12
        _LightDirKeepUp ("環境光の向きを上からに保つ|Keep Ambient Light From Above", Range(0, 1)) = 1
        _AddLightStrength ("追加ライトの強度|Additional Light Strength", Range(0, 2)) = 1
        _LightDirOverride ("ライト方向の上書き (W=割合)|Light Direction Override (W=blend)", Vector) = (0, 0.6, 0.4, 0)
        _ShadowCasterBias ("影のバイアス (cm, 小さな形の自己影を消す)|Shadow Caster Bias (cm, removes small self shadows)", Range(0, 20)) = 10
        _ShadowCasterBiasView ("光が正面から当たるほど強める|Stronger for Front Light", Range(0, 1)) = 1
        _ShadowCasterNormalBias ("影のノーマルバイアス (cm)|Shadow Normal Bias (cm)", Range(0, 5)) = 0.3

        // ---------- Screen space ----------
        [Toggle(_LUMI_SSAO)] _UseSSAO ("SSAO", Float) = 0
        _SSAORadius ("半径 (m)|Radius (m)", Range(0.005, 0.5)) = 0.06
        _SSAOStrength ("強度|Strength", Range(0, 4)) = 1.2
        [IntRange] _SSAOSamples ("サンプル数|Samples", Range(4, 8)) = 6
        _SSAOBias ("バイアス (m)|Bias (m)", Range(0, 0.02)) = 0.002
        _SSAODirect ("直接光にも適用|Apply to Direct Light", Range(0, 1)) = 0.3
        _SSAOColor ("遮蔽色 (カラー AO)|Occlusion Color", Color) = (0.12, 0.06, 0.06, 1)
        _SSAOMaxDistance ("有効距離 (m)|Max Distance (m)", Range(1, 50)) = 12
        [Enum(Hemisphere (standard),1,Horizon,0)] _SSAOMethod ("方式|Method", Float) = 1
        _SSAOSoftness ("やわらかさ|Softness", Range(0, 1)) = 0.35
        _SSAOThickness ("厚み (手前の物を遮蔽とみなす範囲)|Thickness", Range(0.1, 4)) = 1
        _SSAOFalloff ("距離減衰の開始位置 (1 = 減衰なし)|Falloff Start (1 = none)", Range(0, 1)) = 1
        _SSAODistanceScale ("距離で半径を広げる|Radius Grows with Distance", Range(0, 1)) = 0
        _SSAOFarWeight ("遠距離の遮蔽の重み|Far Occlusion Weight", Range(0, 1)) = 0
        _SSAOFarScale ("遠距離の半径倍率|Far Radius Scale", Range(1, 8)) = 3
        _SSAONearWeight ("近距離の遮蔽の重み|Near Occlusion Weight", Range(0, 2)) = 1
        _SSAOMidWeight ("中距離の遮蔽の重み|Mid Occlusion Weight", Range(0, 1)) = 0
        _SSAOMidScale ("中距離の半径倍率|Mid Radius Scale", Range(1, 4)) = 1.8
        _SSAOViewFix ("視野角の補正|View Angle Correction", Range(0, 1)) = 0
        _SSAOAlphaInfluence ("透明度の影響|Transparency Influence", Range(0, 1)) = 0
        _SSAOPower ("指数|Power", Range(0.2, 4)) = 1
        _SSAOContrast ("コントラスト|Contrast", Range(0.2, 3)) = 1
        _SSAOMin ("最小の明るさ|Minimum Visibility", Range(0, 1)) = 0
        _SSAOAmbient ("環境光への影響|Ambient Influence", Range(0, 1)) = 1
        _SSAOSpecular ("反射への影響|Specular Influence", Range(0, 1)) = 1
        _SSAOJitter ("ノイズ (ジッター)|Jitter", Range(0, 1)) = 1
        _SSAOFadeStart ("フェード開始 (有効距離に対する割合)|Fade Start (fraction of max distance)", Range(0, 1)) = 0.7
        _SSAOMask ("SSAO マスク (R)|SSAO Mask (R)", 2D) = "white" {}
        _SSAOMaskStrength ("マスクの強さ|Mask Strength", Range(0, 1)) = 1
        _SSAOAlbedoTint ("遮蔽色にベースカラーを混ぜる|Tint Occlusion with Base Color", Range(0, 1)) = 0
        _SSAONormalStrength ("ノーマルマップの反映|Normal Map Detail", Range(0, 1)) = 0
        [Toggle(_LUMI_SOFTSHADOW)] _UseSoftShadow ("ソフトシャドウ|Soft Shadows", Float) = 1
        _SoftShadowRadius ("ぼかし半径 (m)|Blur Radius (m)", Range(0, 0.1)) = 0.015
        [IntRange] _SoftShadowSamples ("サンプル数|Samples", Range(4, 8)) = 6
        _ShadowSmoothness ("境界の滑らかさ|Edge Smoothness", Range(0, 1)) = 0.6
        _ShadowTerminatorFade ("明暗境界のちらつき防止|Terminator Flicker Guard", Range(0, 0.5)) = 0.15
        [Toggle(_LUMI_CONTACTSHADOW)] _UseContactShadow ("コンタクトシャドウ|Contact Shadows", Float) = 0
        _ContactShadowLength ("長さ (m)|Length (m)", Range(0.01, 0.5)) = 0.08
        _ContactShadowThickness ("厚み (m)|Thickness (m)", Range(0.001, 0.2)) = 0.03
        _ContactShadowStrength ("強度|Strength", Range(0, 1)) = 0.8
        [IntRange] _ContactShadowSteps ("ステップ数|Steps", Range(4, 8)) = 6
        _ContactShadowBias ("開始位置のずらし (m)|Start Offset (m)", Range(0, 0.02)) = 0.003
        _ContactShadowMinDelta ("判定の最小差 (m, 自己影の誤検出を防ぐ)|Minimum Depth Difference (m)", Range(0, 0.01)) = 0.0008
        _ContactShadowSoftness ("境界のやわらかさ (m)|Edge Softness (m)", Range(0, 0.02)) = 0
        _ContactShadowEndFade ("先端の減衰|Fade Toward Ray End", Range(0, 1)) = 1
        _ContactShadowJitter ("ノイズ (ジッター)|Jitter", Range(0, 1)) = 1
        _ContactShadowDistanceScale ("距離で長さを広げる|Length Grows with Distance", Range(0, 1)) = 0
        _ContactShadowMaxDistance ("有効距離 (m, 0 = 無制限)|Max Distance (m, 0 = unlimited)", Range(0, 50)) = 0
        _ContactShadowMask ("受ける側のマスク (R, 黒 = 影なし)|Receive Mask (R, black = none)", 2D) = "white" {}
        _ContactShadowMaskStrength ("マスクの強さ|Mask Strength", Range(0, 1)) = 1

        // ---------- SSS / Backlight ----------
        [Toggle(_LUMI_SSS)] _UseSSS ("サブサーフェス (肌)|Subsurface (Skin)", Float) = 0
        _SSSMap ("SSS マップ (R=マスク G=薄さ)|SSS Map (R mask, G thinness)", 2D) = "white" {}
        _SSSColor ("散乱色|Scatter Color", Color) = (1, 0.35, 0.2, 1)
        _SSSStrength ("強度|Strength", Range(0, 1)) = 0.8
        _SSSWrap ("回り込み|Wrap", Range(0, 1)) = 0.5
        _SSSCurvature ("曲率で調整|Curvature Response", Range(0, 1)) = 0.3
        _TransmissionStrength ("透過光|Transmission", Range(0, 4)) = 0.5
        _TransmissionPower ("透過の鋭さ|Transmission Power", Range(0.1, 16)) = 4
        _TransmissionDistortion ("透過の歪み|Transmission Distortion", Range(0, 1)) = 0.3
        [Toggle(_LUMI_BACKLIGHT)] _UseBacklight ("逆光ライト|Backlight", Float) = 0
        [HDR] _BacklightColor ("色|Color", Color) = (0.85, 0.8, 0.7, 1)
        _BacklightMask ("マスク|Mask", 2D) = "white" {}
        _BacklightBorder ("境界|Border", Range(0, 1)) = 0.35
        _BacklightBlur ("ぼかし|Blur", Range(0, 1)) = 0.05
        _BacklightDirectivity ("指向性|Directivity", Range(0, 20)) = 5
        _BacklightViewStrength ("視線方向の影響|View Direction Strength", Range(0, 1)) = 1
        _BacklightNormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1
        _BacklightMainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0.5

        // ---------- Anisotropic highlight ----------
        [Toggle(_LUMI_ANISO)] _UseAniso ("異方性ハイライト|Anisotropic Highlight", Float) = 0
        [Enum(Strand 2 lobes,0,GGX,1)] _AnisoMode ("方式|Mode", Float) = 0
        [Enum(Tangent,0,Bitangent,1,Radial,2,Circular,3)] _AnisoTangent ("流れの向き|Direction", Float) = 1
        _AnisoAngle ("向きの回転|Rotate Direction", Range(-180, 180)) = 0
        _AnisoCenter ("中心|Center", Vector) = (0.5, 0.5, 0, 0)
        _AnisoStrength ("強度|Strength", Range(0, 4)) = 1
        [Enum(Replace,0,Add,1)] _AnisoBlend ("合成|Blend", Float) = 0
        _AnisoMask ("マスク|Mask", 2D) = "white" {}
        _AnisoShiftMap ("シフトノイズ|Shift Noise", 2D) = "grey" {}
        _AnisoShiftNoise ("ノイズ強度|Noise Strength", Range(0, 2)) = 0.5
        [HDR] _Aniso1Color ("1st ハイライト色|Primary Color", Color) = (0.6, 0.6, 0.6, 1)
        _Aniso1Shift ("1st シフト|Primary Shift", Range(-1, 1)) = 0
        _Aniso1Exponent ("1st 鋭さ|Primary Exponent", Range(1, 1024)) = 256
        [HDR] _Aniso2Color ("2nd ハイライト色|Secondary Color", Color) = (0.6, 0.5, 0.45, 1)
        _Aniso2Shift ("2nd シフト|Secondary Shift", Range(-1, 1)) = -0.3
        _Aniso2Exponent ("2nd 鋭さ|Secondary Exponent", Range(1, 1024)) = 48
        _Aniso2Albedo ("2nd にベースカラーを乗算|Secondary x Base Color", Range(0, 1)) = 1
        _Anisotropy ("伸び|Stretch", Range(-1, 1)) = 0.8
        _AnisoToony ("トゥーン化|Toon", Range(0, 1)) = 0
        _AnisoToonBlur ("トゥーンのぼかし|Toon Blur", Range(0.001, 0.5)) = 0.05

        // ---------- Cloth / Coat ----------
        [Toggle(_LUMI_SHEEN)] _UseSheen ("シーン (布)|Sheen (Cloth)", Float) = 0
        [HDR] _SheenColor ("シーン色|Sheen Color", Color) = (0.3, 0.3, 0.3, 1)
        _SheenMap ("シーンマップ|Sheen Map", 2D) = "white" {}
        _SheenRoughness ("シーンの粗さ|Sheen Roughness", Range(0.05, 1)) = 0.5
        _SheenMask ("マスク|Mask", 2D) = "white" {}
        _SheenFuzz ("フチの毛羽立ち|Edge Fuzz", Range(0, 2)) = 0
        _SheenFuzzPower ("毛羽立ちの幅|Fuzz Width", Range(0.5, 8)) = 3
        [Toggle(_LUMI_CLEARCOAT)] _UseClearCoat ("クリアコート|Clear Coat", Float) = 0
        _ClearCoat ("強度|Strength", Range(0, 1)) = 1
        _ClearCoatMask ("マスク|Mask", 2D) = "white" {}
        _ClearCoatSmoothness ("スムースネス|Smoothness", Range(0, 1)) = 0.95
        [Toggle] _ClearCoatUseNormal ("ノーマルマップを使う|Use Normal Map", Float) = 0
        _ClearCoatColor ("下層の吸収色|Absorption Tint", Color) = (1, 1, 1, 1)
        _ClearCoatSmoothnessMap ("スムースネスマップ|Smoothness Map", 2D) = "white" {}
        [HDR] _ClearCoatSpecColor ("ハイライト色|Highlight Color", Color) = (1, 1, 1, 1)
        _ClearCoatF0 ("反射率|Reflectance", Range(0.02, 0.16)) = 0.04
        _ClearCoatReflStrength ("景色の映り込み|Environment Reflection", Range(0, 2)) = 1
        [Normal] _ClearCoatNormalMap ("コートのノーマルマップ|Coat Normal Map", 2D) = "bump" {}
        _ClearCoatNormalScale ("コートのノーマル強度|Coat Normal Scale", Range(0, 2)) = 0
        _ClearCoatToony ("トゥーン化|Toon", Range(0, 1)) = 0
        _ClearCoatToonBlur ("トゥーンのぼかし|Toon Blur", Range(0.001, 0.5)) = 0.05

        // ---------- Rim ----------
        [Toggle(_LUMI_RIM)] _UseRim ("リムライト1|Rim Light 1", Float) = 0
        [HDR] _RimColor ("色|Color", Color) = (0.66, 0.5, 0.48, 1)
        _RimTex ("テクスチャ / マスク|Texture / Mask", 2D) = "white" {}
        _RimBorder ("境界|Border", Range(0, 1)) = 0.5
        _RimBlur ("ぼかし|Blur", Range(0, 1)) = 0.65
        _RimFresnelPower ("フレネル|Fresnel Power", Range(0.01, 50)) = 3.5
        _RimLightDir ("ライト方向の影響|Light Direction", Range(0, 1)) = 0.5
        _RimShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0.5
        _RimMainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0
        _RimNormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1
        _RimEnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _RimBackfaceMask ("裏面で消す|Backface Mask", Range(0, 1)) = 1
        [Enum(Fresnel,0,Screen Space Depth,1)] _RimMode ("リムの方式|Rim Mode", Float) = 0
        _RimDepthWidth ("深度リムの幅 (cm)|Depth Rim Width (cm)", Range(0, 3)) = 0.4
        _RimDepthThreshold ("深度差のしきい値 (m)|Depth Threshold (m)", Range(0.005, 1)) = 0.08
        [Enum(Add,0,Screen,1,Multiply,2,Replace,3)] _RimBlendMode ("合成モード|Blend Mode", Float) = 0
        _RimLitSideOnly ("光の当たる側にだけ出す|Lit Side Only", Range(0, 1)) = 0
        _RimLitSideBlur ("光の当たる側の境界ぼかし|Lit Side Blur", Range(0.01, 1)) = 0.3
        _RimEmission ("発光にする (ライトの影響を受けない)|Emissive (ignores lights)", Range(0, 1)) = 0
        _RimEmissionStrength ("発光の強さ|Emission Strength", Range(0, 10)) = 1
        _RimBlink ("点滅 (強度, 速さ, 位相, 矩形波)|Blink (strength, speed, phase, square)", Vector) = (0, 2, 0, 0)
        _RimHueSpeed ("色相の変化 (虹色, 回/秒)|Hue Cycle (rainbow, per second)", Range(0, 2)) = 0
        // ---------- Rim light 2 ----------
        [ToggleUI] _UseRim2 ("リムライト2|Rim Light 2", Float) = 0
        [HDR] _Rim2Color ("色|Color", Color) = (0.55, 0.65, 1, 1)
        _Rim2Tex ("テクスチャ / マスク|Texture / Mask", 2D) = "white" {}
        _Rim2Border ("境界|Border", Range(0, 1)) = 0.6
        _Rim2Blur ("ぼかし|Blur", Range(0, 1)) = 0.3
        _Rim2FresnelPower ("フレネル|Fresnel Power", Range(0.01, 50)) = 3
        _Rim2LightDir ("ライト方向の影響|Light Direction", Range(0, 1)) = 0
        _Rim2ShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0
        _Rim2MainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0
        _Rim2NormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1
        _Rim2EnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _Rim2BackfaceMask ("裏面で消す|Backface Mask", Range(0, 1)) = 1
        [Enum(Add,0,Screen,1,Multiply,2,Replace,3)] _Rim2BlendMode ("合成モード|Blend Mode", Float) = 0
        _Rim2LitSideOnly ("光の当たる側にだけ出す|Lit Side Only", Range(0, 1)) = 0
        _Rim2LitSideBlur ("光の当たる側の境界ぼかし|Lit Side Blur", Range(0.01, 1)) = 0.3
        _Rim2Emission ("発光にする (ライトの影響を受けない)|Emissive (ignores lights)", Range(0, 1)) = 0
        _Rim2EmissionStrength ("発光の強さ|Emission Strength", Range(0, 10)) = 1
        _Rim2Blink ("点滅 (強度, 速さ, 位相, 矩形波)|Blink (strength, speed, phase, square)", Vector) = (0, 2, 0, 0)
        _Rim2HueSpeed ("色相の変化 (虹色, 回/秒)|Hue Cycle (rainbow, per second)", Range(0, 2)) = 0
        // ---------- Rim light 3 ----------
        [ToggleUI] _UseRim3 ("リムライト3|Rim Light 3", Float) = 0
        [HDR] _Rim3Color ("色|Color", Color) = (1, 0.85, 0.6, 1)
        _Rim3Tex ("テクスチャ / マスク|Texture / Mask", 2D) = "white" {}
        _Rim3Border ("境界|Border", Range(0, 1)) = 0.6
        _Rim3Blur ("ぼかし|Blur", Range(0, 1)) = 0.3
        _Rim3FresnelPower ("フレネル|Fresnel Power", Range(0.01, 50)) = 3
        _Rim3LightDir ("ライト方向の影響|Light Direction", Range(0, 1)) = 0
        _Rim3ShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0
        _Rim3MainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0
        _Rim3NormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1
        _Rim3EnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _Rim3BackfaceMask ("裏面で消す|Backface Mask", Range(0, 1)) = 1
        [Enum(Add,0,Screen,1,Multiply,2,Replace,3)] _Rim3BlendMode ("合成モード|Blend Mode", Float) = 0
        _Rim3LitSideOnly ("光の当たる側にだけ出す|Lit Side Only", Range(0, 1)) = 0
        _Rim3LitSideBlur ("光の当たる側の境界ぼかし|Lit Side Blur", Range(0.01, 1)) = 0.3
        _Rim3Emission ("発光にする (ライトの影響を受けない)|Emissive (ignores lights)", Range(0, 1)) = 0
        _Rim3EmissionStrength ("発光の強さ|Emission Strength", Range(0, 10)) = 1
        _Rim3Blink ("点滅 (強度, 速さ, 位相, 矩形波)|Blink (strength, speed, phase, square)", Vector) = (0, 2, 0, 0)
        _Rim3HueSpeed ("色相の変化 (虹色, 回/秒)|Hue Cycle (rainbow, per second)", Range(0, 2)) = 0

        // ---------- MatCap ----------
        [Toggle(_LUMI_MATCAP)] _UseMatCap ("マットキャップ|MatCap", Float) = 0
        [HDR] _MatCapColor ("色 (A=強度)|Color (A=strength)", Color) = (1,1,1,1)
        _MatCapTex ("マットキャップ|MatCap", 2D) = "white" {}
        _MatCapMask ("マスク|Mask", 2D) = "white" {}
        [Enum(Normal,0,Add,1,Screen,2,Multiply,3)] _MatCapBlend ("合成モード|Blend Mode", Float) = 1
        _MatCapLod ("ぼかし|Blur", Range(0, 10)) = 0
        _MatCapEnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _MatCapShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0
        _MatCapMainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0
        _MatCapNormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1
        _MatCapPerspective ("パース補正|Perspective Correction", Range(0, 1)) = 1
        _MatCapZRotCancel ("首かしげ補正|Cancel Camera Roll", Range(0, 1)) = 1
        [Toggle] _UseMatCapBump ("専用ノーマルマップ|Custom Normal Map", Float) = 0
        [Normal] _MatCapBumpMap ("ノーマルマップ|Normal Map", 2D) = "bump" {}
        _MatCapBumpScale ("強度|Scale", Range(-10, 10)) = 1
        [Toggle] _UseMatCap2 ("2nd マットキャップ|2nd MatCap", Float) = 0
        [HDR] _MatCap2Color ("色 (A=強度)|Color (A=strength)", Color) = (1,1,1,1)
        _MatCap2Tex ("マットキャップ|MatCap", 2D) = "white" {}
        _MatCap2Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(Normal,0,Add,1,Screen,2,Multiply,3)] _MatCap2Blend ("合成モード|Blend Mode", Float) = 1
        _MatCap2Lod ("ぼかし|Blur", Range(0, 10)) = 0
        _MatCap2EnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _MatCap2ShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0
        _MatCap2NormalStrength ("ノーマルマップ強度|Normal Map Strength", Range(0, 1)) = 1

        // ---------- Glitter ----------
        [Toggle(_LUMI_GLITTER)] _UseGlitter ("ラメ|Glitter", Float) = 0
        [HDR] _GlitterColor ("色|Color", Color) = (1,1,1,1)
        _GlitterMask ("マスク|Mask", 2D) = "white" {}
        [Enum(UV0,0,UV1,1)] _GlitterUV ("UV", Float) = 0
        _GlitterDensity ("密度|Density", Range(1, 1000)) = 150
        _GlitterSize ("粒の大きさ|Particle Size", Range(0.01, 1)) = 0.35
        _GlitterSensitivity ("鋭さ|Sensitivity", Range(1, 256)) = 48
        _GlitterSpeed ("瞬きの速さ|Twinkle Speed", Range(0, 20)) = 3
        _GlitterRandomColor ("ランダム色|Random Color", Range(0, 1)) = 0
        _GlitterEnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        _GlitterShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 1

        // ---------- Emission ----------
        [Toggle(_LUMI_EMISSION)] _UseEmission ("発光|Emission", Float) = 0
        [HDR] _EmissionColor ("色|Color", Color) = (1,1,1,1)
        _EmissionMap ("テクスチャ|Texture", 2D) = "white" {}
        _EmissionMask ("マスク|Mask", 2D) = "white" {}
        _EmissionScroll ("スクロール|Scroll", Vector) = (0,0,0,0)
        _EmissionBlink ("点滅 (強度/速さ/位相/矩形)|Blink (Strength/Speed/Phase/Square)", Vector) = (0,1,0,0)
        _EmissionMainStrength ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0
        _EmissionRainbow ("レインボー|Rainbow", Range(0, 1)) = 0
        _EmissionRainbowSpeed ("レインボーの速さ (周/秒)|Rainbow Speed (cycles/s)", Range(-5, 5)) = 0.5
        _EmissionRainbowScale ("レインボーの繰り返し|Rainbow Repeats", Range(0, 10)) = 1
        [Enum(Whole Surface,0,UV Horizontal,1,UV Vertical,2,Object Height,3,Rings from UV Centre,4)] _EmissionRainbowMode ("レインボーの流れ方|Rainbow Direction", Float) = 1
        [Toggle] _UseEmission2 ("発光2|Emission 2", Float) = 0
        [HDR] _Emission2Color ("色|Color", Color) = (1,1,1,1)
        _Emission2Map ("テクスチャ|Texture", 2D) = "white" {}
        _Emission2Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(UV0,0,UV1,1)] _Emission2UV ("UV", Float) = 0
        _Emission2Scroll ("スクロール|Scroll", Vector) = (0,0,0,0)
        _Emission2Blink ("点滅 (強度/速さ/位相/矩形)|Blink (Strength/Speed/Phase/Square)", Vector) = (0,1,0,0)
        _Emission2Rainbow ("レインボー|Rainbow", Range(0, 1)) = 0
        _Emission2RainbowSpeed ("レインボーの速さ (周/秒)|Rainbow Speed (cycles/s)", Range(-5, 5)) = 0.5
        _Emission2RainbowScale ("レインボーの繰り返し|Rainbow Repeats", Range(0, 10)) = 1
        [Enum(Whole Surface,0,UV Horizontal,1,UV Vertical,2,Object Height,3,Rings from UV Centre,4)] _Emission2RainbowMode ("レインボーの流れ方|Rainbow Direction", Float) = 1
        [ToggleUI] _Emission2AudioLink ("AudioLink", Float) = 0
        [Enum(Bass,0,LowMid,1,HighMid,2,Treble,3)] _Emission2ALBand ("帯域|Band", Float) = 0
        _Emission2ALStrength ("強度|Strength", Range(0, 4)) = 1
        _Emission2ALMin ("最小値|Minimum", Range(0, 1)) = 0
        _Emission2ALDelay ("UV.x 遅延|Delay by UV.x", Range(0, 1)) = 0
        [Toggle] _UseEmission3 ("発光3|Emission 3", Float) = 0
        [HDR] _Emission3Color ("色|Color", Color) = (1,1,1,1)
        _Emission3Map ("テクスチャ|Texture", 2D) = "white" {}
        _Emission3Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(UV0,0,UV1,1)] _Emission3UV ("UV", Float) = 0
        _Emission3Scroll ("スクロール|Scroll", Vector) = (0,0,0,0)
        _Emission3Blink ("点滅 (強度/速さ/位相/矩形)|Blink (Strength/Speed/Phase/Square)", Vector) = (0,1,0,0)
        _Emission3Rainbow ("レインボー|Rainbow", Range(0, 1)) = 0
        _Emission3RainbowSpeed ("レインボーの速さ (周/秒)|Rainbow Speed (cycles/s)", Range(-5, 5)) = 0.5
        _Emission3RainbowScale ("レインボーの繰り返し|Rainbow Repeats", Range(0, 10)) = 1
        [Enum(Whole Surface,0,UV Horizontal,1,UV Vertical,2,Object Height,3,Rings from UV Centre,4)] _Emission3RainbowMode ("レインボーの流れ方|Rainbow Direction", Float) = 1
        [ToggleUI] _Emission3AudioLink ("AudioLink", Float) = 0
        [Enum(Bass,0,LowMid,1,HighMid,2,Treble,3)] _Emission3ALBand ("帯域|Band", Float) = 0
        _Emission3ALStrength ("強度|Strength", Range(0, 4)) = 1
        _Emission3ALMin ("最小値|Minimum", Range(0, 1)) = 0
        _Emission3ALDelay ("UV.x 遅延|Delay by UV.x", Range(0, 1)) = 0
        [Toggle] _UseEmission4 ("発光4|Emission 4", Float) = 0
        [HDR] _Emission4Color ("色|Color", Color) = (1,1,1,1)
        _Emission4Map ("テクスチャ|Texture", 2D) = "white" {}
        _Emission4Mask ("マスク|Mask", 2D) = "white" {}
        [Enum(UV0,0,UV1,1)] _Emission4UV ("UV", Float) = 0
        _Emission4Scroll ("スクロール|Scroll", Vector) = (0,0,0,0)
        _Emission4Blink ("点滅 (強度/速さ/位相/矩形)|Blink (Strength/Speed/Phase/Square)", Vector) = (0,1,0,0)
        _Emission4Rainbow ("レインボー|Rainbow", Range(0, 1)) = 0
        _Emission4RainbowSpeed ("レインボーの速さ (周/秒)|Rainbow Speed (cycles/s)", Range(-5, 5)) = 0.5
        _Emission4RainbowScale ("レインボーの繰り返し|Rainbow Repeats", Range(0, 10)) = 1
        [Enum(Whole Surface,0,UV Horizontal,1,UV Vertical,2,Object Height,3,Rings from UV Centre,4)] _Emission4RainbowMode ("レインボーの流れ方|Rainbow Direction", Float) = 1
        [ToggleUI] _Emission4AudioLink ("AudioLink", Float) = 0
        [Enum(Bass,0,LowMid,1,HighMid,2,Treble,3)] _Emission4ALBand ("帯域|Band", Float) = 0
        _Emission4ALStrength ("強度|Strength", Range(0, 4)) = 1
        _Emission4ALMin ("最小値|Minimum", Range(0, 1)) = 0
        _Emission4ALDelay ("UV.x 遅延|Delay by UV.x", Range(0, 1)) = 0
        [Toggle(_LUMI_AUDIOLINK)] _UseAudioLink ("AudioLink", Float) = 0
        [Enum(Bass,0,LowMid,1,HighMid,2,Treble,3)] _AudioLinkBand ("帯域|Band", Float) = 0
        _AudioLinkStrength ("強度|Strength", Range(0, 4)) = 1
        _AudioLinkMin ("最小値|Minimum", Range(0, 1)) = 0
        _AudioLinkDelay ("UV.x 遅延|Delay by UV.x", Range(0, 1)) = 0

        // ---------- Dissolve / Fade ----------
        [Toggle(_LUMI_DISSOLVE)] _UseDissolve ("ディゾルブ|Dissolve", Float) = 0
        [Enum(Noise Texture,0,UV Vertical,1,Object Height,2)] _DissolveMode ("方式|Mode", Float) = 0
        _DissolveNoise ("ノイズ|Noise", 2D) = "white" {}
        _DissolveAmount ("進行度|Amount", Range(0, 1)) = 0
        _DissolveEdgeWidth ("縁の幅|Edge Width", Range(0, 0.5)) = 0.05
        [HDR] _DissolveEdgeColor ("縁の色|Edge Color", Color) = (2, 1, 0.3, 1)
        _DissolveHeightRange ("高さ範囲 (X=下 Y=上)|Height Range (X min, Y max)", Vector) = (0, 1.8, 0, 0)
        // ---- Flipbook
        [Toggle] _UseFlipbook ("フリップブック|Flipbook", Float) = 0
        _FlipbookTex ("コマのテクスチャ (シート)|Sprite Sheet", 2D) = "black" {}
        [HDR] _FlipbookColor ("色|Color", Color) = (1, 1, 1, 1)
        [Enum(Normal,0,Multiply,1,Add,2,Emission,3)] _FlipbookMode ("合成|Blend", Float) = 3
        [Enum(UV0,0,UV1,1)] _FlipbookUV ("UV", Float) = 0
        [Toggle] _FlipbookClamp ("範囲外は表示しない (デカール)|Clamp (decal)", Float) = 1
        _FlipbookGrid ("列, 行, コマ数, 速度 (fps)|Columns, Rows, Frames, FPS", Vector) = (4, 4, 16, 12)
        _FlipbookFrame ("手動のコマ番号 (-1 で自動)|Manual Frame (-1 = auto)", Float) = -1
        [Toggle] _FlipbookBlend ("コマ間をなめらかに|Blend Between Frames", Float) = 0
        // ---- Backface
        _BackfaceColor ("裏面の色 (A=強度)|Backface Color (A = amount)", Color) = (0.7, 0.7, 0.7, 0)
        _BackfaceTex ("裏面のテクスチャ|Backface Texture", 2D) = "white" {}
        _BackfaceMainBlend ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 1
        [ToggleUI] _BackfaceFlipNormal ("裏面のノーマルを反転|Flip Backface Normal", Float) = 1
        // ---- Fake refraction
        _RefractStrength ("屈折の強さ|Refraction", Range(0, 1)) = 0
        _RefractIOR ("屈折率|IOR", Range(1, 2.5)) = 1.5
        _RefractRoughness ("屈折のぼかし|Refraction Blur", Range(0, 1)) = 0
        _RefractDispersion ("分散 (虹色のにじみ)|Dispersion", Range(0, 0.2)) = 0
        _RefractColor ("屈折の色 (A=メインカラーの乗算)|Refraction Tint (A = multiply main)", Color) = (1, 1, 1, 1)
        // ---- Vertex wobble
        _WobbleStrength ("揺れの大きさ (cm)|Wobble Amount (cm)", Range(0, 10)) = 0
        _WobbleDir ("揺れる向き (ワールド)|Wobble Direction (world)", Vector) = (1, 0, 0.3, 0)
        _WobbleSpeed ("速さ|Speed", Range(0, 10)) = 2
        _WobbleFrequency ("波の細かさ (1/m)|Wave Frequency (1/m)", Range(0, 10)) = 2
        _WobbleGust ("不規則さ (風)|Irregularity (gust)", Range(0, 1)) = 0.5
        _WobbleMask ("揺れのマスク (R)|Wobble Mask (R)", 2D) = "white" {}
        [Toggle] _WobbleVertexColor ("頂点カラー R でマスク|Mask by Vertex Color R", Float) = 0
        // ---- Visibility
        [Enum(Always,0,Mirror Only,1,Hide in Mirror,2)] _MirrorVisibility ("ミラーでの表示|Mirror Visibility", Float) = 0
        [Enum(Always,0,Hide in Camera,1,Camera Only,2)] _CameraVisibility ("カメラでの表示|Camera Visibility", Float) = 0
        [Enum(UV0,0,UV1,1)] _UVTileUV ("UV タイルの UV|UV Tile Channel", Float) = 0
        [HideInInspector] _UVTileHide ("UV タイル非表示|Hidden UV Tiles", Float) = 0
        [Toggle(_LUMI_DISTFADE)] _UseDistanceFade ("距離フェード|Distance Fade", Float) = 0
        _DistanceFadeColor ("フェード色|Fade Color", Color) = (0,0,0,1)
        _DistanceFadeStart ("開始距離 (m)|Start (m)", Float) = 0.1
        _DistanceFadeEnd ("終了距離 (m)|End (m)", Float) = 0.01
        _DistanceFadeStrength ("強度|Strength", Range(0, 1)) = 0
        [Toggle] _NearDither ("カメラ接近でディザ透明|Near Camera Dither", Float) = 0
        _NearDitherDistance ("ディザ距離 (m)|Dither Distance (m)", Range(0, 1)) = 0.15

        // ---------- Post look ----------
        [Toggle(_LUMI_TONEMAP)] _UseTonemap ("トーンマップ / 色調補正|Tonemap / Grading", Float) = 0
        [Enum(None,0,Filmic Contrast,1,Filmic Soft,2,Natural,3,Natural Punchy,4,Neutral,5,Simple,6)] _TonemapMode ("トーンマップ|Tonemapper", Float) = 3
        _Exposure ("露出 (EV)|Exposure (EV)", Range(-4, 4)) = 0.6
        _Contrast ("コントラスト|Contrast", Range(0.5, 2)) = 1.05
        _Saturation ("彩度|Saturation", Range(0, 2)) = 1.1
        _Temperature ("色温度|Temperature", Range(-1, 1)) = 0
        _Tint ("色かぶり|Tint", Range(-1, 1)) = 0
        _Vibrance ("スマート バイブランス|Smart Vibrance", Range(-1, 1)) = 0.15
        _ShadowTint ("暗部の色バランス|Shadow Balance", Color) = (1, 1, 1, 1)
        _HighlightTint ("明部の色バランス|Highlight Balance", Color) = (1, 1, 1, 1)

        // ---------- v1.2: VRC Light Volumes ----------
        [Toggle(_LUMI_LIGHTVOLUMES)] _UseLightVolumes ("VRC ライトボリューム|VRC Light Volumes", Float) = 0
        _LVStrength ("強度|Strength", Range(0, 2)) = 1
        _LVSpecular ("スペキュラ|Specular", Range(0, 1)) = 0.5
        [Enum(Full,0,Dominant Direction (light),1,Off,2)] _LVSpecularMode ("スペキュラの方式|Specular Mode", Float) = 0
        _LVRegular ("ベイクされた環境光 (通常ボリューム)|Baked Light (regular volumes)", Range(0, 2)) = 1
        _LVAdditive ("追加ボリューム (動く光・照明演出)|Additive Volumes (dynamic light)", Range(0, 2)) = 1
        _LVPointLights ("ポイントライトボリューム|Point Light Volumes", Range(0, 2)) = 1
        _LVPointShading ("ポイントライトの陰影 (法線)|Point Light Normal Shading", Range(0, 3)) = 3
        _LVNormalOffset ("サンプル位置を法線方向にずらす (m)|Normal Offset Sampling (m)", Range(0, 0.2)) = 0.02
        _LVObjectCenter ("体全体で均一に (中心でサンプル)|Sample at Object Center", Range(0, 1)) = 0.3
        _LVSaturation ("ライトボリュームの彩度|Light Volume Saturation", Range(0, 2)) = 1
        _LVMinBrightness ("ライトボリューム内の最低の明るさ|Min Brightness in Volumes", Range(0, 0.5)) = 0
        [Toggle(_LUMI_LV_LITE)] _LVLite ("軽量モード (影・クッキー・エリアライト無効)|Lite (no shadows / cookies / area lights)", Float) = 0

        // ---------- v1.4: quality ----------
        _QToonAA ("影の境界のアンチエイリアス|Shadow Border Anti-aliasing", Range(0, 2)) = 1
        _QMicroShadow ("マイクロシャドウ (AO / ノーマルの凹凸に影)|Micro Shadows (AO / normal detail)", Range(0, 1)) = 0.5
        _QSpecClamp ("ハイライトのちらつき防止 (16=オフ)|Highlight Flicker Guard (16=off)", Range(1, 16)) = 6
        _QNormalFadeDist ("遠距離でノーマルを弱める距離 (m, 0=オフ)|Normal Fade Distance (m, 0=off)", Range(0, 30)) = 8
        _QMipBias ("テクスチャのシャープさ (ミップバイアス)|Texture Sharpness (mip bias)", Range(-1.5, 0)) = -0.25
        _QSharpen ("テクスチャのくっきり感 (ローカルコントラスト)|Texture Clarity (local contrast)", Range(0, 1)) = 0.25
        _QShadowComplement ("影に光の補色を入れる|Complementary Shadow Tint", Range(0, 1)) = 0.3
        _QShadowCoolColor ("白い光の時の影色|Shadow Tint Under White Light", Color) = (0.82, 0.86, 1, 1)
        _QDeband ("グラデーションの縞を消す (ディザ)|Remove Banding (dither)", Range(0, 2)) = 1

        // ---------- v1.4: hybrid (toon look + real material) ----------
        _HybridAmount ("トゥーン + リアル質感|Toon + Real Material", Range(0, 1)) = 0
        _HybridLitGradient ("明部のグラデーション|Lit Side Gradient", Range(0, 1)) = 0.4
        _HybridShadeVolume ("影の中の立体感 (環境光)|Volume in Shadow (ambient)", Range(0, 1)) = 0.6
        _HybridEnvTint ("環境光の色移り (明部)|Ambient Bounce on Lit Side", Range(0, 1)) = 0.3

        // ---------- v1.4: eye shadow guard ----------
        [Toggle] _UseEyeGuard ("目の内側に影を乗せない|Eye Shadow Guard", Float) = 0
        _EyeGuardMask ("マスク (R: 白=影なし)|Mask (R: white = no shadow)", 2D) = "white" {}
        _EyeGuardShadow ("落ち影を消す (まぶた・前髪)|Remove Cast Shadows (lids / bangs)", Range(0, 1)) = 1
        _EyeGuardShade ("陰影を消す (ライトの向き)|Remove Shading (light angle)", Range(0, 1)) = 1
        _EyeGuardAO ("AO を消す|Remove AO", Range(0, 1)) = 1
        _EyeParallax ("瞳の奥行き (視差)|Iris Depth (parallax)", Range(0, 0.1)) = 0
        _EyeParallaxMask ("瞳の奥行きマスク (R)|Iris Depth Mask (R)", 2D) = "white" {}
        _EyeGuardBrightness ("明るさ|Brightness", Range(0, 1.5)) = 1

        // ---------- v1.4: auto lighting ----------
        _AutoLight ("自動ライティング|Auto Lighting", Range(0, 1)) = 1
        _AutoKeyRatio ("キーライトの比率 (立体感)|Key Light Ratio (form)", Range(0, 1)) = 0.35
        _AutoProbeAmbient ("景色 (反射プローブ) から環境光を推定|Ambient from Scenery (probe)", Range(0, 1)) = 0.5
        _AutoPointLights ("周りのポイントライトを方向に反映|Point Lights Steer Direction", Range(0, 1)) = 0.6
        _AutoDefaultKey ("方向が無い時の既定キー (カメラ基準)|Default Key When Directionless (view)", Range(0, 1)) = 0.5
        _EnvColorStrength ("環境光の色の強さ|Ambient Color Strength", Range(0, 1)) = 0.55
        _LightColorStrength ("ライトの色の強さ|Light Color Strength", Range(0, 1)) = 0.85
        _DarkColorReduce ("暗所で環境色を抑える|Reduce Ambient Color in the Dark", Range(0, 1)) = 0.85
        _DarkColorThreshold ("暗所とみなす明るさ|Dark Threshold", Range(0.01, 1)) = 0.3

        // ---------- v1.2: lighting / toon extras ----------
        _AmbientShape ("環境光の立体感 (平坦なワールドを補正)|Ambient Shaping (fix flat worlds)", Range(0, 1)) = 0.6
        _EnvNormalize ("反射の明るさをワールドに合わせる|Normalize Reflections to World", Range(0, 1)) = 0.5
        _VirtualKeyLight ("仮想キーライト (平行光源なしのワールド)|Virtual Key Light (no directional light)", Range(0, 1)) = 1
        _SpecEnergyComp ("多重散乱の補正|Multi-scatter Compensation", Range(0, 1)) = 1
        [Enum(Auto Main and SH,0,Main Light Only,1,Fixed World,2,View Based,3,Object Local,4,Main or Camera Fallback,5,From Camera Position,6)] _LightDirMode ("ライト方向の方式|Light Direction Mode", Float) = 0
        _LightBoost ("暗所の明るさブースト|Dark Scene Boost", Range(0, 2)) = 0
        _LightSoftLimit ("上限をなめらかに|Soft Max Limit", Range(0, 1)) = 0
        [IntRange] _ShadowPosterize ("階調化 (0=オフ)|Posterize Steps (0=off)", Range(0, 8)) = 0
        _ShadowDither ("境界ディザ|Border Dither", Range(0, 1)) = 0
        _CastShadowOnly ("落ち影だけで影を作る|Cast Shadows Only", Range(0, 1)) = 0
        _FresnelAlpha ("フレネル透明 (+縁が濃い -縁が薄い)|Fresnel Alpha (+edge opaque, -edge clear)", Range(-1, 1)) = 0

        // ---------- v1.2: spherical normal ----------
        [Toggle(_LUMI_SPHERENORMAL)] _UseSphereNormal ("球面法線 (顔の影を滑らかに)|Spherical Normal (smooth face shading)", Float) = 0
        _SphereNormalStrength ("強度|Strength", Range(0, 1)) = 0.7
        _SphereCenter ("球の中心 (オブジェクト空間 m)|Sphere Center (object space, m)", Vector) = (0, 0, 0, 0)
        _SphereNormalVertical ("縦方向を平坦化|Flatten Vertical", Range(0, 1)) = 0

        // ---------- v1.2: offset rim ----------
        [Toggle(_LUMI_OFFSETRIM)] _UseOffsetRim ("オフセットリムライト|Offset Rim Light", Float) = 0
        [HDR] _OffsetRimColor ("色|Color", Color) = (1, 0.95, 0.9, 1)
        _OffsetRimStrength ("強度|Strength", Range(0, 4)) = 1
        [Enum(Normal,0,Light,1,Vector,2,Normal and Light,3)] _OffsetRimDirMode ("方向|Direction", Float) = 3
        _OffsetRimVector ("方向ベクトル (画面空間)|Direction Vector (screen space)", Vector) = (1, 1, 0, 0)
        _OffsetRimWidth ("幅 (cm)|Width (cm)", Range(0, 3)) = 0.5
        _OffsetRimMaxPx ("最大幅 (px)|Max Width (px)", Range(1, 64)) = 16
        _OffsetRimThreshold ("深度差のしきい値 (m)|Depth Threshold (m)", Range(0.005, 1)) = 0.05
        _OffsetRimSoftness ("柔らかさ|Softness", Range(0, 1)) = 0.5
        _OffsetRimFacing ("輪郭付近に制限|Limit to Silhouette", Range(0, 1)) = 0.3
        _OffsetRimLightInfluence ("ライト色の影響|Light Influence", Range(0, 1)) = 1
        _OffsetRimEnvInfluence ("環境光の影響|Ambient Influence", Range(0, 1)) = 0.3
        _OffsetRimShadowMask ("影で消す|Shadow Mask", Range(0, 1)) = 0.5
        _OffsetRimAlbedo ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0.3
        _OffsetRimEmission ("発光にする (ライトや影の影響を受けない)|Emissive (ignores lights and shadows)", Range(0, 1)) = 0
        _OffsetRimEmissionStrength ("発光の強さ|Emission Strength", Range(0, 10)) = 1
        _OffsetRimBlink ("点滅 (強度, 速さ, 位相, 矩形波)|Blink (strength, speed, phase, square)", Vector) = (0, 2, 0, 0)
        _OffsetRimHueSpeed ("色相の変化 (虹色, 回/秒)|Hue Cycle (rainbow, per second)", Range(0, 2)) = 0
        _OffsetRimEmissionAlbedo ("発光にメインカラーを乗算|Multiply Main Color (emission)", Range(0, 1)) = 0
        _OffsetRimFadeEnd ("フェード距離 (m)|Fade Distance (m)", Range(1, 50)) = 15

        // ---------- v1.2: procedural (no textures) ----------
        [Toggle(_LUMI_CURVATURE)] _UseCurvature ("曲率 (エッジ / くぼみ)|Curvature (Edge / Cavity)", Float) = 0
        [HDR] _CurvEdgeColor ("エッジ色 (A=強度)|Edge Color (A=strength)", Color) = (1, 1, 1, 0.3)
        _CurvCavityColor ("くぼみ色 (A=強度)|Cavity Color (A=strength)", Color) = (0.45, 0.32, 0.32, 0.5)
        _CurvScale ("感度|Sensitivity", Range(0.01, 10)) = 1
        _CurvSharpness ("鋭さ|Sharpness", Range(0, 1)) = 0.5
        [Toggle(_LUMI_IRIDESCENCE)] _UseIridescence ("薄膜干渉 (玉虫色)|Iridescence (Thin Film)", Float) = 0
        _IridStrength ("強度|Strength", Range(0, 2)) = 0.5
        _IridScale ("膜の厚み|Film Thickness", Range(0, 8)) = 2
        _IridOffset ("色相オフセット|Hue Offset", Range(0, 1)) = 0
        _IridSaturation ("彩度|Saturation", Range(0, 1)) = 0.8
        _IridFresnel ("フレネル|Fresnel Power", Range(0, 8)) = 2
        _IridSpecOnly ("反射にだけ乗せる|Reflections Only", Range(0, 1)) = 0.5
        [Toggle(_LUMI_BOUNCE)] _UseBounce ("照り返し (地面の反射光)|Bounce Light (Ground)", Float) = 0
        [HDR] _BounceColor ("色|Color", Color) = (0.55, 0.45, 0.4, 1)
        _BounceStrength ("強度|Strength", Range(0, 2)) = 0.4
        _BouncePower ("下向きの鋭さ|Downward Power", Range(0.5, 8)) = 2
        _BounceHeight ("届く高さ (m)|Reach Height (m)", Range(0.1, 3)) = 1.2
        _BounceLightInfluence ("ライトの明るさを反映|Scale by Light", Range(0, 1)) = 1
        _BounceGroundMatch ("環境の地面色を使う|Use Ambient Ground Color", Range(0, 1)) = 0.5
        [Toggle(_LUMI_FILLLIGHT)] _UseFillLight ("補助ライト (仮想)|Fill Light (virtual)", Float) = 0
        [HDR] _FillColor ("色|Color", Color) = (0.55, 0.6, 0.7, 1)
        _FillDir ("方向 (ビュー空間)|Direction (view space)", Vector) = (-0.6, 0.3, 0.7, 0)
        _FillStrength ("強度|Strength", Range(0, 2)) = 0.3
        _FillBorder ("境界|Border", Range(0, 1)) = 0.5
        _FillBlur ("ぼかし|Blur", Range(0, 1)) = 0.4
        _FillShadowOnly ("影側だけに当てる|Shadow Side Only", Range(0, 1)) = 0.7
        [Toggle(_LUMI_GRADIENT)] _UseGradient ("高さグラデーション / 色相シフト|Height Gradient / Hue Shift", Float) = 0
        _GradTop ("上の色|Top Color", Color) = (1, 1, 1, 1)
        _GradBottom ("下の色|Bottom Color", Color) = (0.85, 0.75, 0.95, 1)
        [Enum(Object Height,0,World Height,1,UV V,2)] _GradSpace ("基準|Space", Float) = 0
        _GradRange ("範囲 (X=下 Y=上)|Range (X bottom, Y top)", Vector) = (0, 1.6, 0, 0)
        [Enum(Normal,0,Add,1,Screen,2,Multiply,3)] _GradBlend ("合成モード|Blend Mode", Float) = 3
        _GradStrength ("強度|Strength", Range(0, 1)) = 1
        _ViewHueShift ("視線で色相シフト|View Hue Shift", Range(-1, 1)) = 0
        [Toggle(_LUMI_HATCH)] _UseHatch ("ハッチング (線影)|Hatching (Ink Lines)", Float) = 0
        _HatchColor ("線の色 (A=強度)|Line Color (A=strength)", Color) = (0.2, 0.15, 0.25, 0.6)
        [Enum(Screen,0,UV,1)] _HatchSpace ("座標|Space", Float) = 0
        _HatchDensity ("密度|Density", Range(10, 600)) = 120
        _HatchAngle ("角度|Angle", Range(0, 180)) = 45
        _HatchWidth ("線の太さ|Line Width", Range(0, 1)) = 0.4
        _HatchThreshold ("描き始める暗さ|Start Darkness", Range(0, 1)) = 0.5
        _HatchCross ("クロスハッチ|Cross Hatch", Range(0, 1)) = 0.5
        _HatchNoise ("線の揺らぎ|Line Jitter", Range(0, 1)) = 0.3
        [Toggle(_LUMI_ANGELRING)] _UseAngelRing ("天使の輪 (テクスチャ不要)|Angel Ring (procedural)", Float) = 0
        [HDR] _AngelColor ("色 (A=強度)|Color (A=strength)", Color) = (1, 1, 1, 0.6)
        _AngelHeight ("位置|Position", Range(-1, 1)) = 0.35
        _AngelWidth ("幅|Width", Range(0.01, 0.5)) = 0.08
        _AngelBlur ("ぼかし|Blur", Range(0, 1)) = 0.3
        _AngelBreakup ("途切れ|Breakup", Range(0, 1)) = 0.5
        _AngelFrequency ("途切れの細かさ (UV.x)|Breakup Frequency (UV.x)", Range(1, 200)) = 60
        _AngelLightInfluence ("ライト色の影響|Light Influence", Range(0, 1)) = 1
        [Toggle(_LUMI_HOLOGRAM)] _UseHologram ("ホログラム / スキャンライン|Hologram / Scanlines", Float) = 0
        [HDR] _HoloColor ("色|Color", Color) = (0.3, 0.8, 1, 1)
        _HoloStrength ("強度|Strength", Range(0, 1)) = 0.5
        _HoloLineDensity ("線の密度|Line Density", Range(1, 500)) = 80
        _HoloLineSpeed ("線の速さ|Line Speed", Range(-10, 10)) = 1
        _HoloFresnel ("フレネル|Fresnel Power", Range(0, 8)) = 2
        _HoloFlicker ("ちらつき|Flicker", Range(0, 1)) = 0.2
        _HoloAlpha ("透明度への影響|Alpha Influence", Range(0, 1)) = 0
        _SkyTopColor ("空の色 (上)|Sky Top", Color) = (0.45, 0.6, 0.85, 1)
        _SkyHorizonColor ("空の色 (地平線)|Sky Horizon", Color) = (0.9, 0.9, 0.95, 1)
        _SkyGroundColor ("地面の色|Ground", Color) = (0.35, 0.3, 0.28, 1)

        // ---------- v1.2: world adaptation / debug ----------
        _WorldAdapt ("ワールドの明るさに順応|World Brightness Adaptation", Range(0, 1)) = 0
        _WorldAdaptTarget ("目標の明るさ|Target Brightness", Range(0.05, 2)) = 0.8
        _WorldAdaptRange ("補正の上限 (倍)|Max Correction (x)", Range(1, 8)) = 3
        [IntRange] _DebugView ("デバッグ表示|Debug View", Range(0, 9)) = 0

        // ---------- tessellation (used by the Tessellation shader variants only) ----------
        _TessEdgeLength ("分割の細かさ (画面上の辺の長さ px)|Edge Length (pixels on screen)", Range(2, 50)) = 12
        _TessMax ("最大分割数|Max Subdivision", Range(1, 32)) = 8
        _TessPhong ("丸み (Phong)|Smoothing (Phong)", Range(0, 1)) = 0.5
        _TessFadeStart ("分割を減らし始める距離 (m)|Fade Start (m)", Range(0, 20)) = 2
        _TessFadeEnd ("分割しなくなる距離 (m)|Fade End (m)", Range(0, 50)) = 8
        _TessMask ("テッセレーションマスク (R)|Tessellation Mask (R)", 2D) = "white" {}

        // ---------- v1.2: double outline ----------
        _Outline2Width ("2nd 幅 (cm)|2nd Width (cm)", Range(0, 2)) = 0
        [HDR] _Outline2Color ("2nd 色|2nd Color", Color) = (1, 1, 1, 1)
        _Outline2MainBlend ("2nd メインカラーの乗算|2nd Multiply Main Color", Range(0, 1)) = 0
        _Outline2EnableLighting ("2nd ライトの色を反映|2nd Apply Lighting", Range(0, 1)) = 1
        _Outline2ZBias ("2nd Z オフセット (cm)|2nd Z Bias (cm)", Range(-40, 40)) = 0

        // ---------- v1.3: richness (avoid a flat matte look) ----------
        _RichShadowSaturation ("影の彩度アップ|Shadow Saturation", Range(0, 1)) = 0.35
        _RichShadowHue ("影の色相シフト|Shadow Hue Shift", Range(-0.5, 0.5)) = 0
        _RichColorDepth ("色の深み (暗部で固有色を濃く)|Color Depth (richer dark colors)", Range(0, 1)) = 0.25
        _RichTerminatorColor ("明暗境界の色 (A=強度)|Terminator Color (A=strength)", Color) = (1, 0.45, 0.35, 0.25)
        _RichTerminatorWidth ("明暗境界の幅|Terminator Width", Range(0.01, 1)) = 0.25
        _RichWrap ("光の回り込み|Light Wrap", Range(0, 1)) = 0.2
        _RichAmbientRim ("環境光のフチ光|Ambient Rim", Range(0, 1)) = 0.25
        [Enum(Fresnel,0,Toon (silhouette only),1)] _RichAmbientRimMode ("フチ光の方式 (トゥーン = 輪郭だけ)|Ambient Rim Mode (toon = silhouette only)", Float) = 0
        _RichSoftSpec ("柔らかい光沢 (2層目)|Soft Gloss (2nd lobe)", Range(0, 1)) = 0.2
        _RichSoftSpecRoughness ("柔らかい光沢の粗さ|Soft Gloss Roughness", Range(0.2, 1)) = 0.6
        _RichMicroContrast ("ディテールの陰影強調|Detail Contrast", Range(0, 1)) = 0.2
        _RichGloss ("フチの艶 (フレネル強調)|Edge Gloss (Fresnel boost)", Range(0, 1)) = 0.3

        // ---------- v1.3: character control ----------
        _AmbientFlatten ("環境光を均一化|Flatten Ambient", Range(0, 1)) = 0
        [Toggle(_LUMI_DEPTHSHADOW)] _UseDepthShadow ("深度シャドウ (髪の落ち影)|Depth Texture Shadow (hair on face)", Float) = 0
        _DepthShadowWidth ("ずらし幅 (cm)|Offset Width (cm)", Range(0, 5)) = 0.8
        _DepthShadowThreshold ("深度差のしきい値 (m)|Depth Threshold (m)", Range(0.001, 0.2)) = 0.015
        _DepthShadowSoftness ("柔らかさ|Softness", Range(0, 1)) = 0.5
        _DepthShadowStrength ("強度|Strength", Range(0, 1)) = 1
        _DepthShadowMaxPx ("最大幅 (px)|Max Width (px)", Range(1, 64)) = 32
        _PerspectiveRemoval ("パース除去 (顔の歪み軽減)|Perspective Removal", Range(0, 1)) = 0
        _PerspectiveCenter ("パース除去の中心 (オブジェクト空間 m)|Removal Center (object space, m)", Vector) = (0, 0, 0, 0)
        _PerspectiveRange ("効果が消える距離 (m)|Fade Out Distance (m)", Range(0.1, 10)) = 2
        _CharTint ("キャラ全体の色|Character Tint", Color) = (1, 1, 1, 1)
        _CharBrightness ("キャラ全体の明るさ|Character Brightness", Range(0, 3)) = 1
        _CharDesaturate ("キャラ全体の彩度を下げる|Character Desaturate", Range(0, 1)) = 0
        [HDR] _CharLerpColor ("キャラ全体を塗る色 (A=量)|Character Fill Color (A=amount)", Color) = (1, 1, 1, 0)
        _OutlineFOVCompensate ("FOV で太さを補正|FOV Compensation", Range(0, 1)) = 0.5

        // ---------- v1.3: detail parameters ----------
        _SHSoftness ("環境光の方向性 (トゥーン)|Ambient Directionality (toon)", Range(0, 1)) = 0.666
        _AmbientShapeContrast ("立体感の強さ|Shaping Contrast", Range(0, 1)) = 0.45
        _AmbientSkyTint ("合成した空側の色味|Synth Sky Tint", Color) = (0.97, 1, 1.04, 1)
        _AmbientGroundTint ("合成した地面側の色味|Synth Ground Tint", Color) = (1.04, 0.98, 0.93, 1)
        _EnvNormalizeRange ("反射補正の最大倍率|Reflection Match Range (x)", Range(1, 8)) = 3
        _SynthReflHighlight ("合成反射のハイライト|Synth Reflection Highlight", Range(0, 2)) = 0.5
        _SynthReflBlur ("合成反射のぼけ|Synth Reflection Blur", Range(0, 1)) = 0.6
        _ToonSpecBorder ("トゥーンハイライトの境界|Toon Highlight Border", Range(0, 1)) = 0.5
        _ToonSpecBlur ("トゥーンハイライトのぼかし|Toon Highlight Blur", Range(0, 0.5)) = 0.06
        _SpecOcclusionStrength ("スペキュラ遮蔽|Specular Occlusion", Range(0, 1)) = 1
        _HorizonOcclusionStrength ("水平線遮蔽|Horizon Occlusion", Range(0, 1)) = 1
        _IridSpecBoost ("反射の色の強さ|Reflection Tint Boost", Range(0.5, 3)) = 1.5
        _Hatch2ndThreshold ("クロスの開始位置|Cross Start", Range(0, 1)) = 0.5
        _HoloFlickerSpeed ("ちらつきの速さ|Flicker Speed", Range(0, 100)) = 37
        _AngelShadowMask ("影で弱める|Shadow Mask", Range(0, 1)) = 0.6
        _CurvLightInfluence ("ライト色の影響|Light Influence", Range(0, 1)) = 1
        _BounceGroundIntensity ("地面色の明るさ|Ground Color Intensity", Range(0, 4)) = 2
        _OutlineFixDistance ("固定幅の基準距離 (m)|Fixed Width Distance (m)", Range(0.1, 10)) = 2
        _OffsetRimFallback ("深度が無い時のフレネル代用|Fresnel Fallback (no depth)", Range(0, 1)) = 1

        // ---------- v1.3: ink line (brush taper) / FPS mode ----------
        [Toggle(_LUMI_INKLINE)] _UseInkLine ("入り抜き輪郭線|Ink Line (brush taper)", Float) = 0
        _InkStrength ("入り抜きの強さ|Taper Strength", Range(0, 1)) = 1
        _InkWidth ("太さ倍率|Width Multiplier", Range(0, 4)) = 1.5
        _InkAngle ("ペンの角度|Pen Angle", Range(0, 180)) = 45
        _InkGap ("線が途切れる範囲|Gap", Range(0, 0.95)) = 0.15
        _InkTaper ("抜きの長さ|Taper Length", Range(0.2, 4)) = 1.5
        _InkMin ("最小の太さ|Minimum Width", Range(0, 1)) = 0
        _InkUnder ("反対側を太くする量|Thicker Opposite Side", Range(0, 1)) = 0.3
        _InkUnderDir ("細くする側の方向 (ワールド)|Thin Side Direction (world)", Vector) = (0, 1, 0, 0)
        _InkNoise ("線のムラ|Width Noise", Range(0, 1)) = 0
        _InkNoiseFreq ("ムラの細かさ|Noise Frequency", Range(1, 60)) = 15
        [Toggle(_LUMI_FPSMODE)] _UseFPSMode ("FPS モード (コマ落ち揺らぎ)|FPS Mode (hand drawn boil)", Float) = 0
        [Enum(Outline Only,0,Whole Mesh,1)] _FPSTarget ("対象|Target", Float) = 0
        _FPSRate ("コマ数 (FPS)|Frame Rate (FPS)", Range(1, 60)) = 12
        _FPSAmp ("揺らぎの大きさ (cm)|Amplitude (cm)", Range(0, 3)) = 0.3
        _FPSFreq ("揺らぎの細かさ (1m あたり)|Frequency (per m)", Range(1, 60)) = 12
        _FPSNormal ("法線方向の割合|Along Normal", Range(0, 1)) = 0.5
        _FPSSnap ("頂点スナップ間隔 (cm)|Vertex Snap (cm)", Range(0, 5)) = 0
        _FPSWidthJitter ("輪郭線の太さの揺らぎ|Outline Width Jitter", Range(0, 1)) = 0.3

        // ---------- Outline (used by MitToon/MitToon Outline) ----------
        _OutlineWidth ("幅 (cm)|Width (cm)", Range(0, 2)) = 0.08
        _OutlineColor ("色|Color", Color) = (0.25, 0.18, 0.2, 1)
        _OutlineTex ("テクスチャ|Texture", 2D) = "white" {}
        _OutlineWidthMask ("幅マスク (R)|Width Mask (R)", 2D) = "white" {}
        _OutlineVertexColorWidth ("頂点カラー A で幅|Width by Vertex Color A", Range(0, 1)) = 0
        _OutlineFixWidth ("画面上の太さを固定|Fixed Screen Width", Range(0, 1)) = 0.5
        _OutlineZBias ("Z オフセット (cm)|Z Bias (cm)", Range(-5, 5)) = 0
        _OutlineMainBlend ("メインカラーの乗算|Multiply Main Color", Range(0, 1)) = 0.8
        _OutlineEnableLighting ("ライトの色を反映|Apply Lighting", Range(0, 1)) = 1
        [Enum(Normal,0,Tangent,1,Vertex Color (baked smooth),2)] _OutlineNormalSource ("法線のソース|Normal Source", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "VRCFallback" = "Toon" }

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

        //LUMI_OUTLINE_PASS

        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }
            Cull [_Cull]
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Blend [_SrcBlend] [_DstBlend], One OneMinusSrcAlpha
            AlphaToMask [_AlphaToMask]
            Offset [_OffsetFactor], [_OffsetUnits]

            CGPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment fragBase
            #pragma multi_compile_fwdbase nolightmap nodynlightmap nodirlightmap
            #pragma multi_compile_vertex _ FOG_LINEAR FOG_EXP FOG_EXP2
            #pragma skip_variants LIGHTMAP_ON DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK DIRLIGHTMAP_COMBINED
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _LUMI_LAYER
            #pragma shader_feature_local _LUMI_NORMALMAP
            #pragma shader_feature_local _LUMI_DETAIL
            #pragma shader_feature_local _LUMI_PARALLAX
            #pragma shader_feature_local _LUMI_SSAO
            #pragma shader_feature_local _LUMI_SOFTSHADOW
            #pragma shader_feature_local _LUMI_CONTACTSHADOW
            #pragma shader_feature_local _LUMI_SSS
            #pragma shader_feature_local _LUMI_FACESDF
            #pragma shader_feature_local _LUMI_COMPAT
            #pragma shader_feature_local _LUMI_BACKLIGHT
            #pragma shader_feature_local _LUMI_ANISO
            #pragma shader_feature_local _LUMI_SHEEN
            #pragma shader_feature_local _LUMI_CLEARCOAT
            #pragma shader_feature_local _LUMI_RIM
            #pragma shader_feature_local _LUMI_MATCAP
            #pragma shader_feature_local _LUMI_GLITTER
            #pragma shader_feature_local _LUMI_EMISSION
            #pragma shader_feature_local _LUMI_AUDIOLINK
            #pragma shader_feature_local _LUMI_DISSOLVE
            #pragma shader_feature_local _LUMI_DISTFADE
            #pragma shader_feature_local _LUMI_TONEMAP
            #pragma shader_feature_local _LUMI_LIGHTVOLUMES
            #pragma shader_feature_local _LUMI_LV_LITE
            #pragma shader_feature_local _LUMI_SPHERENORMAL
            #pragma shader_feature_local _LUMI_OFFSETRIM
            #pragma shader_feature_local _LUMI_CURVATURE
            #pragma shader_feature_local _LUMI_IRIDESCENCE
            #pragma shader_feature_local _LUMI_BOUNCE
            #pragma shader_feature_local _LUMI_FILLLIGHT
            #pragma shader_feature_local _LUMI_GRADIENT
            #pragma shader_feature_local _LUMI_HATCH
            #pragma shader_feature_local _LUMI_ANGELRING
            #pragma shader_feature_local _LUMI_HOLOGRAM
            #pragma shader_feature_local _LUMI_DEPTHSHADOW
            #pragma shader_feature_local _LUMI_FPSMODE
            #include "Include/MitToonPassBIRP.hlsl"
            ENDCG
        }

        Pass
        {
            Name "FORWARD_DELTA"
            Tags { "LightMode" = "ForwardAdd" }
            Cull [_Cull]
            ZWrite Off
            ZTest LEqual
            Blend [_SrcBlendAdd] [_DstBlendAdd], Zero One
            BlendOp [_BlendOpAdd], Add
            AlphaToMask [_AlphaToMask]
            Offset [_OffsetFactor], [_OffsetUnits]

            CGPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment fragAdd
            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_vertex _ FOG_LINEAR FOG_EXP FOG_EXP2
            #pragma skip_variants LIGHTMAP_ON DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK DIRLIGHTMAP_COMBINED
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _LUMI_LAYER
            #pragma shader_feature_local _LUMI_NORMALMAP
            #pragma shader_feature_local _LUMI_DETAIL
            #pragma shader_feature_local _LUMI_PARALLAX
            #pragma shader_feature_local _LUMI_SSS
            #pragma shader_feature_local _LUMI_FACESDF
            #pragma shader_feature_local _LUMI_COMPAT
            #pragma shader_feature_local _LUMI_BACKLIGHT
            #pragma shader_feature_local _LUMI_ANISO
            #pragma shader_feature_local _LUMI_SHEEN
            #pragma shader_feature_local _LUMI_CLEARCOAT
            #pragma shader_feature_local _LUMI_DISSOLVE
            #pragma shader_feature_local _LUMI_DISTFADE
            #pragma shader_feature_local _LUMI_TONEMAP
            #pragma shader_feature_local _LUMI_SPHERENORMAL
            #pragma shader_feature_local _LUMI_GRADIENT
            #pragma shader_feature_local _LUMI_FPSMODE
            #include "Include/MitToonPassBIRP.hlsl"
            ENDCG
        }

        Pass
        {
            Name "SHADOWCASTER"
            Tags { "LightMode" = "ShadowCaster" }
            Cull [_Cull]
            ZWrite On
            ZTest LEqual

            CGPROGRAM
            #pragma target 4.5
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local _LUMI_DISSOLVE
            #pragma shader_feature_local _LUMI_FPSMODE
            #include "Include/MitToonPassBIRP.hlsl"
            ENDCG
        }
    }
    Fallback "Standard"
    CustomEditor "MitToon.Editor.MitToonShaderGUI"
}
