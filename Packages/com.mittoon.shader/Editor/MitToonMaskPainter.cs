// MitToon - Mask Paint: a standalone tool that paints a mask on a mesh in the Scene view and exports it as a PNG.
// Brush (soft sphere in world space), UV island fill (click the mesh or the UV view), left / right mirror,
// fill / invert, undo, seam padding on export. Nothing in the scene or the materials is changed.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using Object = UnityEngine.Object;

namespace MitToon.Editor
{
    public class MitToonMaskPainter : EditorWindow
    {
        class Target
        {
            public Renderer renderer;
            public Transform root;
            public Mesh mesh;              // world space, only the selected material slots
            public GameObject colliderGO;
            public MeshCollider collider;
            public Vector2[] uv;
            public Vector3[] pos;
            public int[] tris;
            public int[] triIsland;        // island id per triangle
            public Dictionary<int, Mesh> islandMesh = new Dictionary<int, Mesh>();
        }

        enum Tool { Brush, UVFill }

        Renderer targetRenderer;
        int slot = -1;                     // -1: every material slot
        Texture2D startTex;
        Action<Texture2D> onSaved;
        string defaultName = "Mask";

        readonly List<Target> targets = new List<Target>();
        RenderTexture rt;
        readonly List<RenderTexture> undo = new List<RenderTexture>();
        Material paintMat, overlayMat;

        Tool tool = Tool.Brush;
        bool erase;
        float sizeCm = 3f, hardness = 0.5f, strength = 1f, paintValue = 1f;
        bool mirror = true, skipBack = true, painting = true, overlay = true;
        float overlayOpacity = 0.55f;
        int newRes = 1024;
        Vector2 scroll;
        Vector3 lastDab; bool stroking;
        Vector3 cursorPos, cursorNormal; bool cursorHit;

        static bool JP => MitToonShaderGUI.JP;
        static string T(string jp, string en) => MitToonShaderGUI.Bare(JP ? jp : en);

        [MenuItem("Tools/MitToon/マスクペイント (Mask Paint)")]
        public static void OpenTool()
        {
            var r = Selection.activeGameObject != null ? Selection.activeGameObject.GetComponentInChildren<Renderer>() : null;
            Open(r, -1, null, null, null);
        }

        // material: picks a renderer in the scene that uses it and selects that slot
        public static void OpenFor(Material material, Texture2D start = null, Action<Texture2D> saveCallback = null, string name = null)
        {
            Renderer r = null; int s = -1;
            foreach (var cand in MitToonSceneUtil.RenderersUsing(new[] { material }))
            {
                if (!cand.gameObject.activeInHierarchy || !cand.enabled) continue;
                r = cand; s = Array.IndexOf(cand.sharedMaterials, material);
                break;
            }
            Open(r, s, start, saveCallback, name ?? (material != null ? material.name + "_Mask" : null));
        }

        public static void Open(Renderer r, int materialSlot, Texture2D start, Action<Texture2D> saveCallback, string name)
        {
            foreach (var w in Resources.FindObjectsOfTypeAll<MitToonMaskPainter>()) w.Close();
            var win = CreateInstance<MitToonMaskPainter>();
            win.titleContent = new GUIContent("MitToon Mask Paint");
            win.targetRenderer = r;
            win.slot = materialSlot;
            win.startTex = start;
            win.onSaved = saveCallback;
            if (!string.IsNullOrEmpty(name)) win.defaultName = name;
            else if (r != null) win.defaultName = r.name + "_Mask";
            win.minSize = new Vector2(330, 600);
            win.ShowUtility();
            win.Begin();
        }

        // ------------------------------------------------------------------ setup
        void Begin()
        {
            paintMat = new Material(Shader.Find("Hidden/MitToon/MaskPaint")) { hideFlags = HideFlags.HideAndDontSave };
            overlayMat = new Material(Shader.Find("Hidden/MitToon/MaskOverlay")) { hideFlags = HideFlags.HideAndDontSave };
            CreateRT(startTex != null ? startTex.width : newRes, startTex != null ? startTex.height : newRes, startTex);
            BuildTargets();
            SceneView.duringSceneGui += OnScene;
            EditorApplication.update += Tick;
            SceneView.RepaintAll();
        }

        void CreateRT(int w, int h, Texture src)
        {
            if (rt != null) { rt.Release(); DestroyImmediate(rt); }
            rt = new RenderTexture(w, h, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear)
                { hideFlags = HideFlags.HideAndDontSave, wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Bilinear, name = "MitToon Mask" };
            rt.Create();
            BlitKeep(src != null ? src : Texture2D.whiteTexture, rt);
            padDirty = true;
            ClearUndo();
        }

