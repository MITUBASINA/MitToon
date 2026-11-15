// 1.1.4 split the stencil into normal / outline / transparent (like lilToon). Before that the outline and the
// transparent back faces used the normal stencil, so materials saved with a stencil get it copied once:
// the whole project after the update, and materials imported later (avatar packages made with an older version).
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    [InitializeOnLoad]
    static class MitToonStencilMigration
    {
        const string Key = "MitToon.StencilSplit.v1.";

        static MitToonStencilMigration()
        {
            EditorApplication.delayCall += () =>
            {
                string k = Key + Application.dataPath;
                if (EditorPrefs.GetBool(k, false)) return;
                EditorPrefs.SetBool(k, true);
                Migrate(AssetDatabase.FindAssets("t:Material", new[] { "Assets" }).Select(AssetDatabase.GUIDToAssetPath));
            };
        }

        internal static int Migrate(System.Collections.Generic.IEnumerable<string> paths)
        {
            int n = 0;
            foreach (var p in paths)
            {
                var m = AssetDatabase.LoadAssetAtPath<Material>(p);
                if (m == null || m.shader == null || !m.shader.name.StartsWith("MitToon/") || !m.HasProperty("_StencilSplit")) continue;
                if (m.GetFloat("_StencilSplit") > 0.5f) continue;
                // only materials that use a stencil change; the rest keep their file untouched
                if (m.GetFloat("_StencilComp") == 8 && m.GetFloat("_StencilPass") == 0 && m.GetFloat("_StencilFail") == 0 && m.GetFloat("_StencilZFail") == 0) continue;
                MitToonShaderGUI.MigrateStencilSplit(m);
                MitToonShaderGUI.SyncKeywords(m);
                EditorUtility.SetDirty(m);
                n++;
            }
            if (n > 0) { AssetDatabase.SaveAssets(); Debug.Log($"MitToon: copied the stencil to the outline / transparent stencil on {n} material(s)."); }
            return n;
        }

        class Importer : AssetPostprocessor
        {
            static void OnPostprocessAllAssets(string[] imported, string[] deleted, string[] moved, string[] movedFrom)
            {
                var mats = imported.Where(p => p.EndsWith(".mat", System.StringComparison.OrdinalIgnoreCase)).ToArray();
                if (mats.Length > 0) EditorApplication.delayCall += () => Migrate(mats);
            }
        }
    }
}
