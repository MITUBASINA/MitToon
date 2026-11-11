using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // Finds scene objects from a material, so inspector buttons work while the material (not the avatar) is selected.
    public static class MitToonSceneUtil
    {
        public static List<Renderer> RenderersUsing(IEnumerable<Material> materials)
        {
            var set = new HashSet<Material>(materials.Where(m => m != null));
            var list = new List<Renderer>();
            if (set.Count == 0) return list;
            foreach (var r in Object.FindObjectsByType<Renderer>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (EditorUtility.IsPersistent(r)) continue;
                if (r.sharedMaterials.Any(m => m != null && set.Contains(m))) list.Add(r);
            }
            return list;
        }

        // Avatar root: top-most Animator above the transform, otherwise the scene root
        public static Transform AvatarRoot(Transform t)
        {
            Transform best = null;
            for (var p = t; p != null; p = p.parent)
                if (p.GetComponent<Animator>() != null) best = p;
            return best != null ? best : t.root;
        }

        public static List<Transform> AvatarsUsing(IEnumerable<Material> materials)
        {
            return RenderersUsing(materials).Select(r => AvatarRoot(r.transform)).Distinct().ToList();
        }

        public static bool Confirm(string jp, string en, IEnumerable<Object> targets)
        {
            var names = string.Join("\n", targets.Select(o => "  " + o.name));
            return EditorUtility.DisplayDialog("MitToon", $"{jp}\n{en}\n\n{names}", "OK", "キャンセル / Cancel");
        }

        public static void NotFound()
        {
            EditorUtility.DisplayDialog("MitToon",
                "このマテリアルを使っているオブジェクトが開いているシーンに見つかりません。アバターをシーンに置いてから押してください。\n" +
                "No object in the open scenes uses this material. Put the avatar in the scene first.", "OK");
        }
    }
}
