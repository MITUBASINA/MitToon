using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace MitToon.Editor
{
    // One window for every material of an avatar: convert from lilToon, edit many MitToon materials at once,
    // and set up the fake shadow (hair shadow on the face).
    // Bulk editing shows the normal MitToon inspector on a scratch copy of one material; whatever is changed there
    // (and only that) is copied to every selected material, so the rest of each material stays as it was.
    public class MitToonAvatarBatch : EditorWindow
    {
        const string OutRoot = "Assets/MitToon_UserData";

        enum Kind { MitToon, FakeShadow, Convertible, LilFakeShadow, Other }
        class Entry { public Material mat; public Kind kind; public bool on = true; }

        GameObject avatar;
        readonly List<Entry> entries = new List<Entry>();
        int tab;
        Vector2 listScroll, mainScroll;
        bool keepOriginals = true;

        // bulk editing
        Material proxy;
        MaterialEditor proxyEditor;
        Material proxySource;
        int baseIndex;

        // fake shadow
        int faceIndex, hairIndex;
        int stencilRef = 51;
        GameObject lastAvatar;

        static string T(string jp, string en) => MitToonShaderGUI.JP ? jp : en;

        [MenuItem("Tools/MitToon/アバターのマテリアル一括設定 (Avatar Batch)")]
        static void Open()
        {
            var w = GetWindow<MitToonAvatarBatch>("MitToon Batch");
            w.minSize = new Vector2(420, 480);
            if (Selection.activeGameObject != null) w.SetAvatar(Selection.activeGameObject.transform.root.gameObject);
        }

        void OnDisable() => DropProxy();
        void OnFocus() { if (avatar != null) Rescan(); }

        void SetAvatar(GameObject go)
        {
            avatar = go;
            Rescan();
        }

        static Kind KindOf(Material m)
        {
            var s = m.shader;
            if (s == null) return Kind.Other;
            if (s.name == MitToonCompatConverter.FakeShadowShaderName) return Kind.FakeShadow;
            if (s.name.StartsWith("MitToon/")) return Kind.MitToon;
            if (MitToonCompatConverter.IsFakeShadowSource(s)) return Kind.LilFakeShadow;
            if (MitToonCompatConverter.IsSource(s)) return Kind.Convertible;
            return Kind.Other;
        }

        Renderer[] Renderers() => avatar != null ? avatar.GetComponentsInChildren<Renderer>(true) : new Renderer[0];

        void Rescan()
        {
            var old = entries.ToDictionary(e => e.mat, e => e.on);
            entries.Clear();
            var seen = new HashSet<Material>();
            foreach (var r in Renderers())
                foreach (var m in r.sharedMaterials)
                    if (m != null && seen.Add(m))
                        entries.Add(new Entry { mat = m, kind = KindOf(m), on = !old.TryGetValue(m, out var on) || on });
            entries.Sort((a, b) => a.kind != b.kind ? a.kind.CompareTo(b.kind) : string.CompareOrdinal(a.mat.name, b.mat.name));
            // start from the stencil value the avatar's fake shadow already uses
            var fake = entries.FirstOrDefault(e => (e.kind == Kind.FakeShadow || e.kind == Kind.LilFakeShadow) && e.mat.HasProperty("_StencilRef"));
            if (fake != null && avatar != lastAvatar) stencilRef = Mathf.Clamp(Mathf.RoundToInt(fake.mat.GetFloat("_StencilRef")), 1, 255);
            lastAvatar = avatar;
            Repaint();
        }

        IEnumerable<Material> Selected(params Kind[] kinds) => entries.Where(e => e.on && kinds.Contains(e.kind)).Select(e => e.mat);

        void OnGUI()
        {
            EditorGUILayout.Space(4);
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUI.BeginChangeCheck();
                var go = (GameObject)EditorGUILayout.ObjectField(T("アバター", "Avatar"), avatar, typeof(GameObject), true);
                if (EditorGUI.EndChangeCheck()) SetAvatar(go);
                if (GUILayout.Button(T("選択中", "Selection"), GUILayout.Width(70)) && Selection.activeGameObject != null)
                    SetAvatar(Selection.activeGameObject.transform.root.gameObject);
            }
            if (avatar == null)
            {
                EditorGUILayout.HelpBox(T("ヒエラルキーのアバターを指定してください。", "Pick an avatar in the hierarchy."), MessageType.Info);
                return;
            }
            DrawList();
            EditorGUILayout.Space(4);
            tab = GUILayout.Toolbar(tab, new[] { T("lilToon から変換", "Convert from lilToon"), T("一括編集", "Bulk Edit"), T("フェイクシャドウ", "Fake Shadow") });
            EditorGUILayout.Space(4);
            // vertical scrolling only and a fixed content width: otherwise wide inspector rows widen the view and the help boxes get cut off
            mainScroll = EditorGUILayout.BeginScrollView(mainScroll, false, false, GUIStyle.none, GUI.skin.verticalScrollbar, GUIStyle.none);
            EditorGUILayout.BeginVertical(GUILayout.Width(position.width - 20));
            if (tab == 0) DrawConvert();
            else if (tab == 1) DrawBulk();
            else DrawFakeShadow();
            EditorGUILayout.EndVertical();
            EditorGUILayout.EndScrollView();
        }

        // ------------------------------------------------------------------ material list
        void DrawList()
        {
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField(T("マテリアル", "Materials") + $" ({entries.Count(e => e.on)}/{entries.Count})", EditorStyles.boldLabel);
                if (GUILayout.Button(T("全選択", "All"), EditorStyles.miniButtonLeft, GUILayout.Width(60))) entries.ForEach(e => e.on = true);
                if (GUILayout.Button(T("解除", "None"), EditorStyles.miniButtonMid, GUILayout.Width(50))) entries.ForEach(e => e.on = false);
                if (GUILayout.Button(T("再読込", "Rescan"), EditorStyles.miniButtonRight, GUILayout.Width(60))) Rescan();
            }
            listScroll = EditorGUILayout.BeginScrollView(listScroll, EditorStyles.helpBox, GUILayout.Height(Mathf.Clamp(entries.Count * 20 + 8, 48, 200)));
            foreach (var e in entries)
            {
                using (new EditorGUILayout.HorizontalScope())
                {
                    e.on = EditorGUILayout.Toggle(e.on, GUILayout.Width(16));
                    using (new EditorGUI.DisabledScope(true)) EditorGUILayout.ObjectField(e.mat, typeof(Material), false);
                    GUILayout.Label(KindLabel(e.kind), EditorStyles.miniLabel, GUILayout.Width(110));
                }
            }
            EditorGUILayout.EndScrollView();
        }

        static string KindLabel(Kind k)
        {
            switch (k)
            {
                case Kind.MitToon: return "MitToon";
                case Kind.FakeShadow: return T("MitToon フェイクシャドウ", "MitToon Fake Shadow");
                case Kind.Convertible: return T("lilToon (変換できます)", "lilToon (convertible)");
                case Kind.LilFakeShadow: return T("lilToon フェイクシャドウ", "lilToon Fake Shadow");
                default: return T("対象外", "Other");
            }
        }

        // ------------------------------------------------------------------ convert
        void DrawConvert()
        {
            var targets = Selected(Kind.Convertible, Kind.LilFakeShadow).ToList();
            EditorGUILayout.HelpBox(T("lilToon のマテリアルを、見た目をおおまかに保ったまま MitToon に変換します。フェイクシャドウのマテリアルは MitToon のフェイクシャドウに変換します。",
                                      "Converts lilToon materials to MitToon, keeping roughly the same look. Fake shadow materials become MitToon fake shadows."), MessageType.None);
            keepOriginals = EditorGUILayout.ToggleLeft(T("元のマテリアルを残す (複製を変換してアバターに差し替え)", "Keep the originals (convert copies and swap them on the avatar)"), keepOriginals);
            if (keepOriginals)
                EditorGUILayout.HelpBox(T($"複製は {OutRoot}/Converted/{avatar.name} に保存します。アニメーションで切り替えるマテリアルは差し替わらないので、必要ならアニメーション側も変更してください。",
                                          $"Copies are saved to {OutRoot}/Converted/{avatar.name}. Materials swapped by animations are not replaced; update those animations if needed."), MessageType.Info);
            using (new EditorGUI.DisabledScope(targets.Count == 0))
                if (GUILayout.Button(T($"選択中の {targets.Count} 個を変換", $"Convert {targets.Count} selected"), GUILayout.Height(28)))
                    Convert(targets);
            if (targets.Count == 0)
                EditorGUILayout.HelpBox(T("選択中のマテリアルに、変換できる lilToon のマテリアルはありません。", "No convertible lilToon material is selected."), MessageType.None);
        }

        void Convert(List<Material> targets)
        {
            var map = new Dictionary<Material, Material>();
            int noted = 0;
            if (keepOriginals)
            {
                string dir = EnsureFolder(OutRoot + "/Converted/" + Safe(avatar.name));
                foreach (var m in targets)
                {
                    var copy = new Material(m) { name = m.name };
                    AssetDatabase.CreateAsset(copy, AssetDatabase.GenerateUniqueAssetPath(dir + "/" + Safe(m.name) + ".mat"));
                    map[m] = copy;
                }
                var rs = Renderers();
                Undo.RecordObjects(rs, "MitToon Batch Convert");
                foreach (var r in rs)
                {
                    var arr = r.sharedMaterials;
                    bool changed = false;
                    for (int i = 0; i < arr.Length; i++)
                        if (arr[i] != null && map.TryGetValue(arr[i], out var c)) { arr[i] = c; changed = true; }
                    if (changed) { r.sharedMaterials = arr; PrefabUtility.RecordPrefabInstancePropertyModifications(r); }
                }
            }
            else
            {
                Undo.RecordObjects(targets.ToArray(), "MitToon Batch Convert");
                foreach (var m in targets) map[m] = m;
            }
            foreach (var kv in map)
            {
                var notes = MitToonCompatConverter.Convert(kv.Value);
                EditorUtility.SetDirty(kv.Value);
                if (notes.Count > 0) { noted++; Debug.Log("MitToon: " + kv.Value.name + "\n  " + string.Join("\n  ", notes), kv.Value); }
            }
            AssetDatabase.SaveAssets();
            Debug.Log($"MitToon: {map.Count} 個のマテリアルを変換しました" + (noted > 0 ? $" (うち {noted} 個は一部の設定に近い値を使っています。詳細は上のログ)" : ""));
            Rescan();
        }

        // ------------------------------------------------------------------ bulk edit
        void DrawBulk()
        {
            var mats = Selected(Kind.MitToon).ToList();
            if (mats.Count == 0)
            {
                DropProxy();
                EditorGUILayout.HelpBox(T("選択中のマテリアルに MitToon のマテリアルがありません。", "No MitToon material is selected."), MessageType.Info);
                return;
            }
            EditorGUILayout.HelpBox(T($"下のインスペクターで変更した項目だけが、選択中の {mats.Count} 個のマテリアルすべてに反映されます。表示している値は基準のマテリアルのものです。元に戻すには Ctrl+Z を使ってください。",
                                      $"Only what you change in the inspector below is applied to all {mats.Count} selected materials. The values shown are the base material's. Undo with Ctrl+Z."), MessageType.Info);
            baseIndex = Mathf.Clamp(baseIndex, 0, mats.Count - 1);
            baseIndex = EditorGUILayout.Popup(T("基準のマテリアル", "Base Material"), baseIndex, mats.Select(m => m.name).ToArray());
            if (proxy == null || proxySource != mats[baseIndex]) MakeProxy(mats[baseIndex]);

            var before = Snapshot(proxy);
            var shaderBefore = proxy.shader;
            int queueBefore = proxy.renderQueue;
            try
            {
                EditorGUILayout.Space(4);
                proxyEditor.PropertiesGUI();
            }
            finally
            {
                // also runs when the inspector leaves the GUI early (outline / tessellation switches)
                ApplyChanges(mats, before, shaderBefore, queueBefore);
            }
        }

        void MakeProxy(Material src)
        {
            DropProxy();
            proxySource = src;
            proxy = new Material(src) { name = src.name + " (batch)", hideFlags = HideFlags.DontSave };
            proxyEditor = (MaterialEditor)UnityEditor.Editor.CreateEditor(proxy);
        }

        void DropProxy()
        {
            if (proxyEditor != null) DestroyImmediate(proxyEditor);
            if (proxy != null) DestroyImmediate(proxy);
            proxyEditor = null; proxy = null; proxySource = null;
        }

        static Dictionary<string, object> Snapshot(Material m)
        {
            var d = new Dictionary<string, object>();
            var sh = m.shader;
            for (int i = 0; i < sh.GetPropertyCount(); i++)
            {
                string p = sh.GetPropertyName(i);
                switch (sh.GetPropertyType(i))
                {
                    case ShaderPropertyType.Float:
                    case ShaderPropertyType.Range: d[p] = m.GetFloat(p); break;
                    case ShaderPropertyType.Color: d[p] = m.GetColor(p); break;
                    case ShaderPropertyType.Vector: d[p] = m.GetVector(p); break;
                    case ShaderPropertyType.Texture:
                        var s = m.GetTextureScale(p); var o = m.GetTextureOffset(p);
                        d[p] = (m.GetTexture(p), new Vector4(s.x, s.y, o.x, o.y));
                        break;
                }
            }
            return d;
        }

        void ApplyChanges(List<Material> mats, Dictionary<string, object> before, Shader shaderBefore, int queueBefore)
        {
            if (proxy == null) return;
            var after = Snapshot(proxy);
            var changed = after.Where(kv => !before.TryGetValue(kv.Key, out var b) || !Equals(b, kv.Value)).Select(kv => kv.Key).ToList();
            bool shaderChanged = proxy.shader != shaderBefore;
            bool queueChanged = proxy.renderQueue != queueBefore;
            if (changed.Count == 0 && !shaderChanged && !queueChanged) return;

            var targets = mats.Where(m => m != null).ToArray();
            Undo.RecordObjects(targets, "MitToon Batch Edit");
            bool outlineChanged = shaderChanged && MitToonShaderGUI.IsOutlineShader(proxy.shader) != MitToonShaderGUI.IsOutlineShader(shaderBefore);
            bool tessChanged = shaderChanged && MitToonShaderGUI.IsTessShader(proxy.shader) != MitToonShaderGUI.IsTessShader(shaderBefore);
            bool modeChanged = changed.Contains("_RenderMode");
            foreach (var m in targets)
            {
                foreach (var p in changed)
                {
                    if (!m.HasProperty(p)) continue;
                    switch (after[p])
                    {
                        case float f: m.SetFloat(p, f); break;
                        case Color c: m.SetColor(p, c); break;
                        case Vector4 v: m.SetVector(p, v); break;
                        case System.ValueTuple<Texture, Vector4> t:
                            m.SetTexture(p, t.Item1);
                            m.SetTextureScale(p, new Vector2(t.Item2.x, t.Item2.y));
                            m.SetTextureOffset(p, new Vector2(t.Item2.z, t.Item2.w));
                            break;
                    }
                }
                if (outlineChanged || tessChanged || modeChanged)
                {
                    bool outline = outlineChanged ? MitToonShaderGUI.IsOutlineShader(proxy.shader) : MitToonShaderGUI.IsOutlineShader(m.shader);
                    bool tess = tessChanged ? MitToonShaderGUI.IsTessShader(proxy.shader) : MitToonShaderGUI.IsTessShader(m.shader);
                    bool two = m.HasProperty("_RenderMode") && MitToonShaderGUI.IsTwoPassMode(Mathf.RoundToInt(m.GetFloat("_RenderMode")));
                    var s = Shader.Find(MitToonShaderGUI.ShaderNameFor(outline, two, tess));
                    int q = m.renderQueue;
                    if (s != null && s != m.shader) { m.shader = s; m.renderQueue = q; }
                }
                if (modeChanged) MitToonShaderGUI.ApplyRenderMode(m, true);
                if (queueChanged) m.renderQueue = proxy.renderQueue;
                MitToonShaderGUI.SyncKeywords(m);
                EditorUtility.SetDirty(m);
            }
            if (shaderChanged)
            {
                // the inspector of the scratch copy has to be rebuilt for the new shader
                if (proxyEditor != null) DestroyImmediate(proxyEditor);
                proxyEditor = (MaterialEditor)UnityEditor.Editor.CreateEditor(proxy);
            }
        }

        // ------------------------------------------------------------------ fake shadow
        void DrawFakeShadow()
        {
            EditorGUILayout.HelpBox(T("髪のメッシュにフェイクシャドウのマテリアルを重ね、顔の上にだけ髪の影を落とします。顔のマテリアルがステンシルを書き込み、フェイクシャドウはその部分にだけ描かれます。",
                                      "A fake shadow material on the hair mesh drops a hair shadow onto the face only. The face material writes the stencil and the fake shadow only draws there."), MessageType.None);
            var fakes = entries.Where(e => e.kind == Kind.FakeShadow || e.kind == Kind.LilFakeShadow).Select(e => e.mat).ToList();
            if (fakes.Count > 0 && fakes.Any(m => KindOf(m) == Kind.LilFakeShadow))
                EditorGUILayout.HelpBox(T("lilToon のフェイクシャドウがあります。「lilToon から変換」タブで MitToon に変換できます。", "There are lilToon fake shadows; convert them in the Convert tab."), MessageType.Info);

            EditorGUILayout.LabelField(T("1. 髪にフェイクシャドウを追加", "1. Add a fake shadow to the hair"), EditorStyles.boldLabel);
            var rs = Renderers().Where(r => r is SkinnedMeshRenderer || r is MeshRenderer).ToArray();
            if (rs.Length == 0) { EditorGUILayout.HelpBox(T("メッシュがありません。", "No meshes."), MessageType.None); return; }
            hairIndex = Mathf.Clamp(hairIndex, 0, rs.Length - 1);
            hairIndex = EditorGUILayout.Popup(T("髪のメッシュ", "Hair Mesh"), hairIndex, rs.Select(r => r.name).ToArray());
            var hair = rs[hairIndex];
            var mesh = MeshOf(hair);
            bool already = hair.sharedMaterials.Any(m => m != null && m.shader != null && m.shader.name == MitToonCompatConverter.FakeShadowShaderName);
            if (mesh != null && mesh.subMeshCount > 1)
                EditorGUILayout.HelpBox(T("このメッシュは複数のマテリアルを持っています。追加したフェイクシャドウは最後のマテリアルの部分にだけ描かれます。",
                                          "This mesh has several materials; the added fake shadow draws only the last one's part."), MessageType.Warning);
            using (new EditorGUI.DisabledScope(already))
                if (GUILayout.Button(already ? T("追加済みです", "Already added") : T("フェイクシャドウを追加", "Add Fake Shadow"))) AddFakeShadow(hair);

            EditorGUILayout.Space(8);
            EditorGUILayout.LabelField(T("2. 顔のマテリアルにステンシルを設定", "2. Set the stencil on the face material"), EditorStyles.boldLabel);
            var mt = entries.Where(e => e.kind == Kind.MitToon).Select(e => e.mat).ToList();
            if (mt.Count == 0) { EditorGUILayout.HelpBox(T("MitToon のマテリアルがありません。先に変換してください。", "No MitToon material yet; convert first."), MessageType.None); return; }
            faceIndex = Mathf.Clamp(faceIndex, 0, mt.Count - 1);
            faceIndex = EditorGUILayout.Popup(T("顔のマテリアル", "Face Material"), faceIndex, mt.Select(m => m.name).ToArray());
            stencilRef = EditorGUILayout.IntSlider(T("ステンシル参照値", "Stencil Ref"), stencilRef, 1, 255);
            var face = mt[faceIndex];
            bool ok = Mathf.RoundToInt(face.GetFloat("_StencilRef")) == stencilRef && Mathf.RoundToInt(face.GetFloat("_StencilPass")) == (int)StencilOp.Replace;
            if (ok) EditorGUILayout.HelpBox(T("この顔のマテリアルは設定済みです。", "This face material is already set."), MessageType.None);
            if (GUILayout.Button(T("顔とフェイクシャドウのステンシルを合わせる", "Match the stencil of face and fake shadows")))
            {
                var all = new List<Material> { face };
                all.AddRange(fakes.Where(m => KindOf(m) == Kind.FakeShadow));
                Undo.RecordObjects(all.ToArray(), "MitToon Fake Shadow Stencil");
                face.SetFloat("_StencilRef", stencilRef);
                face.SetFloat("_StencilComp", (float)CompareFunction.Always);
                face.SetFloat("_StencilPass", (float)StencilOp.Replace);
                EditorUtility.SetDirty(face);
                foreach (var f in all.Skip(1))
                {
                    f.SetFloat("_StencilRef", stencilRef);
                    f.SetFloat("_StencilComp", (float)CompareFunction.Equal);
                    EditorUtility.SetDirty(f);
                }
            }
        }

        static Mesh MeshOf(Renderer r)
        {
            if (r is SkinnedMeshRenderer s) return s.sharedMesh;
            var mf = r.GetComponent<MeshFilter>();
            return mf != null ? mf.sharedMesh : null;
        }

        void AddFakeShadow(Renderer hair)
        {
            var sh = Shader.Find(MitToonCompatConverter.FakeShadowShaderName);
            if (sh == null) return;
            string dir = EnsureFolder(OutRoot + "/FakeShadow/" + Safe(avatar.name));
            var m = new Material(sh) { name = hair.name + "_FakeShadow" };
            m.SetFloat("_StencilRef", stencilRef);
            AssetDatabase.CreateAsset(m, AssetDatabase.GenerateUniqueAssetPath(dir + "/" + Safe(m.name) + ".mat"));
            Undo.RecordObject(hair, "MitToon Add Fake Shadow");
            var arr = hair.sharedMaterials.ToList();
            arr.Add(m);
            hair.sharedMaterials = arr.ToArray();
            PrefabUtility.RecordPrefabInstancePropertyModifications(hair);
            AssetDatabase.SaveAssets();
            Rescan();
        }

        // ------------------------------------------------------------------ helpers
        static string Safe(string s)
        {
            foreach (var c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
            return s;
        }

        static string EnsureFolder(string path)
        {
            var parts = path.Split('/');
            string cur = parts[0];
            for (int i = 1; i < parts.Length; i++)
            {
                string next = cur + "/" + parts[i];
                if (!AssetDatabase.IsValidFolder(next)) AssetDatabase.CreateFolder(cur, parts[i]);
                cur = next;
            }
            return cur;
        }
    }
}
