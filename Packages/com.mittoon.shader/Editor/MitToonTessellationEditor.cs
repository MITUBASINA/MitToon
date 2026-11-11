// MitToon - inspector for the MitToon Tessellation build component
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    [CustomEditor(typeof(MitToonTessellation))]
    public class MitToonTessellationEditor : UnityEditor.Editor
    {
        static bool JP => MitToonShaderGUI.JP;
        static string T(string jp, string en) => MitToonShaderGUI.Bare(JP ? jp : en);

        void Field(string name, string jp, string en)
        {
            var p = serializedObject.FindProperty(name);
            if (p != null) EditorGUILayout.PropertyField(p, new GUIContent(T(jp, en)), true);
        }

        static List<Material> TargetMaterials(MitToonTessellation c)
        {
            IEnumerable<Renderer> rs = c.scope == MitToonTessellation.TargetScope.ListedRenderers
                ? c.renderers.Where(r => r != null) : c.GetComponentsInChildren<Renderer>(true);
            return rs.SelectMany(r => r.sharedMaterials)
                     .Where(m => m != null && m.shader != null && m.shader.name.StartsWith("MitToon/") && !c.excludeMaterials.Contains(m))
                     .Distinct().ToList();
        }

        public override void OnInspectorGUI()
        {
            var c = (MitToonTessellation)target;
            serializedObject.Update();
            using (new GUILayout.HorizontalScope())
            {
                GUILayout.FlexibleSpace();
                if (GUILayout.Button(JP ? "English" : "日本語", EditorStyles.miniButton, GUILayout.Width(70))) MitToonShaderGUI.JP = !JP;
            }
            if (!System.AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name == "nadena.dev.ndmf"))
                EditorGUILayout.HelpBox(T("NDMF が見つかりません。VCC で NDMF (または Modular Avatar) を追加してください。", "NDMF not found. Add NDMF (or Modular Avatar) with VCC."), MessageType.Warning);
            Field("scope", "対象", "Targets");
            if (c.scope == MitToonTessellation.TargetScope.ListedRenderers) Field("renderers", "レンダラー", "Renderers");
            Field("excludeMaterials", "除外するマテリアル", "Excluded Materials");

            EditorGUILayout.Space(6);
            Field("overrideSettings", "設定を上書き (オフ: マテリアルの値を使う)", "Override Settings (off: use material values)");
            using (new EditorGUI.DisabledScope(!c.overrideSettings))
            {
                Field("edgeLength", "分割の細かさ (画面上の辺の長さ px)", "Edge Length (pixels on screen)");
                Field("maxSubdivision", "最大分割数", "Max Subdivision");
                Field("smoothing", "丸み (Phong)", "Smoothing (Phong)");
                Field("fadeStart", "分割を減らし始める距離 (m)", "Fade Start (m)");
                Field("fadeEnd", "分割しなくなる距離 (m)", "Fade End (m)");
            }

            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField(T("マスク (白い所だけ分割)", "Mask (white areas are subdivided)"), EditorStyles.boldLabel);
            Field("mask", "共通マスク (空: マテリアルのマスク)", "Common Mask (empty: material's own)");
            serializedObject.ApplyModifiedProperties();

            var mats = TargetMaterials(c);
            if (mats.Count == 0)
                EditorGUILayout.HelpBox(T("対象に MitToon のマテリアルがありません。", "No MitToon material in the targets."), MessageType.None);
            foreach (var m in mats)
            {
                var entry = c.materialMasks.FirstOrDefault(x => x != null && x.material == m);
                using (new GUILayout.HorizontalScope())
                {
                    EditorGUILayout.ObjectField(m, typeof(Material), false, GUILayout.MinWidth(80));
                    EditorGUI.BeginChangeCheck();
                    var tex = (Texture2D)EditorGUILayout.ObjectField(entry != null ? entry.mask : null, typeof(Texture2D), false, GUILayout.Width(150));
                    if (EditorGUI.EndChangeCheck()) SetMask(c, m, tex);
                    if (GUILayout.Button(T("ペイント", "Paint"), GUILayout.Width(64)))
                    {
                        var start = entry != null && entry.mask != null ? entry.mask : c.mask != null ? c.mask : m.GetTexture("_TessMask") as Texture2D;
                        var comp = c; var mat = m;
                        MitToonMaskPainter.OpenFor(m, start, saved => SetMask(comp, mat, saved), m.name + "_TessMask");
                    }
                }
            }
        }

        static void SetMask(MitToonTessellation c, Material m, Texture2D tex)
        {
            if (c == null) return;
            Undo.RecordObject(c, "Set Tessellation Mask");
            var entry = c.materialMasks.FirstOrDefault(x => x != null && x.material == m);
            if (entry == null) { entry = new MitToonTessellation.MaterialMask { material = m }; c.materialMasks.Add(entry); }
            entry.mask = tex;
            if (tex == null) c.materialMasks.Remove(entry);
            EditorUtility.SetDirty(c);
        }
    }
}
