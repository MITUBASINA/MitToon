using System;
using UnityEngine;

namespace MitToon.Editor
{
    // Presets. "Style" presets set the look (toon amount, screen space effects, grading) and should be applied to every
    // material of an avatar. "Material" presets only change the surface of one material and can be stacked on a style.
    // Values follow common material categories (skin / hair / cloth / clear coat / anisotropic / wetness) and filmic grading,
    // plus game / VTuber cel techniques (face SDF, ILM, depth rim, stencil hair see-through).
    public static class MitToonPresets
    {
        public struct Cat { public string jp, en; }
        public struct Preset { public string id, jp, en; public Cat category; public Action<Material> apply; }

        static readonly Cat Style = new Cat { jp = "スタイル (全マテリアル共通)", en = "Style (all materials)" };
        static readonly Cat Mat = new Cat { jp = "素材", en = "Material" };
        static readonly Cat Stencil = new Cat { jp = "ステンシル", en = "Stencil" };

        static void F(Material m, string n, float v) { if (m.HasProperty(n)) m.SetFloat(n, v); }
        static void C(Material m, string n, Color c) { if (m.HasProperty(n)) m.SetColor(n, c); }

        static void Grade(Material m, float mode, float exposure, float contrast, float sat, float vibrance)
        {
            F(m, "_UseTonemap", mode > 0 ? 1 : 0); F(m, "_TonemapMode", mode); F(m, "_Exposure", exposure);
            F(m, "_Contrast", contrast); F(m, "_Saturation", sat); F(m, "_Vibrance", vibrance);
            F(m, "_Temperature", 0); F(m, "_Tint", 0); C(m, "_ShadowTint", Color.white); C(m, "_HighlightTint", Color.white);
            RichGI(m);
        }

        // MitToon GI defaults shared by every style: robust in flat / probe-less / dark worlds
        static void RichGI(Material m)
        {
            F(m, "_AmbientShape", 0.6f); F(m, "_EnvNormalize", 0.5f); F(m, "_VirtualKeyLight", 1); F(m, "_SpecEnergyComp", 1);
            F(m, "_ReflCubeMode", 0); F(m, "_LightSoftLimit", 0.5f);
            F(m, "_UseLightVolumes", MitToonShaderGUI.LightVolumesInstalled ? 1 : 0);
        }

        // Style presets start from the shader defaults of every look related property, so switching styles never leaves
        // features of the previous style behind (textures, masks and per material settings are not touched).
        static readonly string[] StyleProps =
        {
            "_ToonAmount", "_ShadowBorder", "_ShadowBlur", "_Shadow2ndBlur", "_Shadow2ndColor", "_ShadowBorderColor", "_ShadowBorderRange",
            "_ShadowColor", "_ShadowEnvStrength", "_LightMinLimit", "_LightMaxLimit", "_SpecularToony", "_SpecularStrength", "_EnvReflStrength",
            "_UseRim", "_RimMode", "_RimFresnelPower", "_RimBorder", "_RimBlur", "_RimLightDir", "_RimShadowMask", "_RimColor",
            "_RimDepthWidth", "_RimDepthThreshold", "_UseSSAO", "_SSAOStrength", "_SSAODirect", "_SSAOColor",
            "_UseSoftShadow", "_ShadowSmoothness", "_UseContactShadow", "_UseDepthShadow", "_DepthShadowWidth", "_DepthShadowStrength",
            "_AmbientFlatten", "_HybridAmount", "_HybridLitGradient", "_HybridShadeVolume", "_HybridEnvTint",
            "_RichWrap", "_RichTerminatorColor", "_RichColorDepth", "_RichShadowSaturation", "_RichSoftSpec", "_RichSoftSpecRoughness",
            "_RichGloss", "_RichAmbientRim", "_QShadowComplement", "_WorldAdapt",
            "_LightColorMode", "_LightMapMode", "_AutoShadowColor",
        };
        static void ResetStyle(Material m)
        {
            var sh = m.shader;
            foreach (var n in StyleProps)
            {
                int i = sh.FindPropertyIndex(n);
                if (i < 0) continue;
                var t = sh.GetPropertyType(i);
                if (t == UnityEngine.Rendering.ShaderPropertyType.Color || t == UnityEngine.Rendering.ShaderPropertyType.Vector)
                    m.SetVector(n, sh.GetPropertyDefaultVectorValue(i));
                else if (t == UnityEngine.Rendering.ShaderPropertyType.Float || t == UnityEngine.Rendering.ShaderPropertyType.Range)
                    m.SetFloat(n, sh.GetPropertyDefaultFloatValue(i));
            }
        }

