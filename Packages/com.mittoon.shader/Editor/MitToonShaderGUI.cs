using System;
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace MitToon.Editor
{
    // Module style inspector: categories, toggleable modules with a "⋮" menu (reset / copy / paste),
    // nested sub modules, expandable texture rows and a property search bar.
    public class MitToonShaderGUI : ShaderGUI
    {
        public const string BaseShaderName = "MitToon/MitToon";
        public const string OutlineShaderName = "MitToon/MitToon Outline";
        public const string TwoPassShaderName = "MitToon/MitToon TwoPass";
        public const string OutlineTwoPassShaderName = "MitToon/MitToon Outline TwoPass";
        public const string TessSuffix = " Tessellation";
        public static bool IsOutlineShader(Shader s) => s != null && s.name.StartsWith("MitToon/MitToon Outline");
        public static bool IsTessShader(Shader s) => s != null && s.name.StartsWith("MitToon/") && s.name.EndsWith(TessSuffix);
        public static bool IsTwoPassMode(int mode) => mode == 5 || mode == 6;
        public static string ShaderNameFor(bool outline, bool twoPass, bool tess = false) =>
            (outline ? (twoPass ? OutlineTwoPassShaderName : OutlineShaderName) : (twoPass ? TwoPassShaderName : BaseShaderName)) + (tess ? TessSuffix : "");
        public static readonly string[] AllShaderNames =
        {
            BaseShaderName, OutlineShaderName, TwoPassShaderName, OutlineTwoPassShaderName,
            BaseShaderName + TessSuffix, OutlineShaderName + TessSuffix, TwoPassShaderName + TessSuffix, OutlineTwoPassShaderName + TessSuffix,
        };
        public const string Version = "1.0";
        static readonly Color Accent = new Color(0.36f, 0.62f, 1f);

        public static bool JP
        {
            get => EditorPrefs.GetBool("MitToon.JP", true);
            set => EditorPrefs.SetBool("MitToon.JP", value);
        }

        public static readonly (string prop, string kw)[] KeywordMap =
        {
            ("_UseLayer", "_LUMI_LAYER"), ("_UseBumpMap", "_LUMI_NORMALMAP"), ("_UseDetail", "_LUMI_DETAIL"),
            ("_UseParallax", "_LUMI_PARALLAX"), ("_UseSSAO", "_LUMI_SSAO"), ("_UseSoftShadow", "_LUMI_SOFTSHADOW"),
            ("_UseContactShadow", "_LUMI_CONTACTSHADOW"), ("_UseSSS", "_LUMI_SSS"), ("_UseBacklight", "_LUMI_BACKLIGHT"),
            ("_UseAniso", "_LUMI_ANISO"), ("_UseSheen", "_LUMI_SHEEN"), ("_UseClearCoat", "_LUMI_CLEARCOAT"),
            ("_UseRim", "_LUMI_RIM"), ("_UseMatCap", "_LUMI_MATCAP"),
            ("_UseGlitter", "_LUMI_GLITTER"), ("_UseEmission", "_LUMI_EMISSION"), ("_UseAudioLink", "_LUMI_AUDIOLINK"),
            ("_UseDissolve", "_LUMI_DISSOLVE"), ("_UseDistanceFade", "_LUMI_DISTFADE"), ("_UseTonemap", "_LUMI_TONEMAP"), ("_UseFaceSDF", "_LUMI_FACESDF"),
            ("_UseLightVolumes", "_LUMI_LIGHTVOLUMES"), ("_UseSphereNormal", "_LUMI_SPHERENORMAL"), ("_UseOffsetRim", "_LUMI_OFFSETRIM"),
            ("_UseCurvature", "_LUMI_CURVATURE"), ("_UseIridescence", "_LUMI_IRIDESCENCE"), ("_UseBounce", "_LUMI_BOUNCE"),
            ("_UseFillLight", "_LUMI_FILLLIGHT"), ("_UseGradient", "_LUMI_GRADIENT"), ("_UseHatch", "_LUMI_HATCH"),
            ("_UseAngelRing", "_LUMI_ANGELRING"), ("_UseHologram", "_LUMI_HOLOGRAM"), ("_CompatShading", "_LUMI_COMPAT"),
            ("_UseDepthShadow", "_LUMI_DEPTHSHADOW"), ("_UseInkLine", "_LUMI_INKLINE"), ("_UseFPSMode", "_LUMI_FPSMODE"),
        };

        const string LightVolumesInclude = "Packages/red.sim.lightvolumes/Shaders/LightVolumes.cginc";
        static bool? lvInstalled;
        public static bool LightVolumesInstalled
        {
            get
            {
                if (lvInstalled == null) lvInstalled = System.IO.File.Exists(System.IO.Path.GetFullPath(LightVolumesInclude));
                return lvInstalled.Value;
            }
        }

        MaterialEditor me;
        MaterialProperty[] props;
        bool collecting;
        readonly List<string> stack = new List<string>();
        readonly List<bool> showAllStack = new List<bool>();
        static Dictionary<string, List<string>> sectionProps;
        static readonly Dictionary<string, string> sectionToggle = new Dictionary<string, string>();
        static readonly Dictionary<string, Dictionary<string, object>> clipboard = new Dictionary<string, Dictionary<string, object>>();
        static string search = "";
        static GUIStyle moduleStyle, subModuleStyle, headerLabel, subHeaderLabel, categoryStyle, subStyle, boxStyle, subBoxStyle, menuStyle, titleStyle;

        class TexValue { public Texture tex; public Vector4 st; }

        // ================================================================== helpers
        static string T(string jp, string en) => Bare(JP ? jp : en);
        // labels are shown without the notes in brackets: "速度 (fps)" -> "速度"
        static readonly Dictionary<string, string> bareCache = new Dictionary<string, string>();
        public static string Bare(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            if (bareCache.TryGetValue(s, out var r)) return r;
            r = s;
            string prev;
            do { prev = r; r = System.Text.RegularExpressions.Regex.Replace(r, @"\s*[(（][^()（）]*[)）]", ""); } while (r != prev);
            r = r.Trim();
            if (r.Length == 0) r = s;
            bareCache[s] = r;
            return r;
        }
        // name lookup: the inspector asks for hundreds of properties per repaint, a linear search each time was slow
        readonly Dictionary<string, MaterialProperty> propMap = new Dictionary<string, MaterialProperty>();
        MaterialProperty[] propMapFor;
        MaterialProperty P(string n)
        {
            if (!ReferenceEquals(propMapFor, props))
            {
                propMap.Clear();
                if (props != null) foreach (var p in props) if (p != null) propMap[p.name] = p;
                propMapFor = props;
            }
            return n != null && propMap.TryGetValue(n, out var r) ? r : null;
        }
        static readonly Dictionary<string, GUIContent[]> labelCache = new Dictionary<string, GUIContent[]>();
        static GUIContent Label(MaterialProperty p)
        {
            if (!labelCache.TryGetValue(p.displayName, out var l))
            {
                var s = p.displayName.Split('|');
                l = new[] { new GUIContent(Bare(s[0])), new GUIContent(Bare(s.Length < 2 ? s[0] : s[1])) };
                labelCache[p.displayName] = l;
            }
            return JP ? l[0] : l[1];
        }
        bool Searching => !collecting && !string.IsNullOrEmpty(search);
        bool ShowAll => showAllStack.Count > 0 && showAllStack[showAllStack.Count - 1];
        static bool TextMatch(string text) => text.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0;
        static bool Matches(MaterialProperty p) => p != null && (TextMatch(p.displayName) || TextMatch(p.name));
        void Register(string n)
        {
            if (string.IsNullOrEmpty(n)) return;
            foreach (var id in stack)
            {
                if (!sectionProps.TryGetValue(id, out var l)) sectionProps[id] = l = new List<string>();
                if (!l.Contains(n)) l.Add(n);
            }
        }
        bool Show(MaterialProperty p)
        {
            if (p == null) return false;
            if (collecting) { Register(p.name); return false; }
            return !Searching || ShowAll || Matches(p);
        }
        bool When(bool c) => collecting || Searching || c;
        float F(string n) { var p = P(n); return p != null ? p.floatValue : 0; }

        void Prop(string n) { var p = P(n); if (Show(p)) me.ShaderProperty(p, Label(p)); }
        void Props(params string[] ns) { foreach (var n in ns) Prop(n); }
        bool Toggle(string n)
        {
            var p = P(n);
            if (Show(p)) me.ShaderProperty(p, Label(p));
            return collecting || (p != null && p.floatValue > 0.5f);
        }
        void Sub(string jp, string en)
        {
            if (collecting || Searching) return;
            EditorGUILayout.Space(3);
            EditorGUILayout.LabelField(T(jp, en), subStyle);
        }
        void Info(string jp, string en, MessageType type = MessageType.Info)
        {
            if (collecting || Searching) return;
            if (type != MessageType.Warning && type != MessageType.Error) return;   // explanations are not shown, only warnings
            EditorGUILayout.HelpBox(T(jp, en), type);
        }

        void Vec(string n, string[] labels, float[] min, float[] max)
        {
            var p = P(n);
            if (!Show(p)) return;
            EditorGUILayout.LabelField(Label(p));
            EditorGUI.indentLevel++;
            var v = p.vectorValue;
            EditorGUI.BeginChangeCheck();
            EditorGUI.showMixedValue = p.hasMixedValue;
            for (int i = 0; i < labels.Length; i++)
                v[i] = min[i] < max[i] ? EditorGUILayout.Slider(labels[i], v[i], min[i], max[i]) : EditorGUILayout.FloatField(labels[i], v[i]);
            EditorGUI.showMixedValue = false;
            if (EditorGUI.EndChangeCheck()) p.vectorValue = v;
            EditorGUI.indentLevel--;
        }
        void ScrollVec(string n) => Vec(n, new[] { T("横スクロール", "Scroll X"), T("縦スクロール", "Scroll Y"), T("回転 (rad)", "Rotation (rad)") },
                                        new[] { 0f, 0f, -3.1416f }, new[] { 0f, 0f, 3.1416f });
        void BlinkVec(string n) => Vec(n, new[] { T("強度", "Strength"), T("速さ", "Speed"), T("位相", "Phase"), T("矩形波", "Square") },
                                       new[] { 0f, 0f, 0f, 0f }, new[] { 1f, 20f, 6.283f, 1f });

        // Texture row with a ▶ to reveal tiling and related options
        void Tex(string n, string extra = null, params string[] sub)
        {
            var p = P(n);
            if (p == null) return;
            var e = extra != null ? P(extra) : null;
            if (collecting)
            {
                Register(n); if (e != null) Register(extra);
                foreach (var s in sub) Register(s.Contains(":") ? s.Substring(s.IndexOf(':') + 1) : s);
                return;
            }
            if (Searching && !ShowAll && !Matches(p) && !Matches(e) && !sub.Any(s => Matches(P(s.Contains(":") ? s.Substring(s.IndexOf(':') + 1) : s)))) return;

            bool hasST = (p.flags & MaterialProperty.PropFlags.NoScaleOffset) == 0;
            var r = me.TexturePropertySingleLine(Label(p), p, e);
            if (!hasST && sub.Length == 0) return;
            string key = "MitToon.TexFold." + n;
            bool open = Searching || SessionState.GetBool(key, false);
            bool now = EditorGUI.Foldout(new Rect(r.x - 13, r.y + 2, 13, 14), open, GUIContent.none, true);
            if (now != open && !Searching) SessionState.SetBool(key, now);
            if (!now) return;
            EditorGUI.indentLevel += 2;
            if (hasST) me.TextureScaleOffsetProperty(p);
            foreach (var s in sub)
            {
                if (s.StartsWith("scroll:")) ScrollVec(s.Substring(7));
                else if (s.StartsWith("blink:")) BlinkVec(s.Substring(6));
                else { var sp = P(s); if (sp != null) me.ShaderProperty(sp, Label(sp)); }
            }
            EditorGUI.indentLevel -= 2;
            EditorGUILayout.Space(2);
        }

        // ================================================================== modules
        void Category(string jp, string en)
        {
            if (collecting || Searching) return;
            EditorGUILayout.Space(8);
            var r = GUILayoutUtility.GetRect(16, 18, GUILayout.ExpandWidth(true));
            GUI.Label(r, T(jp, en), categoryStyle);
            EditorGUI.DrawRect(new Rect(r.x, r.yMax - 1, r.width, 1), new Color(Accent.r, Accent.g, Accent.b, 0.45f));
            EditorGUILayout.Space(2);
        }

        bool Module(string id, string jp, string en, string toggle = null, bool sub = false, bool defaultOpen = false,
                    Func<bool> customGet = null, Action<bool> customSet = null)
        {
            if (collecting)
            {
                stack.Add(id);
                if (toggle != null) { sectionToggle[id] = toggle; Register(toggle); }
                return true;
            }
            bool titleMatch = false;
            if (Searching)
            {
                titleMatch = ShowAll || TextMatch(jp) || TextMatch(en);
                bool any = sectionProps.TryGetValue(id, out var l) && l.Any(n => Matches(P(n)));
                if (!titleMatch && !any) return false;
            }

            var rect = GUILayoutUtility.GetRect(16, sub ? 20 : 24, GUILayout.ExpandWidth(true));
            if (sub) rect.xMin += 6;
            string key = "MitToon.Fold." + id;
            bool open = Searching || EditorPrefs.GetBool(key, defaultOpen);
            var tp = toggle != null ? P(toggle) : null;
            bool hasToggle = tp != null || customGet != null;
            bool enabled = customGet != null ? customGet() : (tp == null || tp.floatValue > 0.5f);

            GUI.Box(rect, GUIContent.none, sub ? subModuleStyle : moduleStyle);
            if (hasToggle) EditorGUI.DrawRect(new Rect(rect.x + 1, rect.y + 2, 3, rect.height - 4), enabled ? Accent : new Color(0.5f, 0.5f, 0.5f, 0.6f));

            float x = rect.x + 20;
            if (hasToggle)
            {
                if (tp != null) EditorGUI.showMixedValue = tp.hasMixedValue;
                EditorGUI.BeginChangeCheck();
                bool v = EditorGUI.Toggle(new Rect(x, rect.y + (rect.height - 16) * 0.5f, 16, 16), enabled);
                EditorGUI.showMixedValue = false;
                if (EditorGUI.EndChangeCheck())
                {
                    if (customSet != null) customSet(v);
                    else
                    {
                        tp.floatValue = v ? 1 : 0;
                        foreach (var t in me.targets) SyncKeywords((Material)t);
                    }
                    if (v) { open = true; EditorPrefs.SetBool(key, true); }
                    enabled = v;
                }
                x += 18;
            }
            bool hasPresets = MitToonSectionPresets.Modules.ContainsKey(id);
            float presetW = hasPresets ? EditorStyles.miniButton.CalcSize(new GUIContent(T("プリセット ▾", "Preset ▾"))).x + 6 : 0;
            var cc = GUI.contentColor;
            if (!enabled) GUI.contentColor = new Color(1, 1, 1, 0.5f);
            GUI.Label(new Rect(x, rect.y, rect.xMax - x - 26 - presetW, rect.height), T(jp, en), sub ? subHeaderLabel : headerLabel);
            GUI.contentColor = cc;

            var targets = me.targets.Cast<Material>().ToArray();
            if (hasPresets && GUI.Button(new Rect(rect.xMax - 24 - presetW, rect.y + (rect.height - 16) * 0.5f, presetW, 16), T("プリセット ▾", "Preset ▾"), EditorStyles.miniButton))
                PresetMenu(targets, id, toggle, null);
            if (GUI.Button(new Rect(rect.xMax - 22, rect.y + (rect.height - 18) * 0.5f, 20, 18), "⋮", menuStyle))
                ModuleMenu(targets, id, toggle);
            var ev = Event.current;
            if (ev.type == EventType.Repaint)
                EditorStyles.foldout.Draw(new Rect(rect.x + 5, rect.y + (rect.height - 13) * 0.5f, 13, 13), false, false, open, false);
            if (ev.type == EventType.MouseDown && rect.Contains(ev.mousePosition))
            {
                if (ev.button == 1) { ModuleMenu(targets, id, toggle); ev.Use(); }
                else if (ev.button == 0 && !Searching) { open = !open; EditorPrefs.SetBool(key, open); ev.Use(); }
            }
            if (!open) return false;

            showAllStack.Add(ShowAll || titleMatch);
            EditorGUILayout.BeginVertical(sub ? subBoxStyle : boxStyle);
            EditorGUI.BeginDisabledGroup(!enabled);
            return true;
        }

        void EndModule()
        {
            if (collecting) { stack.RemoveAt(stack.Count - 1); return; }
            EditorGUI.EndDisabledGroup();
            EditorGUILayout.EndVertical();
            showAllStack.RemoveAt(showAllStack.Count - 1);
        }

        void ModuleMenu(Material[] targets, string id, string toggle)
        {
            var menu = new GenericMenu();
            if (MitToonSectionPresets.Modules.ContainsKey(id))
            {
                PresetMenu(targets, id, toggle, menu);
                menu.AddSeparator("");
            }
            menu.AddItem(new GUIContent(T("リセット (既定値に戻す)", "Reset to defaults")), false, () =>
            {
                Undo.RecordObjects(targets, "MitToon Reset Module");
                foreach (var m in targets) ResetSection(m, id, toggle);
            });
            menu.AddItem(new GUIContent(T("コピー", "Copy")), false, () => clipboard[id] = CopySection(targets[0], id));
            if (clipboard.ContainsKey(id))
                menu.AddItem(new GUIContent(T("ペースト", "Paste")), false, () =>
                {
                    Undo.RecordObjects(targets, "MitToon Paste Module");
                    foreach (var m in targets) PasteSection(m, clipboard[id]);
                });
            else menu.AddDisabledItem(new GUIContent(T("ペースト", "Paste")));
            menu.AddSeparator("");
            menu.AddItem(new GUIContent(T("このモジュールだけ開く", "Open only this module")), false, () =>
            {
                foreach (var k in sectionProps.Keys) EditorPrefs.SetBool("MitToon.Fold." + k, k == id);
            });
            menu.ShowAsContext();
        }

        // per module presets: switch the module on (when it has a toggle) and set its values
        void PresetMenu(Material[] targets, string id, string toggle, GenericMenu into)
        {
            var menu = into ?? new GenericMenu();
            string prefix = into != null ? T("プリセット/", "Presets/") : "";
            foreach (var it in MitToonSectionPresets.Modules[id])
            {
                var item = it;
                menu.AddItem(new GUIContent(prefix + T(item.jp, item.en)), false, () =>
                {
                    Undo.RecordObjects(targets, "MitToon Module Preset");
                    foreach (var m in targets)
                    {
                        if (toggle != null && m.HasProperty(toggle)) m.SetFloat(toggle, 1);
                        item.apply(m);
                        SyncKeywords(m);
                        EditorUtility.SetDirty(m);
                    }
                    EditorPrefs.SetBool("MitToon.Fold." + id, true);
                });
            }
            if (into == null) menu.ShowAsContext();
        }

        static void ResetSection(Material m, string id, string toggle)
        {
            if (!sectionProps.TryGetValue(id, out var names)) return;
            var sh = m.shader;
            foreach (var n in names)
            {
                if (n == toggle || n == "_CompatShading") continue;   // the shared shading model is not part of one section
                int i = sh.FindPropertyIndex(n);
                if (i < 0) continue;
                switch (sh.GetPropertyType(i))
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range: m.SetFloat(n, sh.GetPropertyDefaultFloatValue(i)); break;
                    case ShaderPropertyType.Color: m.SetColor(n, sh.GetPropertyDefaultVectorValue(i)); break;
                    case ShaderPropertyType.Vector: m.SetVector(n, sh.GetPropertyDefaultVectorValue(i)); break;
                    case ShaderPropertyType.Texture:
                        m.SetTexture(n, null);
                        m.SetTextureScale(n, Vector2.one);
                        m.SetTextureOffset(n, Vector2.zero);
                        break;
                }
            }
            SyncKeywords(m);
        }

        static Dictionary<string, object> CopySection(Material m, string id)
        {
            var d = new Dictionary<string, object>();
            if (!sectionProps.TryGetValue(id, out var names)) return d;
            var sh = m.shader;
            foreach (var n in names)
            {
                int i = sh.FindPropertyIndex(n);
                if (i < 0) continue;
                switch (sh.GetPropertyType(i))
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range: d[n] = m.GetFloat(n); break;
                    case ShaderPropertyType.Color: d[n] = m.GetColor(n); break;
                    case ShaderPropertyType.Vector: d[n] = m.GetVector(n); break;
                    case ShaderPropertyType.Texture:
                        var s = m.GetTextureScale(n); var o = m.GetTextureOffset(n);
                        d[n] = new TexValue { tex = m.GetTexture(n), st = new Vector4(s.x, s.y, o.x, o.y) };
                        break;
                }
            }
            return d;
        }

        static void PasteSection(Material m, Dictionary<string, object> d)
        {
            foreach (var kv in d)
            {
                if (!m.HasProperty(kv.Key)) continue;
                switch (kv.Value)
                {
                    case float f: m.SetFloat(kv.Key, f); break;
                    case Color c: m.SetColor(kv.Key, c); break;
                    case Vector4 v: m.SetVector(kv.Key, v); break;
                    case TexValue t:
                        m.SetTexture(kv.Key, t.tex);
                        m.SetTextureScale(kv.Key, new Vector2(t.st.x, t.st.y));
                        m.SetTextureOffset(kv.Key, new Vector2(t.st.z, t.st.w));
                        break;
                }
            }
            SyncKeywords(m);
        }

        // ================================================================== GUI entry
        static void InitStyles()
        {
            if (moduleStyle != null) return;
            moduleStyle = new GUIStyle("ShurikenModuleTitle") { fixedHeight = 0, border = new RectOffset(15, 7, 4, 4) };
            subModuleStyle = new GUIStyle(moduleStyle);
            headerLabel = new GUIStyle(EditorStyles.boldLabel) { fontSize = 12, alignment = TextAnchor.MiddleLeft };
            subHeaderLabel = new GUIStyle(EditorStyles.boldLabel) { fontSize = 11, alignment = TextAnchor.MiddleLeft };
            categoryStyle = new GUIStyle(EditorStyles.miniBoldLabel) { fontSize = 11, normal = { textColor = Accent } };
            subStyle = new GUIStyle(EditorStyles.miniBoldLabel) { normal = { textColor = Accent } };
            boxStyle = new GUIStyle(EditorStyles.helpBox) { padding = new RectOffset(16, 6, 6, 6), margin = new RectOffset(4, 4, 0, 4) };
            subBoxStyle = new GUIStyle(boxStyle) { margin = new RectOffset(10, 2, 0, 4) };
            menuStyle = new GUIStyle(EditorStyles.label) { alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
            titleStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 15, normal = { textColor = Color.white } };
        }

        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            me = materialEditor;
            props = properties;
            var mat = (Material)me.target;
            InitStyles();

            if (sectionProps == null)
            {
                sectionProps = new Dictionary<string, List<string>>();
                collecting = true;
                try { DrawAll(mat); }
                finally { collecting = false; stack.Clear(); }
            }
            showAllStack.Clear();
            DrawTitle();
            DrawSearch();
            DrawAll(mat);
            DrawFooter();
        }

        void DrawAll(Material mat)
        {
            DrawQuick(mat);
            DrawBase(mat);

            Category("カラー", "Color");
            DrawMain();
            DrawLayers();
            DrawBackface();

            Category("ノーマル & 凹凸", "Normals & Height");
            DrawNormal();

            Category("影", "Shadows");
            DrawShadow();
            DrawScreenSpace();
            DrawFace();
            DrawEyeGuard();

            Category("ライティング", "Lighting");
            DrawLighting();
            DrawRichness();
            DrawQuality();

            Category("素材", "Surface");
            DrawPBR();
            DrawAniso();
            DrawCloth();
            DrawSkin();
            DrawAngelRing();

            Category("マットキャップ & リム", "MatCap & Rim");
            DrawMatCap();
            DrawRim();

            Category("発光", "Emission");
            DrawEmission();
            DrawGlitter();
            DrawFlipbook();

            Category("エフェクト", "Effects");
            DrawProcedural();
            DrawRefraction();
            DrawDissolve();

            Category("形状 & 動き", "Shape & Motion");
            DrawTessellation(mat);
            DrawWobble();
            DrawFPS();

            Category("アウトライン", "Outlines");
            DrawOutline(mat);

            Category("仕上げ", "Finishing");
            DrawGrading();
            DrawCharControl();

            Category("レンダリング", "Rendering");
            DrawVisibility();
            DrawAdvanced();

            Category("ツール", "Tools");
            DrawMaskPaintTool();
        }

        void DrawTitle()
        {
            var r = GUILayoutUtility.GetRect(16, 32, GUILayout.ExpandWidth(true));
            EditorGUI.DrawRect(r, new Color(0.12f, 0.15f, 0.24f));
            EditorGUI.DrawRect(new Rect(r.x, r.yMax - 2, r.width, 2), Accent);
            GUI.Label(new Rect(r.x + 8, r.y + 6, 160, 20), "MitToon Shader", titleStyle);
            GUI.Label(new Rect(r.x + 126, r.y + 10, 60, 16), "v" + Version, EditorStyles.miniLabel);
            float langW = Mathf.Max(GUI.skin.button.CalcSize(new GUIContent("日本語")).x + 6, 44) * 2;
            int lang = GUI.Toolbar(new Rect(r.xMax - 96 - langW, r.y + 7, langW, 18), JP ? 0 : 1, new[] { "日本語", "EN" });
            if (lang != (JP ? 0 : 1)) JP = lang == 0;
            if (GUI.Button(new Rect(r.xMax - 90, r.y + 7, 84, 18), T("プリセット ▼", "Presets ▼")))
            {
                var targets = me.targets.Cast<Material>().ToArray();
                var menu = new GenericMenu();
                foreach (var pr in MitToonPresets.All)
                {
                    var id = pr.id;
                    menu.AddItem(new GUIContent((JP ? pr.category.jp : pr.category.en) + "/" + (JP ? pr.jp : pr.en)), false, () =>
                    {
                        Undo.RecordObjects(targets, "MitToon Preset");
                        foreach (var m in targets) MitToonPresets.Apply(m, id);
                    });
                }
                menu.ShowAsContext();
            }
            EditorGUILayout.Space(3);
        }

        void DrawSearch()
        {
            EditorGUILayout.BeginHorizontal();
            search = EditorGUILayout.TextField(search, EditorStyles.toolbarSearchField);
            if (GUILayout.Button("×", EditorStyles.miniButton, GUILayout.Width(22))) { search = ""; GUI.FocusControl(null); }
            EditorGUILayout.EndHorizontal();
            if (Searching) EditorGUILayout.LabelField(T("検索中: 一致する項目だけを表示しています", "Searching: showing matching properties only"), EditorStyles.centeredGreyMiniLabel);
            EditorGUILayout.Space(2);
        }

        void DrawFooter()
        {
            EditorGUILayout.Space(10);
            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button(T("すべて閉じる", "Collapse all")))
                foreach (var k in sectionProps.Keys) EditorPrefs.SetBool("MitToon.Fold." + k, false);
            if (GUILayout.Button(T("無効モジュールのテクスチャを外す", "Strip textures of disabled modules")))
            {
                if (EditorUtility.DisplayDialog("MitToon",
                    T("OFF になっているモジュールのテクスチャ参照を外します (アップロードサイズ削減)。よろしいですか?",
                      "Remove texture references used only by disabled modules (smaller uploads)?"), "OK", T("キャンセル", "Cancel")))
                {
                    var targets = me.targets.Cast<Material>().ToArray();
                    Undo.RecordObjects(targets, "MitToon Strip Textures");
                    foreach (var m in targets) StripDisabledTextures(m);
                }
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.BeginHorizontal();
            if (GUILayout.Button(new GUIContent(T("全設定をコピー (テクスチャ以外)", "Copy all settings (no textures)"),
                    T("テクスチャとノーマルマップ以外の全パラメータ・描画モード・アウトライン有無・キューをクリップボードへ", "Every value except textures / normal maps, plus render mode, outline and queue"))))
            {
                EditorGUIUtility.systemCopyBuffer = SerializeSettings((Material)me.target);
                Debug.Log("[MitToon] " + T("設定をコピーしました", "Settings copied"));
            }
            using (new EditorGUI.DisabledScope(!(EditorGUIUtility.systemCopyBuffer ?? "").StartsWith(SettingsHeader)))
            {
                if (GUILayout.Button(T("全設定を貼り付け", "Paste all settings")))
                {
                    var targets = me.targets.Cast<Material>().ToArray();
                    Undo.RecordObjects(targets, "MitToon Paste Settings");
                    foreach (var m in targets) PasteSettings(m, EditorGUIUtility.systemCopyBuffer);
                    GUIUtility.ExitGUI();
                }
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField("MitToon Shader v" + Version + "  /  BIRP", EditorStyles.centeredGreyMiniLabel);
        }

        // ---- copy / paste every setting except textures (text in the system clipboard: works across materials and projects)
        const string SettingsHeader = "MITTOON_SETTINGS v1";
        static readonly System.Globalization.CultureInfo Inv = System.Globalization.CultureInfo.InvariantCulture;

        static string Join4(float a, float b, float c, float d) =>
            a.ToString("R", Inv) + "," + b.ToString("R", Inv) + "," + c.ToString("R", Inv) + "," + d.ToString("R", Inv);

        public static string SerializeSettings(Material m)
        {
            var sb = new System.Text.StringBuilder(SettingsHeader).Append('\n');
            sb.Append("@shader\t").Append(m.shader.name).Append('\n');
            sb.Append("@queue\t").Append(m.renderQueue.ToString(Inv)).Append('\n');
            var sh = m.shader;
            for (int i = 0; i < sh.GetPropertyCount(); i++)
            {
                string n = sh.GetPropertyName(i);
                switch (sh.GetPropertyType(i))
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range:
                        sb.Append(n).Append("\tf\t").Append(m.GetFloat(n).ToString("R", Inv)).Append('\n'); break;
                    case ShaderPropertyType.Int:
                        sb.Append(n).Append("\ti\t").Append(m.GetInt(n).ToString(Inv)).Append('\n'); break;
                    case ShaderPropertyType.Color:
                        var c = m.GetColor(n);
                        sb.Append(n).Append("\tc\t").Append(Join4(c.r, c.g, c.b, c.a)).Append('\n'); break;
                    case ShaderPropertyType.Vector:
                        var v = m.GetVector(n);
                        sb.Append(n).Append("\tv\t").Append(Join4(v.x, v.y, v.z, v.w)).Append('\n'); break;
                    default: break; // textures (incl. normal maps) are skipped
                }
            }
            return sb.ToString();
        }

        public static void PasteSettings(Material m, string text)
        {
            if (string.IsNullOrEmpty(text) || !text.StartsWith(SettingsHeader)) return;
            int queue = int.MinValue;
            foreach (var line in text.Split('\n'))
            {
                var t = line.TrimEnd('\r').Split('\t');
                if (t.Length < 2) continue;
                if (t[0] == "@shader")
                {
                    // keep the outline variant in sync, never switch away from MitToon
                    if (m.shader != null && m.shader.name.StartsWith("MitToon/") && t[1].StartsWith("MitToon/") && m.shader.name != t[1])
                    {
                        var sh = Shader.Find(t[1]);
                        if (sh != null) m.shader = sh;
                    }
                    continue;
                }
                if (t[0] == "@queue") { int.TryParse(t[1], System.Globalization.NumberStyles.Integer, Inv, out queue); continue; }
                if (t.Length < 3 || !m.HasProperty(t[0])) continue;
                float[] f = t[2].Split(',').Select(x => float.Parse(x, Inv)).ToArray();
                switch (t[1])
                {
                    case "f": m.SetFloat(t[0], f[0]); break;
                    case "i": m.SetInt(t[0], (int)f[0]); break;
                    case "c": if (f.Length == 4) m.SetColor(t[0], new Color(f[0], f[1], f[2], f[3])); break;
                    case "v": if (f.Length == 4) m.SetVector(t[0], new Vector4(f[0], f[1], f[2], f[3])); break;
                }
            }
            SyncKeywords(m);
            if (queue != int.MinValue) m.renderQueue = queue;
            EditorUtility.SetDirty(m);
        }

        [MenuItem("CONTEXT/Material/MitToon: 全設定をコピー (テクスチャ以外)")]
        static void CopyCtx(MenuCommand c) => EditorGUIUtility.systemCopyBuffer = SerializeSettings((Material)c.context);
        [MenuItem("CONTEXT/Material/MitToon: 全設定を貼り付け")]
        static void PasteCtx(MenuCommand c)
        {
            var m = (Material)c.context;
            Undo.RecordObject(m, "MitToon Paste Settings");
            PasteSettings(m, EditorGUIUtility.systemCopyBuffer);
        }
        [MenuItem("Assets/MitToon/選択中のマテリアルに全設定を貼り付け (Paste settings to selected)")]
        static void PasteSelected()
        {
            var mats = Selection.objects.OfType<Material>().ToArray();
            Undo.RecordObjects(mats, "MitToon Paste Settings");
            foreach (var m in mats) PasteSettings(m, EditorGUIUtility.systemCopyBuffer);
            Debug.Log("[MitToon] " + mats.Length + " materials updated");
        }

        static void StripDisabledTextures(Material m)
        {
            foreach (var kv in sectionToggle)
            {
                if (!m.HasProperty(kv.Value) || m.GetFloat(kv.Value) > 0.5f) continue;
                if (!sectionProps.TryGetValue(kv.Key, out var names)) continue;
                foreach (var n in names)
                {
                    int i = m.shader.FindPropertyIndex(n);
                    if (i >= 0 && m.shader.GetPropertyType(i) == ShaderPropertyType.Texture) m.SetTexture(n, null);
                }
            }
        }

        // ================================================================== sections
        static readonly string[] ModesJP = { "不透明", "カットアウト", "半透明 (1パス)", "半透明 乗算済み (1パス)", "加算", "半透明 (2パス)", "半透明 乗算済み (2パス)" };
        static readonly string[] ModesEN = { "Opaque", "Cutout", "Transparent (1 pass)", "Premultiplied (1 pass)", "Additive", "Transparent (2 pass)", "Premultiplied (2 pass)" };

        bool HasOutline(Material mat) => IsOutlineShader(mat.shader);

        // picks the shader file matching outline on/off and the 1 / 2 pass render mode
        static void SwitchShader(Material m, bool outline)
        {
            bool two = m.HasProperty("_RenderMode") && IsTwoPassMode(Mathf.RoundToInt(m.GetFloat("_RenderMode")));
            var sh = Shader.Find(ShaderNameFor(outline, two, IsTessShader(m.shader)));
            if (sh == null || m.shader == sh) return;
            int q = m.renderQueue;
            m.shader = sh;
            m.renderQueue = q;
            SyncKeywords(m);
        }

        void SetOutline(bool on)
        {
            var sh = Shader.Find(on ? OutlineShaderName : BaseShaderName);
            if (sh == null) return;
            var targets = me.targets.Cast<Material>().ToArray();
            Undo.RecordObjects(targets, "Toggle Outline");
            foreach (var m in targets)
            {
                int q = m.renderQueue;
                bool two = m.HasProperty("_RenderMode") && IsTwoPassMode(Mathf.RoundToInt(m.GetFloat("_RenderMode")));
                var s2 = Shader.Find(ShaderNameFor(on, two, IsTessShader(m.shader)));
                m.shader = s2 != null ? s2 : sh;
                m.renderQueue = q;
                SyncKeywords(m);
            }
            GUIUtility.ExitGUI();
        }

        void SetTess(bool on)
        {
            var targets = me.targets.Cast<Material>().ToArray();
            Undo.RecordObjects(targets, "Toggle Tessellation");
            foreach (var m in targets)
            {
                int q = m.renderQueue;
                bool two = m.HasProperty("_RenderMode") && IsTwoPassMode(Mathf.RoundToInt(m.GetFloat("_RenderMode")));
                var s2 = Shader.Find(ShaderNameFor(IsOutlineShader(m.shader), two, on));
                if (s2 == null) continue;
                m.shader = s2;
                m.renderQueue = q;
                SyncKeywords(m);
            }
            GUIUtility.ExitGUI();
        }

        // ================================================================== quick setup
        static readonly string[] QuickMaterialIds = { "skinanime", "skin", "face", "hair", "eye", "cotton", "leather", "metal" };
        static readonly List<MitToonSectionPresets.Cost> costItems = new List<MitToonSectionPresets.Cost>();
        static GUIStyle quickButton, tagStyle;

        bool QuickWholeAvatar
        {
            get => EditorPrefs.GetBool("MitToon.QuickAvatar", true);
            set => EditorPrefs.SetBool("MitToon.QuickAvatar", value);
        }

        // the selected materials, or every MitToon material of their avatars
        Material[] QuickTargets(bool wholeAvatar)
        {
            var sel = me.targets.Cast<Material>().ToArray();
            if (!wholeAvatar) return sel;
            var all = MitToonSectionPresets.AvatarMaterials(sel);
            foreach (var m in sel) if (!all.Contains(m)) all.Add(m);
            return all.ToArray();
        }

        void ApplyQuick(Material[] targets, string undo, Action<Material> a)
        {
            Undo.RecordObjects(targets, undo);
            foreach (var m in targets) { a(m); SyncKeywords(m); EditorUtility.SetDirty(m); }
        }

        void ButtonGrid(int count, int cols, Func<int, string> label, Action<int> click)
        {
            // equal widths: the inspector width minus the module box padding
            float w = (EditorGUIUtility.currentViewWidth - 70f) / cols - 3f;
            for (int i = 0; i < count; i += cols)
            {
                EditorGUILayout.BeginHorizontal();
                for (int j = i; j < i + cols && j < count; j++)
                    if (GUILayout.Button(new GUIContent(label(j), label(j)), quickButton, GUILayout.Width(w))) click(j);
                EditorGUILayout.EndHorizontal();
            }
        }

        void DrawQuick(Material mat)
        {
            if (!Module("quick", "かんたん設定", "Quick Setup", null, false, true)) return;
            if (collecting || Searching) { EndModule(); return; }
            if (quickButton == null)
            {
                quickButton = new GUIStyle(EditorStyles.miniButton) { fixedHeight = 22, fontSize = 11 };
                tagStyle = new GUIStyle(EditorStyles.miniLabel) { alignment = TextAnchor.MiddleRight };
            }

            // 1. style: the look of the whole avatar
            Sub("1. スタイル (見た目の方向)", "1. Style (overall look)");
            bool whole = EditorGUILayout.ToggleLeft(T("アバターの全 MitToon マテリアルにまとめて適用", "Apply to every MitToon material of the avatar"), QuickWholeAvatar);
            if (whole != QuickWholeAvatar) QuickWholeAvatar = whole;
            var styles = MitToonPresets.All.Where(p => p.category.en.StartsWith("Style")).ToArray();
            ButtonGrid(styles.Length, 2, i => T(styles[i].jp, styles[i].en), i =>
            {
                var id = styles[i].id;
                ApplyQuick(QuickTargets(QuickWholeAvatar), "MitToon Style", m => MitToonPresets.Apply(m, id));
            });

            // 2. material: this material only
            Sub("2. 素材 (このマテリアル)", "2. Surface (this material)");
            var mats = QuickMaterialIds.Select(id => MitToonPresets.All.FirstOrDefault(p => p.id == id)).Where(p => p.id != null).ToArray();
            ButtonGrid(mats.Length, 4, i => T(mats[i].jp, mats[i].en), i =>
            {
                var id = mats[i].id;
                ApplyQuick(me.targets.Cast<Material>().ToArray(), "MitToon Surface", m => MitToonPresets.Apply(m, id));
            });
            EditorGUILayout.LabelField(T("ほかの素材は右上の「プリセット ▼」にあります。", "More surfaces are in \"Presets ▼\" at the top right."), EditorStyles.centeredGreyMiniLabel);

            // 3. load
            Sub("3. 負荷", "3. Performance");
            EditorGUILayout.BeginHorizontal();
            for (int lv = 0; lv < 3; lv++)
            {
                int level = lv;
                if (GUILayout.Button(JP ? MitToonSectionPresets.LevelJP[lv] : MitToonSectionPresets.LevelEN[lv], quickButton))
                    ApplyQuick(QuickTargets(QuickWholeAvatar), "MitToon Quality", m => MitToonSectionPresets.ApplyQuality(m, level));
            }
            EditorGUILayout.EndHorizontal();
            EditorGUILayout.LabelField(T("軽量: SSAO と接触影を切り、サンプル数を最小に / 標準 / 高品質: サンプル数を最大に。見た目の方向は変えません。",
                                         "Light: no SSAO / contact shadows, fewest samples. Standard. High: most samples. The look stays the same."), EditorStyles.wordWrappedMiniLabel);

            // load meter of the (first) selected material
            float load = MitToonSectionPresets.Estimate(mat, costItems);
            string grade = load < 1.25f ? T("軽い", "light") : load < 1.7f ? T("普通", "medium") : T("重い", "heavy");
            EditorGUILayout.LabelField(T($"負荷の目安: 一般的なトゥーンシェーダーの約 {load:0.0} 倍 ({grade})", $"Estimated load: about {load:0.0}x a typical toon shader ({grade})"), EditorStyles.boldLabel);
            var bar = GUILayoutUtility.GetRect(16, 8, GUILayout.ExpandWidth(true));
            EditorGUI.DrawRect(bar, new Color(0, 0, 0, 0.25f));
            EditorGUI.DrawRect(new Rect(bar.x, bar.y, bar.width * Mathf.Clamp01(load / 3f), bar.height), MitToonSectionPresets.LoadColor(load));
            EditorGUI.DrawRect(new Rect(bar.x + bar.width / 3f, bar.y - 2, 2, bar.height + 4), new Color(1, 1, 1, 0.8f));   // 1.0x mark
            EditorGUILayout.Space(2);
            bool anyDepth = false;
            foreach (var it in costItems.OrderByDescending(c => c.value).Take(6))
            {
                anyDepth |= it.depth;
                EditorGUILayout.BeginHorizontal();
                EditorGUILayout.LabelField(T(it.jp, it.en) + (it.depth ? T("  (深度)", "  (depth)") : ""), GUILayout.MinWidth(80));
                GUILayout.Label("+" + it.value.ToString("0.00"), tagStyle, GUILayout.Width(40));
                using (new EditorGUI.DisabledScope(it.off == null))
                    if (GUILayout.Button(T("オフ", "Off"), EditorStyles.miniButton, GUILayout.Width(44)))
                    {
                        var off = it.off;
                        ApplyQuick(me.targets.Cast<Material>().ToArray(), "MitToon Feature Off", m => off(m));
                    }
                EditorGUILayout.EndHorizontal();
            }
            if (anyDepth)
                EditorGUILayout.LabelField(T("(深度) はカメラの深度テクスチャを使う効果です。影付きのディレクショナルライトがないワールドでは自動でオフになります。",
                                             "(depth) effects read the camera depth texture. They turn off by themselves in worlds without a shadowed directional light."), EditorStyles.wordWrappedMiniLabel);
            EndModule();
        }

        void DrawBase(Material mat)
        {
            if (!Module("base", "レンダリング プリセット / トゥーン度", "Render Preset / Toon Amount", null, false, true)) return;
            if (collecting) { Register("_RenderMode"); Register("_Cutoff"); }
            else
            {
                var rm = P("_RenderMode");
                EditorGUI.showMixedValue = rm.hasMixedValue;
                EditorGUI.BeginChangeCheck();
                int mode = EditorGUILayout.Popup(T("描画モード", "Render Mode"), (int)rm.floatValue, JP ? ModesJP : ModesEN);
                EditorGUI.showMixedValue = false;
                if (EditorGUI.EndChangeCheck())
                {
                    Undo.RecordObjects(me.targets, "Render Mode");
                    rm.floatValue = mode;
                    bool switched = false;
                    foreach (var t in me.targets)
                    {
                        var m = (Material)t;
                        ApplyRenderMode(m, true);
                        var before = m.shader;
                        SwitchShader(m, IsOutlineShader(m.shader));
                        switched |= before != m.shader;
                    }
                    if (switched) GUIUtility.ExitGUI();
                }
                if (mode == 1) Prop("_Cutoff");
                if (mode == 2 || mode == 3)
                    Info("1パス: 面を 1 回だけ描きます。軽く、薄い布やエフェクト向きです。重なった部分が乱れる場合は 2パスにしてください。",
                         "1 pass: each face once. Cheap; good for thin cloth and effects. Use 2 pass if overlapping parts sort badly.", MessageType.None);
                if (IsTwoPassMode(mode))
                    Info("2パス: 裏面を先に描いてから表面を描きます。髪の毛先、スカート、レースなど自分自身と重なる半透明がきれいに重なります (描画コストは約 2 倍)。",
                         "2 pass: back faces first, then front faces. Self-overlapping transparency such as hair tips, skirts and lace sorts correctly (about 2x cost).", MessageType.None);
            }
            Prop("_Cull");
            Prop("_ToonAmount");
            if (!collecting && !Searching)
                EditorGUILayout.LabelField(" ", T("← リアル (PBR)        トゥーン (アニメ) →", "<- Realistic (PBR)          Toon (anime) ->"), EditorStyles.centeredGreyMiniLabel);
            EndModule();
        }

        void DrawMain()
        {
            if (!Module("main", "メインカラー", "Main Color", null, false, true)) return;
            Tex("_MainTex", "_Color", "scroll:_MainScroll");
            Vec("_MainTexHSVG", new[] { T("色相", "Hue"), T("彩度", "Saturation"), T("明度", "Value"), T("ガンマ", "Gamma") },
                new[] { -0.5f, 0f, 0f, 0.1f }, new[] { 0.5f, 2f, 2f, 3f });
            Tex("_MainColorAdjustMask");
            Sub("アルファ", "Alpha");
            Prop("_AlphaMaskMode");
            if (When(F("_AlphaMaskMode") > 0.5f)) Tex("_AlphaMask");
            Props("_AlphaMaskValue", "_UseVertexColor", "_FresnelAlpha");
            EndModule();
            if (Module("gradient", "高さグラデーション / 色相シフト", "Height Gradient / Hue Shift", "_UseGradient"))
            {
                Props("_GradTop", "_GradBottom", "_GradSpace");
                Vec("_GradRange", new[] { T("下端", "Bottom"), T("上端", "Top") }, new[] { 0f, 0f }, new[] { 0f, 0f });
                Props("_GradBlend", "_GradStrength", "_ViewHueShift");
                EndModule();
            }
        }

        void DrawLayers()
        {
            if (!Module("layer", "カラーレイヤー", "Color Layers", "_UseLayer")) return;
            foreach (var n in new[] { "2", "3" })
            {
                if (Module("layer" + n, n + (n == "2" ? "nd" : "rd") + T(" レイヤー", " Layer"), n + (n == "2" ? "nd" : "rd") + " Layer", "_UseMain" + n, true))
                {
                    Tex("_Main" + n + "Tex", "_Main" + n + "Color", "_Main" + n + "UV", "_Main" + n + "Decal", "scroll:_Main" + n + "Scroll");
                    Tex("_Main" + n + "Mask");
                    Prop("_Main" + n + "Blend");
                    EndModule();
                }
            }
            EndModule();
        }

        void DrawNormal()
        {
            if (Module("normal", "ノーマルマップ", "Normal Map", "_UseBumpMap"))
            {
                Tex("_BumpMap", "_BumpScale");
                Tex("_BumpMask");
                if (Module("bump2", "2nd ノーマルマップ", "2nd Normal Map", "_UseBump2", true))
                {
                    Tex("_Bump2Map", "_Bump2Scale");
                    Tex("_Bump2Mask");
                    EndModule();
                }
                EndModule();
            }
            if (Module("detail", "ディテールマップ", "Detail Maps", "_UseDetail"))
            {
                Tex("_DetailMask");
                Tex("_DetailAlbedoMap", "_DetailAlbedoScale", "_DetailUV");
                Tex("_DetailNormalMap", "_DetailNormalScale");
                EndModule();
            }
            if (Module("parallax", "視差 (ハイトマップ)", "Parallax (Height)", "_UseParallax"))
            {
                Tex("_ParallaxMap", "_Parallax");
                Prop("_ParallaxMode");
                if (When(F("_ParallaxMode") > 0.5f)) Prop("_ParallaxSteps");
                EndModule();
            }
        }

        void DrawShadow()
        {
            if (!Module("shadow", "影 (トゥーン)", "Toon Shadow", null, false, true)) return;
            ModeRow();
            bool compat = Compat, ramp = !compat && F("_ShadowRampMode") > 0.5f;
            Tex("_ShadowMaskTex", "_ShadowStrength");
            if (When(!compat)) Prop("_ShadowRampMode");
            if (When(ramp)) { Tex("_ShadowRampTex"); Prop("_ShadowRampRow"); }
            if (When(!ramp))
            {
                // one block per shadow step: colour, border, blur, then what only the compatible mode reads
                Sub("1影", "1st Shadow");
                Tex("_ShadowColorTex", "_ShadowColor");
                Props("_ShadowBorder", "_ShadowBlur");
                if (When(compat)) Props("_ShadowNormalStrength", "_ShadowReceive");
                Sub("2影", "2nd Shadow");
                Tex("_Shadow2ndColorTex", "_Shadow2ndColor");
                Props("_Shadow2ndBorder", "_Shadow2ndBlur");
                if (When(compat)) Props("_Shadow2ndNormalStrength", "_Shadow2ndReceive");
                if (When(compat))
                {
                    Sub("3影", "3rd Shadow");
                    Tex("_Shadow3rdColorTex", "_Shadow3rdColor");
                    Props("_Shadow3rdBorder", "_Shadow3rdBlur", "_Shadow3rdNormalStrength", "_Shadow3rdReceive");
                }
                Sub("影の色の調整", "Shadow Color Tuning");
                Props("_ShadowMainStrength", "_ShadowEnvStrength", "_ShadowBorderColor", "_ShadowBorderRange");
            }
            Sub("落ち影", "Cast Shadows");
            Prop("_ReceiveCastShadow");
            if (When(!compat)) Props("_ReceiveShadowStrength", "_CastShadowSoftness", "_CastShadowOnly");
            Sub("AO / マスク", "AO / Masks");
            if (When(!compat)) Prop("_ShadowAOShift");
            if (When(compat))
            {
                Tex("_ShadowBorderMask");
                Vec("_CompatAOShift", new[] { T("1影 倍率", "1st Scale"), T("1影 オフセット", "1st Offset"), T("2影 倍率", "2nd Scale"), T("2影 オフセット", "2nd Offset") },
                    new float[4], new float[4]);
                Vec("_ShadowAOShift2", new[] { T("3影 倍率", "3rd Scale"), T("3影 オフセット", "3rd Offset") }, new float[2], new float[2]);
                Prop("_ShadowPostAO");
                Tex("_ShadowBlurMask");
                Prop("_BackfaceForceShadow");
            }
            if (When(!compat))
            {
                if (Module("autoshadow", "影色の自動生成", "Auto Shadow Color", null, true))
                {
                    Props("_AutoShadowColor", "_AutoShadowHue", "_AutoShadowDarkness");
                    EndModule();
                }
                if (Module("posterize", "階調 / ディザ", "Posterize / Dither", null, true))
                {
                    Props("_ShadowPosterize", "_ShadowDither");
                    EndModule();
                }
                if (Module("ilm", "ILM マップ (ゲーム風)", "ILM Map (game style)", "_UseILM", true))
                {
                    Tex("_ILMMap");
                    EndModule();
                }
            }
            EndModule();
        }

        bool Compat { get { var p = P("_CompatShading"); return p != null && p.floatValue > 0.5f; } }

        // the shading model is one switch for the whole material, shown at the top of every section it changes
        void ModeRow()
        {
            var p = P("_CompatShading");
            if (!Show(p)) return;
            var label = new GUIContent(T("計算方式", "Shading Model"),
                T("影、リム、マットキャップ、逆光で共通の切り替えです。lilToon は lilToon から移行したマテリアルの見た目をおおまかに再現し、その間は MitToon 独自の陰影や質感の機能は使われません。",
                  "One switch shared by shadow, rim, matcap and backlight. lilToon roughly reproduces the look of a material migrated from lilToon; MitToon's own shading and material features are skipped while it is on."));
            var opts = new[] { new GUIContent("MitToon"), new GUIContent("lilToon") };
            EditorGUI.showMixedValue = p.hasMixedValue;
            EditorGUI.BeginChangeCheck();
            int v = EditorGUILayout.Popup(label, p.floatValue > 0.5f ? 1 : 0, opts);
            EditorGUI.showMixedValue = false;
            if (EditorGUI.EndChangeCheck())
            {
                p.floatValue = v;
                foreach (var t in me.targets) SyncKeywords((Material)t);
            }
            EditorGUILayout.Space(2);
        }

        void DrawQuality()
        {
            if (!Module("quality", "高品質化", "Quality", null, false, true)) return;
            Sub("にじみ・ちらつき", "Aliasing / Flicker");
            Props("_QToonAA", "_QSpecClamp", "_QNormalFadeDist");
            Sub("細部", "Detail");
            Props("_QMicroShadow", "_QMipBias", "_QSharpen", "_QDeband");
            Sub("負荷", "Performance");
            Prop("_QLodDistance");
            Info("影の境界を画素単位でなめらかにし、尖ったハイライトのちらつき、遠くのノーマルマップのざらつき、暗いグラデーションの縞を抑えます。マイクロシャドウは AO やノーマルの凹みに直接光の影を落とし、細部を引き締めます。",
                 "Pixel aware cel borders, no sparkling highlights, no shimmering normal maps far away and no banding in dark gradients. Micro shadows let AO / normal cavities block direct light for crisper detail.", MessageType.None);
            EndModule();
        }

        void DrawLighting()
        {
            if (!Module("lighting", "ライティング", "Lighting")) return;
            Props("_LightMinLimit", "_LightMaxLimit", "_LightSoftLimit", "_LightBoost", "_MonochromeLighting", "_AsUnlit", "_VertexLightStrength", "_AddLightStrength");
            Sub("追加ライト (ポイント / スポット)", "Additional Lights (point / spot)");
            Props("_AddLightSoftness", "_AddLightCastShadow", "_AddLightMaxLimit", "_AddLightPassthrough", "_AddLightMonochrome", "_AddLightSmoothFalloff", "_AddLightIgnoreDirectional");
            Sub("自動ライティング (周りのライトと景色から計算)", "Auto Lighting (from lights and scenery)");
            Props("_AutoLight", "_AutoKeyRatio", "_AutoProbeAmbient", "_AutoPointLights", "_AutoDefaultKey");
            if (!collecting && !Searching && GUILayout.Button(T("ワールド照明シミュレーターを開く (暗所・夕方・クラブなどで確認)", "Open Lighting Simulator (check dark / sunset / club)")))
                MitToonLightingSim.Open();
            Sub("色の受け方", "Color Response");
            Props("_EnvColorStrength", "_LightColorStrength", "_DarkColorReduce", "_DarkColorThreshold");
            Info("ライトプローブ、反射プローブ (景色)、近くのポイントライト、平行光源を解析して、光の方向・キーライトと環境光の配分・色を自動で決めます。環境光が強すぎて平坦なワールドでは一部をキーライトに回して立体感を出します。暗い場所では環境の色をほぼ無彩色にします。",
                 "Analyses light probes, the reflection probe (scenery), nearby point lights and the directional light to pick the light direction, the key / ambient balance and the color. In flat worlds part of the ambient becomes a key light. In the dark the ambient color is almost neutral.", MessageType.None);
            Sub("ライトの計算方式", "Light Model");
            Props("_LightColorMode", "_LightMapMode");
            if (When(Mathf.RoundToInt(F("_LightColorMode")) == 2)) Prop("_UnlitIntensity");
            Info("色の方式: 自動 = 景色やライトを解析 (MitToon 標準) / 標準 = 直接光 + 法線方向の環境光 / 常に見える = 暗い所でも最低限の明るさ / SH 明暗 = ライトプローブの明るい側と暗い側 (定番のトゥーン) / フラット = 方向なしの均一な光。\n明暗の付け方: トゥーン境界 / ハーフランバートのグラデーション / ランバート / 落ち影のみ / 陰影なし。",
                 "Color: Auto = analyses scenery and lights (MitToon default) / Standard = direct + ambient along the normal / Always Visible = minimum brightness in the dark / SH Lit and Shade = bright and dark side of the probe (classic toon) / Flat = uniform light.\nLight map: toon border / half lambert gradient / lambert / cast shadows only / no shading.", MessageType.None);
            Sub("ライト方向", "Light Direction");
            Prop("_LightDirMode");
            if (When(Mathf.RoundToInt(F("_LightDirMode")) == 6)) Props("_LightViewYaw", "_LightViewPitch");
            Prop("_LightDirKeepUp");
            Vec("_LightDirOverride", new[] { "X", "Y", "Z", T("割合", "Blend") }, new[] { -1f, -1f, -1f, 0f }, new[] { 1f, 1f, 1f, 1f });
            Sub("MitToon GI (どのワールドでもリッチに)", "MitToon GI (rich in any world)");
            Props("_AmbientShape", "_AmbientFlatten", "_EnvNormalize", "_VirtualKeyLight", "_SpecEnergyComp");
            if (Module("gidetail", "GI 詳細", "GI Details", null, true))
            {
                Props("_SHSoftness", "_AmbientShapeContrast", "_AmbientSkyTint", "_AmbientGroundTint", "_EnvNormalizeRange", "_SynthReflHighlight", "_SynthReflBlur");
                EndModule();
            }
            Info("物理ベースの BRDF / GI をベースに、平坦な環境光の立体化、プローブ無しワールドでの SH 反射合成、反射の明るさ合わせ、平行光源の無いワールドでの仮想キーライト、多重散乱補正を行います。",
                 "Physically based BRDF / GI plus: hemisphere shaping for flat ambient, SH synthesised reflections without probes, probe brightness matching, a virtual key light for worlds without a directional light and multi-scatter compensation.", MessageType.None);
            if (Module("lightvolumes", "VRC ライトボリューム", "VRC Light Volumes", "_UseLightVolumes", true))
            {
                Props("_LVStrength");
                Sub("種類ごとの強さ", "Per Type Strength");
                Props("_LVRegular", "_LVAdditive", "_LVPointLights", "_LVPointShading");
                Sub("サンプリング", "Sampling");
                Props("_LVObjectCenter", "_LVNormalOffset");
                Sub("色", "Color");
                Props("_LVSaturation", "_LVMinBrightness");
                Sub("スペキュラ", "Specular");
                Props("_LVSpecular", "_LVSpecularMode");
                Sub("負荷", "Performance");
                Prop("_LVLite");
                Info("通常ボリューム = ワールドに焼き込まれた光、追加ボリューム = 動く光や照明演出、ポイントライトボリューム = ライトボリューム製の点光源 / スポット / エリアライトです。ポイントライトは 1 灯ずつ陰影とハイライトを計算します。\nデバッグ表示を「ライトボリューム」にすると受けている光を確認できます (紫 = ボリュームの外)。",
                     "Regular = light baked into the world, Additive = moving / show lights, Point Light Volumes = light volume point / spot / area lights, each shaded with its own highlight.\nSet Debug View to Light Volume to see what is received (purple = outside any volume).", MessageType.None);
                if (!collecting && !Searching && !LightVolumesInstalled)
                    Info("VRC Light Volumes パッケージ (red.sim.lightvolumes) が見つからないため無効化されます。VCC で追加してください。",
                         "The VRC Light Volumes package (red.sim.lightvolumes) is missing, so this is disabled. Add it with VCC.", MessageType.Warning);
                EndModule();
            }
            if (Module("spherenormal", "球面法線 (顔の影を滑らかに)", "Spherical Normal (smooth face)", "_UseSphereNormal", true))
            {
                Props("_SphereNormalStrength", "_SphereNormalVertical");
                Vec("_SphereCenter", new[] { "X", "Y", "Z" }, new[] { 0f, 0f, 0f }, new[] { 0f, 0f, 0f });
                Info("拡散光の計算だけを球の法線に寄せ、鼻や口まわりの汚い影を消します。顔メッシュの Root Bone を Head にして中心を頭の中心に合わせてください。",
                     "Bends only the diffuse normal toward a sphere to remove messy nose / mouth shadows. Set the face Root Bone to Head and put the center at the head center.", MessageType.None);
                EndModule();
            }
            if (Module("filllight", "補助ライト (仮想)", "Fill Light (virtual)", "_UseFillLight", true))
            {
                Props("_FillColor", "_FillStrength", "_FillBorder", "_FillBlur", "_FillShadowOnly");
                Vec("_FillDir", new[] { "X", "Y", "Z" }, new[] { -1f, -1f, -1f }, new[] { 1f, 1f, 1f });
                EndModule();
            }
            if (Module("bounce", "照り返し (地面の反射光)", "Bounce Light (ground)", "_UseBounce", true))
            {
                Props("_BounceColor", "_BounceStrength", "_BouncePower", "_BounceHeight", "_BounceLightInfluence", "_BounceGroundMatch", "_BounceGroundIntensity");
                EndModule();
            }
            Sub("影の生成 (ShadowCaster)", "Shadow Caster");
            Props("_ShadowCasterBias", "_ShadowCasterBiasView", "_ShadowCasterNormalBias");
            Info("影を作るときに形を光から遠ざけます。鼻や前髪、服のしわなどの小さな形がアバター自身に落とす影と、そのちらつきが消え、腕や頭のような大きな物の影だけが残ります。0 にすると従来の動作です。",
                 "Pushes the shape away from the light when the shadow is made. Small shapes (nose, bangs, cloth folds) stop shadowing the avatar and their shimmer goes away; only large shapes (arms, head) still cast. 0 = previous behavior.", MessageType.None);
            EndModule();
        }

        void DrawScreenSpace()
        {
            if (!Module("ss", "スクリーンスペース (SSAO / 落ち影)", "Screen Space (SSAO / Shadows)", null, false, true)) return;
            if (Module("ssao", "SSAO (アンビエントオクルージョン)", "SSAO", "_UseSSAO", true))
            {
                SSAODebugButton();
                Props("_SSAOStrength", "_SSAORadius", "_SSAOColor", "_SSAOAlbedoTint");
                Sub("品質", "Quality");
                Props("_SSAOMethod", "_SSAOSamples", "_SSAOJitter");
                Sub("形", "Shape");
                Props("_SSAOSoftness", "_SSAOThickness", "_SSAOFalloff", "_SSAOBias", "_SSAONormalStrength");
                Sub("マルチスケール", "Multi Scale");
                Prop("_SSAONearWeight");
                Prop("_SSAOMidWeight");
                if (When(F("_SSAOMidWeight") > 0)) Prop("_SSAOMidScale");
                Prop("_SSAOFarWeight");
                if (When(F("_SSAOFarWeight") > 0)) Prop("_SSAOFarScale");
                Sub("トーン", "Tone");
                Props("_SSAOPower", "_SSAOContrast", "_SSAOMin");
                Sub("どこに効かせるか", "Where It Applies");
                Props("_SSAOAmbient", "_SSAODirect", "_SSAOSpecular", "_SSAOViewFix", "_SSAOAlphaInfluence");
                Tex("_SSAOMask", "_SSAOMaskStrength");
                Sub("距離", "Distance");
                Props("_SSAOMaxDistance", "_SSAOFadeStart", "_SSAODistanceScale");
                EndModule();
            }
            if (Module("softshadow", "ソフトシャドウ (カク付かない落ち影)", "Soft Shadows", "_UseSoftShadow", true))
            {
                Props("_SoftShadowRadius", "_SoftShadowSamples", "_ShadowSmoothness");
                Sub("ちらつき防止", "Flicker Guard");
                Prop("_ShadowTerminatorFade");
                EndModule();
            }
            if (Module("depthshadow", "深度シャドウ (髪の落ち影)", "Depth Texture Shadow (hair on face)", "_UseDepthShadow", true))
            {
                Props("_DepthShadowWidth", "_DepthShadowMaxPx", "_DepthShadowThreshold", "_DepthShadowSoftness", "_DepthShadowStrength");
                EndModule();
            }
            if (Module("contact", "コンタクトシャドウ", "Contact Shadows", "_UseContactShadow", true))
            {
                Props("_ContactShadowLength", "_ContactShadowThickness", "_ContactShadowStrength", "_ContactShadowSteps");
                Info("追加の設定はすべて初期値のとき従来と同じ見た目になります。深度テクスチャには物の区別がないため、鼻など顔自身が落とす影だけを消したいときは「受ける側のマスク」で鼻の周りを黒く塗ってください。",
                     "Every extra setting keeps the previous look at its default. The depth texture cannot tell objects apart, so to drop only the shadow the face casts on itself (nose), paint the area around the nose black in the receive mask.", MessageType.None);
                Sub("形", "Shape");
                Props("_ContactShadowBias", "_ContactShadowMinDelta", "_ContactShadowSoftness", "_ContactShadowEndFade");
                Sub("距離", "Distance");
                Props("_ContactShadowDistanceScale", "_ContactShadowMaxDistance");
                Sub("マスク / ノイズ", "Mask / Noise");
                Tex("_ContactShadowMask", "_ContactShadowMaskStrength");
                Props("_ContactShadowJitter");
                EndModule();
            }
            if (!collecting && !Searching && (F("_UseSSAO") > 0.5f || F("_UseContactShadow") > 0.5f || F("_UseSoftShadow") > 0.5f || F("_UseDepthShadow") > 0.5f))
            {
                Info("カメラの深度テクスチャを使います。影付きのディレクショナルライトが無いワールドでは深度が作られず、これらの効果は自動でオフになります。どのワールドでも使いたい場合は、下のボタンで深度ライトを追加してください (ライト数 +1)。ただし深度ライトがあると、見ている人の側でワールド全体の深度をもう一度描くため、重いワールドでは FPS が大きく下がります。",
                     "Uses the camera depth texture. Worlds without a shadowed directional light have no depth, and these effects then turn off by themselves. To use them in every world, add a depth light with the button below (+1 light). Note: with the depth light, viewers render the depth of the whole world once more, which costs a lot of FPS in heavy worlds.");
                if (GUILayout.Button(T("このマテリアルのアバターに深度ライトを追加", "Add Depth Light to avatars using this material")))
                    MitToonDepthLight.AddForMaterials(me.targets.Cast<Material>().ToArray());
            }
            EndModule();
        }

        // switches the debug view to "AO only" and back, so the occlusion is easy to judge while tuning
        void SSAODebugButton()
        {
            if (collecting || Searching) return;
            var p = P("_DebugView");
            if (p == null) return;
            bool on = Mathf.RoundToInt(p.floatValue) == 5;
            if (GUILayout.Toggle(on, on ? T("AO の確認中 (クリックで戻す)", "Showing AO only (click to go back)") : T("AO だけを表示して確認", "Show AO only"), "Button") != on)
                p.floatValue = on ? 0 : 5;
        }

        void DrawRichness()
        {
            if (!Module("richness", "質感", "Material Feel", null, false, true)) return;
            Sub("トゥーン + リアル質感", "Toon + Real Material");
            Prop("_HybridAmount");
            if (When(F("_HybridAmount") > 0.001f)) Props("_HybridLitGradient", "_HybridShadeVolume", "_HybridEnvTint");
            Sub("拡散光", "Diffuse");
            Props("_RichWrap", "_RichTerminatorColor", "_RichTerminatorWidth", "_RichMicroContrast");
            Sub("影の色", "Shade Color");
            Props("_RichColorDepth", "_RichShadowSaturation", "_RichShadowHue", "_QShadowComplement", "_QShadowCoolColor");
            Sub("光沢", "Gloss");
            Props("_RichSoftSpec", "_RichSoftSpecRoughness", "_RichGloss", "_RichAmbientRim");
            Props("_RichAmbientRimMode");
            Info("「トゥーン」では環境光のフチ光を、背景との境目 (本当の輪郭) にだけ平らな帯で出します。マズルの側面や頬のような内側の曲面には光が入りません。深度テクスチャが無いワールドでは消えます。",
                 "Toon puts the ambient rim only on the real silhouette (against the background) as a flat band; inner curved surfaces such as a muzzle side or a cheek get none. It disappears in worlds without a depth texture.", MessageType.None);
            Info("トゥーン + リアル質感: セルの影の形はそのままに、明部の減衰と影の中の立体感を加えます (トゥーン度 1 推奨)。他の項目は平坦でマットな見た目を避ける味付けで、全部 0 で素の見た目になります。",
                 "Toon + Real keeps the cel shadow shape but adds falloff in the light and volume in the shadow (best with Toon Amount 1). The rest avoids a flat matte look; all 0 = plain.", MessageType.None);
            EndModule();
        }

        void DrawCharControl()
        {
            if (!Module("charctl", "キャラ全体 (全マテリアル共通にする)", "Whole Character (same on all materials)")) return;
            Sub("色", "Color");
            Props("_CharTint", "_CharBrightness", "_CharDesaturate", "_CharLerpColor");
            Sub("ワールドの明るさに順応", "World Brightness Adaptation");
            Props("_WorldAdapt", "_WorldAdaptTarget", "_WorldAdaptRange");
            Sub("パース除去 (近距離の顔の歪みを減らす)", "Perspective Removal (less distortion up close)");
            Props("_PerspectiveRemoval", "_PerspectiveRange");
            Vec("_PerspectiveCenter", new[] { "X", "Y", "Z" }, new[] { 0f, 0f, 0f }, new[] { 0f, 0f, 0f });
            if (F("_PerspectiveRemoval") > 0.001f)
                Info("VR と VR のミラーでは自動で無効になります (両目の立体感と合わないため)。デスクトップ視点、カメラ、デスクトップのミラーで効きます。",
                     "Turned off automatically in VR and VR mirrors (it conflicts with stereo depth). Works in desktop view, cameras and desktop mirrors.", MessageType.None);
            EndModule();
        }

        void DrawSkin()
        {
            if (Module("sss", "サブサーフェス (肌)", "Subsurface (Skin)", "_UseSSS"))
            {
                Tex("_SSSMap", "_SSSColor");
                Props("_SSSStrength", "_SSSWrap", "_SSSCurvature");
                Sub("透過光", "Transmission");
                Props("_TransmissionStrength", "_TransmissionPower", "_TransmissionDistortion");
                EndModule();
            }
            if (Module("backlight", "逆光ライト", "Backlight", "_UseBacklight"))
            {
                ModeRow();
                Tex("_BacklightMask", "_BacklightColor");
                Props("_BacklightBorder", "_BacklightBlur", "_BacklightDirectivity", "_BacklightViewStrength", "_BacklightNormalStrength", "_BacklightMainStrength");
                if (When(Compat)) Props("_BacklightReceiveShadow", "_BacklightBackfaceMask");
                EndModule();
            }
        }

        void DrawEyeGuard()
        {
            if (!Module("eyeguard", "目の影除け (目の内側に影を乗せない)", "Eye Shadow Guard", "_UseEyeGuard")) return;
            Tex("_EyeGuardMask");
            Props("_EyeGuardShadow", "_EyeGuardShade", "_EyeGuardAO", "_EyeGuardBrightness");
            Sub("瞳の奥行き", "Iris Depth");
            Prop("_EyeParallax");
            Tex("_EyeParallaxMask");
            Info("マスクの白い部分 (白目・瞳) にまぶたや前髪の落ち影、ライト方向の陰影、AO が乗らなくなります。目だけのマテリアルならマスクは白のままで構いません。ライトの明るさと色には今まで通り追従します。",
                 "White areas of the mask (sclera / iris) receive no eyelid or bang shadows, no light angle shading and no AO. For an eye-only material keep the mask white. Brightness and color still follow the lights.", MessageType.None);
            EndModule();
        }

        void DrawFace()
        {
            if (!Module("facesdf", "顔 SDF 影 (ゲーム / VTuber 風)", "Face SDF Shadow (game style)", "_UseFaceSDF")) return;
            Tex("_FaceSDFTex");
            Tex("_FaceSDFMask");
            Props("_FaceSDFBlur", "_FaceSDFFlip");
            Vec("_FaceForward", new[] { "X", "Y", "Z" }, new[] { -1f, -1f, -1f }, new[] { 1f, 1f, 1f });
            Vec("_FaceUp", new[] { "X", "Y", "Z" }, new[] { -1f, -1f, -1f }, new[] { 1f, 1f, 1f });
            Info("顔メッシュの SkinnedMeshRenderer の Root Bone を Head にすると、オブジェクト軸が頭に追従します。DCC ツールからの書き出しなら正面が (0,-1,0)、上が (0,0,1) のことがあります。",
                 "Set the face SkinnedMeshRenderer Root Bone to Head so the object axes follow the head. Some exports may need forward (0,-1,0) and up (0,0,1).");
            if (!collecting && !Searching && GUILayout.Button(T("このマテリアルのメッシュの Root Bone を Head に設定", "Set Root Bone of meshes using this material to Head")))
                MitToonOutlineBaker.SetRootBoneToHead(me.targets.Cast<Material>().ToArray());
            EndModule();
        }

        void DrawPBR()
        {
            if (!Module("pbr", "PBR / 反射", "PBR / Reflection", null, false, true)) return;
            Prop("_PBRMapMode");
            if (When(F("_PBRMapMode") < 0.5f))
            {
                Tex("_MetallicMap", "_Metallic");
                Tex("_SmoothnessMap", "_Smoothness", "_SmoothnessIsRoughness");
                Tex("_OcclusionMap", "_OcclusionStrength");
            }
            if (When(F("_PBRMapMode") > 0.5f))
            {
                Tex("_MaskMap");
                if (!collecting && !Searching)
                    EditorGUILayout.LabelField(" ", F("_PBRMapMode") < 1.5f ? T("R=メタリック G=AO A=スムースネス", "R=Metallic G=AO A=Smoothness")
                                                                             : T("R=AO G=ラフネス B=メタリック", "R=AO G=Roughness B=Metallic"), EditorStyles.miniLabel);
                if (When(F("_PBRMapMode") > 0.5f) && !collecting) Props("_Metallic", "_Smoothness", "_OcclusionStrength");
            }
            Prop("_Reflectance");
            Sub("スペキュラ", "Specular");
            Props("_SpecularColor", "_SpecularStrength", "_SpecularToony");
            if (When(F("_SpecularToony") > 0.001f)) Props("_ToonSpecBorder", "_ToonSpecBlur");
            Tex("_SpecularMask");
            Sub("濡れ (Wetness)", "Wetness");
            Tex("_WetnessMask", "_Wetness");
            Sub("環境", "Environment");
            Props("_EnvReflStrength", "_EnvLightStrength", "_ReflCubeMode");
            float cm = F("_ReflCubeMode");
            if (When(cm > 0.5f && cm < 1.5f || cm > 3.5f)) Tex("_ReflCube", "_ReflCubeIntensity");
            if (When(cm < 0.5f || (cm > 2.5f && cm < 3.5f))) Prop("_ReflCubeIntensity");
            if (When(cm > 2.5f && cm < 3.5f)) Props("_SkyTopColor", "_SkyHorizonColor", "_SkyGroundColor");
            Sub("スペキュラ AA", "Specular AA");
            Props("_SpecAA", "_SpecAAThreshold");
            Sub("遮蔽", "Occlusion");
            Props("_SpecOcclusionStrength", "_HorizonOcclusionStrength");
            EndModule();
            if (Module("iridescence", "薄膜干渉 (玉虫色)", "Iridescence (thin film)", "_UseIridescence"))
            {
                Props("_IridStrength", "_IridScale", "_IridOffset", "_IridSaturation", "_IridFresnel", "_IridSpecOnly", "_IridSpecBoost");
                EndModule();
            }
        }

        void DrawAniso()
        {
            if (!Module("aniso", "異方性ハイライト", "Anisotropic Highlight", "_UseAniso")) return;
            Props("_AnisoMode", "_AnisoStrength", "_AnisoBlend");
            Tex("_AnisoMask");
            Sub("向き", "Direction");
            Props("_AnisoTangent", "_AnisoAngle");
            if (When(F("_AnisoTangent") > 1.5f)) Vec("_AnisoCenter", new[] { "U", "V" }, new[] { 0f, 0f }, new[] { 1f, 1f });
            Sub("ハイライト", "Highlight");
            if (When(F("_AnisoMode") < 0.5f))
            {
                Tex("_AnisoShiftMap", "_AnisoShiftNoise");
                Props("_Aniso1Color", "_Aniso1Shift", "_Aniso1Exponent", "_Aniso2Color", "_Aniso2Shift", "_Aniso2Exponent", "_Aniso2Albedo");
            }
            if (When(F("_AnisoMode") > 0.5f)) Props("_Aniso1Color", "_Anisotropy");
            Sub("トゥーン", "Toon");
            Prop("_AnisoToony");
            if (When(F("_AnisoToony") > 0)) Prop("_AnisoToonBlur");
            EndModule();
        }

        void DrawAngelRing()
        {
            if (!Module("angelring", "天使の輪 (テクスチャ不要)", "Angel Ring (procedural)", "_UseAngelRing")) return;
            Props("_AngelColor", "_AngelHeight", "_AngelWidth", "_AngelBlur", "_AngelBreakup", "_AngelFrequency", "_AngelLightInfluence", "_AngelShadowMask");
            EndModule();
        }

        void DrawCloth()
        {
            if (Module("sheen", "シーン (布・ベルベット)", "Sheen (cloth / velvet)", "_UseSheen"))
            {
                Tex("_SheenMap", "_SheenColor");
                Tex("_SheenMask");
                Props("_SheenRoughness", "_SheenFuzz", "_SheenFuzzPower");
                EndModule();
            }
            if (Module("coat", "クリアコート", "Clear Coat", "_UseClearCoat"))
            {
                Tex("_ClearCoatMask", "_ClearCoat");
                Sub("表面", "Surface");
                Tex("_ClearCoatSmoothnessMap", "_ClearCoatSmoothness");
                Props("_ClearCoatF0", "_ClearCoatSpecColor", "_ClearCoatReflStrength");
                Sub("ノーマル", "Normal");
                Prop("_ClearCoatUseNormal");
                Tex("_ClearCoatNormalMap", "_ClearCoatNormalScale");
                Sub("下層", "Under the Coat");
                Prop("_ClearCoatColor");
                Sub("トゥーン", "Toon");
                Prop("_ClearCoatToony");
                if (When(F("_ClearCoatToony") > 0)) Prop("_ClearCoatToonBlur");
                EndModule();
            }
        }

        void DrawMatCap()
        {
            if (!Module("matcap", "マットキャップ", "MatCap", "_UseMatCap")) return;
            ModeRow();
            Tex("_MatCapTex", "_MatCapColor");
            Tex("_MatCapMask");
            Props("_MatCapBlend", "_MatCapLod", "_MatCapEnableLighting", "_MatCapShadowMask", "_MatCapMainStrength",
                  "_MatCapNormalStrength", "_MatCapPerspective", "_MatCapZRotCancel");
            if (When(Compat)) Prop("_MatCapBackfaceMask");
            if (Module("matcapbump", "専用ノーマルマップ", "Custom Normal Map", "_UseMatCapBump", true))
            {
                Tex("_MatCapBumpMap", "_MatCapBumpScale");
                EndModule();
            }
            if (Module("matcap2", "2nd マットキャップ", "2nd MatCap", "_UseMatCap2", true))
            {
                Tex("_MatCap2Tex", "_MatCap2Color");
                Tex("_MatCap2Mask");
                Props("_MatCap2Blend", "_MatCap2Lod", "_MatCap2EnableLighting", "_MatCap2ShadowMask", "_MatCap2NormalStrength");
                EndModule();
            }
            EndModule();
        }

        void DrawRim()
        {
            if (Module("rimgroup", "リムライト", "Rim Light", null))
            {
                ModeRow();
                bool compat = Compat;
                if (Module("rim", "リムライト1", "Rim Light 1", "_UseRim", true))
                {
                    Tex("_RimTex", "_RimColor");
                    Prop("_RimBlendMode");
                    if (When(!compat)) Prop("_RimLitSideOnly");
                    if (When(!compat && F("_RimLitSideOnly") > 0)) Prop("_RimLitSideBlur");
                    Props("_RimBorder", "_RimBlur", "_RimFresnelPower", "_RimLightDir");
                    if (When(compat)) Prop("_RimDirRange");
                    Props("_RimShadowMask", "_RimMainStrength", "_RimNormalStrength", "_RimEnableLighting", "_RimBackfaceMask");
                    if (When(compat))
                    {
                        Sub("影側のリム", "Shadow Side Rim");
                        Props("_RimIndirColor", "_RimIndirRange", "_RimIndirBorder", "_RimIndirBlur");
                    }
                    if (When(!compat))
                    {
                        Sub("深度リム (ゲーム風の一定幅リム)", "Depth Rim (constant width)");
                        Prop("_RimMode");
                        if (When(F("_RimMode") > 0.5f)) Props("_RimDepthWidth", "_RimDepthThreshold");
                    }
                    EndModule();
                }
                for (int n = 2; n <= 3; n++)
                {
                    string r = "_Rim" + n;
                    if (Module("rim" + n, "リムライト" + n, "Rim Light " + n, "_UseRim" + n, true))
                    {
                        Tex(r + "Tex", r + "Color");
                        Prop(r + "BlendMode");
                        if (When(!compat)) Prop(r + "LitSideOnly");
                        if (When(!compat && F(r + "LitSideOnly") > 0)) Prop(r + "LitSideBlur");
                        Props(r + "Border", r + "Blur", r + "FresnelPower", r + "LightDir", r + "ShadowMask", r + "MainStrength",
                              r + "NormalStrength", r + "EnableLighting", r + "BackfaceMask");
                        EndModule();
                    }
                }
                if (When(compat) && Module("rimshade", "リムシェード (輪郭を暗く)", "Rim Shade (darker edges)", "_UseRimShade", true))
                {
                    Tex("_RimShadeMask", "_RimShadeColor");
                    Props("_RimShadeBorder", "_RimShadeBlur", "_RimShadeFresnelPower", "_RimShadeNormalStrength");
                    EndModule();
                }
                EndModule();
            }
            if (Module("offsetrim", "オフセットリムライト", "Offset Rim Light", "_UseOffsetRim"))
            {
                Props("_OffsetRimColor", "_OffsetRimStrength", "_OffsetRimDirMode");
                if (When(F("_OffsetRimDirMode") > 1.5f && F("_OffsetRimDirMode") < 2.5f))
                    Vec("_OffsetRimVector", new[] { "X", "Y" }, new[] { -1f, -1f }, new[] { 1f, 1f });
                Props("_OffsetRimWidth", "_OffsetRimMaxPx", "_OffsetRimThreshold", "_OffsetRimSoftness", "_OffsetRimFacing",
                      "_OffsetRimLightInfluence", "_OffsetRimEnvInfluence", "_OffsetRimShadowMask", "_OffsetRimAlbedo", "_OffsetRimFadeEnd", "_OffsetRimFallback");
                Sub("発光", "Emission");
                Props("_OffsetRimEmission", "_OffsetRimEmissionStrength", "_OffsetRimEmissionAlbedo", "_OffsetRimHueSpeed");
                BlinkVec("_OffsetRimBlink");
                Info("「発光にする」を 1 にすると、ライト・環境光・影の影響を受けずに常に同じ明るさで光ります (暗いワールドでも見えます)。HDR の色や発光の強さを上げるとワールドのブルームで光がにじみます。",
                     "At 1 the rim glows at the same brightness regardless of lights, ambient and shadows (visible in dark worlds). Raise the HDR colour or strength to bloom in worlds with post processing.", MessageType.None);
                Info("深度テクスチャで輪郭の奥行きの差を拾う一定幅のリムです。深度が無い環境 (鏡など) ではフレネルで代用します。",
                     "Constant width rim from depth discontinuities. Falls back to fresnel where no depth texture exists (mirrors).", MessageType.None);
                EndModule();
            }
        }

        void DrawGlitter()
        {
            if (!Module("glitter", "ラメ", "Glitter", "_UseGlitter")) return;
            Tex("_GlitterMask", "_GlitterColor");
            Props("_GlitterUV", "_GlitterDensity", "_GlitterSize", "_GlitterSensitivity", "_GlitterSpeed", "_GlitterRandomColor",
                  "_GlitterEnableLighting", "_GlitterShadowMask");
            EndModule();
        }

        // rainbow settings of one emission slot; the rest only shows once it is in use
        void Rainbow(string pre)
        {
            Prop(pre + "Rainbow");
            var amount = P(pre + "Rainbow");
            if (collecting || amount == null || amount.hasMixedValue || amount.floatValue > 0.001f)
                Props(pre + "RainbowMode", pre + "RainbowSpeed", pre + "RainbowScale");
        }

        // four separate emission modules, each with its own rainbow and AudioLink
        void DrawEmission()
        {
            if (!Module("emissiongroup", "発光", "Emission", null)) return;
            if (Module("emission", "発光1", "Emission 1", "_UseEmission", true))
            {
                Tex("_EmissionMap", "_EmissionColor", "scroll:_EmissionScroll");
                Tex("_EmissionMask");
                BlinkVec("_EmissionBlink");
                Prop("_EmissionMainStrength");
                Rainbow("_Emission");
                if (Module("audiolink", "AudioLink", "AudioLink", "_UseAudioLink", true))
                {
                    Props("_AudioLinkBand", "_AudioLinkStrength", "_AudioLinkMin", "_AudioLinkDelay");
                    EndModule();
                }
                EndModule();
            }
            for (int n = 2; n <= 4; n++)
            {
                string e = "_Emission" + n;
                if (Module("emission" + n, "発光" + n, "Emission " + n, "_UseEmission" + n, true))
                {
                    Tex(e + "Map", e + "Color", e + "UV", "scroll:" + e + "Scroll");
                    Tex(e + "Mask");
                    BlinkVec(e + "Blink");
                    Rainbow(e);
                    if (Module("audiolink" + n, "AudioLink", "AudioLink", e + "AudioLink", true))
                    {
                        Props(e + "ALBand", e + "ALStrength", e + "ALMin", e + "ALDelay");
                        EndModule();
                    }
                    EndModule();
                }
            }
            EndModule();
        }

        void DrawProcedural()
        {
            if (Module("curvature", "曲率 (エッジ / くぼみ)", "Curvature (edge / cavity)", "_UseCurvature"))
            {
                Props("_CurvEdgeColor", "_CurvCavityColor", "_CurvScale", "_CurvSharpness", "_CurvLightInfluence");
                EndModule();
            }
            if (Module("hatch", "ハッチング (線影)", "Hatching (ink lines)", "_UseHatch"))
            {
                Props("_HatchColor", "_HatchSpace", "_HatchDensity", "_HatchAngle", "_HatchWidth", "_HatchThreshold", "_HatchCross", "_Hatch2ndThreshold", "_HatchNoise");
                EndModule();
            }
            if (Module("hologram", "ホログラム / スキャンライン", "Hologram / Scanlines", "_UseHologram"))
            {
                Props("_HoloColor", "_HoloStrength", "_HoloLineDensity", "_HoloLineSpeed", "_HoloFresnel", "_HoloFlicker", "_HoloFlickerSpeed", "_HoloAlpha");
                EndModule();
            }
        }

        void DrawFPS()
        {
            if (!Module("fpsmode", "FPS モード (コマ落ち揺らぎ)", "FPS Mode (hand drawn boil)", "_UseFPSMode")) return;
            Props("_FPSTarget", "_FPSRate", "_FPSAmp", "_FPSFreq", "_FPSNormal", "_FPSSnap", "_FPSWidthJitter");
            Info("指定したコマ数でだけ変化するノイズで頂点や輪郭線を揺らし、手描きアニメのような「コマ落ち」の動きにします。「輪郭線のみ」はアウトライン付きシェーダーで有効です。",
                 "Noise that only changes at the given frame rate wobbles vertices / outlines like hand drawn animation. Outline Only needs the outline shader.", MessageType.None);
            EndModule();
        }

        void DrawFlipbook()
        {
            if (!Module("flipbook", "フリップブック (コマ送りアニメ)", "Flipbook (sprite sheet)", "_UseFlipbook")) return;
            Tex("_FlipbookTex");
            Props("_FlipbookColor", "_FlipbookMode", "_FlipbookUV", "_FlipbookClamp");
            Vec("_FlipbookGrid", new[] { T("列", "Columns"), T("行", "Rows"), T("コマ数", "Frames"), T("速度 (fps)", "Speed (fps)") },
                new[] { 1f, 1f, 1f, 0f }, new[] { 64f, 64f, 4096f, 120f });
            Props("_FlipbookFrame", "_FlipbookBlend");
            if (!collecting && GUILayout.Button(T("GIF を読み込む (シートに変換)", "Import GIF (convert to a sprite sheet)")))
            {
                // the file dialog must not open in the middle of the inspector's layout
                var mats = me.targets.Cast<Material>().ToArray();
                EditorApplication.delayCall += () => MitToonGifImporter.ImportToFlipbook(mats);
                GUIUtility.ExitGUI();
            }
            Info("左上から右へ並んだコマを順に再生します。「手動のコマ番号」をアニメーションで動かすと表情差分などの切り替えにも使えます。",
                 "Plays frames laid out from the top left. Animate Manual Frame to switch expressions or other variations.", MessageType.None);
            EndModule();
        }

        void DrawBackface()
        {
            if (!Module("backface", "裏面", "Backface")) return;
            Props("_BackfaceColor");
            Tex("_BackfaceTex");
            Props("_BackfaceMainBlend", "_BackfaceFlipNormal");
            Info("両面表示 (カリング Off) の時に、スカートやそでの内側など裏面だけ色を変えます。", "Recolours back faces (inside of skirts / sleeves) when culling is Off.", MessageType.None);
            EndModule();
        }

        void DrawRefraction()
        {
            if (!Module("refraction", "疑似屈折 (宝石 / ガラス)", "Fake Refraction (gem / glass)")) return;
            Props("_RefractStrength", "_RefractIOR", "_RefractRoughness", "_RefractDispersion", "_RefractColor");
            Info("反射プローブを屈折方向で読み、奥の景色が透けて見えるようにします。GrabPass を使わないので軽く、不透明のままでも使えます。",
                 "Reads the reflection probe along the refracted ray so the scenery shows through. No grab pass: cheap and works on opaque materials.", MessageType.None);
            EndModule();
        }

        void DrawMaskPaintTool()
        {
            if (!Module("maskpaint", "マスクペイント (マスク画像の作成)", "Mask Paint (create mask images)")) return;
            Info("メッシュに直接塗ってマスク画像 (PNG) を出力する独立したツールです。ブラシ、UV塗りつぶし、左右対称に対応しています。出力した画像はテッセレーション、揺れ、発光など好きなマスク欄に入れて使います。",
                 "A separate tool that paints on the mesh and exports a mask image (PNG). Brush, UV island fill and left / right mirror. Put the exported image into any mask slot (tessellation, wobble, emission ...).", MessageType.None);
            if (GUILayout.Button(T("マスクペイントを開く", "Open Mask Paint"), GUILayout.Height(26)))
                MitToonMaskPainter.OpenFor((Material)me.target);
            EndModule();
        }

        void DrawTessellation(Material mat)
        {
            if (!Module("tess", "テッセレーション (メッシュの細分化)", "Tessellation (mesh subdivision)", null, false, false, () => IsTessShader(mat.shader), SetTess)) return;
            Info("ポリゴンを GPU で細かく分割します。輪郭が丸くなります。PC 専用 (Quest / Android ではフォールバックになります)。重いので、マスクで必要な所だけに絞ってください。",
                 "Subdivides the mesh on the GPU: rounder silhouettes. PC only (Quest / Android use the fallback). It is heavy, so limit it with the mask.", MessageType.None);
            Props("_TessEdgeLength", "_TessMax", "_TessPhong");
            Sub("距離", "Distance");
            Props("_TessFadeStart", "_TessFadeEnd");
            Sub("マスク", "Mask");
            Tex("_TessMask");
            Info("マスクの白い所だけ分割されます (黒は元のポリゴンのまま)。丸みもマスクに従います。",
                 "Only white areas are subdivided (black keeps the original polygons). Smoothing follows the mask too.", MessageType.None);
            Sub("ビルド時に設定 (NDMF)", "Set at Build (NDMF)");
            Info("アバターに「MitToon Tessellation」コンポーネントを付けると、アップロード時にマテリアルを複製してテッセレーション版に切り替えます (元のマテリアルは変わりません)。",
                 "Add the MitToon Tessellation component to the avatar to clone the materials and switch them to tessellation at upload (the original materials stay unchanged).", MessageType.None);
            EndModule();
        }

        void DrawWobble()
        {
            if (!Module("wobble", "揺れ (頂点アニメーション)", "Wobble (vertex animation)")) return;
            Props("_WobbleStrength");
            Vec("_WobbleDir", new[] { "X", "Y", "Z" }, new[] { -1f, -1f, -1f }, new[] { 1f, 1f, 1f });
            Props("_WobbleSpeed", "_WobbleFrequency", "_WobbleGust");
            Tex("_WobbleMask");
            Prop("_WobbleVertexColor");
            Info("髪先やリボン、植物などを風で揺らします。マスクの白い所だけが動きます (影とアウトラインも一緒に動きます)。",
                 "Sways hair tips, ribbons or plants in the wind. Only white areas of the mask move (shadows and outlines follow).", MessageType.None);
            EndModule();
        }

        void DrawVisibility()
        {
            if (!Module("visibility", "表示制御 (ミラー / カメラ / UV タイル)", "Visibility (mirror / camera / UV tile)")) return;
            Props("_MirrorVisibility", "_CameraVisibility");
            Sub("UV タイルで非表示", "Hide by UV Tile");
            Prop("_UVTileUV");
            var p = P("_UVTileHide");
            if (Show(p))
            {
                Info("UV を 0-1 の外 (最大 4x4 マス) にずらした部分を、マスごとに消せます。アニメーションで切り替えれば、マテリアルを分けずに衣装やパーツの表示を切り替えられます。",
                     "Hides mesh parts whose UVs sit in the chosen tile (up to 4x4). Animate it to toggle outfit parts without extra materials.", MessageType.None);
                int mask = (int)p.floatValue;
                EditorGUI.BeginChangeCheck();
                for (int y = 3; y >= 0; y--)
                {
                    EditorGUILayout.BeginHorizontal();
                    GUILayout.Space(18);
                    for (int x = 0; x < 4; x++)
                    {
                        int b = 1 << (x + y * 4);
                        bool on = GUILayout.Toggle((mask & b) != 0, x + "," + y, "Button", GUILayout.Width(48));
                        mask = on ? mask | b : mask & ~b;
                    }
                    EditorGUILayout.EndHorizontal();
                }
                if (EditorGUI.EndChangeCheck()) p.floatValue = mask;
            }
            EndModule();
        }

        void DrawDissolve()
        {
            if (Module("dissolve", "ディゾルブ", "Dissolve", "_UseDissolve"))
            {
                Prop("_DissolveMode");
                float m = F("_DissolveMode");
                if (When(m < 0.5f)) Tex("_DissolveNoise");
                if (When(m > 1.5f)) Vec("_DissolveHeightRange", new[] { T("下端", "Min"), T("上端", "Max") }, new[] { 0f, 0f }, new[] { 0f, 0f });
                Props("_DissolveAmount", "_DissolveEdgeWidth", "_DissolveEdgeColor");
                EndModule();
            }
            if (Module("distfade", "距離フェード", "Distance Fade", "_UseDistanceFade"))
            {
                Props("_DistanceFadeColor", "_DistanceFadeStart", "_DistanceFadeEnd", "_DistanceFadeStrength", "_NearDither");
                if (When(F("_NearDither") > 0.5f)) Prop("_NearDitherDistance");
                EndModule();
            }
        }

        void DrawOutline(Material mat)
        {
            if (!Module("outline", "アウトライン", "Outline", null, false, false, () => HasOutline(mat), SetOutline)) return;
            Tex("_OutlineTex", "_OutlineColor");
            Tex("_OutlineWidthMask", "_OutlineWidth");
            Props("_OutlineNormalSource", "_OutlineVertexColorWidth", "_OutlineFixWidth", "_OutlineZBias", "_OutlineMainBlend", "_OutlineEnableLighting");
            Props("_OutlineFixDistance", "_OutlineFOVCompensate");
            if (Module("inkline", "入り抜き輪郭線 (筆の強弱)", "Ink Line (brush taper)", "_UseInkLine", true))
            {
                Props("_InkStrength", "_InkWidth", "_InkAngle", "_InkGap", "_InkTaper", "_InkMin", "_InkUnder");
                Vec("_InkUnderDir", new[] { "X", "Y", "Z" }, new[] { -1f, -1f, -1f }, new[] { 1f, 1f, 1f });
                Props("_InkNoise", "_InkNoiseFreq");
                Info("線の向き (画面上) に応じて平筆のように太さが変わり、端が細く抜けます。", "Width follows the stroke direction like a flat pen and tapers at the ends.", MessageType.None);
                EndModule();
            }
            Sub("二重アウトライン (外側)", "Double Outline (outer)");
            Props("_Outline2Width", "_Outline2Color", "_Outline2MainBlend", "_Outline2EnableLighting", "_Outline2ZBias");
            if (!collecting && !Searching && GUILayout.Button(T("このマテリアルのメッシュにスムーズ法線をベイク (頂点カラー)", "Bake smoothed normals to vertex colors (meshes using this material)")))
                MitToonOutlineBaker.BakeForMaterials(me.targets.Cast<Material>().ToArray());
            EndModule();
        }

        void DrawGrading()
        {
            if (!Module("grading", "トーンマップ / 色調補正", "Tonemap / Color Grading", "_UseTonemap")) return;
            Props("_TonemapMode", "_Exposure", "_Contrast", "_Saturation", "_Vibrance", "_Temperature", "_Tint", "_ShadowTint", "_HighlightTint");
            Info("アバターの全マテリアルで同じ値にしてください (プリセットの「スタイル」で一括設定できます)。", "Keep these identical on every material of the avatar (use a Style preset).", MessageType.None);
            Info("ポストエフェクト無しで映画的な階調を出すためのマテリアル単位の補正です。",
                 "Per material grading for a filmic response without post processing.", MessageType.None);
            EndModule();
        }

        void DebugPopup()
        {
            var p = P("_DebugView");
            if (p == null || !Show(p)) return;
            var o = JP ? new[] { "オフ", "アルベド", "法線", "ライティング", "影", "AO", "深度の有効性", "曲率", "環境光 (SH / LV)", "ライトボリューム" }
                       : new[] { "Off", "Albedo", "Normal", "Lighting", "Shadow", "Ambient Occlusion", "Depth Validity", "Curvature", "Ambient (SH / LV)", "Light Volume" };
            EditorGUI.BeginChangeCheck();
            int v = EditorGUILayout.Popup(Label(p), Mathf.RoundToInt(p.floatValue), o.Select(x => new GUIContent(x)).ToArray());
            if (EditorGUI.EndChangeCheck()) p.floatValue = v;
        }

        void DrawAdvanced()
        {
            if (!Module("advanced", "詳細設定 (深度 / ステンシル)", "Advanced (Depth / Stencil)")) return;
            DebugPopup();
            Props("_ZWrite", "_ZTest", "_AlphaToMask", "_OffsetFactor", "_OffsetUnits");
            Sub("ステンシル", "Stencil");
            Props("_StencilRef", "_StencilReadMask", "_StencilWriteMask", "_StencilComp", "_StencilPass", "_StencilFail", "_StencilZFail");
            if (!collecting && !Searching)
            {
                EditorGUILayout.Space(2);
                me.RenderQueueField();
                me.EnableInstancingField();
            }
            EndModule();
        }

        // ================================================================== material setup
        public override void ValidateMaterial(Material material) => SyncKeywords(material);

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            if (MitToonCompatConverter.IsSource(oldShader))
            {
                // switched from a compatible toon shader: keep the look (values read before the shader changes)
                var sn = MitToonCompatConverter.Take(material);
                base.AssignNewShaderToMaterial(material, oldShader, newShader);
                foreach (var note in MitToonCompatConverter.Apply(material, sn)) Debug.Log("MitToon: " + material.name + ": " + note, material);
                return;
            }
            base.AssignNewShaderToMaterial(material, oldShader, newShader);
            if (oldShader == null || !oldShader.name.StartsWith("MitToon/")) ApplyRenderMode(material, true);
            SyncKeywords(material);
        }

        public static void SyncKeywords(Material m)
        {
            foreach (var (prop, kw) in KeywordMap)
            {
                if (!m.HasProperty(prop)) continue;
                bool on = m.GetFloat(prop) > 0.5f;
                if (kw == "_LUMI_LIGHTVOLUMES" && !LightVolumesInstalled) on = false;   // keep the shader compiling without the package
                if (on) m.EnableKeyword(kw); else m.DisableKeyword(kw);
            }
            // rim lights 1-3 share one keyword
            if (m.HasProperty("_UseRim2"))
            {
                if (On("_UseRim") || On("_UseRim2") || On("_UseRim3")) m.EnableKeyword("_LUMI_RIM"); else m.DisableKeyword("_LUMI_RIM");
            }
            m.DisableKeyword("_LUMI_RIMSHADE");   // removed feature, cleared from old materials
            // emission 1-4 are separate modules sharing one keyword; each has its own AudioLink
            bool On(string p) => m.HasProperty(p) && m.GetFloat(p) > 0.5f;
            if (m.HasProperty("_UseEmission"))
            {
                bool e1 = On("_UseEmission"), e2 = On("_UseEmission2"), e3 = On("_UseEmission3"), e4 = On("_UseEmission4");
                bool al = (e1 && On("_UseAudioLink")) || (e2 && On("_Emission2AudioLink")) || (e3 && On("_Emission3AudioLink")) || (e4 && On("_Emission4AudioLink"));
                if (e1 || e2 || e3 || e4) m.EnableKeyword("_LUMI_EMISSION"); else m.DisableKeyword("_LUMI_EMISSION");
                if (al) m.EnableKeyword("_LUMI_AUDIOLINK"); else m.DisableKeyword("_LUMI_AUDIOLINK");
            }
            ApplyRenderMode(m, false);
        }

        public static void ApplyRenderMode(Material m, bool reset)
        {
            if (!m.HasProperty("_RenderMode")) return;
            int mode = Mathf.RoundToInt(m.GetFloat("_RenderMode"));
            m.DisableKeyword("_ALPHATEST_ON");
            m.DisableKeyword("_ALPHABLEND_ON");
            m.DisableKeyword("_ALPHAPREMULTIPLY_ON");
            switch (mode)
            {
                case 1:
                    Set(m, BlendMode.One, BlendMode.Zero, BlendMode.One, BlendMode.One, 1, reset);
                    m.EnableKeyword("_ALPHATEST_ON");
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    if (reset) m.renderQueue = (int)RenderQueue.AlphaTest;
                    if (reset && m.HasProperty("_AlphaToMask")) m.SetFloat("_AlphaToMask", 1);   // anti-aliased cutout edge
                    break;
                case 2:
                case 5:
                    // depth write on: the nearest layer of the same mesh wins instead of random overlap
                    Set(m, BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha, BlendMode.SrcAlpha, BlendMode.One, 1, reset);
                    m.EnableKeyword("_ALPHABLEND_ON");
                    m.SetOverrideTag("RenderType", "Transparent");
                    if (reset) m.renderQueue = (int)RenderQueue.Transparent;
                    break;
                case 3:
                case 6:
                    Set(m, BlendMode.One, BlendMode.OneMinusSrcAlpha, BlendMode.One, BlendMode.One, 1, reset);
                    m.EnableKeyword("_ALPHAPREMULTIPLY_ON");
                    m.SetOverrideTag("RenderType", "Transparent");
                    if (reset) m.renderQueue = (int)RenderQueue.Transparent;
                    break;
                case 4:
                    Set(m, BlendMode.One, BlendMode.One, BlendMode.One, BlendMode.One, 0, reset);
                    m.EnableKeyword("_ALPHAPREMULTIPLY_ON");
                    m.SetOverrideTag("RenderType", "Transparent");
                    if (reset) m.renderQueue = (int)RenderQueue.Transparent;
                    break;
                default:
                    Set(m, BlendMode.One, BlendMode.Zero, BlendMode.One, BlendMode.One, 1, reset);
                    m.SetOverrideTag("RenderType", "");
                    if (reset) m.renderQueue = -1;
                    break;
            }
        }

        static void Set(Material m, BlendMode src, BlendMode dst, BlendMode srcAdd, BlendMode dstAdd, int zwrite, bool setZWrite)
        {
            m.SetFloat("_SrcBlend", (float)src);
            m.SetFloat("_DstBlend", (float)dst);
            m.SetFloat("_SrcBlendAdd", (float)srcAdd);
            m.SetFloat("_DstBlendAdd", (float)dstAdd);
            if (setZWrite) m.SetFloat("_ZWrite", zwrite);
        }
    }
}
