// Material migrations, once for the whole project after an update and for materials imported later (avatar packages
// made with an older version):
// - 1.1.4 split the stencil into normal / outline / transparent (like lilToon). Before that the outline and the
//   transparent back faces used the normal stencil, so materials saved with a stencil get it copied once.
// - the URP shading model got its own keyword (_LUMI_URPSHADING): materials saved with it on get the keyword.
// - the pseudo ray tracing was removed: materials on the "MitToon RayTrace" shader (now missing) go to MitToon.
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace MitToon.Editor
{
    [InitializeOnLoad]
    static class MitToonStencilMigration
    {
        const string Key = "MitToon.StencilSplit.v1.";
        const string KeyUrp = "MitToon.URPKeyword.v1.";
        const string KeyRT = "MitToon.RayTraceRemoved.v1.";
        const string RayTraceGuid = "6b6eb122b15ade741a91d8fb7275707e";   // the removed "MitToon/MitToon RayTrace"

        static MitToonStencilMigration()
        {
            EditorApplication.delayCall += () =>
            {
                string k = Key + Application.dataPath, ku = KeyUrp + Application.dataPath, kr = KeyRT + Application.dataPath;
                if (EditorPrefs.GetBool(k, false) && EditorPrefs.GetBool(ku, false) && EditorPrefs.GetBool(kr, false)) return;
                EditorPrefs.SetBool(k, true); EditorPrefs.SetBool(ku, true); EditorPrefs.SetBool(kr, true);
                Migrate(AssetDatabase.FindAssets("t:Material", new[] { "Assets" }).Select(AssetDatabase.GUIDToAssetPath));
            };
        }

        // the material was saved with the RayTrace shader, which is gone (Unity shows it with the error shader)
        static bool WasRayTrace(Material m, string path)
        {
            if (m.shader != null && m.shader.name != "Hidden/InternalErrorShader") return false;
            try { return File.ReadAllText(path).Contains("guid: " + RayTraceGuid); }
            catch { return false; }
        }

        internal static int Migrate(System.Collections.Generic.IEnumerable<string> paths)
        {
            int n = 0, nu = 0, nr = 0;
            Shader main = null;
            foreach (var p in paths)
            {
                var m = AssetDatabase.LoadAssetAtPath<Material>(p);
                if (m == null) continue;
                bool moved = WasRayTrace(m, p);
                if (moved)
                {
                    if (main == null) main = Shader.Find("MitToon/MitToon");
                    if (main == null) continue;
                    int mode = m.HasProperty("_RenderMode") ? Mathf.RoundToInt(m.GetFloat("_RenderMode")) : 0;
                    m.shader = main;
                    mode = m.HasProperty("_RenderMode") ? Mathf.RoundToInt(m.GetFloat("_RenderMode")) : mode;
                    if (mode == 0) m.renderQueue = -1;
                    else if (mode == 1) m.renderQueue = (int)RenderQueue.AlphaTest;
                    m.DisableKeyword("_LUMI_RAYTRACE");
                    nr++;
                }
                if (m.shader == null || !m.shader.name.StartsWith("MitToon/")) continue;
                // only materials that need it change; the rest keep their file untouched
                bool stencil = m.HasProperty("_StencilSplit") && m.GetFloat("_StencilSplit") < 0.5f
                    && !(m.GetFloat("_StencilComp") == 8 && m.GetFloat("_StencilPass") == 0 && m.GetFloat("_StencilFail") == 0 && m.GetFloat("_StencilZFail") == 0);
                bool urp = m.HasProperty("_URPShading") && m.GetFloat("_URPShading") > 0.5f && !m.IsKeywordEnabled("_LUMI_URPSHADING");
                bool rt = m.IsKeywordEnabled("_LUMI_RAYTRACE");
                if (!stencil && !urp && !rt && !moved) continue;
                if (stencil) { MitToonShaderGUI.MigrateStencilSplit(m); n++; }
                if (urp) nu++;
                if (rt) m.DisableKeyword("_LUMI_RAYTRACE");
                MitToonShaderGUI.SyncKeywords(m);
                EditorUtility.SetDirty(m);
            }
            if (n + nu + nr > 0) AssetDatabase.SaveAssets();
            if (n > 0) Debug.Log($"MitToon: copied the stencil to the outline / transparent stencil on {n} material(s).");
            if (nu > 0) Debug.Log($"MitToon: turned on the URP shading keyword on {nu} material(s).");
            if (nr > 0) Debug.Log($"MitToon: the pseudo ray tracing was removed; moved {nr} material(s) from the RayTrace shader to MitToon/MitToon.");
            return n + nu + nr;
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
