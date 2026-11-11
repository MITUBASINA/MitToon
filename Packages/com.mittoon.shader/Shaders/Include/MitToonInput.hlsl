// MitToon Shader - material inputs. Uses UnityPerMaterial so that the same file works for URP (SRP Batcher).
#ifndef MITTOON_INPUT_INCLUDED
#define MITTOON_INPUT_INCLUDED

CBUFFER_START(UnityPerMaterial)
    // Main
    float4 _Color;
    float4 _MainTex_ST;
    float4 _MainTexHSVG;
    float4 _MainScroll;
    float  _AlphaMaskMode;
    float  _AlphaMaskValue;
    float  _Cutoff;
    float  _AlphaToMask;
    float  _UseVertexColor;
    float  _RenderMode;
    // Layers
    float  _UseMain2, _Main2Blend, _Main2UV, _Main2Decal;
    float4 _Main2Color, _Main2Tex_ST, _Main2Scroll;
    float  _UseMain3, _Main3Blend, _Main3UV, _Main3Decal;
    float4 _Main3Color, _Main3Tex_ST, _Main3Scroll;
    // Normal / detail / parallax
    float  _BumpScale, _UseBump2, _Bump2Scale;
    float4 _Bump2Map_ST;
    float4 _DetailAlbedoMap_ST;
    float  _DetailAlbedoScale, _DetailNormalScale, _DetailUV;
    float  _Parallax, _ParallaxSteps, _ParallaxMode;
    // PBR
    float  _ToonAmount;
    float  _Metallic, _Smoothness, _PBRMapMode, _SmoothnessIsRoughness, _OcclusionStrength;
    float  _Reflectance, _SpecularStrength, _SpecularToony, _EnvReflStrength;
    float4 _SpecularColor;
    float  _ReflCubeMode, _ReflCubeIntensity;
    float4 _ReflCube_HDR;
    float  _SpecAA, _SpecAAThreshold, _EnvLightStrength;
    // Toon shadow
    float  _ShadowStrength, _ShadowBorder, _ShadowBlur;
    float4 _ShadowColor, _Shadow2ndColor;
    float  _Shadow2ndBorder, _Shadow2ndBlur;
    float4 _ShadowBorderColor;
    float  _ShadowBorderRange, _ShadowMainStrength, _ShadowEnvStrength, _ShadowAOShift, _ReceiveShadowStrength, _CastShadowSoftness, _ReceiveCastShadow;
    float4 _Shadow3rdColor, _CompatAOShift, _ShadowAOShift2;
    float  _Shadow3rdBorder, _Shadow3rdBlur, _ShadowNormalStrength, _Shadow2ndNormalStrength, _Shadow3rdNormalStrength;
    float  _ShadowReceive, _Shadow2ndReceive, _Shadow3rdReceive, _ShadowPostAO, _BackfaceForceShadow;
    float4 _RimIndirColor, _RimShadeColor, _MatCapTex_ST, _MatCap2Tex_ST;
    float  _RimDirRange, _RimIndirRange, _RimIndirBorder, _RimIndirBlur, _UseRimShade, _RimShadeNormalStrength, _RimShadeBorder, _RimShadeBlur, _RimShadeFresnelPower;
    float  _BacklightReceiveShadow, _BacklightBackfaceMask, _MatCapBackfaceMask, _UseBacklight, _UseMatCap;
    float  _ShadowRampMode;
    // Lighting
    float  _LightMinLimit, _LightMaxLimit, _MonochromeLighting, _AsUnlit, _VertexLightStrength, _AddLightStrength;
    float4 _LightDirOverride;
    float  _TessEdgeLength, _TessMax, _TessPhong, _TessFadeStart, _TessFadeEnd;
    float  _LightColorMode, _LightMapMode, _UnlitIntensity, _LightViewYaw, _LightViewPitch;
    float  _AutoShadowColor, _AutoShadowHue, _AutoShadowDarkness, _QLodDistance;
    float  _AddLightSoftness, _AddLightCastShadow;
    float  _AddLightMaxLimit, _AddLightPassthrough, _AddLightMonochrome, _AddLightSmoothFalloff, _AddLightIgnoreDirectional, _LightDirKeepUp;
    float  _UseFlipbook, _FlipbookMode, _FlipbookUV, _FlipbookClamp, _FlipbookFrame, _FlipbookBlend;
    float4 _FlipbookTex_ST, _FlipbookColor, _FlipbookGrid;
    float4 _BackfaceColor; float _BackfaceMainBlend, _BackfaceFlipNormal;
    float  _RefractStrength, _RefractIOR, _RefractRoughness, _RefractDispersion; float4 _RefractColor;
    float  _WobbleStrength, _WobbleSpeed, _WobbleFrequency, _WobbleGust, _WobbleVertexColor; float4 _WobbleDir;
    float  _MirrorVisibility, _CameraVisibility, _UVTileUV, _UVTileHide;
    float  _ShadowCasterBias, _ShadowCasterNormalBias, _ShadowCasterBiasView;
    // Screen space
    float  _SSAORadius, _SSAOStrength, _SSAOSamples, _SSAOBias, _SSAODirect, _SSAOMaxDistance;
    float  _SSAOMethod, _SSAOSoftness, _SSAOThickness, _SSAOFalloff, _SSAODistanceScale, _SSAOFarWeight, _SSAOFarScale, _SSAONearWeight, _SSAOMidWeight, _SSAOMidScale, _SSAOViewFix, _SSAOAlphaInfluence;
    float  _SSAOPower, _SSAOContrast, _SSAOMin, _SSAOAmbient, _SSAOSpecular, _SSAOJitter, _SSAOAlbedoTint, _SSAONormalStrength;
    float  _SSAOFadeStart, _SSAOMaskStrength;
    float4 _SSAOColor;
    float  _SoftShadowRadius, _SoftShadowSamples, _ShadowSmoothness;
    float  _ShadowTerminatorFade;
    float  _ContactShadowLength, _ContactShadowThickness, _ContactShadowStrength, _ContactShadowSteps;
    float  _ContactShadowBias, _ContactShadowMinDelta, _ContactShadowSoftness, _ContactShadowEndFade, _ContactShadowJitter;
    float  _ContactShadowDistanceScale, _ContactShadowMaxDistance, _ContactShadowMaskStrength;
    // SSS / backlight
    float4 _SSSColor;
    float  _SSSStrength, _SSSWrap, _SSSCurvature, _TransmissionStrength, _TransmissionPower, _TransmissionDistortion;
    float4 _BacklightColor;
    float  _BacklightBorder, _BacklightBlur, _BacklightDirectivity, _BacklightViewStrength, _BacklightNormalStrength, _BacklightMainStrength;
    // Hair
    float  _AnisoMode, _AnisoTangent, _Anisotropy, _AnisoShiftNoise, _AnisoAngle, _AnisoStrength, _AnisoBlend, _Aniso2Albedo, _AnisoToony, _AnisoToonBlur;
    float4 _AnisoCenter;
    float4 _AnisoShiftMap_ST;
    float4 _Aniso1Color, _Aniso2Color;
    float  _Aniso1Shift, _Aniso1Exponent, _Aniso2Shift, _Aniso2Exponent;
    // Sheen / coat
    float4 _SheenColor;
    float  _SheenRoughness, _SheenFuzz, _SheenFuzzPower;
    float  _ClearCoat, _ClearCoatSmoothness, _ClearCoatUseNormal, _ClearCoatF0, _ClearCoatReflStrength, _ClearCoatNormalScale, _ClearCoatToony, _ClearCoatToonBlur;
    float4 _ClearCoatSpecColor, _ClearCoatNormalMap_ST;
    // Rim
    float4 _RimColor;
    float  _RimBorder, _RimBlur, _RimFresnelPower, _RimLightDir, _RimShadowMask, _RimMainStrength, _RimNormalStrength, _RimEnableLighting, _RimBackfaceMask;
    float  _UseRim, _RimBlendMode, _RimLitSideOnly, _RimLitSideBlur;
    float4 _Rim2Color;
    float  _UseRim2, _Rim2Border, _Rim2Blur, _Rim2FresnelPower, _Rim2LightDir, _Rim2ShadowMask, _Rim2MainStrength, _Rim2NormalStrength, _Rim2EnableLighting, _Rim2BackfaceMask;
    float  _Rim2BlendMode, _Rim2LitSideOnly, _Rim2LitSideBlur;
    float4 _Rim3Color;
    float  _UseRim3, _Rim3Border, _Rim3Blur, _Rim3FresnelPower, _Rim3LightDir, _Rim3ShadowMask, _Rim3MainStrength, _Rim3NormalStrength, _Rim3EnableLighting, _Rim3BackfaceMask;
    float  _Rim3BlendMode, _Rim3LitSideOnly, _Rim3LitSideBlur;
    // MatCap
    float4 _MatCapColor;
    float  _MatCapBlend, _MatCapLod, _MatCapEnableLighting, _MatCapShadowMask, _MatCapMainStrength, _MatCapNormalStrength;
    float  _MatCapPerspective, _MatCapZRotCancel, _UseMatCapBump, _MatCapBumpScale;
    float  _UseMatCap2;
    float4 _MatCap2Color;
    float  _MatCap2Blend, _MatCap2Lod, _MatCap2EnableLighting, _MatCap2ShadowMask, _MatCap2NormalStrength;
    // Glitter
    float4 _GlitterColor;
    float  _GlitterDensity, _GlitterSize, _GlitterSensitivity, _GlitterSpeed, _GlitterRandomColor, _GlitterEnableLighting, _GlitterShadowMask, _GlitterUV;
    // Emission
    float4 _EmissionColor, _EmissionMap_ST, _EmissionScroll, _EmissionBlink;
    float  _EmissionMainStrength;
    float  _UseEmission2, _Emission2UV;
    float4 _Emission2Color, _Emission2Map_ST, _Emission2Scroll, _Emission2Blink;
    float  _UseEmission3, _Emission3UV;
    float4 _Emission3Color, _Emission3Map_ST, _Emission3Scroll, _Emission3Blink;
    float  _UseEmission4, _Emission4UV;
    float4 _Emission4Color, _Emission4Map_ST, _Emission4Scroll, _Emission4Blink;
    float  _Emission4Rainbow, _Emission4RainbowSpeed, _Emission4RainbowScale, _Emission4RainbowMode;
    float  _Emission4AudioLink, _Emission4ALBand, _Emission4ALStrength, _Emission4ALMin, _Emission4ALDelay;
    float  _EmissionRainbow, _EmissionRainbowSpeed, _EmissionRainbowScale, _EmissionRainbowMode;
    float  _Emission2Rainbow, _Emission2RainbowSpeed, _Emission2RainbowScale, _Emission2RainbowMode;
    float  _Emission3Rainbow, _Emission3RainbowSpeed, _Emission3RainbowScale, _Emission3RainbowMode;
    float  _AudioLinkBand, _AudioLinkStrength, _AudioLinkMin, _AudioLinkDelay;
    float  _UseAudioLink, _UseEmission;
    float  _Emission2AudioLink, _Emission2ALBand, _Emission2ALStrength, _Emission2ALMin, _Emission2ALDelay;
    float  _Emission3AudioLink, _Emission3ALBand, _Emission3ALStrength, _Emission3ALMin, _Emission3ALDelay;
    // Dissolve / fade
    float4 _DissolveNoise_ST;
    float  _DissolveMode, _DissolveAmount, _DissolveEdgeWidth;
    float4 _DissolveEdgeColor, _DissolveHeightRange;
    float4 _DistanceFadeColor;
    float  _DistanceFadeStart, _DistanceFadeEnd, _DistanceFadeStrength, _NearDither, _NearDitherDistance;
    // Grading
    float  _TonemapMode, _Exposure, _Contrast, _Saturation, _Temperature, _Tint;
    // v1.1: grading / wetness / ILM / face SDF / depth rim / outline normals
    float  _Vibrance;
    float4 _ShadowTint, _HighlightTint;
    float  _Wetness;
    float4 _ClearCoatColor;
    float  _UseILM, _ShadowRampRow;
    float  _FaceSDFBlur, _FaceSDFFlip;
    float4 _FaceForward, _FaceUp;
    float  _RimMode, _RimDepthWidth, _RimDepthThreshold;
    float  _OutlineNormalSource;
    // v1.2: light volumes / lighting extras
    float  _LVStrength, _LVSpecular, _LVSpecularMode, _LVRegular, _LVAdditive, _LVPointLights, _LVPointShading;
    float  _LVNormalOffset, _LVObjectCenter, _LVSaturation, _LVMinBrightness;
    float  _AmbientShape, _EnvNormalize, _VirtualKeyLight, _SpecEnergyComp;
    // v1.4: quality
    float  _QToonAA, _QMicroShadow, _QSpecClamp, _QNormalFadeDist, _QMipBias, _QDeband;
    float  _QSharpen, _QShadowComplement, _EyeParallax;
    float4 _QShadowCoolColor;
    float4 _MainTex_TexelSize;
    // v1.4: hybrid
    float  _HybridAmount, _HybridLitGradient, _HybridShadeVolume, _HybridEnvTint;
    // v1.4: eye shadow guard
    float  _UseEyeGuard, _EyeGuardShadow, _EyeGuardShade, _EyeGuardAO, _EyeGuardBrightness;
    // v1.4: auto lighting / ambient colour
    float  _AutoLight, _AutoKeyRatio, _AutoProbeAmbient, _AutoPointLights, _AutoDefaultKey;
    float  _EnvColorStrength, _LightColorStrength, _DarkColorReduce, _DarkColorThreshold;
    float  _LightDirMode, _LightBoost, _LightSoftLimit, _ShadowPosterize, _ShadowDither, _CastShadowOnly, _FresnelAlpha;
    float4 _SphereCenter;
    float  _SphereNormalStrength, _SphereNormalVertical;
    // v1.2: offset rim
    float4 _OffsetRimColor, _OffsetRimVector;
    float  _OffsetRimStrength, _OffsetRimDirMode, _OffsetRimWidth, _OffsetRimMaxPx, _OffsetRimThreshold, _OffsetRimSoftness;
    float  _OffsetRimEmission, _OffsetRimEmissionStrength, _OffsetRimHueSpeed, _OffsetRimEmissionAlbedo; float4 _OffsetRimBlink;
    float  _OffsetRimFacing, _OffsetRimLightInfluence, _OffsetRimEnvInfluence, _OffsetRimShadowMask, _OffsetRimAlbedo, _OffsetRimFadeEnd;
    // v1.2: procedural
    float4 _CurvEdgeColor, _CurvCavityColor;
    float  _CurvScale, _CurvSharpness;
    float  _IridStrength, _IridScale, _IridOffset, _IridSaturation, _IridFresnel, _IridSpecOnly;
    float4 _BounceColor;
    float  _BounceStrength, _BouncePower, _BounceHeight, _BounceLightInfluence, _BounceGroundMatch;
    float4 _FillColor, _FillDir;
    float  _FillStrength, _FillBorder, _FillBlur, _FillShadowOnly;
    float4 _GradTop, _GradBottom, _GradRange;
    float  _GradSpace, _GradBlend, _GradStrength, _ViewHueShift;
    float4 _HatchColor;
    float  _HatchSpace, _HatchDensity, _HatchAngle, _HatchWidth, _HatchThreshold, _HatchCross, _HatchNoise;
    float4 _AngelColor;
    float  _AngelHeight, _AngelWidth, _AngelBlur, _AngelBreakup, _AngelFrequency, _AngelLightInfluence;
    float4 _HoloColor;
    float  _HoloStrength, _HoloLineDensity, _HoloLineSpeed, _HoloFresnel, _HoloFlicker, _HoloAlpha;
    float4 _SkyTopColor, _SkyHorizonColor, _SkyGroundColor;
    float  _WorldAdapt, _WorldAdaptTarget, _WorldAdaptRange, _DebugView;
    // v1.2: double outline
    float  _Outline2Width, _Outline2MainBlend, _Outline2EnableLighting, _Outline2ZBias;
    float4 _Outline2Color;
    // v1.3: richness
    float  _RichShadowSaturation, _RichShadowHue, _RichColorDepth, _RichTerminatorWidth, _RichWrap, _RichAmbientRim, _RichAmbientRimMode;
    float  _RichSoftSpec, _RichSoftSpecRoughness, _RichMicroContrast, _RichGloss;
    float4 _RichTerminatorColor;
    // v1.3: character control
    float  _AmbientFlatten, _DepthShadowWidth, _DepthShadowThreshold, _DepthShadowSoftness, _DepthShadowStrength, _DepthShadowMaxPx;
    float  _PerspectiveRemoval, _PerspectiveRange, _CharBrightness, _CharDesaturate, _OutlineFOVCompensate;
    float4 _PerspectiveCenter, _CharTint, _CharLerpColor;
    // v1.3: detail parameters
    float  _SHSoftness, _AmbientShapeContrast, _EnvNormalizeRange, _SynthReflHighlight, _SynthReflBlur;
    float4 _AmbientSkyTint, _AmbientGroundTint;
    float  _ToonSpecBorder, _ToonSpecBlur, _SpecOcclusionStrength, _HorizonOcclusionStrength, _IridSpecBoost, _Hatch2ndThreshold;
    float  _HoloFlickerSpeed, _AngelShadowMask, _CurvLightInfluence, _BounceGroundIntensity;
    float  _OutlineFixDistance, _OffsetRimFallback;
    // v1.3: ink line / FPS mode
    float  _InkStrength, _InkWidth, _InkAngle, _InkGap, _InkTaper, _InkMin, _InkUnder, _InkNoise, _InkNoiseFreq;
    float4 _InkUnderDir;
    float  _FPSTarget, _FPSRate, _FPSAmp, _FPSFreq, _FPSNormal, _FPSSnap, _FPSWidthJitter;
    // Outline
    float  _OutlineWidth, _OutlineVertexColorWidth, _OutlineFixWidth, _OutlineZBias, _OutlineEnableLighting, _OutlineMainBlend;
    float4 _OutlineColor;