        public static readonly Preset[] All =
        {
            // ---------------------------------------------------------------- styles
            new Preset { id = "anime", category = Style, jp = "アニメ トゥーン", en = "Anime Toon", apply = m =>
            {
                ResetStyle(m);
                F(m, "_AutoShadowColor", 0.5f);
                F(m, "_ToonAmount", 1); F(m, "_ShadowBlur", 0.05f); F(m, "_SpecularToony", 0.7f); F(m, "_SpecularStrength", 0.4f);
                F(m, "_EnvReflStrength", 0.3f); F(m, "_UseSoftShadow", 1);
                F(m, "_UseRim", 1); F(m, "_RimFresnelPower", 3.5f);
                Grade(m, 0, 0, 1, 1, 0);
            }},
            new Preset { id = "game", category = Style, jp = "ゲーム / VTuber 風 (セル + 深度リム + 髪の影)", en = "Game / VTuber Cel (depth rim + hair shadow)", apply = m =>
            {
                ResetStyle(m);
                F(m, "_AutoShadowColor", 0.4f); F(m, "_LightColorMode", 3);
                F(m, "_ToonAmount", 1); F(m, "_ShadowBlur", 0.015f); F(m, "_Shadow2ndBlur", 0.02f);
                C(m, "_Shadow2ndColor", new Color(0.68f, 0.66f, 0.79f, 0.35f));
                C(m, "_ShadowBorderColor", new Color(1f, 0.5f, 0.42f, 0.35f)); F(m, "_ShadowBorderRange", 0.04f);
                F(m, "_ShadowEnvStrength", 0.15f); F(m, "_AmbientFlatten", 0.5f); F(m, "_LightMinLimit", 0.12f); F(m, "_LightMaxLimit", 1.1f);
                F(m, "_SpecularToony", 1); F(m, "_SpecularStrength", 0.6f); F(m, "_EnvReflStrength", 0.2f);
                F(m, "_UseRim", 1); F(m, "_RimMode", 1); F(m, "_RimDepthWidth", 0.35f); F(m, "_RimDepthThreshold", 0.08f);
                C(m, "_RimColor", new Color(1f, 0.95f, 0.92f, 0.45f)); F(m, "_RimLightDir", 0.7f); F(m, "_RimShadowMask", 0.8f);
                F(m, "_UseSoftShadow", 1); F(m, "_ShadowSmoothness", 0.2f);
                F(m, "_UseDepthShadow", 1); F(m, "_DepthShadowWidth", 0.8f); F(m, "_DepthShadowStrength", 0.8f);
                Grade(m, 5, 0.1f, 1.05f, 1.05f, 0.15f);
            }},
            new Preset { id = "toonreal", category = Style, jp = "トゥーン + リアル質感 (3D アニメ風)", en = "Toon + Real Material (3D anime)", apply = m =>
            {
                ResetStyle(m);
                F(m, "_AutoShadowColor", 0.5f);
                F(m, "_ToonAmount", 1); F(m, "_ShadowBlur", 0.05f); F(m, "_ShadowEnvStrength", 0.45f);
                F(m, "_HybridAmount", 1); F(m, "_HybridLitGradient", 0.4f); F(m, "_HybridShadeVolume", 0.6f); F(m, "_HybridEnvTint", 0.3f);
                F(m, "_SpecularToony", 0.3f); F(m, "_SpecularStrength", 0.8f); F(m, "_EnvReflStrength", 0.6f);
                F(m, "_RichSoftSpec", 0.35f); F(m, "_RichSoftSpecRoughness", 0.55f); F(m, "_RichGloss", 0.45f); F(m, "_RichAmbientRim", 0.3f);
                C(m, "_ShadowBorderColor", new Color(1f, 0.45f, 0.35f, 0.35f)); F(m, "_ShadowBorderRange", 0.06f);
                F(m, "_UseSoftShadow", 1); F(m, "_ShadowSmoothness", 0.25f); F(m, "_UseContactShadow", 1);
                F(m, "_UseRim", 1); F(m, "_RimFresnelPower", 5f); F(m, "_RimBorder", 0.55f); F(m, "_RimBlur", 1f); F(m, "_RimLightDir", 0.8f);
                C(m, "_RimColor", new Color(1f, 0.97f, 0.95f, 0.18f)); F(m, "_RimShadowMask", 0.8f);
                Grade(m, 3, 0.35f, 1.05f, 1.08f, 0.15f);
            }},
            new Preset { id = "semireal", category = Style, jp = "リアル寄りアニメ", en = "Semi Realistic", apply = m =>
            {
                ResetStyle(m);
                F(m, "_ToonAmount", 0.45f); F(m, "_SpecularToony", 0); F(m, "_SpecularStrength", 1); F(m, "_EnvReflStrength", 1);
                F(m, "_ShadowBlur", 0.18f); F(m, "_ShadowEnvStrength", 0.5f);
                F(m, "_UseSSAO", 1); F(m, "_SSAOStrength", 1.2f); C(m, "_SSAOColor", new Color(0.14f, 0.07f, 0.06f));
                F(m, "_UseSoftShadow", 1); F(m, "_ShadowSmoothness", 0.6f); F(m, "_UseContactShadow", 1);
                F(m, "_UseRim", 1); C(m, "_RimColor", new Color(0.5f, 0.45f, 0.45f, 0.5f)); F(m, "_RimBlur", 0.8f);
                Grade(m, 3, 0.55f, 1.1f, 1.05f, 0.2f);
            }},
            new Preset { id = "realistic", category = Style, jp = "リアル (PBR)", en = "Realistic (PBR)", apply = m =>
            {
                ResetStyle(m);
                F(m, "_ToonAmount", 0); F(m, "_SpecularToony", 0); F(m, "_SpecularStrength", 1); F(m, "_EnvReflStrength", 1.1f);
                F(m, "_UseSSAO", 1); F(m, "_SSAOStrength", 1.3f); F(m, "_SSAODirect", 0.4f); C(m, "_SSAOColor", new Color(0.1f, 0.05f, 0.05f));
                F(m, "_UseSoftShadow", 1); F(m, "_UseContactShadow", 1); F(m, "_UseRim", 0);
                Grade(m, 4, 0.45f, 1.1f, 1f, 0.1f);
            }},
            new Preset { id = "classic", category = Style, jp = "クラシック トゥーン (スフィア加算)", en = "Classic Toon (add sphere)", apply = m =>
            {
                ResetStyle(m);
                F(m, "_LightColorMode", 2);
                F(m, "_ToonAmount", 1); F(m, "_ShadowBlur", 0.08f); C(m, "_ShadowColor", new Color(0.86f, 0.82f, 0.88f));
                F(m, "_SpecularToony", 0.5f); F(m, "_UseMatCap", 1); F(m, "_MatCapBlend", 1); C(m, "_MatCapColor", new Color(1, 1, 1, 0.6f));
                F(m, "_UseRim", 0);
                Grade(m, 0, 0, 1, 1, 0);
            }},

            // ---------------------------------------------------------------- materials
            new Preset { id = "skin", category = Mat, jp = "肌 (SSS)", en = "Skin (SSS)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.5f); F(m, "_Reflectance", 0.42f);
                F(m, "_UseSSS", 1); C(m, "_SSSColor", new Color(1f, 0.35f, 0.2f)); F(m, "_SSSStrength", 0.8f); F(m, "_SSSWrap", 0.5f);
                F(m, "_SSSCurvature", 0.5f); F(m, "_TransmissionStrength", 0.6f);
                C(m, "_ShadowColor", new Color(0.93f, 0.75f, 0.73f)); C(m, "_ShadowBorderColor", new Color(1f, 0.35f, 0.25f, 0.6f));
                F(m, "_ShadowBorderRange", 0.08f); F(m, "_UseBacklight", 1); C(m, "_BacklightColor", new Color(1f, 0.6f, 0.45f, 0.6f));
                C(m, "_SSAOColor", new Color(0.2f, 0.05f, 0.04f));
            }},
            new Preset { id = "skinanime", category = Mat, jp = "肌 (アニメ)", en = "Skin (anime)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.3f); F(m, "_SpecularStrength", 0.2f); F(m, "_UseSSS", 0);
                C(m, "_ShadowColor", new Color(0.96f, 0.78f, 0.76f)); C(m, "_ShadowBorderColor", new Color(1f, 0.45f, 0.35f, 0.5f));
                F(m, "_ShadowBorderRange", 0.05f);
            }},
            new Preset { id = "face", category = Mat, jp = "顔 (滑らかな影 / SDF)", en = "Face (smooth shadow / SDF)", apply = m =>
            {
                // SDF when a face shadow map is assigned, otherwise a spherical normal smooths the face shading
                bool sdf = m.HasProperty("_FaceSDFTex") && m.GetTexture("_FaceSDFTex") != null;
                F(m, "_UseFaceSDF", sdf ? 1 : 0); F(m, "_FaceSDFBlur", 0.02f);
                F(m, "_UseSphereNormal", sdf ? 0 : 1); F(m, "_SphereNormalStrength", 0.7f); F(m, "_Smoothness", 0.3f); F(m, "_SpecularStrength", 0.1f);
                F(m, "_UseContactShadow", 1); F(m, "_ReceiveShadowStrength", 0.6f);
                C(m, "_ShadowColor", new Color(0.96f, 0.78f, 0.76f));
            }},
            new Preset { id = "hair", category = Mat, jp = "髪 (天使の輪)", en = "Hair (angel ring)", apply = m =>
            {
                // no shift map: the procedural ring needs no texture
                bool tex = m.HasProperty("_AnisoShiftMap") && m.GetTexture("_AnisoShiftMap") != null;
                F(m, "_UseAngelRing", tex ? 0 : 1); C(m, "_AngelColor", new Color(1f, 0.97f, 0.95f, 0.55f)); F(m, "_AngelHeight", 0.35f);
                F(m, "_AngelWidth", 0.07f); F(m, "_AngelBreakup", 0.5f);
                F(m, "_UseAniso", tex ? 1 : 0); F(m, "_AnisoMode", 0); F(m, "_AnisoTangent", 1); F(m, "_Smoothness", 0.6f);
                C(m, "_Aniso1Color", new Color(0.55f, 0.55f, 0.55f)); F(m, "_Aniso1Shift", 0.1f); F(m, "_Aniso1Exponent", 300);
                C(m, "_Aniso2Color", new Color(0.6f, 0.5f, 0.45f)); F(m, "_Aniso2Shift", -0.25f); F(m, "_Aniso2Exponent", 40);
                F(m, "_SpecularStrength", 0.5f); F(m, "_UseContactShadow", 1);
            }},
            new Preset { id = "eye", category = Mat, jp = "瞳 (角膜クリアコート)", en = "Eye (cornea clear coat)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.2f); F(m, "_ShadowStrength", 0.35f); F(m, "_ReceiveShadowStrength", 0.3f);
                F(m, "_UseClearCoat", 1); F(m, "_ClearCoat", 1); F(m, "_ClearCoatSmoothness", 0.98f); F(m, "_EnvReflStrength", 1.2f);
                F(m, "_UseRim", 0); F(m, "_SSAODirect", 0); F(m, "_UseEyeGuard", 1);
            }},
            new Preset { id = "cotton", category = Mat, jp = "布 (コットン)", en = "Cloth (cotton)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.15f); F(m, "_Reflectance", 0.4f); F(m, "_SpecularStrength", 0.4f);
                F(m, "_UseSheen", 1); C(m, "_SheenColor", new Color(0.25f, 0.25f, 0.25f)); F(m, "_SheenRoughness", 0.6f);
            }},
            new Preset { id = "velvet", category = Mat, jp = "布 (ベルベット)", en = "Cloth (velvet)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.1f); F(m, "_SpecularStrength", 0.2f);
                F(m, "_UseSheen", 1); C(m, "_SheenColor", new Color(0.7f, 0.7f, 0.7f)); F(m, "_SheenRoughness", 0.3f);
            }},
            new Preset { id = "satin", category = Mat, jp = "布 (サテン)", en = "Cloth (satin)", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.7f); F(m, "_UseAniso", 1); F(m, "_AnisoMode", 1); F(m, "_Anisotropy", 0.7f);
                C(m, "_Aniso1Color", Color.white); F(m, "_UseSheen", 1); C(m, "_SheenColor", new Color(0.3f, 0.3f, 0.3f)); F(m, "_SheenRoughness", 0.4f);
            }},
            new Preset { id = "leather", category = Mat, jp = "レザー", en = "Leather", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.5f); F(m, "_Reflectance", 0.45f); F(m, "_SpecularStrength", 0.8f);
                F(m, "_UseClearCoat", 1); F(m, "_ClearCoat", 0.3f); F(m, "_ClearCoatSmoothness", 0.7f);
            }},
            new Preset { id = "latex", category = Mat, jp = "ラテックス / 光沢プラスチック", en = "Latex / Glossy Plastic", apply = m =>
            {
                F(m, "_Metallic", 0); F(m, "_Smoothness", 0.8f); F(m, "_SpecularStrength", 1.2f);
                F(m, "_UseClearCoat", 1); F(m, "_ClearCoat", 1); F(m, "_ClearCoatSmoothness", 0.95f); F(m, "_EnvReflStrength", 1.2f);
            }},
            new Preset { id = "metal", category = Mat, jp = "金属 (磨き)", en = "Metal (polished)", apply = m =>
            {
                F(m, "_Metallic", 1); F(m, "_Smoothness", 0.85f); F(m, "_EnvReflStrength", 1.2f); F(m, "_UseAniso", 0);
            }},
            new Preset { id = "brushed", category = Mat, jp = "金属 (ヘアライン)", en = "Metal (brushed)", apply = m =>
            {
                F(m, "_Metallic", 1); F(m, "_Smoothness", 0.7f); F(m, "_UseAniso", 1); F(m, "_AnisoMode", 1); F(m, "_Anisotropy", 0.85f);
                C(m, "_Aniso1Color", Color.white);
            }},
            new Preset { id = "wet", category = Mat, jp = "濡れ (Wetness)", en = "Wet", apply = m =>
            {
                F(m, "_Wetness", 0.8f); F(m, "_EnvReflStrength", 1.2f);
            }},
            new Preset { id = "gem", category = Mat, jp = "宝石 / ラメ", en = "Gem / Glitter", apply = m =>
            {
                F(m, "_Smoothness", 0.9f); F(m, "_UseClearCoat", 1); F(m, "_ClearCoatSmoothness", 0.98f);
                F(m, "_UseGlitter", 1); F(m, "_GlitterRandomColor", 0.4f);
            }},

            new Preset { id = "pearl", category = Mat, jp = "パール / 玉虫色", en = "Pearl / Iridescent", apply = m =>
            {
                F(m, "_Smoothness", 0.8f); F(m, "_UseIridescence", 1); F(m, "_IridStrength", 0.6f); F(m, "_IridScale", 2.5f);
                F(m, "_IridSpecOnly", 0.5f); F(m, "_UseClearCoat", 1); F(m, "_ClearCoatSmoothness", 0.95f);
            }},
            new Preset { id = "hologram", category = Mat, jp = "ホログラム", en = "Hologram", apply = m =>
            {
                F(m, "_UseHologram", 1); F(m, "_HoloStrength", 0.6f); F(m, "_HoloAlpha", 0.6f); F(m, "_UseEmission", 0);
            }},
            new Preset { id = "sketch", category = Mat, jp = "線画ハッチング", en = "Sketch Hatching", apply = m =>
            {
                F(m, "_UseHatch", 1); F(m, "_HatchDensity", 140); F(m, "_HatchCross", 0.6f); F(m, "_UseCurvature", 1);
            }},
            new Preset { id = "inkline", category = Mat, jp = "手描き線 (入り抜き + FPS)", en = "Hand drawn line (taper + FPS)", apply = m =>
            {
                F(m, "_UseInkLine", 1); F(m, "_InkWidth", 1.6f); F(m, "_InkTaper", 1.5f);
                F(m, "_UseFPSMode", 1); F(m, "_FPSTarget", 0); F(m, "_FPSRate", 12); F(m, "_FPSAmp", 0.15f); F(m, "_FPSWidthJitter", 0.35f);
            }},

            // ---------------------------------------------------------------- stencil
            new Preset { id = "stencileye", category = Stencil, jp = "前髪透け: 目・眉 側", en = "Hair see-through: eyes / brows", apply = m =>
            {
                F(m, "_StencilRef", 47); F(m, "_StencilComp", 8); F(m, "_StencilPass", 2); m.renderQueue = 2001;
            }},
            new Preset { id = "stencilhair", category = Stencil, jp = "前髪透け: 前髪 側", en = "Hair see-through: bangs", apply = m =>
            {
                F(m, "_StencilRef", 47); F(m, "_StencilComp", 6); F(m, "_StencilPass", 0); m.renderQueue = 2002;
            }},
            new Preset { id = "stencilreset", category = Stencil, jp = "ステンシル解除", en = "Reset stencil", apply = m =>
            {
                F(m, "_StencilRef", 0); F(m, "_StencilComp", 8); F(m, "_StencilPass", 0); m.renderQueue = -1;
            }},
        };

        public static void Apply(Material m, string id)
        {
            foreach (var p in All) if (p.id == id) p.apply(m);
            MitToonShaderGUI.SyncKeywords(m);
        }
    }
}
