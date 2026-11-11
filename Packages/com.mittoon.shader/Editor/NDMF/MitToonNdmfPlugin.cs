// MitToon - NDMF build pass: applies MitToon Tessellation components without touching the source assets.
using System.Collections.Generic;
using System.Linq;
using nadena.dev.ndmf;
using UnityEngine;
using UnityEngine.Rendering;

[assembly: ExportsPlugin(typeof(MitToon.NDMF.MitToonNdmfPlugin))]

namespace MitToon.NDMF
{
    public class MitToonNdmfPlugin : Plugin<MitToonNdmfPlugin>
    {
        public override string QualifiedName => "mittoon.ndmf";
        public override string DisplayName => "MitToon";

        const string TessSuffix = " Tessellation";

        protected override void Configure()
        {
            // after mesh merging tools have run in Transforming, before optimizers
            InPhase(BuildPhase.Transforming)
                .Run("MitToon Tessellation", ApplyTessellation)
                .PreviewingWith(new MitToonTessBorderPreview());
        }

        static void ApplyTessellation(BuildContext ctx)
        {
            var comps = ctx.AvatarRootTransform.GetComponentsInChildren<MitToonTessellation>(true);

            // deeper components win over the ones above them
            var owner = new Dictionary<Renderer, MitToonTessellation>();
            foreach (var c in comps.OrderBy(Depth))
            {
                IEnumerable<Renderer> rs = c.scope == MitToonTessellation.TargetScope.ListedRenderers
                    ? c.renderers.Where(r => r != null)
                    : c.GetComponentsInChildren<Renderer>(true);
                foreach (var r in rs) owner[r] = c;
            }

            var cache = new Dictionary<(Material, MitToonTessellation), Material>();
            foreach (var kv in owner)
            {
                var r = kv.Key; var c = kv.Value;
                var mats = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    var src = mats[i];
                    if (src == null || src.shader == null || !src.shader.name.StartsWith("MitToon/")) continue;
                    if (c.excludeMaterials.Contains(src)) continue;
                    if (!cache.TryGetValue((src, c), out var dst))
                    {
                        dst = MakeTessMaterial(src, c);
                        if (dst != null) ctx.AssetSaver.SaveAsset(dst);
                        cache[(src, c)] = dst;
                    }
                    if (dst == null) continue;
                    mats[i] = dst;
                    changed = true;
                }
                if (changed) r.sharedMaterials = mats;
            }
            foreach (var c in comps) Object.DestroyImmediate(c);

            // every renderer that ends up with a tessellation material (component or set by hand) gets crack free borders
            foreach (var r in ctx.AvatarRootTransform.GetComponentsInChildren<Renderer>(true))
            {
                var smr = r as SkinnedMeshRenderer;
                var mf = smr == null ? r.GetComponent<MeshFilter>() : null;
                var mesh = smr != null ? smr.sharedMesh : mf != null ? mf.sharedMesh : null;
                var baked = BuildBorderMesh(mesh, r.sharedMaterials, r);
                if (baked == null) continue;
                ctx.AssetSaver.SaveAsset(baked);
                if (smr != null) smr.sharedMesh = baked; else mf.sharedMesh = baked;
            }
        }

        // TEXCOORD6 = (shared uv, locked, 1) for the tessellation shader, see MitToonTessellation.hlsl
        internal static bool IsTess(Material m) =>
            m != null && m.shader != null && m.shader.name.StartsWith("MitToon/") && m.shader.name.EndsWith(TessSuffix);