        void BuildTargets()
        {
            ClearTargets();
            if (targetRenderer == null) return;
            var t = MakeTarget(targetRenderer);
            if (t != null) targets.Add(t);
            SceneView.RepaintAll();
        }

        // World space copy of the renderer's current (skinned) shape. How BakeMesh treats scale differs with the
        // transform setup (scaled avatar roots, FBX unit scale), so every candidate is checked against the
        // renderer's own world bounds and the closest one is used.
        internal static Vector3[] WorldVertices(Renderer r, out Vector3[] normals, out Mesh src)
        {
            normals = null; src = null;
            var tr = r.transform;
            var l2w = tr.localToWorldMatrix;
            var trs = Matrix4x4.TRS(tr.position, tr.rotation, Vector3.one);
            if (r is SkinnedMeshRenderer smr)
            {
                if (smr.sharedMesh == null) return null;
                var a = new Mesh(); smr.BakeMesh(a, false);
                var b = new Mesh(); smr.BakeMesh(b, true);
                var cands = new[] { (a, l2w), (b, trs), (a, trs), (b, l2w) };
                var want = r.bounds;
                // reference points: a few vertices skinned on the CPU from the bones (exact, unlike the loose bounds)
                var refIdx = new List<int>(); var refPos = new List<Vector3>();
                SkinReference(smr, refIdx, refPos);
                float best = float.MaxValue; Vector3[] bestV = null; Vector3[] bestN = null; Mesh bestM = null;
                foreach (var (m, mat) in cands)
                {
                    var v = m.vertices;
                    if (v.Length == 0) continue;
                    float err = 0;
                    if (refIdx.Count > 0)
                        for (int k = 0; k < refIdx.Count; k++) err += (mat.MultiplyPoint3x4(v[refIdx[k]]) - refPos[k]).magnitude;
                    else
                    {
                        var bb = new Bounds(mat.MultiplyPoint3x4(v[0]), Vector3.zero);
                        for (int i = 1; i < v.Length; i++) bb.Encapsulate(mat.MultiplyPoint3x4(v[i]));
                        err = (bb.center - want.center).magnitude + (bb.size - want.size).magnitude;
                    }
                    if (err < best)
                    {
                        best = err;
                        for (int i = 0; i < v.Length; i++) v[i] = mat.MultiplyPoint3x4(v[i]);
                        var n = m.normals; var nm = mat.inverse.transpose;
                        if (n != null) for (int i = 0; i < n.Length; i++) n[i] = nm.MultiplyVector(n[i]).normalized;
                        bestV = v; bestN = n; bestM = m;
                    }
                }
                if (bestM != a) DestroyImmediate(a);
                if (bestM != b) DestroyImmediate(b);
                normals = bestN; src = bestM;
                return bestV;
            }
            var mf = r.GetComponent<MeshFilter>();
            if (mf == null || mf.sharedMesh == null) return null;
            src = Instantiate(mf.sharedMesh);
            var vs = src.vertices; var ns = src.normals; var nmat = l2w.inverse.transpose;
            for (int i = 0; i < vs.Length; i++) vs[i] = l2w.MultiplyPoint3x4(vs[i]);
            if (ns != null) for (int i = 0; i < ns.Length; i++) ns[i] = nmat.MultiplyVector(ns[i]).normalized;
            normals = ns;
            return vs;
        }

        // checks the world space copy against the renderer bounds for every mesh in the scene
        internal static void DiagnoseBake(System.Text.StringBuilder log)
        {
            foreach (var r in Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None))
            {
                if (!(r is SkinnedMeshRenderer) && r.GetComponent<MeshFilter>() == null) continue;
                var v = WorldVertices(r, out _, out var src);
                if (v == null || v.Length == 0) continue;
                DestroyImmediate(src);
                var bb = new Bounds(v[0], Vector3.zero);
                foreach (var p in v) bb.Encapsulate(p);
                log.AppendLine(string.Format("bake {0}: mesh {1} / renderer {2} / lossy {3}", r.name, bb, r.bounds, r.transform.lossyScale));
            }
        }

