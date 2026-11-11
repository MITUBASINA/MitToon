using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // Adds a black, almost invisible directional light with shadows so that Unity renders _CameraDepthTexture
    // (needed by SSAO / contact shadows / depth aware soft shadows in worlds without a shadowed realtime light).
    public static class MitToonDepthLight
    {
        const string LightName = MitToonDepthLightSetup.LightName;

        [MenuItem("Tools/MitToon/深度ライトを追加 (Add Depth Light)")]
        public static void AddToSelection()
        {
            var sel = Selection.activeGameObject;
            if (sel == null)
            {
                EditorUtility.DisplayDialog("MitToon", "Hierarchy でアバターのルートを選択してください。\nSelect the avatar root in the Hierarchy.", "OK");
                return;
            }
            AddToRoot(MitToonSceneUtil.AvatarRoot(sel.transform));
        }

        // Inspector button: the avatar is found from the material
        public static void AddForMaterials(Material[] materials)
        {
            var roots = MitToonSceneUtil.AvatarsUsing(materials);
            if (roots.Count == 0) { MitToonSceneUtil.NotFound(); return; }
            if (!MitToonSceneUtil.Confirm("次のアバターに深度ライトを追加します。", "Add a depth light to:", roots)) return;
            foreach (var r in roots) AddToRoot(r);
        }

        public static void AddToRoot(Transform root)
        {
            var existing = root.Find(LightName);
            var go = existing != null ? existing.gameObject : new GameObject(LightName);
            if (existing == null)
            {
                Undo.RegisterCreatedObjectUndo(go, "Add MitToon DepthLight");
                go.transform.SetParent(root, false);
            }
            var l = go.GetComponent<Light>();
            if (l == null) l = Undo.AddComponent<Light>(go);
            Undo.RecordObject(l, "Setup MitToon DepthLight");
            MitToonDepthLightSetup.Apply(l);
            if (existing == null) go.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
            EditorGUIUtility.PingObject(go);
            Debug.Log("[MitToon] DepthLight を追加しました (Lights +1)。 / DepthLight added.");
        }
    }
}