        // returns a copy of the mesh with the border data, or null when nothing needs to be done
        internal static Mesh BuildBorderMesh(Mesh mesh, Material[] mats, Renderer r)
        {
            if (mesh == null || mats == null) return null;
            var tessSlots = mats.Select(IsTess).ToArray();
            if (!tessSlots.Any(x => x)) return null;
            if (mesh.HasVertexAttribute(VertexAttribute.TexCoord6))
            {
                Debug.LogWarning("[MitToon] " + r.name + ": UV6 is already used, tessellation borders are not baked (small cracks may appear).", r);
                return null;
            }
            try
            {
                var pos = mesh.vertices; var nrm = mesh.normals; var uv = new List<Vector2>(); mesh.GetUVs(0, uv);
                int n = pos.Length;
                if (n == 0) return null;
                if (uv.Count != n) { uv.Clear(); uv.AddRange(new Vector2[n]); }
                bool hasN = nrm != null && nrm.Length == n;

                // weld split vertices by position
                float q = Mathf.Max(mesh.bounds.size.magnitude, 1e-4f) * 1e-6f;
                var groups = new Dictionary<Vector3Int, int>();
                var g = new int[n];
                var first = new List<int>();
                for (int v = 0; v < n; v++)
                {
                    var p = pos[v];
                    var k = new Vector3Int(Mathf.RoundToInt(p.x / q), Mathf.RoundToInt(p.y / q), Mathf.RoundToInt(p.z / q));
                    if (!groups.TryGetValue(k, out int id)) { id = first.Count; groups[k] = id; first.Add(v); }
                    g[v] = id;
                }
                var locked = new bool[first.Count];
                if (hasN)
                    for (int v = 0; v < n; v++)
                        if (Vector3.Dot(nrm[v], nrm[first[g[v]]]) < 0.999f) locked[g[v]] = true;   // hard edge

                // edges: (count, material key, mixed); key -1 = not tessellated
                int subCount = mesh.subMeshCount;
                var subKey = new int[subCount];
                for (int s = 0; s < subCount; s++) subKey[s] = -1;
                for (int i = 0; i < mats.Length; i++)
                {
                    int s = Mathf.Min(i, subCount - 1);
                    if (s >= 0 && tessSlots[i] && mats[i] != null) subKey[s] = mats[i].GetInstanceID();
                }
                var edges = new Dictionary<long, (int count, int key, bool mixed)>();
                var vKey = new int[n]; var vSet = new bool[n];
                for (int s = 0; s < subCount; s++)
                {
                    if (mesh.GetTopology(s) != MeshTopology.Triangles) continue;
                    var tri = mesh.GetTriangles(s);
                    int key = subKey[s];
                    for (int t = 0; t + 2 < tri.Length; t += 3)
                        for (int e = 0; e < 3; e++)
                        {
                            int a = tri[t + e], b = tri[t + (e + 1) % 3];
                            if (!vSet[a]) { vSet[a] = true; vKey[a] = key; }
                            int ga = g[a], gb = g[b];
                            if (ga == gb) continue;
                            long ek = ga < gb ? ((long)ga << 32) | (uint)gb : ((long)gb << 32) | (uint)ga;
                            if (edges.TryGetValue(ek, out var ed)) edges[ek] = (ed.count + 1, ed.key, ed.mixed || ed.key != key);
                            else edges[ek] = (1, key, false);
                        }
                }
                foreach (var kv in edges)
                {
                    if (kv.Value.count > 1 && !kv.Value.mixed) continue;   // open edge or material border
                    locked[(int)(kv.Key >> 32)] = true;
                    locked[(int)(kv.Key & 0xffffffff)] = true;
                }

                // shared uv per (group, material) so every split vertex samples the masks at the same place
                var canon = new Dictionary<(int, int), Vector2>();
                var data = new List<Vector4>(n);
                for (int v = 0; v < n; v++)
                {
                    var ck = (g[v], vKey[v]);
                    if (!canon.TryGetValue(ck, out var cu)) { cu = uv[v]; canon[ck] = cu; }
                    data.Add(new Vector4(cu.x, cu.y, locked[g[v]] ? 1 : 0, 1));
                }

                var copy = Object.Instantiate(mesh);
                copy.name = mesh.name;
                copy.SetUVs(6, data);
                return copy;
            }
            catch (System.Exception ex)
            {
                Debug.LogWarning("[MitToon] " + r.name + ": could not bake tessellation borders: " + ex.Message, r);
                return null;
            }
        }

        static int Depth(Component c)
        {
            int d = 0;
            for (var t = c.transform; t != null; t = t.parent) d++;
            return d;
        }

        static Material MakeTessMaterial(Material src, MitToonTessellation c)
        {
            string name = src.shader.name.EndsWith(TessSuffix) ? src.shader.name : src.shader.name + TessSuffix;
            var sh = Shader.Find(name);
            if (sh == null)
            {
                Debug.LogWarning("[MitToon] Tessellation shader not found: " + name);
                return null;
            }
            var m = new Material(src) { name = src.name + " (Tessellation)" };
            int queue = src.renderQueue;
            var keywords = src.shaderKeywords;
            m.shader = sh;
            m.shaderKeywords = keywords;   // same local keywords exist in every MitToon variant
            m.renderQueue = queue;

            if (c.overrideSettings)
            {
                Set(m, "_TessEdgeLength", c.edgeLength);
                Set(m, "_TessMax", c.maxSubdivision);
                Set(m, "_TessPhong", c.smoothing);
                Set(m, "_TessFadeStart", c.fadeStart);
                Set(m, "_TessFadeEnd", Mathf.Max(c.fadeEnd, c.fadeStart + 0.01f));
            }
            var per = c.materialMasks.FirstOrDefault(x => x != null && x.material == src && x.mask != null);
            var mask = per != null ? per.mask : c.mask;
            if (mask != null && m.HasProperty("_TessMask")) m.SetTexture("_TessMask", mask);
            return m;
        }

        static void Set(Material m, string prop, float v)
        {
            if (m.HasProperty(prop)) m.SetFloat(prop, v);
        }
    }
}
