using System;
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // Per module presets (shown as "▾" on the module header), the quality levels of the quick setup and the
    // load estimate. Values are only the settings of the module, so they stack on any style / material preset.
    public static class MitToonSectionPresets
    {
        public struct Item { public string jp, en; public Action<Material> apply; }

        static void F(Material m, string n, float v) { if (m.HasProperty(n)) m.SetFloat(n, v); }
        // SSAO presets start from the same neutral shape
        static void SSAOBase(Material m)
        {
            F(m, "_SSAOMethod", 1); F(m, "_SSAOSoftness", 0.35f); F(m, "_SSAOThickness", 1); F(m, "_SSAOFalloff", 1);
            F(m, "_SSAOFarWeight", 0); F(m, "_SSAOPower", 1); F(m, "_SSAOContrast", 1); F(m, "_SSAOMin", 0);
            F(m, "_SSAONearWeight", 1); F(m, "_SSAOMidWeight", 0); F(m, "_SSAOViewFix", 0.5f);
        }
        static void C(Material m, string n, Color c) { if (m.HasProperty(n)) m.SetColor(n, c); }
        static float G(Material m, string n) => m.HasProperty(n) ? m.GetFloat(n) : 0f;
        static bool On(Material m, string n) => G(m, n) > 0.5f;
        static Item I(string jp, string en, Action<Material> a) => new Item { jp = jp, en = en, apply = a };

        public static readonly Dictionary<string, Item[]> Modules = new Dictionary<string, Item[]>
        {
            ["aniso"] = new[]
            {
                I("髪 (2 本の帯)", "Hair (two bands)", m => { F(m, "_AnisoMode", 0); F(m, "_AnisoTangent", 1); F(m, "_AnisoAngle", 0); F(m, "_AnisoBlend", 0);
                    F(m, "_Aniso1Shift", 0); F(m, "_Aniso1Exponent", 256); F(m, "_Aniso2Shift", -0.3f); F(m, "_Aniso2Exponent", 48); F(m, "_Aniso2Albedo", 1); F(m, "_AnisoToony", 0); }),
                I("アニメ髪 (くっきり)", "Anime hair (crisp)", m => { F(m, "_AnisoMode", 0); F(m, "_AnisoTangent", 1); F(m, "_AnisoBlend", 0);
                    F(m, "_Aniso1Exponent", 128); F(m, "_Aniso2Exponent", 32); F(m, "_AnisoToony", 1); F(m, "_AnisoToonBlur", 0.04f); }),
                I("サテン / 布", "Satin / cloth", m => { F(m, "_AnisoMode", 1); F(m, "_AnisoTangent", 0); F(m, "_Anisotropy", 0.6f); F(m, "_AnisoBlend", 0); F(m, "_AnisoToony", 0); }),
                I("ヘアライン金属 (直線)", "Brushed metal (straight)", m => { F(m, "_AnisoMode", 1); F(m, "_AnisoTangent", 0); F(m, "_Anisotropy", 0.85f); F(m, "_AnisoBlend", 0); F(m, "_AnisoToony", 0); }),
                I("ヘアライン金属 (同心円)", "Brushed metal (circular)", m => { F(m, "_AnisoMode", 1); F(m, "_AnisoTangent", 3); F(m, "_Anisotropy", 0.85f); F(m, "_AnisoBlend", 0); F(m, "_AnisoToony", 0); }),
            },
            ["shadow"] = new[]
            {
                I("アニメ (くっきり 1 影)", "Anime (crisp, 1 tone)", m => { F(m, "_ShadowBorder", 0.5f); F(m, "_ShadowBlur", 0.03f);
                    C(m, "_Shadow2ndColor", new Color(0.68f, 0.66f, 0.79f, 0f)); F(m, "_ShadowBorderRange", 0.03f); F(m, "_ShadowEnvStrength", 0.2f); }),
                I("やわらか (2 影)", "Soft (2 tones)", m => { F(m, "_ShadowBorder", 0.5f); F(m, "_ShadowBlur", 0.12f); F(m, "_Shadow2ndBorder", 0.2f); F(m, "_Shadow2ndBlur", 0.15f);
                    C(m, "_Shadow2ndColor", new Color(0.68f, 0.66f, 0.79f, 0.6f)); F(m, "_ShadowBorderRange", 0.08f); F(m, "_ShadowEnvStrength", 0.3f); }),
                I("塗り風 (影色を自動で作る)", "Painted (auto shadow color)", m => { F(m, "_AutoShadowColor", 0.7f); F(m, "_ShadowBlur", 0.06f);
                    F(m, "_ShadowBorderRange", 0.06f); C(m, "_ShadowBorderColor", new Color(1f, 0.4f, 0.3f, 0.5f)); }),
                I("グラデーション (リアル寄り)", "Gradient (semi real)", m => { F(m, "_ShadowBorder", 0.45f); F(m, "_ShadowBlur", 0.35f);
                    C(m, "_Shadow2ndColor", new Color(0.68f, 0.66f, 0.79f, 0.3f)); F(m, "_ShadowEnvStrength", 0.5f); }),
                I("影なし (フラット)", "No shading (flat)", m => F(m, "_ShadowStrength", 0f)),
            },
            ["rim"] = new[]
            {
                I("控えめ", "Subtle", m => { C(m, "_RimColor", new Color(1f, 0.97f, 0.95f, 0.25f)); F(m, "_RimBorder", 0.55f); F(m, "_RimBlur", 0.8f);
                    F(m, "_RimFresnelPower", 4f); F(m, "_RimLightDir", 0.6f); F(m, "_RimShadowMask", 0.7f); }),
                I("くっきりアニメ", "Crisp anime", m => { C(m, "_RimColor", new Color(1f, 0.95f, 0.92f, 0.6f)); F(m, "_RimBorder", 0.6f); F(m, "_RimBlur", 0.1f);
                    F(m, "_RimFresnelPower", 3f); F(m, "_RimLightDir", 0.8f); F(m, "_RimShadowMask", 0.9f); }),
                I("逆光風 (光の反対側)", "Back light look", m => { C(m, "_RimColor", new Color(1f, 0.9f, 0.8f, 0.5f)); F(m, "_RimBorder", 0.5f); F(m, "_RimBlur", 0.5f);
                    F(m, "_RimFresnelPower", 3f); F(m, "_RimLightDir", 0f); F(m, "_RimShadowMask", 0f); }),
                I("暗いフチ (ふち取り)", "Dark edge", m => { C(m, "_RimColor", new Color(0.3f, 0.22f, 0.25f, 0.5f)); F(m, "_RimBorder", 0.6f); F(m, "_RimBlur", 0.4f);
                    F(m, "_RimFresnelPower", 4f); F(m, "_RimLightDir", 0f); F(m, "_RimShadowMask", 0f); }),
            },
            ["offsetrim"] = new[]
            {
                I("控えめ", "Subtle", m => { F(m, "_OffsetRimStrength", 0.6f); F(m, "_OffsetRimWidth", 0.35f); F(m, "_OffsetRimEmission", 0f); }),
                I("標準", "Standard", m => { F(m, "_OffsetRimStrength", 1f); F(m, "_OffsetRimWidth", 0.5f); F(m, "_OffsetRimEmission", 0f); }),
                I("強め (光る)", "Strong (glow)", m => { F(m, "_OffsetRimStrength", 2f); F(m, "_OffsetRimWidth", 0.7f); F(m, "_OffsetRimEmission", 0.4f); }),
            },
            ["matcap"] = new[]
            {
                I("ツヤ (加算 控えめ)", "Gloss (add, subtle)", m => { F(m, "_MatCapBlend", 1); C(m, "_MatCapColor", new Color(1, 1, 1, 0.35f)); F(m, "_MatCapEnableLighting", 1); F(m, "_MatCapMainStrength", 0); }),
                I("ツヤ (スクリーン)", "Gloss (screen)", m => { F(m, "_MatCapBlend", 2); C(m, "_MatCapColor", new Color(1, 1, 1, 0.6f)); F(m, "_MatCapEnableLighting", 1); F(m, "_MatCapMainStrength", 0); }),
                I("金属 (乗算 + 素材色)", "Metal (multiply + base color)", m => { F(m, "_MatCapBlend", 3); C(m, "_MatCapColor", new Color(1, 1, 1, 0.8f)); F(m, "_MatCapEnableLighting", 1); F(m, "_MatCapMainStrength", 1); }),
                I("置き換え (デフォルメ)", "Replace (stylized)", m => { F(m, "_MatCapBlend", 0); C(m, "_MatCapColor", new Color(1, 1, 1, 1)); F(m, "_MatCapEnableLighting", 1); F(m, "_MatCapMainStrength", 1); }),
            },
            ["backlight"] = new[]
            {
                I("控えめ", "Subtle", m => { C(m, "_BacklightColor", new Color(0.85f, 0.8f, 0.7f, 0.4f)); F(m, "_BacklightBorder", 0.4f); F(m, "_BacklightBlur", 0.1f); }),
                I("肌の透け (赤み)", "Skin glow (warm)", m => { C(m, "_BacklightColor", new Color(1f, 0.6f, 0.45f, 0.6f)); F(m, "_BacklightBorder", 0.35f); F(m, "_BacklightBlur", 0.2f); }),
                I("強め", "Strong", m => { C(m, "_BacklightColor", new Color(1f, 0.95f, 0.9f, 1f)); F(m, "_BacklightBorder", 0.3f); F(m, "_BacklightBlur", 0.05f); }),
            },
            ["angelring"] = new[]
            {
                I("控えめ", "Subtle", m => { C(m, "_AngelColor", new Color(1f, 0.97f, 0.95f, 0.35f)); F(m, "_AngelWidth", 0.06f); }),
                I("標準", "Standard", m => { C(m, "_AngelColor", new Color(1f, 0.97f, 0.95f, 0.55f)); F(m, "_AngelWidth", 0.07f); }),
                I("強め", "Strong", m => { C(m, "_AngelColor", new Color(1f, 1f, 1f, 0.85f)); F(m, "_AngelWidth", 0.1f); }),
            },
            ["outline"] = new[]
            {
                I("細い", "Thin", m => { F(m, "_OutlineWidth", 0.04f); F(m, "_OutlineMainBlend", 0.8f); F(m, "_OutlineFixWidth", 0.5f); }),
                I("標準", "Standard", m => { F(m, "_OutlineWidth", 0.08f); F(m, "_OutlineMainBlend", 0.8f); F(m, "_OutlineFixWidth", 0.5f); }),
                I("太め (くっきり)", "Bold", m => { F(m, "_OutlineWidth", 0.16f); F(m, "_OutlineMainBlend", 0.6f); F(m, "_OutlineFixWidth", 0.8f); }),
                I("素材色になじませる", "Blend with base color", m => { C(m, "_OutlineColor", new Color(0.55f, 0.45f, 0.5f, 1f)); F(m, "_OutlineMainBlend", 1f); }),
                I("黒い線", "Black line", m => { C(m, "_OutlineColor", new Color(0.05f, 0.04f, 0.05f, 1f)); F(m, "_OutlineMainBlend", 0f); }),
            },
            ["grading"] = new[]
            {
                I("ナチュラル", "Natural", m => { F(m, "_TonemapMode", 3); F(m, "_Exposure", 0.4f); F(m, "_Contrast", 1.05f); F(m, "_Saturation", 1.05f); F(m, "_Vibrance", 0.1f); }),
                I("鮮やか", "Vivid", m => { F(m, "_TonemapMode", 4); F(m, "_Exposure", 0.4f); F(m, "_Contrast", 1.1f); F(m, "_Saturation", 1.15f); F(m, "_Vibrance", 0.3f); }),
                I("やわらか", "Soft", m => { F(m, "_TonemapMode", 2); F(m, "_Exposure", 0.3f); F(m, "_Contrast", 0.95f); F(m, "_Saturation", 1f); F(m, "_Vibrance", 0.1f); }),
                I("映画風", "Cinematic", m => { F(m, "_TonemapMode", 1); F(m, "_Exposure", 0.3f); F(m, "_Contrast", 1.15f); F(m, "_Saturation", 0.95f); F(m, "_Vibrance", 0f); }),
            },
            ["richness"] = new[]
            {
                I("素のまま (すべて 0)", "Plain (all 0)", m => { foreach (var n in new[] { "_HybridAmount", "_RichWrap", "_RichColorDepth", "_RichShadowSaturation", "_RichShadowHue",
                    "_QShadowComplement", "_RichSoftSpec", "_RichGloss", "_RichAmbientRim", "_RichMicroContrast" }) F(m, n, 0); C(m, "_RichTerminatorColor", new Color(1f, 0.45f, 0.35f, 0f)); }),
                I("標準", "Standard", m => { F(m, "_HybridAmount", 0); F(m, "_RichWrap", 0.2f); F(m, "_RichColorDepth", 0.25f); F(m, "_RichShadowSaturation", 0.35f);
                    F(m, "_QShadowComplement", 0.3f); F(m, "_RichSoftSpec", 0.2f); F(m, "_RichGloss", 0.3f); F(m, "_RichAmbientRim", 0.25f); C(m, "_RichTerminatorColor", new Color(1f, 0.45f, 0.35f, 0.25f)); }),
                I("リッチ (立体感 + 艶)", "Rich (volume + gloss)", m => { F(m, "_HybridAmount", 1); F(m, "_HybridLitGradient", 0.4f); F(m, "_HybridShadeVolume", 0.6f); F(m, "_RichWrap", 0.3f);
                    F(m, "_RichColorDepth", 0.35f); F(m, "_RichShadowSaturation", 0.45f); F(m, "_QShadowComplement", 0.35f); F(m, "_RichSoftSpec", 0.35f); F(m, "_RichGloss", 0.45f);
                    F(m, "_RichAmbientRim", 0.3f); C(m, "_RichTerminatorColor", new Color(1f, 0.45f, 0.35f, 0.35f)); }),
            },
            ["lighting"] = new[]
            {
                I("標準 (自動)", "Standard (auto)", m => { F(m, "_LightColorMode", 0); F(m, "_LightMinLimit", 0.05f); F(m, "_LightMaxLimit", 1f); F(m, "_LightBoost", 0f); }),
                I("暗いワールドでも見える", "Visible in dark worlds", m => { F(m, "_LightColorMode", 0); F(m, "_LightMinLimit", 0.15f); F(m, "_LightMaxLimit", 1f); F(m, "_LightBoost", 0.6f); }),
                I("まぶしさを抑える", "Tame bright worlds", m => { F(m, "_LightMaxLimit", 0.85f); F(m, "_LightBoost", 0f); }),
                I("フラット (陰影を弱く)", "Flat (soft shading)", m => { F(m, "_LightColorMode", 4); F(m, "_LightMinLimit", 0.1f); }),
            },
            ["ss"] = new[]
            {
                I("軽量 (SSAO / 接触影なし)", "Light (no SSAO / contact)", m => ApplyQuality(m, 0)),
                I("標準", "Standard", m => ApplyQuality(m, 1)),
                I("高品質", "High", m => ApplyQuality(m, 2)),
            },
            ["quality"] = new[]
            {
                I("軽量", "Light", m => ApplyQuality(m, 0)),
                I("標準", "Standard", m => ApplyQuality(m, 1)),
                I("高品質", "High", m => ApplyQuality(m, 2)),
            },
            ["softshadow"] = new[]
            {
                I("くっきり", "Crisp", m => { F(m, "_SoftShadowRadius", 0.005f); F(m, "_ShadowSmoothness", 0.2f); }),
                I("標準", "Standard", m => { F(m, "_SoftShadowRadius", 0.015f); F(m, "_ShadowSmoothness", 0.6f); }),
                I("ふんわり", "Soft", m => { F(m, "_SoftShadowRadius", 0.04f); F(m, "_ShadowSmoothness", 0.8f); }),
            },
            ["ssao"] = new[]
            {
                I("控えめ", "Subtle", m => { SSAOBase(m); F(m, "_SSAORadius", 0.04f); F(m, "_SSAOStrength", 0.8f); }),
                I("標準", "Standard", m => { SSAOBase(m); F(m, "_SSAORadius", 0.06f); F(m, "_SSAOStrength", 1.2f); }),
                I("強め", "Strong", m => { SSAOBase(m); F(m, "_SSAORadius", 0.1f); F(m, "_SSAOStrength", 1.8f); }),
                I("くっきり (すき間を締める)", "Crisp contact", m => { SSAOBase(m); F(m, "_SSAORadius", 0.03f); F(m, "_SSAOStrength", 1.6f); F(m, "_SSAOSoftness", 0.15f); F(m, "_SSAOPower", 1.5f); }),
                I("ふんわり広め (マルチスケール)", "Soft and wide (multi scale)", m => { SSAOBase(m); F(m, "_SSAORadius", 0.05f); F(m, "_SSAOStrength", 1.1f); F(m, "_SSAOSoftness", 0.6f); F(m, "_SSAOFarWeight", 0.6f); F(m, "_SSAOFarScale", 3f); }),
                // quality levels: only the cost related settings, the look settings stay as they are
                I("品質/1 最低 (軽い)", "Quality/1 Lowest (light)", m => { F(m, "_SSAOSamples", 4); F(m, "_SSAOJitter", 1); F(m, "_SSAOMidWeight", 0); F(m, "_SSAOFarWeight", 0); }),
                I("品質/2 低", "Quality/2 Low", m => { F(m, "_SSAOSamples", 5); F(m, "_SSAOJitter", 1); F(m, "_SSAOMidWeight", 0); F(m, "_SSAOFarWeight", 0); }),
                I("品質/3 標準", "Quality/3 Standard", m => { F(m, "_SSAOSamples", 6); F(m, "_SSAOJitter", 1); F(m, "_SSAOMidWeight", 0); F(m, "_SSAOFarWeight", 0); }),
                I("品質/4 高", "Quality/4 High", m => { F(m, "_SSAOSamples", 7); F(m, "_SSAOJitter", 1); F(m, "_SSAOMidWeight", 0.4f); F(m, "_SSAOMidScale", 1.8f); F(m, "_SSAOFarWeight", 0); }),
                I("品質/5 最高 (重い)", "Quality/5 Highest (heavy)", m => { F(m, "_SSAOSamples", 8); F(m, "_SSAOJitter", 1); F(m, "_SSAOMidWeight", 0.4f); F(m, "_SSAOMidScale", 1.8f); F(m, "_SSAOFarWeight", 0.3f); F(m, "_SSAOFarScale", 3.5f); }),
                I("近中遠を分けて重ねる", "Near / mid / far layered", m => { SSAOBase(m); F(m, "_SSAORadius", 0.04f); F(m, "_SSAOStrength", 1.2f);
                    F(m, "_SSAONearWeight", 1); F(m, "_SSAOMidWeight", 0.5f); F(m, "_SSAOMidScale", 2f); F(m, "_SSAOFarWeight", 0.3f); F(m, "_SSAOFarScale", 4f); }),
                I("地平線方式 (面の凹みを強調)", "Horizon method (stresses creases)", m => { SSAOBase(m); F(m, "_SSAOMethod", 0); F(m, "_SSAORadius", 0.06f); F(m, "_SSAOStrength", 1.2f); F(m, "_SSAOFalloff", 0.7f); }),
            },
            ["depthshadow"] = new[]
            {
                I("控えめ", "Subtle", m => { F(m, "_DepthShadowWidth", 0.5f); F(m, "_DepthShadowStrength", 0.6f); }),
                I("標準", "Standard", m => { F(m, "_DepthShadowWidth", 0.8f); F(m, "_DepthShadowStrength", 1f); }),
                I("強め", "Strong", m => { F(m, "_DepthShadowWidth", 1.4f); F(m, "_DepthShadowStrength", 1f); }),
            },
        };

        // ---- quality levels: only the cost related settings, the look direction stays
        public static readonly string[] LevelJP = { "軽量", "標準", "高品質" };
        public static readonly string[] LevelEN = { "Light", "Standard", "High" };
        public static void ApplyQuality(Material m, int level)
        {
            int samples = level == 0 ? 4 : level == 1 ? 6 : 8;
            F(m, "_SSAOSamples", samples); F(m, "_SoftShadowSamples", samples); F(m, "_ContactShadowSteps", samples);
            F(m, "_QLodDistance", level == 0 ? 8 : level == 1 ? 12 : 20);
            F(m, "_QDeband", level == 0 ? 0 : 1);
            F(m, "_QSharpen", level == 0 ? 0 : 0.25f);
            if (level == 0)
            {
                // the two effects that read the depth many times per pixel
                F(m, "_UseSSAO", 0); F(m, "_UseContactShadow", 0);
            }
            MitToonShaderGUI.SyncKeywords(m);
        }

        // ---- load estimate, relative to a typical toon shader with a main texture and toon shadows (= 1.0).
        // Weights come from GPU timings of a full screen avatar (2560x1440, MSAA 4x); they are a guide, not a measurement.
        public struct Cost { public string jp, en; public float value; public bool depth; public Action<Material> off; }

        public static float Estimate(Material m, List<Cost> items)
        {
            items?.Clear();
            if (m == null || m.shader == null) return 0;
            float total = 0.92f;
            void Add(bool cond, string jp, string en, float v, bool depth, Action<Material> off)
            {
                if (!cond) return;
                total += v;
                items?.Add(new Cost { jp = jp, en = en, value = v, depth = depth, off = off });
            }
            Action<Material> Kw(string toggle) => x => { F(x, toggle, 0); MitToonShaderGUI.SyncKeywords(x); };

            float ss = Mathf.Clamp(G(m, "_SoftShadowSamples"), 4, 8), ao = Mathf.Clamp(G(m, "_SSAOSamples"), 4, 8), cs = Mathf.Clamp(G(m, "_ContactShadowSteps"), 4, 8);
            Add(On(m, "_UseSSAO"), "SSAO", "SSAO", (0.06f + 0.03f * ao) * (G(m, "_SSAOFarWeight") > 0.001f ? 1.9f : 1f), true, Kw("_UseSSAO"));
            Add(On(m, "_UseContactShadow"), "コンタクトシャドウ", "Contact Shadows", 0.05f + 0.03f * cs, true, Kw("_UseContactShadow"));
            Add(On(m, "_UseSoftShadow"), "ソフトシャドウ", "Soft Shadows", 0.05f + 0.02f * ss, false, Kw("_UseSoftShadow"));
            Add(On(m, "_UseOffsetRim"), "オフセットリム", "Offset Rim", 0.12f, true, Kw("_UseOffsetRim"));
            Add(On(m, "_UseDepthShadow"), "深度シャドウ", "Depth Shadow", 0.03f, true, Kw("_UseDepthShadow"));
            Add(On(m, "_UseRim") && G(m, "_RimMode") > 0.5f, "深度リム", "Depth Rim", 0.05f, true, x => F(x, "_RimMode", 0));
            Add(On(m, "_UseParallax"), "視差", "Parallax", G(m, "_ParallaxMode") > 0.5f ? 0.3f : 0.05f, false, Kw("_UseParallax"));
            Add(On(m, "_UseGlitter"), "ラメ", "Glitter", 0.08f, false, Kw("_UseGlitter"));
            Add(G(m, "_RefractStrength") > 0.001f, "疑似屈折", "Fake Refraction", G(m, "_RefractDispersion") > 0.001f ? 0.15f : 0.06f, false, x => F(x, "_RefractStrength", 0));
            Add(MitToonShaderGUI.IsOutlineShader(m.shader), "アウトライン", "Outline", 0.12f + (G(m, "_Outline2Width") > 0 ? 0.1f : 0f), false, null);
            Add(MitToonShaderGUI.IsTessShader(m.shader), "テッセレーション", "Tessellation", 0.6f, false, null);
            Add(MitToonShaderGUI.IsTwoPassMode(Mathf.RoundToInt(G(m, "_RenderMode"))), "半透明 2パス", "Transparent 2 pass", 0.8f, false, null);
            int light = 0;
            foreach (var t in new[] { "_UseMatCap", "_UseBacklight", "_UseRim", "_UseRim2", "_UseRim3", "_UseAngelRing", "_UseAniso", "_UseSheen", "_UseClearCoat",
                                      "_UseEmission", "_UseEmission2", "_UseEmission3", "_UseEmission4", "_UseBumpMap", "_UseLayer", "_UseDetail", "_UseSSS", "_UseIridescence", "_UseTonemap", "_UseLightVolumes",
                                      "_UseFaceSDF", "_UseHatch", "_UseCurvature", "_UseBounce", "_UseFillLight", "_UseGradient", "_UseHologram" })
                if (On(m, t)) light++;
            Add(light > 0, "その他の機能 (" + light + " 個)", "Other features (" + light + ")", 0.035f * light, false, null);
            return total;
        }

        public static Color LoadColor(float v) =>
            v < 1.25f ? new Color(0.35f, 0.8f, 0.45f) : v < 1.7f ? new Color(0.95f, 0.78f, 0.3f) : new Color(0.95f, 0.4f, 0.35f);

        // MitToon materials of the avatars that use the given materials (for "apply to the whole avatar")
        public static List<Material> AvatarMaterials(IEnumerable<Material> materials)
        {
            var set = new HashSet<Material>();
            foreach (var root in MitToonSceneUtil.AvatarsUsing(materials))
                foreach (var r in root.GetComponentsInChildren<Renderer>(true))
                    foreach (var m in r.sharedMaterials)
                        if (m != null && m.shader != null && m.shader.name.StartsWith("MitToon/")) set.Add(m);
            return set.ToList();
        }
    }
}
