using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    public static class MitToonOutlineBaker
    {
        // in the project's Assets (MitToon itself is a package), so the MitToon package never carries someone's baked meshes
        const string BakeRoot = "Assets/MitToon_UserData";
        const string BakeDir = BakeRoot + "/BakedOutline";

        static bool EnsureBakeDir()
        {
            if (!AssetDatabase.IsValidFolder(BakeRoot)) AssetDatabase.CreateFolder("Assets", "MitToon_UserData");
            if (!AssetDatabase.IsValidFolder(BakeDir)) AssetDatabase.CreateFolder(BakeRoot, "BakedOutline");
            return true;
        }

        // Averages normals of vertices sharing a position (hard edges, UV seams) and stores the result in tangent space
        // in the vertex color RGB. Outline "Normal Source = Vertex Color" then gives unbroken outlines like game shaders.
        [MenuItem("Tools/MitToon/アウトライン用スムーズ法線をベイク (Bake Smooth Normals)")]
        public static void BakeSelection()
        {
            if (!EnsureBakeDir()) return;
            int count = 0;
            var done = new HashSet<Renderer>();
            foreach (var go in Selection.gameObjects)
            {
                foreach (var r in go.GetComponentsInChildren<Renderer>(true))
                    if (done.Add(r) && BakeRenderer(r)) count++;
            }
            ReportBake(count);
        }

        // Inspector button: bakes every scene mesh that uses the material
        public static void BakeForMaterials(Material[] materials)
        {
            var rends = MitToonSceneUtil.RenderersUsing(materials).Where(r => r is SkinnedMeshRenderer || r.GetComponent<MeshFilter>() != null).ToList();
            if (rends.Count == 0) { MitToonSceneUtil.NotFound(); return; }
            if (!MitToonSceneUtil.Confirm("次のメッシュにスムーズ法線をベイクします (頂点カラーを上書き)。", "Bake smoothed normals into:", rends)) return;
            if (!EnsureBakeDir()) return;
            ReportBake(rends.Count(BakeRenderer));
        }

        static bool BakeRenderer(Renderer r)
        {
            if (r is SkinnedMeshRenderer smr)
            {
                var m = Bake(smr.sharedMesh);
                if (m == null) return false;
                Undo.RecordObject(smr, "MitToon Bake Smooth Normals");
                smr.sharedMesh = m;
                return true;
            }
            var mf = r.GetComponent<MeshFilter>();
            if (mf == null) return false;
            var mm = Bake(mf.sharedMesh);
            if (mm == null) return false;
            Undo.RecordObject(mf, "MitToon Bake Smooth Normals");
            mf.sharedMesh = mm;
            return true;
        }

        static void ReportBake(int count)
        {
            EditorUtility.DisplayDialog("MitToon", count > 0
                ? $"{count} 個のメッシュにベイクしました。\nアウトラインの「法線のソース」を Vertex Color にしてください。\n(頂点カラーを上書きするため「頂点カラーを乗算」は OFF のまま使ってください)"
                : "ベイクできるメッシュが見つかりません (法線と接線が必要です)。", "OK");
        }

        static Mesh Bake(Mesh src)
        {
            if (src == null) return null;
            var normals = src.normals;
            var tangents = src.tangents;
            var verts = src.vertices;
            if (normals.Length == 0 || tangents.Length == 0) return null;

            var sum = new Dictionary<Vector3Int, Vector3>();
            Vector3Int Key(Vector3 p) => new Vector3Int(Mathf.RoundToInt(p.x * 10000), Mathf.RoundToInt(p.y * 10000), Mathf.RoundToInt(p.z * 10000));
            for (int i = 0; i < verts.Length; i++)
            {
                var k = Key(verts[i]);
                sum.TryGetValue(k, out var s);
                sum[k] = s + normals[i];
            }
            var old = src.colors;
            var colors = new Color[verts.Length];
            for (int i = 0; i < verts.Length; i++)
            {
                var n = normals[i].normalized;
                var t = new Vector3(tangents[i].x, tangents[i].y, tangents[i].z).normalized;
                var b = Vector3.Cross(n, t) * tangents[i].w;
                var sm = sum[Key(verts[i])].normalized;
                var ts = new Vector3(Vector3.Dot(sm, t), Vector3.Dot(sm, b), Vector3.Dot(sm, n));
                float a = old.Length == verts.Length ? old[i].a : 1f;
                colors[i] = new Color(ts.x * 0.5f + 0.5f, ts.y * 0.5f + 0.5f, ts.z * 0.5f + 0.5f, a);
            }

            var dst = Object.Instantiate(src);
            dst.name = src.name + "_MitToonSmooth";
            dst.colors = colors;
            var path = AssetDatabase.GenerateUniqueAssetPath($"{BakeDir}/{dst.name}.asset");
            AssetDatabase.CreateAsset(dst, path);
            AssetDatabase.SaveAssets();
            return dst;
        }

        // Face SDF needs object axes that follow the head: make the head bone the root bone of the face renderer.
        // The face renderers are found from the material, no hierarchy selection needed.
        public static void SetRootBoneToHead(Material[] materials)
        {
            var list = new List<(SkinnedMeshRenderer smr, Transform head)>();
            foreach (var r in MitToonSceneUtil.RenderersUsing(materials))
            {
                if (!(r is SkinnedMeshRenderer smr)) continue;
                var anim = MitToonSceneUtil.AvatarRoot(r.transform).GetComponent<Animator>();
                var head = anim != null && anim.isHuman ? anim.GetBoneTransform(HumanBodyBones.Head) : null;
                if (head != null) list.Add((smr, head));
            }
            if (list.Count == 0)
            {
                EditorUtility.DisplayDialog("MitToon", "このマテリアルを使っている Humanoid アバターの SkinnedMeshRenderer がシーンに見つかりません。\n" +
                    "No SkinnedMeshRenderer of a Humanoid avatar in the open scenes uses this material.", "OK");
                return;
            }
            if (!MitToonSceneUtil.Confirm("次のメッシュの Root Bone を Head にします。", "Set Root Bone to Head on:", list.Select(x => x.smr))) return;
            foreach (var (smr, head) in list)
            {
                Undo.RecordObject(smr, "MitToon Root Bone To Head");
                smr.rootBone = head;
                smr.localBounds = new Bounds(Vector3.up * 0.08f, Vector3.one * 0.5f);
                Debug.Log("[MitToon] Root Bone を Head に設定しました: " + smr.name);
            }
        }
    }
}