CBUFFER_END
// set globally by the VRChat client (0 = normal view)
float _VRChatMirrorMode;
float _VRChatCameraMode;

Texture2D _MainTex;            SamplerState sampler_MainTex;
Texture2D _AlphaMask;
Texture2D _Main2Tex, _Main2Mask, _Main3Tex, _Main3Mask;
Texture2D _BumpMap, _Bump2Map, _Bump2Mask;
Texture2D _DetailAlbedoMap, _DetailNormalMap, _DetailMask;
Texture2D _ParallaxMap;
Texture2D _MaskMap, _MetallicMap, _SmoothnessMap, _OcclusionMap;
Texture2D _ShadowColorTex, _Shadow2ndColorTex, _ShadowMaskTex, _ShadowRampTex, _Shadow3rdColorTex, _ShadowBorderMask, _ShadowBlurMask, _RimShadeMask, _MainColorAdjustMask;
Texture2D _SSSMap, _BacklightMask;
Texture2D _AnisoShiftMap, _AnisoMask;
Texture2D _SheenMap, _ClearCoatMask, _SheenMask, _BumpMask, _ClearCoatSmoothnessMap, _ClearCoatNormalMap;
Texture2D _RimTex, _Rim2Tex, _Rim3Tex;
Texture2D _MatCapTex, _MatCapMask, _MatCapBumpMap, _MatCap2Tex, _MatCap2Mask;
Texture2D _GlitterMask;
Texture2D _EmissionMap, _EmissionMask, _Emission2Map, _Emission2Mask, _Emission3Map, _Emission3Mask, _Emission4Map, _Emission4Mask;
Texture2D _DissolveNoise;
Texture2D _FlipbookTex, _BackfaceTex, _WobbleMask;
Texture2D _OutlineTex, _OutlineWidthMask;
Texture2D _SSAOMask, _ContactShadowMask;
Texture2D _SpecularMask, _WetnessMask, _ILMMap, _FaceSDFTex, _FaceSDFMask;
Texture2D _TessMask;
Texture2D _EyeGuardMask;
Texture2D _EyeParallaxMask;
TextureCube _ReflCube;
Texture2D _AudioTexture;       float4 _AudioTexture_TexelSize;

SamplerState sampler_linear_clamp;
SamplerState sampler_trilinear_clamp;
SamplerState sampler_point_clamp;
SamplerState sampler_trilinear_repeat;

#define LUMI_SAMPLE(tex, uv)        tex.Sample(sampler_MainTex, uv)
#define LUMI_SAMPLE_LOD(tex, uv, l) tex.SampleLevel(sampler_MainTex, uv, l)
#define LUMI_SAMPLE_CLAMP(tex, uv)  tex.Sample(sampler_linear_clamp, uv)

#endif
