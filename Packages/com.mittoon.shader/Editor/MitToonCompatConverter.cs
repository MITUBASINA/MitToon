using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace MitToon.Editor
{
    // Switches materials of a common toon shader family to MitToon with the same look.
    // The values are read while the old shader is still assigned, the shading switches to the compatible mode
    // (the same light and shadow maths), and the settings whose meaning or name differ are translated.
    public static class MitToonCompatConverter
    {
        // recognised by its property set, not by name
        public static bool IsSource(Shader s)
        {
            if (s == null || s.name.StartsWith("MitToon/")) return false;
            bool has(string p) => s.FindPropertyIndex(p) >= 0;
            return has("_UseShadow") && has("_ShadowBorderMask") && has("_TransparentMode") && has("_MainTexHSVG");
        }

        public class Snapshot
        {
            public string shaderName;
            public int renderQueue;
            public readonly Dictionary<string, float> f = new Dictionary<string, float>();
            public readonly Dictionary<string, Vector4> v = new Dictionary<string, Vector4>();
            public readonly Dictionary<string, Color> c = new Dictionary<string, Color>();
            public readonly HashSet<string> hdr = new HashSet<string>();
            public readonly Dictionary<string, (Texture tex, Vector2 scale, Vector2 offset)> t = new Dictionary<string, (Texture, Vector2, Vector2)>();
            public float F(string p, float def = 0) => f.TryGetValue(p, out var x) ? x : def;
            public bool On(string p) => F(p) > 0.5f;
        }

        public static Snapshot Take(Material m)
        {
            var sn = new Snapshot { shaderName = m.shader.name, renderQueue = m.renderQueue };
            var sh = m.shader;
            for (int i = 0; i < sh.GetPropertyCount(); i++)
            {
                string p = sh.GetPropertyName(i);
                switch (sh.GetPropertyType(i))
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range: sn.f[p] = m.GetFloat(p); break;
                    case ShaderPropertyType.Int: sn.f[p] = m.GetInteger(p); break;
                    case ShaderPropertyType.Color:
                        sn.c[p] = m.GetColor(p);
                        if ((sh.GetPropertyFlags(i) & ShaderPropertyFlags.HDR) != 0) sn.hdr.Add(p);
                        break;
                    case ShaderPropertyType.Vector: sn.v[p] = m.GetVector(p); break;
                    case ShaderPropertyType.Texture: sn.t[p] = (m.GetTexture(p), m.GetTextureScale(p), m.GetTextureOffset(p)); break;
                }
            }
            return sn;
        }

        // MitToon extras that the source shader does not have: switched to neutral so they add nothing
        static readonly (string p, float v)[] Neutral =
        {
            ("_CompatShading", 1), ("_ToonAmount", 1), ("_HybridAmount", 0),
            ("_RichShadowSaturation", 0), ("_RichColorDepth", 0), ("_RichShadowHue", 0), ("_QShadowComplement", 0),
            ("_RichSoftSpec", 0), ("_RichAmbientRim", 0), ("_RichGloss", 0), ("_QDeband", 0), ("_QSharpen", 0),
            ("_AutoShadowColor", 0), ("_WorldAdapt", 0), ("_FresnelAlpha", 0), ("_RefractStrength", 0),
            ("_AddLightSmoothFalloff", 0), ("_AddLightIgnoreDirectional", 0), ("_ReceiveCastShadow", 1),
            ("_RimMode", 0), ("_RimLitSideOnly", 0), ("_Rim2LitSideOnly", 0), ("_Rim3LitSideOnly", 0),
            ("_UseRim2", 0), ("_UseRim3", 0), ("_UseEmission3", 0), ("_UseEmission4", 0), ("_UseFlipbook", 0), ("_UseEyeGuard", 0),
            ("_EmissionRainbow", 0), ("_Emission2Rainbow", 0), ("_WobbleStrength", 0), ("_PerspectiveRemoval", 0), ("_Outline2Width", 0),
            ("_BackfaceMainBlend", 0), ("_DebugView", 0),
            ("_ShadowCasterBias", 0), ("_ShadowCasterBiasView", 0), ("_ShadowCasterNormalBias", 0), ("_QMipBias", 0), ("_QNormalFadeDist", 0),
        };
        // feature switches that come from the source; every other MitToon feature switch is turned off
        static readonly HashSet<string> Kept = new HashSet<string>
        {
            "_UseLayer", "_UseBumpMap", "_UseParallax", "_UseBacklight", "_UseRim", "_UseMatCap", "_UseGlitter",
            "_UseEmission", "_UseAudioLink", "_UseDissolve", "_UseDistanceFade",
        };

        // returns notes about settings that have no exact counterpart (empty when everything carried over)
        public static List<string> Apply(Material m, Snapshot sn)
        {
            var notes = new List<string>();
            string n = sn.shaderName;
            bool outline = n.Contains("Outline");
            bool tess = n.Contains("Tessellation");
            int mode = n.Contains("TwoPassTransparent") ? 5 : n.Contains("Transparent") ? 2 : n.Contains("Cutout") ? 1 : 0;
            int tm = Mathf.RoundToInt(sn.F("_TransparentMode"));
            if (mode == 0 && tm == 1) mode = 1;
            if (mode == 0 && tm == 2) mode = 2;
            if (tm >= 3) notes.Add("屈折 / ファー / 宝石の描画は通常の描画として変換しました");
            var target = Shader.Find(MitToonShaderGUI.ShaderNameFor(outline, MitToonShaderGUI.IsTwoPassMode(mode), tess));
            if (target == null) { notes.Add("MitToon シェーダーが見つかりません"); return notes; }
            m.shader = target;

            // everything MitToon has goes back to its default, then the shared settings are copied over
            var sh = m.shader;
            for (int i = 0; i < sh.GetPropertyCount(); i++)
            {
                string p = sh.GetPropertyName(i);
                var type = sh.GetPropertyType(i);
                switch (type)
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range:
                    case ShaderPropertyType.Int:
                        m.SetFloat(p, sn.f.TryGetValue(p, out var fv) ? fv : sh.GetPropertyDefaultFloatValue(i)); break;
                    case ShaderPropertyType.Color:
                        m.SetColor(p, sn.c.TryGetValue(p, out var cv) ? Space(m, p, sn, p, cv) : (Color)sh.GetPropertyDefaultVectorValue(i)); break;
                    case ShaderPropertyType.Vector:
                        m.SetVector(p, sn.v.TryGetValue(p, out var vv) ? vv : sh.GetPropertyDefaultVectorValue(i)); break;
                    case ShaderPropertyType.Texture:
                        if (sn.t.TryGetValue(p, out var tv)) { m.SetTexture(p, tv.tex); m.SetTextureScale(p, tv.scale); m.SetTextureOffset(p, tv.offset); }
                        else { m.SetTexture(p, null); m.SetTextureScale(p, Vector2.one); m.SetTextureOffset(p, Vector2.zero); }
                        break;
                }
            }
            foreach (var (prop, kw) in MitToonShaderGUI.KeywordMap)
                if (!Kept.Contains(prop) && m.HasProperty(prop)) m.SetFloat(prop, 0);
            foreach (var (p, v) in Neutral) S(m, p, v);

            // ---- translated settings
            V(m, "_CompatAOShift", sn, "_ShadowAOShift");
            // settings that share an existing MitToon slider
            if (!sn.On("_UseShadow")) S(m, "_ShadowStrength", 0);
            S(m, "_QToonAA", sn.F("_AAStrength", 1));
            S(m, "_RimLightDir", sn.F("_RimDirStrength"));
            if (sn.v.TryGetValue("_LightDirectionOverride", out var ld) && ((Vector3)ld).magnitude > 0.01f)
            {
                // the source adds an offset to the light direction; here it becomes a blend toward that direction
                float len = ((Vector3)ld).magnitude;
                var dir = ((Vector3)ld).normalized;
                S4(m, "_LightDirOverride", new Vector4(dir.x, dir.y, dir.z, Mathf.Clamp01(len / (1 + len))));
                if (ld.w != 0) notes.Add("オブジェクト基準のライト方向補正はワールド基準の近い向きにしました");
            }
            T(m, "_ShadowMaskTex", sn, "_ShadowStrengthMask");
            S(m, "_BackfaceFlipNormal", sn.F("_FlipNormal"));
            if (sn.F("_ShadowMaskType") > 0.5f) notes.Add("影マスクの種類 (平面 / SDF) は通常の影として変換しました");
            if (sn.F("_ShadowColorType") > 0.5f) notes.Add("影色の LUT 指定は通常の影色として変換しました");

            // layers
            bool l2 = sn.On("_UseMain2ndTex"), l3 = sn.On("_UseMain3rdTex");
            S(m, "_UseLayer", l2 || l3 ? 1 : 0);
            Layer(m, sn, "2", "2nd", l2);
            Layer(m, sn, "3", "3rd", l3);
            // second normal map
            S(m, "_UseBump2", sn.F("_UseBump2ndMap"));
            T(m, "_Bump2Map", sn, "_Bump2ndMap"); F(m, "_Bump2Scale", sn, "_Bump2ndScale"); T(m, "_Bump2Mask", sn, "_Bump2ndScaleMask");
            if (sn.On("_UseBump2ndMap") && !m.IsKeywordEnabled("_LUMI_NORMALMAP")) S(m, "_UseBumpMap", 1);

            // matcaps: the strength goes into the colour alpha, the blend mode is a separate value
            S(m, "_MatCapBlend", sn.F("_MatCapBlendMode", 1));
            C(m, "_MatCapColor", Space(m, "_MatCapColor", sn, "_MatCapColor", Alpha(sn, "_MatCapColor", sn.F("_MatCapBlend", 1))));
            T(m, "_MatCapMask", sn, "_MatCapBlendMask");
            S(m, "_UseMatCapBump", sn.F("_MatCapCustomNormal"));
            S(m, "_UseMatCap2", sn.F("_UseMatCap2nd"));
            C(m, "_MatCap2Color", Space(m, "_MatCap2Color", sn, "_MatCap2ndColor", Alpha(sn, "_MatCap2ndColor", sn.F("_MatCap2ndBlend", 1))));
            T(m, "_MatCap2Tex", sn, "_MatCap2ndTex"); T(m, "_MatCap2Mask", sn, "_MatCap2ndBlendMask");
            S(m, "_MatCap2Blend", sn.F("_MatCap2ndBlendMode", 1));
            F(m, "_MatCap2Lod", sn, "_MatCap2ndLod"); F(m, "_MatCap2EnableLighting", sn, "_MatCap2ndEnableLighting");
            F(m, "_MatCap2ShadowMask", sn, "_MatCap2ndShadowMask"); F(m, "_MatCap2NormalStrength", sn, "_MatCap2ndNormalStrength");

            // rim: blend modes are numbered differently (0 normal 1 add 2 screen 3 multiply -> 0 add 1 screen 2 multiply 3 replace)
            int rb = Mathf.RoundToInt(sn.F("_RimBlendMode", 1));
            S(m, "_RimBlendMode", rb == 0 ? 3 : rb - 1);
            T(m, "_RimTex", sn, "_RimColorTex");
            // backlight
            T(m, "_BacklightMask", sn, "_BacklightColorTex");
            // textures of features drawn differently or not at all: kept in the matching MitToon slot so nothing is dropped
            T(m, "_GlitterMask", sn, "_GlitterColorTex");
            T(m, "_AnisoMask", sn, "_AnisotropyScaleMask"); T(m, "_AnisoShiftMap", sn, "_AnisotropyShiftNoiseMask");
            T(m, "_SmoothnessMap", sn, "_SmoothnessTex"); T(m, "_MetallicMap", sn, "_MetallicGlossMap");
            T(m, "_DissolveNoise", sn, "_DissolveNoiseMask");

            // emission: mask, blink (strength, type, speed, phase -> strength, speed, phase, square), blend amount into the alpha
            T(m, "_EmissionMask", sn, "_EmissionBlendMask");
            S4(m, "_EmissionBlink", Blink(sn, "_EmissionBlink"));
            C(m, "_EmissionColor", Space(m, "_EmissionColor", sn, "_EmissionColor", Alpha(sn, "_EmissionColor", sn.F("_EmissionBlend", 1))));
            Scroll(m, "_EmissionScroll", sn, "_EmissionMap_ScrollRotate");
            S(m, "_UseEmission2", sn.F("_UseEmission2nd"));
            C(m, "_Emission2Color", Space(m, "_Emission2Color", sn, "_Emission2ndColor", Alpha(sn, "_Emission2ndColor", sn.F("_Emission2ndBlend", 1))));
            T(m, "_Emission2Map", sn, "_Emission2ndMap"); T(m, "_Emission2Mask", sn, "_Emission2ndBlendMask");
            S4(m, "_Emission2Blink", Blink(sn, "_Emission2ndBlink"));
            S(m, "_Emission2UV", sn.F("_Emission2ndMap_UVMode") > 0.5f ? 1 : 0);
            Scroll(m, "_Emission2Scroll", sn, "_Emission2ndMap_ScrollRotate");
            if ((sn.On("_UseEmission") && sn.F("_EmissionBlendMode", 1) != 1) || (sn.On("_UseEmission2nd") && sn.F("_Emission2ndBlendMode", 1) != 1))
                notes.Add("発光の合成モードは加算として変換しました");
            if (sn.On("_EmissionUseGrad") || sn.On("_Emission2ndUseGrad")) notes.Add("発光のグラデーションは変換していません");

            // not carried over (no counterpart in the compatible mode)
            if (sn.On("_UseReflection")) notes.Add("反射 (スペキュラ / 映り込み) は変換していません");
            if (sn.On("_UseAnisotropy")) notes.Add("異方性反射は変換していません");
            if (sn.On("_UseGlitter")) notes.Add("ラメは MitToon のラメに置き換えました (見た目が少し変わります)");
            if (sn.F("_MainGradationStrength") > 0) notes.Add("メインのグラデーションマップは変換していません");
            if (sn.On("_UseDither")) notes.Add("ディザ透過は変換していません");

            // render mode, then the source's own render states
            S(m, "_RenderMode", mode);
            MitToonShaderGUI.ApplyRenderMode(m, true);
            foreach (var p in new[] { "_Cull", "_ZWrite", "_ZTest", "_AlphaToMask", "_OffsetFactor", "_OffsetUnits" })
                if (sn.f.ContainsKey(p)) S(m, p, sn.f[p]);
            // the source mixes extra (point / spot) lights with its own blend, usually Max, so overlapping lights do not burn out
            foreach (var (from, to) in new[] { ("_SrcBlendFA", "_SrcBlendAdd"), ("_DstBlendFA", "_DstBlendAdd"), ("_BlendOpFA", "_BlendOpAdd") })
                if (sn.f.ContainsKey(from)) S(m, to, sn.f[from]);
            if (mode != 0 || sn.renderQueue != m.shader.renderQueue) m.renderQueue = sn.renderQueue;
            MitToonShaderGUI.SyncKeywords(m);
            return notes;
        }

        static void Layer(Material m, Snapshot sn, string d, string s, bool on)
        {
            S(m, "_UseMain" + d, on ? 1 : 0);
            C(m, "_Main" + d + "Color", sn.c.TryGetValue("_Color" + s, out var c) ? Space(m, "_Main" + d + "Color", sn, "_Color" + s, c) : Color.white);
            T(m, "_Main" + d + "Tex", sn, "_Main" + s + "Tex");
            T(m, "_Main" + d + "Mask", sn, "_Main" + s + "BlendMask");
            F(m, "_Main" + d + "Blend", sn, "_Main" + s + "TexBlendMode");
            S(m, "_Main" + d + "UV", sn.F("_Main" + s + "Tex_UVMode") > 0.5f ? 1 : 0);
            F(m, "_Main" + d + "Decal", sn, "_Main" + s + "TexIsDecal");
            Scroll(m, "_Main" + d + "Scroll", sn, "_Main" + s + "Tex_ScrollRotate");
        }

        static Vector4 Blink(Snapshot sn, string p)
        {
            var b = sn.v.TryGetValue(p, out var x) ? x : new Vector4(0, 0, Mathf.PI, 0);
            return new Vector4(b.x, b.z, b.w, b.y);
        }
        static Color Alpha(Snapshot sn, string p, float k)
        {
            var c = sn.c.TryGetValue(p, out var x) ? x : Color.white;
            c.a *= k; return c;
        }
        static void Scroll(Material m, string to, Snapshot sn, string from)
        {
            if (!m.HasProperty(to) || !sn.v.TryGetValue(from, out var v)) return;
            m.SetVector(to, new Vector4(v.x, v.y, v.w, 0));
        }
        // Unity hands an [HDR] colour to the shader as stored, a plain colour converted to linear; when only one side
        // is [HDR] the stored value is converted so the shader gets the same number as before
        static Color Space(Material m, string to, Snapshot sn, string from, Color c)
        {
            if (QualitySettings.activeColorSpace != ColorSpace.Linear) return c;
            int i = m.shader.FindPropertyIndex(to);
            if (i < 0) return c;
            bool hdrTo = (m.shader.GetPropertyFlags(i) & ShaderPropertyFlags.HDR) != 0;
            if (hdrTo == sn.hdr.Contains(from)) return c;
            return hdrTo ? c.linear : c.gamma;
        }
        static void S(Material m, string p, float v) { if (m.HasProperty(p)) m.SetFloat(p, v); }
        static void S4(Material m, string p, Vector4 v) { if (m.HasProperty(p)) m.SetVector(p, v); }
        static void C(Material m, string p, Color c) { if (m.HasProperty(p)) m.SetColor(p, c); }
        static void F(Material m, string to, Snapshot sn, string from) { if (sn.f.TryGetValue(from, out var v)) S(m, to, v); }
        static void V(Material m, string to, Snapshot sn, string from) { if (sn.v.TryGetValue(from, out var v)) S4(m, to, v); }
        static void T(Material m, string to, Snapshot sn, string from)
        {
            if (!m.HasProperty(to) || !sn.t.TryGetValue(from, out var t)) return;
            m.SetTexture(to, t.tex); m.SetTextureScale(to, t.scale); m.SetTextureOffset(to, t.offset);
        }

        // ------------------------------------------------------------------ menu
        [MenuItem("Tools/MitToon/選択中の lilToon マテリアルを MitToon に変換 (見た目を保つ)")]
        static void ConvertSelected()
        {
            var mats = new HashSet<Material>();
            foreach (var o in Selection.objects)
            {
                if (o is Material mm) mats.Add(mm);
                else if (o is GameObject g)
                    foreach (var r in g.GetComponentsInChildren<Renderer>(true))
                        foreach (var sm in r.sharedMaterials) if (sm != null) mats.Add(sm);
            }
            foreach (var guid in Selection.assetGUIDs)
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                if (AssetDatabase.IsValidFolder(path))
                    foreach (var g in AssetDatabase.FindAssets("t:Material", new[] { path }))
                    {
                        var mm = AssetDatabase.LoadAssetAtPath<Material>(AssetDatabase.GUIDToAssetPath(g));
                        if (mm != null) mats.Add(mm);
                    }
            }
            var targets = mats.Where(x => IsSource(x.shader)).ToList();
            if (targets.Count == 0) { EditorUtility.DisplayDialog("MitToon", "変換できるマテリアルが選択されていません。", "OK"); return; }
            if (!EditorUtility.DisplayDialog("MitToon", targets.Count + " 個のマテリアルを MitToon に変換します。元に戻すには Ctrl+Z を使ってください。", "変換", "キャンセル")) return;
            Undo.RecordObjects(targets.ToArray(), "MitToon convert");
            int noted = 0;
            foreach (var mt in targets)
            {
                var notes = Apply(mt, Take(mt));
                EditorUtility.SetDirty(mt);
                if (notes.Count > 0) { noted++; Debug.Log("MitToon: " + mt.name + "\n  " + string.Join("\n  ", notes), mt); }
            }
            AssetDatabase.SaveAssets();
            Debug.Log($"MitToon: {targets.Count} 個のマテリアルを変換しました" + (noted > 0 ? $" (うち {noted} 個は一部の設定に近い値を使っています。詳細は上のログ)" : ""));
        }
        [MenuItem("Tools/MitToon/選択中の lilToon マテリアルを MitToon に変換 (見た目を保つ)", true)]
        static bool ConvertSelectedValid() => Selection.objects.Length > 0;

        [MenuItem("CONTEXT/Material/lilToon から MitToon に変換 (見た目を保つ)")]
        static void ConvertContext(MenuCommand cmd)
        {
            var m = cmd.context as Material;
            if (m == null || !IsSource(m.shader)) { EditorUtility.DisplayDialog("MitToon", "このマテリアルは変換に対応していません。", "OK"); return; }
            Undo.RecordObject(m, "MitToon convert");
            var notes = Apply(m, Take(m));
            EditorUtility.SetDirty(m);
            if (notes.Count > 0) Debug.Log("MitToon: " + m.name + "\n  " + string.Join("\n  ", notes), m);
        }
    }
}
