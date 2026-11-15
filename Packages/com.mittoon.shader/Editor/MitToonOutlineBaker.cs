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
            var rends = Selection.gameObjects.SelectMany(go => go.GetComponentsInChildren<Renderer>(true)).Distinct()
                .Where(r => r is SkinnedMeshRenderer || r.GetComponent<MeshFilter>() != null).ToList();
            ReportBake(BakeAll(rends));
        }

        // Inspector button: bakes every scene mesh that uses the material
        public static void BakeForMaterials(Material[] materials)
        {
            var rends = MitToonSceneUtil.RenderersUsing(materials).Where(r => r is SkinnedMeshRenderer || r.GetComponent<MeshFilter>() != null).ToList();
            if (rends.Count == 0) { MitToonSceneUtil.NotFound(); return; }
            if (!MitToonSceneUtil.Confirm("次のメッシュにスムーズ法線をベイクします (頂点カラーを上書き)。", "Bake smoothed normals into:", rends)) return;
            if (!EnsureBakeDir()) return;
            ReportBake(BakeAll(rends));
        }

        // features that read the mesh tangent; a renderer whose materials use none of them gets the smooth normal in the tangent
        public static bool NeedsTangents(Material m)
        {
            if (m == null || m.shader == null || !m.shader.name.StartsWith("MitToon/")) return m != null;   // other shaders: keep their tangents
            bool On(string p) => m.HasProperty(p) && m.GetFloat(p) > 0.5f;
            float F(string p) => m.HasProperty(p) ? m.GetFloat(p) : 0;
            return On("_UseBumpMap") || On("_UseBump2") || On("_UseDetail") || On("_UseParallax") || On("_UseAniso") || On("_UseMatCapBump")
                || (F("_ClearCoatNormalScale") > 0.001f && m.HasProperty("_ClearCoatNormalMap") && m.GetTexture("_ClearCoatNormalMap") != null)
                || (F("_EyeParallax") > 0.0001f && On("_UseEyeGuard"));
        }

        // Smooth normals go into the tangent when nothing needs the tangent: skinned like the normal, so both sides of a hard
        // edge stay together when bones bend (PhysBones). The vertex color form is decoded through each vertex's own
        // tangent frame, and blended (linear) skinning bends those frames differently, which opens cracks in thick outlines.
        // A material shared with a renderer that needs its tangents keeps every renderer on the vertex color form.
        static int BakeAll(List<Renderer> rends)
        {
            var tangentMode = rends.ToDictionary(r => r, r => !r.sharedMaterials.Any(NeedsTangents));
            for (bool changed = true; changed;)
            {
                changed = false;
                foreach (var m in rends.SelectMany(r => r.sharedMaterials).Where(m => m != null).Distinct())
                {
                    var users = rends.Where(r => r.sharedMaterials.Contains(m)).ToList();
                    if (users.Any(r => !tangentMode[r]) && users.Any(r => tangentMode[r]))
                    {
                        foreach (var r in users) tangentMode[r] = false;
                        changed = true;
                    }
                }
            }
            int count = rends.Count(r => BakeRenderer(r, tangentMode[r]));
            foreach (var m in rends.SelectMany(r => r.sharedMaterials).Where(m => m != null && m.HasProperty("_OutlineNormalSource")).Distinct())
            {
                Undo.RecordObject(m, "MitToon Bake Smooth Normals");
                m.SetFloat("_OutlineNormalSource", rends.Where(r => r.sharedMaterials.Contains(m)).All(r => tangentMode[r]) ? 1 : 2);
                EditorUtility.SetDirty(m);
            }
            return count;
        }

        static bool BakeRenderer(Renderer r, bool tangentMode)
        {
            var mats = r.sharedMaterials;
            if (r is SkinnedMeshRenderer smr)
            {
                var m = Bake(smr.sharedMesh, mats, tangentMode);
                if (m == null) return false;
                Undo.RecordObject(smr, "MitToon Bake Smooth Normals");
                smr.sharedMesh = m;
                return true;
            }
            var mf = r.GetComponent<MeshFilter>();
            if (mf == null) return false;
            var mm = Bake(mf.sharedMesh, mats, tangentMode);
            if (mm == null) return false;
            Undo.RecordObject(mf, "MitToon Bake Smooth Normals");
            mf.sharedMesh = mm;
            return true;
        }

        static void ReportBake(int count)
        {
            EditorUtility.DisplayDialog("MitToon", count > 0
                ? $"{count} 個のメッシュにベイクしました。アウトラインの「法線のソース」も設定しました。\n(法線マップなどを使わないメッシュは接線に、使うメッシュは頂点カラーに焼いています)"
                : "ベイクできるメッシュが見つかりません (法線と接線が必要です)。", "OK");
        }

        // width of the outline per vertex as the shader computes it from the material (mask x vertex color A), or -1 when nothing varies
        static float[] Widths(Mesh src, Material[] mats, Color[] old)
        {
            var uv = src.uv;
            var w = Enumerable.Repeat(1f, src.vertexCount).ToArray();
            bool any = false;
            var cache = new Dictionary<Texture, Texture2D>();
            for (int sub = 0; sub < src.subMeshCount && sub < mats.Length; sub++)
            {
                var m = mats[sub];
                if (m == null || !m.HasProperty("_OutlineWidthMask")) continue;
                var tex = m.GetTexture("_OutlineWidthMask");
                float vcw = m.HasProperty("_OutlineVertexColorWidth") ? m.GetFloat("_OutlineVertexColorWidth") : 0;
                if (tex == null && vcw <= 0) continue;
                any = true;
                Texture2D rd = null;
                if (tex != null && !cache.TryGetValue(tex, out rd)) cache[tex] = rd = Readable(tex);
                foreach (int i in src.GetTriangles(sub).Distinct())
                {
                    float x = 1;
                    if (rd != null && uv.Length == w.Length) x = rd.GetPixelBilinear(uv[i].x, uv[i].y).r;   // like the shader: no tiling
                    float a = old.Length == w.Length ? old[i].a : 1f;
                    w[i] = x * Mathf.Lerp(1, a, vcw);
                }
            }
            foreach (var t in cache.Values) if (t != null) Object.DestroyImmediate(t);
            return any ? w : null;
        }

        static Texture2D Readable(Texture tex)
        {
            var rt = RenderTexture.GetTemporary(tex.width, tex.height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
            Graphics.Blit(tex, rt);
            var rd = new Texture2D(tex.width, tex.height, TextureFormat.RGBA32, false, true);
            var prev = RenderTexture.active; RenderTexture.active = rt;
            rd.ReadPixels(new Rect(0, 0, tex.width, tex.height), 0, 0); rd.Apply();
            RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt);
            return rd;
        }

        static Mesh Bake(Mesh src, Material[] mats = null, bool tangentMode = false)
        {
            if (src == null) return null;
            var normals = src.normals;
            var tangents = src.tangents;
            var verts = src.vertices;
            if (normals.Length == 0) return null;
            // a mesh baked into its tangent before: get real tangents back
            bool hadSmoothTangent = tangents.Length == verts.Length && verts.Length > 0
                && Enumerable.Range(0, verts.Length).Average(i => Mathf.Abs(Vector3.Dot(normals[i].normalized, ((Vector3)tangents[i]).normalized))) > 0.5f;
            if (tangents.Length != verts.Length || hadSmoothTangent)
            {
                if (src.uv.Length != verts.Length) return null;
                var tmp = Object.Instantiate(src);
                tmp.RecalculateTangents();
                tangents = tmp.tangents;
                Object.DestroyImmediate(tmp);
            }

            var sum = new Dictionary<Vector3Int, Vector3>();
            Vector3Int Key(Vector3 p) => new Vector3Int(Mathf.RoundToInt(p.x * 10000), Mathf.RoundToInt(p.y * 10000), Mathf.RoundToInt(p.z * 10000));
            for (int i = 0; i < verts.Length; i++)
            {
                var k = Key(verts[i]);
                sum.TryGetValue(k, out var s);
                sum[k] = s + normals[i];
            }
            var old = src.colors;
            // the width (mask x vertex color A) averaged over vertices on one position, so UV seams do not tear the outline
            var widths = mats != null ? Widths(src, mats, old) : null;
            var wsum = new Dictionary<Vector3Int, (float s, int n)>();
            if (widths != null)
                for (int i = 0; i < verts.Length; i++)
                {
                    var k = Key(verts[i]);
                    wsum.TryGetValue(k, out var e);
                    wsum[k] = (e.s + widths[i], e.n + 1);
                }
            var colors = new Color[verts.Length];
            var outTangents = new Vector4[verts.Length];
            for (int i = 0; i < verts.Length; i++)
            {
                var n = normals[i].normalized;
                var t = new Vector3(tangents[i].x, tangents[i].y, tangents[i].z).normalized;
                var b = Vector3.Cross(n, t) * tangents[i].w;
                var sm = sum[Key(verts[i])].normalized;
                var ts = new Vector3(Vector3.Dot(sm, t), Vector3.Dot(sm, b), Vector3.Dot(sm, n));
                float a = old.Length == verts.Length ? old[i].a : 1f;
                if (widths != null) { var e = wsum[Key(verts[i])]; a = e.s / e.n; }
                if (tangentMode)
                {
                    // tangent = smooth normal; the color keeps its RGB, A holds the width as above
                    var oc = old.Length == verts.Length && !hadSmoothTangent ? old[i] : Color.white;
                    colors[i] = new Color(oc.r, oc.g, oc.b, a);
                    outTangents[i] = new Vector4(sm.x, sm.y, sm.z, 1);
                }
                else
                {
                    colors[i] = new Color(ts.x * 0.5f + 0.5f, ts.y * 0.5f + 0.5f, ts.z * 0.5f + 0.5f, a);
                    outTangents[i] = tangents[i];
                }
            }

            if (mats != null)
                foreach (var m in mats)
                    if (m != null && m.HasProperty("_OutlineWidthBaked"))
                    {
                        Undo.RecordObject(m, "MitToon Bake Smooth Normals");
                        m.SetFloat("_OutlineWidthBaked", widths != null ? 1 : 0);
                        EditorUtility.SetDirty(m);
                    }

            // baking a baked mesh again (new mask, older version): update it in place instead of stacking copies
            if (AssetDatabase.GetAssetPath(src).StartsWith(BakeDir + "/"))
            {
                Undo.RecordObject(src, "MitToon Bake Smooth Normals");
                src.colors = colors;
                src.tangents = outTangents;
                EditorUtility.SetDirty(src);
                AssetDatabase.SaveAssets();
                return src;
            }
            var dst = Object.Instantiate(src);
            dst.name = src.name + "_MitToonSmooth";
            dst.colors = colors;
            dst.tangents = outTangents;
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