        static void SkinReference(SkinnedMeshRenderer smr, List<int> idx, List<Vector3> pos)
        {
            var mesh = smr.sharedMesh; var bones = smr.bones;
            var bind = mesh.bindposes;
            var verts = mesh.vertices;
            if (bones == null || bones.Length == 0 || bind.Length != bones.Length || verts.Length == 0) return;
            var counts = mesh.GetBonesPerVertex();
            var weights = mesh.GetAllBoneWeights();
            if (counts.Length != verts.Length) return;
            var start = new int[verts.Length];
            for (int i = 1; i < verts.Length; i++) start[i] = start[i - 1] + counts[i - 1];
            int step = Mathf.Max(1, verts.Length / 16);
            for (int i = 0; i < verts.Length && idx.Count < 16; i += step)
            {
                Vector3 p = Vector3.zero; float wsum = 0; bool ok = true;
                for (int k = 0; k < counts[i]; k++)
                {
                    var bw = weights[start[i] + k];
                    if (bw.boneIndex >= bones.Length || bones[bw.boneIndex] == null) { ok = false; break; }
                    p += (bones[bw.boneIndex].localToWorldMatrix * bind[bw.boneIndex]).MultiplyPoint3x4(verts[i]) * bw.weight;
                    wsum += bw.weight;
                }
                if (!ok || wsum < 0.5f) continue;
                idx.Add(i); pos.Add(p / wsum);
            }
        }

