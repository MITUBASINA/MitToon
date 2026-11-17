// Material migrations, once for the whole project after an update and for materials imported later (avatar packages
// made with an older version):
// - 1.1.4 split the stencil into normal / outline / transparent (like lilToon). Before that the outline and the
//   transparent back faces used the normal stencil, so materials saved with a stencil get it copied once.
// - the URP shading model got its own keyword (_LUMI_URPSHADING): materials saved with it on get the keyword.
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    [InitializeOnLoad]
    static class MitToonStencilMigration
    {
        const string Key = "MitToon.StencilSplit.v1.";
        const string KeyUrp = "MitToon.URPKeyword.v1.";

        static MitToonStencilMigration()
        {
            EditorApplication.delayCall += () =>
            {
                string k = Key + Application.dataPath, ku = KeyUrp + Application.dataPath;
                if (EditorPrefs.GetBool(k, false) && EditorPrefs.GetBool(ku, false)) return;
                EditorPrefs.SetBool(k, true); EditorPrefs.SetBool(ku, true);
                Migrate(AssetDatabase.FindAssets("t:Material", new[] { "Assets" }).Select(AssetDatabase.GUIDToAssetPath));
            };
        }

        internal static int Migrate(System.Collections.Generic.IEnumerable<string> paths)
        {
            int n = 0, nu = 0;
            foreach (var p in paths)
            {
                var m = AssetDatabase.LoadAssetAtPath<Material>(p);
                if (m == null || m.shader == null || !m.shader.name.StartsWith("MitToon/")) continue;
                // only materials that need it change; the rest keep their file untouched
                bool stencil = m.HasProperty("_StencilSplit") && m.GetFloat("_StencilSplit") < 0.5f
                    && !(m.GetFloat("_StencilComp") == 8 && m.GetFloat("_StencilPass") == 0 && m.GetFloat("_StencilFail") == 0 && m.GetFloat("_StencilZFail") == 0);
                bool urp = m.HasProperty("_URPShading") && m.GetFloat("_URPShading") > 0.5f && !m.IsKeywordEnabled("_LUMI_URPSHADING");
                if (!stencil && !urp) continue;
                if (stencil) { MitToonShaderGUI.MigrateStencilSplit(m); n++; }
                if (urp) nu++;
                MitToonShaderGUI.SyncKeywords(m);
                EditorUtility.SetDirty(m);
            }
            if (n + nu > 0) AssetDatabase.SaveAssets();
            if (n > 0) Debug.Log($"MitToon: copied the stencil to the outline / transparent stencil on {n} material(s).");
            if (nu > 0) Debug.Log($"MitToon: turned on the URP shading keyword on {nu} material(s).");
            return n + nu;
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