        Target MakeTarget(Renderer r)
        {
            var v = WorldVertices(r, out var n, out var src);
            if (v == null) return null;
            var mats = r.sharedMaterials;
            var idx = new List<int>();
            for (int s = 0; s < src.subMeshCount; s++)
            {
                // extra material slots beyond the sub mesh count draw the last sub mesh again
                bool uses = slot < 0 || s == slot || (s == src.subMeshCount - 1 && slot >= src.subMeshCount);
                if (uses && src.GetTopology(s) == MeshTopology.Triangles) idx.AddRange(src.GetTriangles(s));
            }
            var uv = src.uv;
            DestroyImmediate(src);
            if (idx.Count == 0 || uv == null || uv.Length != v.Length) return null;

            var mesh = new Mesh { hideFlags = HideFlags.HideAndDontSave, indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
            mesh.vertices = v;
            if (n != null && n.Length == v.Length) mesh.normals = n;
            mesh.uv = uv;
            mesh.SetTriangles(idx, 0);
            mesh.RecalculateBounds();

            var go = new GameObject("MitToon Mask Paint Collider") { hideFlags = HideFlags.HideAndDontSave };
            var col = go.AddComponent<MeshCollider>();
            col.sharedMesh = mesh;
            var t = new Target
            {
                renderer = r, root = MitToonSceneUtil.AvatarRoot(r.transform), mesh = mesh, colliderGO = go, collider = col,
                uv = uv, pos = v, tris = idx.ToArray(),
            };
            t.triIsland = ComputeIslands(t);
            return t;
        }

        // UV islands: triangles joined through vertices that share UV and position (hard edges do not split an island)
        static int[] ComputeIslands(Target t)
        {
            var key = new Dictionary<(int, int, int, int, int), int>();
            int vc = t.pos.Length;
            var weld = new int[vc];
            for (int i = 0; i < vc; i++)
            {
                var p = t.pos[i]; var u = t.uv[i];
                var k = (Mathf.RoundToInt(u.x * 8192), Mathf.RoundToInt(u.y * 8192),
                         Mathf.RoundToInt(p.x * 10000), Mathf.RoundToInt(p.y * 10000), Mathf.RoundToInt(p.z * 10000));
                if (!key.TryGetValue(k, out int id)) { id = key.Count; key[k] = id; }
                weld[i] = id;
            }
            var parent = Enumerable.Range(0, key.Count).ToArray();
            int Find(int x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }
            void Union(int a, int b) { a = Find(a); b = Find(b); if (a != b) parent[a] = b; }
            int tc = t.tris.Length / 3;
            for (int i = 0; i < tc; i++)
            {
                Union(weld[t.tris[i * 3]], weld[t.tris[i * 3 + 1]]);
                Union(weld[t.tris[i * 3]], weld[t.tris[i * 3 + 2]]);
            }
            var res = new int[tc];
            for (int i = 0; i < tc; i++) res[i] = Find(weld[t.tris[i * 3]]);
            return res;
        }

        // ------------------------------------------------------------------ painting
        void PushUndo()
        {
            var c = new RenderTexture(rt.descriptor) { hideFlags = HideFlags.HideAndDontSave };
            Graphics.CopyTexture(rt, c);
            undo.Add(c);
            while (undo.Count > 30) { undo[0].Release(); DestroyImmediate(undo[0]); undo.RemoveAt(0); }
        }

        void PopUndo()
        {
            if (undo.Count == 0) return;
            var c = undo[undo.Count - 1];
            undo.RemoveAt(undo.Count - 1);
            Graphics.CopyTexture(c, rt);
            c.Release(); DestroyImmediate(c);
            SceneView.RepaintAll(); Repaint();
        }

        void ClearUndo()
        {
            foreach (var c in undo) if (c != null) { c.Release(); DestroyImmediate(c); }
            undo.Clear();
        }

        float CurrentValue => erase ? 0f : paintValue;

        void SetupPaint(float value, float str)
        {
            paintMat.SetFloat("_FlipY", SystemInfo.graphicsUVStartsAtTop ? -1f : 1f);
            paintMat.SetFloat("_Value", value);
            paintMat.SetFloat("_Strength", str);
            paintMat.SetFloat("_Hardness", hardness);
        }

        void DrawInto(RenderTexture target, int pass, Func<Target, Mesh> meshOf)
        {
            var prev = RenderTexture.active;
            Graphics.SetRenderTarget(target);
            GL.PushMatrix();
            GL.LoadIdentity();
            foreach (var t in targets)
            {
                var m = meshOf(t);
                if (m == null) continue;
                paintMat.SetPass(pass);
                Graphics.DrawMeshNow(m, Matrix4x4.identity);
            }
            GL.PopMatrix();
            RenderTexture.active = prev;
        }

        Vector3 Mirror(Target t, Vector3 p)
        {
            var l = t.root.InverseTransformPoint(p);
            l.x = -l.x;
            return t.root.TransformPoint(l);
        }
        Vector3 MirrorDir(Target t, Vector3 d)
        {
            var l = t.root.InverseTransformDirection(d);
            l.x = -l.x;
            return t.root.TransformDirection(l);
        }

        // Seam padding. Painting rasterizes triangles in UV space, so texels whose centre lies just outside a
        // triangle (all along the UV island borders) are never written and show up as unpainted lines.
        // Uncovered texels next to an island copy their covered neighbours, growing a few pixels per call.
        bool padDirty;
        void Pad(RenderTexture target, int pixels)
        {
            if (targets.Count == 0) return;
            var prevActive = RenderTexture.active;
            var desc = target.descriptor;
            var tmp = RenderTexture.GetTemporary(desc);
            var cov = RenderTexture.GetTemporary(desc);
            var cov2 = RenderTexture.GetTemporary(desc);
            Graphics.Blit(Texture2D.blackTexture, cov);
            SetupPaint(1, 1);
            DrawInto(cov, 2, t => t.mesh);
            for (int i = 0; i < pixels; i++)
            {
                paintMat.SetTexture("_Cov", cov);
                Graphics.Blit(target, tmp, paintMat, 3);
                Graphics.Blit(tmp, target);
                Graphics.Blit(cov, cov2, paintMat, 4);
                Graphics.Blit(cov2, cov);
            }
            RenderTexture.ReleaseTemporary(tmp); RenderTexture.ReleaseTemporary(cov); RenderTexture.ReleaseTemporary(cov2);
            RenderTexture.active = prevActive;
        }

        // runs outside of any Scene view repaint: blitting while the Scene view draws switches its render target (flicker)
        void Tick()
        {
            if (!padDirty || rt == null) return;
            padDirty = false;
            Pad(rt, 4);
            SceneView.RepaintAll();
            Repaint();
        }

        void Dab(Vector3 p, Vector3 viewDir)
        {
            padDirty = true;
            float r = sizeCm * 0.01f;
            SetupPaint(CurrentValue, strength);
            paintMat.SetVector("_BrushDir", new Vector4(viewDir.x, viewDir.y, viewDir.z, skipBack ? 1 : 0));
            paintMat.SetVector("_Brush", new Vector4(p.x, p.y, p.z, r));
            // the mirror is per avatar: each target uses its own root
            var prev = RenderTexture.active;
            Graphics.SetRenderTarget(rt);
            GL.PushMatrix(); GL.LoadIdentity();
            foreach (var t in targets)
            {
                var mp = Mirror(t, p);
                bool useMirror = mirror && Vector3.Distance(mp, p) > r * 0.5f;   // on the centre line one dab is enough
                paintMat.SetVector("_Brush2", useMirror ? new Vector4(mp.x, mp.y, mp.z, r) : Vector4.zero);
                paintMat.SetVector("_BrushDir2", MirrorDir(t, viewDir));   // the mirrored dab looks from the mirrored side
                paintMat.SetPass(0);
                Graphics.DrawMeshNow(t.mesh, Matrix4x4.identity);
            }
            GL.PopMatrix();
            RenderTexture.active = prev;
        }

        Mesh IslandMesh(Target t, int island)
        {
            if (t.islandMesh.TryGetValue(island, out var m)) return m;
            var idx = new List<int>();
            for (int i = 0; i < t.triIsland.Length; i++)
                if (t.triIsland[i] == island) { idx.Add(t.tris[i * 3]); idx.Add(t.tris[i * 3 + 1]); idx.Add(t.tris[i * 3 + 2]); }
            m = new Mesh { hideFlags = HideFlags.HideAndDontSave, indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
            m.vertices = t.pos; m.uv = t.uv;
            m.SetTriangles(idx, 0);
            t.islandMesh[island] = m;
            return m;
        }

        void FillIsland(Target t, int tri, bool withMirror)
        {
            padDirty = true;
            var islands = new List<(Target, int)> { (t, t.triIsland[tri]) };
            if (withMirror)
            {
                // the island on the other side: cast at the mirrored centre of the clicked triangle
                var c = (t.pos[t.tris[tri * 3]] + t.pos[t.tris[tri * 3 + 1]] + t.pos[t.tris[tri * 3 + 2]]) / 3f;
                var nrm = Vector3.Cross(t.pos[t.tris[tri * 3 + 1]] - t.pos[t.tris[tri * 3]], t.pos[t.tris[tri * 3 + 2]] - t.pos[t.tris[tri * 3]]).normalized;
                var mc = Mirror(t, c); var mn = MirrorDir(t, nrm);
                foreach (var dir in new[] { -mn, mn })
                    if (Raycast(new Ray(mc - dir * 0.03f, dir), 0.06f, out var mt, out int mtri)) { islands.Add((mt, mt.triIsland[mtri])); break; }
            }
            SetupPaint(CurrentValue, strength);
            var prev = RenderTexture.active;
            Graphics.SetRenderTarget(rt);
            GL.PushMatrix(); GL.LoadIdentity();
            foreach (var (tt, isl) in islands.Distinct())
            {
                paintMat.SetPass(1);
                Graphics.DrawMeshNow(IslandMesh(tt, isl), Matrix4x4.identity);
            }
            GL.PopMatrix();
            RenderTexture.active = prev;
        }

        bool Raycast(Ray ray, float maxDist, out Target hitT, out int tri) => Raycast(ray, maxDist, out hitT, out tri, out _);
        bool Raycast(Ray ray, float maxDist, out Target hitT, out int tri, out RaycastHit best)
        {
            hitT = null; tri = -1; best = default;
            float bd = float.MaxValue;
            foreach (var t in targets)
            {
                if (t.collider != null && t.collider.Raycast(ray, out var h, maxDist) && h.distance < bd)
                { bd = h.distance; best = h; hitT = t; tri = h.triangleIndex; }
            }
            return hitT != null;
        }

        // ------------------------------------------------------------------ scene view
        void OnScene(SceneView sv)
        {
            if (rt == null) { Close(); return; }
            var e = Event.current;
            if (overlay && e.type == EventType.Repaint)
            {
                overlayMat.SetTexture("_MaskTex", rt);
                overlayMat.SetFloat("_Opacity", overlayOpacity);
                overlayMat.SetPass(0);
                foreach (var t in targets) Graphics.DrawMeshNow(t.mesh, Matrix4x4.identity);
            }
            if (!painting) return;

            int id = GUIUtility.GetControlID(FocusType.Passive);
            if (e.type == EventType.Layout) HandleUtility.AddDefaultControl(id);

            if (e.type == EventType.KeyDown)
            {
                if (e.keyCode == KeyCode.Z && (e.control || e.command)) { PopUndo(); e.Use(); return; }
                if (e.keyCode == KeyCode.LeftBracket) { sizeCm = Mathf.Max(0.1f, sizeCm / 1.2f); e.Use(); Repaint(); }
                if (e.keyCode == KeyCode.RightBracket) { sizeCm = Mathf.Min(50f, sizeCm * 1.2f); e.Use(); Repaint(); }
            }

            var ray = HandleUtility.GUIPointToWorldRay(e.mousePosition);
            if (e.type == EventType.MouseMove || e.type == EventType.MouseDrag || e.type == EventType.MouseDown || e.type == EventType.Repaint)
            {
                cursorHit = Raycast(ray, 1000f, out var ht, out int htri, out var hit);
                if (cursorHit) { cursorPos = hit.point; cursorNormal = hit.normal; }
                if (e.type == EventType.MouseMove) sv.Repaint();

                bool lmb = e.button == 0 && !e.alt;
                if (lmb && e.type == EventType.MouseDown && cursorHit)
                {
                    PushUndo();
                    if (tool == Tool.UVFill) FillIsland(ht, htri, mirror);
                    else { Dab(cursorPos, ray.direction); lastDab = cursorPos; stroking = true; }
                    GUIUtility.hotControl = id;
                    e.Use(); Repaint();
                }
                else if (lmb && e.type == EventType.MouseDrag && stroking && cursorHit && tool == Tool.Brush)
                {
                    float spacing = sizeCm * 0.01f * 0.2f;
                    float d = Vector3.Distance(lastDab, cursorPos);
                    if (d > spacing)
                    {
                        int steps = Mathf.Min(Mathf.CeilToInt(d / spacing), 32);
                        for (int s = 1; s <= steps; s++) Dab(Vector3.Lerp(lastDab, cursorPos, s / (float)steps), ray.direction);
                        lastDab = cursorPos;
                    }
                    e.Use();
                }
            }
            if (e.type == EventType.MouseUp && e.button == 0 && GUIUtility.hotControl == id)
            {
                stroking = false;
                GUIUtility.hotControl = 0;
                e.Use(); Repaint();
            }

            if (cursorHit && e.type == EventType.Repaint)
            {
                float r = sizeCm * 0.01f;
                Handles.color = erase ? new Color(0.4f, 0.7f, 1f) : new Color(1f, 0.5f, 0.75f);
                if (tool == Tool.Brush)
                {
                    Handles.DrawWireDisc(cursorPos, cursorNormal, r);
                    Handles.DrawWireDisc(cursorPos, cursorNormal, r * Mathf.Max(hardness, 0.05f));
                    if (mirror && targets.Count > 0)
                    {
                        var t = targets[0];
                        Handles.color = new Color(Handles.color.r, Handles.color.g, Handles.color.b, 0.5f);
                        Handles.DrawWireDisc(Mirror(t, cursorPos), MirrorDir(t, cursorNormal), r);
                    }
                }
                else Handles.DrawSolidDisc(cursorPos, cursorNormal, HandleUtility.GetHandleSize(cursorPos) * 0.03f);
            }
        }

        // ------------------------------------------------------------------ window
        void OnGUI()
        {
            if (rt == null) { EditorGUILayout.HelpBox(T("ウィンドウを開き直してください。", "Reopen the window."), MessageType.Warning); return; }
            scroll = EditorGUILayout.BeginScrollView(scroll);
            EditorGUILayout.LabelField(T("マスクペイント", "Mask Paint"), EditorStyles.boldLabel);

            // target mesh and material slot
            EditorGUI.BeginChangeCheck();
            targetRenderer = (Renderer)EditorGUILayout.ObjectField(T("塗るメッシュ", "Mesh"), targetRenderer, typeof(Renderer), true);
            if (targetRenderer != null)
            {
                var mats = targetRenderer.sharedMaterials;
                var names = new[] { T("すべてのマテリアル", "All Materials") }.Concat(mats.Select((m, i) => i + ": " + (m != null ? m.name : "(none)"))).ToArray();
                slot = EditorGUILayout.Popup(T("マテリアル (UV の範囲)", "Material (UV area)"), Mathf.Clamp(slot + 1, 0, names.Length - 1), names) - 1;
            }
            if (EditorGUI.EndChangeCheck()) BuildTargets();
            if (targetRenderer == null)
                EditorGUILayout.HelpBox(T("シーンにあるメッシュ (Skinned Mesh Renderer / Mesh Renderer) を指定してください。", "Pick a mesh renderer in the scene."), MessageType.Info);
            else if (targets.Count == 0)
                EditorGUILayout.HelpBox(T("このメッシュには UV が無いか、選んだマテリアルの面がありません。", "This mesh has no UV or no faces for the chosen material."), MessageType.Warning);
            using (new GUILayout.HorizontalScope())
            {
                startTex = (Texture2D)EditorGUILayout.ObjectField(T("元にする画像", "Start From"), startTex, typeof(Texture2D), false);
                if (GUILayout.Button(T("読み込む", "Load"), GUILayout.Width(70)) && startTex != null)
                { CreateRT(startTex.width, startTex.height, startTex); SceneView.RepaintAll(); }
            }

            EditorGUILayout.Space(6);
            painting = GUILayout.Toggle(painting, painting ? T("シーンビューで塗る (ON)", "Paint in Scene View (ON)") : T("シーンビューで塗る (OFF)", "Paint in Scene View (OFF)"), "Button", GUILayout.Height(26));
            tool = (Tool)GUILayout.Toolbar((int)tool, new[] { T("ブラシ", "Brush"), T("UV塗りつぶし", "UV Island Fill") });
            erase = GUILayout.Toolbar(erase ? 1 : 0, new[] { T("塗る (白)", "Paint (white)"), T("消す (黒)", "Erase (black)") }) == 1;
            mirror = EditorGUILayout.ToggleLeft(T("左右対称 (アバターの X 軸で反転)", "Left / Right Mirror (avatar X axis)"), mirror);

            EditorGUILayout.Space(4);
            if (tool == Tool.Brush)
            {
                sizeCm = EditorGUILayout.Slider(T("ブラシの大きさ (cm)  [ ]", "Brush Size (cm)  [ ]"), sizeCm, 0.1f, 50f);
                hardness = EditorGUILayout.Slider(T("硬さ", "Hardness"), hardness, 0f, 1f);
                skipBack = EditorGUILayout.Toggle(T("裏側の面は塗らない", "Skip Faces Turned Away"), skipBack);
            }
            strength = EditorGUILayout.Slider(T("濃さ", "Strength"), strength, 0.01f, 1f);
            using (new EditorGUI.DisabledScope(erase))
                paintValue = EditorGUILayout.Slider(T("塗る値 (1 = 白)", "Paint Value (1 = white)"), paintValue, 0f, 1f);

            EditorGUILayout.Space(4);
            using (new GUILayout.HorizontalScope())
            {
                if (GUILayout.Button(T("全体を白", "Fill White"))) { PushUndo(); BlitKeep(Texture2D.whiteTexture, rt); }
                if (GUILayout.Button(T("全体を黒", "Fill Black"))) { PushUndo(); BlitKeep(Texture2D.blackTexture, rt); }
                if (GUILayout.Button(T("反転", "Invert"))) { PushUndo(); Invert(); padDirty = true; }
            }
            using (new GUILayout.HorizontalScope())
            {
                using (new EditorGUI.DisabledScope(undo.Count == 0))
                    if (GUILayout.Button(T("元に戻す (Ctrl+Z)", "Undo (Ctrl+Z)") + " " + undo.Count)) PopUndo();
                if (GUILayout.Button(T("メッシュを再取得", "Reload Mesh"))) BuildTargets();
            }

            EditorGUILayout.Space(4);
            using (new GUILayout.HorizontalScope())
            {
                overlay = EditorGUILayout.ToggleLeft(T("マスクを色で表示", "Show Mask Overlay"), overlay, GUILayout.Width(150));
                using (new EditorGUI.DisabledScope(!overlay)) overlayOpacity = GUILayout.HorizontalSlider(overlayOpacity, 0.1f, 1f);
            }
            if (GUI.changed) SceneView.RepaintAll();

            EditorGUILayout.Space(4);
            EditorGUILayout.LabelField(T("UV (クリックでその UV アイランドを塗りつぶし)", "UV (click to fill that UV island)"), EditorStyles.miniBoldLabel);
            DrawUVView();

            EditorGUILayout.Space(4);
            using (new GUILayout.HorizontalScope())
            {
                newRes = EditorGUILayout.IntPopup(T("新規解像度", "New Size"), newRes, new[] { "512", "1024", "2048", "4096" }, new[] { 512, 1024, 2048, 4096 });
                if (GUILayout.Button(T("白で作り直す", "New (white)"), GUILayout.Width(100)) &&
                    EditorUtility.DisplayDialog("MitToon", T("今の内容を消して作り直しますか?", "Discard the current mask and start over?"), "OK", T("キャンセル", "Cancel")))
                { CreateRT(newRes, newRes, null); SceneView.RepaintAll(); }
            }
            using (new EditorGUI.DisabledScope(targets.Count == 0 && onSaved == null))
                if (GUILayout.Button(T("PNG で出力", "Export PNG"), GUILayout.Height(32))) Export();
            EditorGUILayout.EndScrollView();
        }

        static void BlitKeep(Texture src, RenderTexture dst)
        {
            var prev = RenderTexture.active;
            Graphics.Blit(src, dst);
            RenderTexture.active = prev;
            SceneView.RepaintAll();
        }

        void Invert()
        {
            var prevActive = RenderTexture.active;
            var tmp = RenderTexture.GetTemporary(rt.descriptor);
            Graphics.Blit(rt, tmp, paintMat, 5);
            Graphics.Blit(tmp, rt);
            RenderTexture.ReleaseTemporary(tmp);
            RenderTexture.active = prevActive;
        }

        void DrawUVView()
        {
            float size = Mathf.Min(position.width - 24, 360);
            var rect = GUILayoutUtility.GetRect(size, size, GUILayout.ExpandWidth(false));
            rect.x += (position.width - size) * 0.5f - 4;
            var e = Event.current;
            if (e.type == EventType.Repaint)
            {
                EditorGUI.DrawPreviewTexture(rect, rt, null, ScaleMode.StretchToFill);
                // UV wire frame (fractional part, so tiled UVs still land on the image)
                Handles.BeginGUI();
                Handles.color = new Color(0.2f, 1f, 0.6f, 0.35f);
                var lines = new List<Vector3>();
                foreach (var t in targets)
                {
                    int tc = t.tris.Length / 3;
                    int step = Mathf.Max(1, tc / 20000);   // keep the view responsive on dense meshes
                    for (int i = 0; i < tc; i += step)
                        for (int k = 0; k < 3; k++)
                        {
                            lines.Add(UVToRect(rect, t.uv[t.tris[i * 3 + k]]));
                            lines.Add(UVToRect(rect, t.uv[t.tris[i * 3 + (k + 1) % 3]]));
                        }
                }
                if (lines.Count > 0) Handles.DrawLines(lines.ToArray());
                Handles.EndGUI();
            }
            if (e.type == EventType.MouseDown && e.button == 0 && rect.Contains(e.mousePosition))
            {
                var uv = new Vector2((e.mousePosition.x - rect.x) / rect.width, 1f - (e.mousePosition.y - rect.y) / rect.height);
                foreach (var t in targets)
                {
                    int tri = FindTriangleUV(t, uv);
                    if (tri < 0) continue;
                    PushUndo();
                    FillIsland(t, tri, mirror);
                    break;
                }
                e.Use();
                SceneView.RepaintAll();
            }
        }

        static Vector3 UVToRect(Rect r, Vector2 uv)
        {
            uv.x -= Mathf.Floor(uv.x); uv.y -= Mathf.Floor(uv.y);
            return new Vector3(r.x + uv.x * r.width, r.y + (1f - uv.y) * r.height, 0);
        }

        static int FindTriangleUV(Target t, Vector2 p)
        {
            int tc = t.tris.Length / 3;
            for (int i = 0; i < tc; i++)
            {
                Vector2 a = Frac(t.uv[t.tris[i * 3]]), b = Frac(t.uv[t.tris[i * 3 + 1]]), c = Frac(t.uv[t.tris[i * 3 + 2]]);
                float d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
                if (Mathf.Abs(d) < 1e-12f) continue;
                float l1 = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d;
                float l2 = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d;
                if (l1 >= 0 && l2 >= 0 && l1 + l2 <= 1) return i;
            }
            return -1;
        }
        static Vector2 Frac(Vector2 v) => new Vector2(v.x - Mathf.Floor(v.x), v.y - Mathf.Floor(v.y));

        // ------------------------------------------------------------------ export / close
        void Export()
        {
            string dir = "Assets";
            var sp = startTex != null ? AssetDatabase.GetAssetPath(startTex) : null;
            if (!string.IsNullOrEmpty(sp)) dir = Path.GetDirectoryName(sp).Replace('\\', '/');
            else if (targetRenderer != null)
            {
                var m = targetRenderer.sharedMaterials.FirstOrDefault(x => x != null && !string.IsNullOrEmpty(AssetDatabase.GetAssetPath(x)));
                if (m != null) dir = Path.GetDirectoryName(AssetDatabase.GetAssetPath(m)).Replace('\\', '/');
            }
            string defName = !string.IsNullOrEmpty(sp) && sp.EndsWith(".png") ? Path.GetFileNameWithoutExtension(sp) : defaultName;
            var path = EditorUtility.SaveFilePanelInProject(T("マスクを出力", "Export Mask"), defName, "png", "", dir);
            if (string.IsNullOrEmpty(path)) return;

            // seam padding: grow painted islands a few pixels so bilinear / mip sampling does not bleed at UV seams
            var desc = rt.descriptor;
            var img = RenderTexture.GetTemporary(desc);
            Graphics.Blit(rt, img);
            Pad(img, 8);
            var prev = RenderTexture.active;
            RenderTexture.active = img;
            var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBA32, false, true);
            tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
            tex.Apply();
            RenderTexture.active = prev;
            RenderTexture.ReleaseTemporary(img);
            File.WriteAllBytes(path, tex.EncodeToPNG());
            DestroyImmediate(tex);

            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            if (AssetImporter.GetAtPath(path) is TextureImporter ti)
            {
                ti.textureType = TextureImporterType.Default;
                ti.sRGBTexture = false;   // masks are data
                ti.alphaSource = TextureImporterAlphaSource.None;
                ti.mipmapEnabled = true;
                ti.SaveAndReimport();
            }
            var saved = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
            startTex = saved;
            onSaved?.Invoke(saved);
            EditorGUIUtility.PingObject(saved);
            ShowNotification(new GUIContent(T("出力しました", "Exported")));
        }

        void OnDisable()
        {
            SceneView.duringSceneGui -= OnScene;
            EditorApplication.update -= Tick;
            ClearTargets();
            ClearUndo();
            if (rt != null) { rt.Release(); DestroyImmediate(rt); rt = null; }
            if (paintMat != null) DestroyImmediate(paintMat);
            if (overlayMat != null) DestroyImmediate(overlayMat);
            SceneView.RepaintAll();
        }

        void ClearTargets()
        {
            foreach (var t in targets)
            {
                if (t.colliderGO != null) DestroyImmediate(t.colliderGO);
                if (t.mesh != null) DestroyImmediate(t.mesh);
                foreach (var m in t.islandMesh.Values) if (m != null) DestroyImmediate(m);
            }
            targets.Clear();
        }
    }
}
