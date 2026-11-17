using System.Linq;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // Adds a shadowed spot light (almost no brightness) above the avatar's face, aimed down at the body. MitToon reads it
    // as the shadow light: its soft shadow (PCSS) darkens the avatar in any world. It reaches avatars only
    // (Player / PlayerLocal / MirrorReflection) and turns on PCSS in the avatar's MitToon materials.
    public static class MitToonShadowLight
    {
        public const string LightName = "MitToon ShadowLight";
        public const string PivotName = "MitToon ShadowLight Pivot";
        // set by MitToon.VRC (VRChat SDK present): adds / reads the world rotation lock of the pivot (pivot, avatar root)
        public static System.Action<Transform, Transform> AddRotationLock;
        public static System.Func<Transform, bool> HasRotationLock;
        // Player (9) + PlayerLocal (10) + MirrorReflection (18), plus Default (0) where the avatar sits in the editor.
        // Default is removed on upload (MitToon.VRC.MitToonShadowLightBuildHook) so the light never reaches the world.
        const int CullingMask = (1 << 0) | (1 << 9) | (1 << 10) | (1 << 18);

        // what the light moves with
        public enum Follow { Body = 0, Head = 1, Chest = 2 }
        public static readonly string[] FollowJP = { "体 (アバター全体)", "頭 (頭の向きで影が動く)", "胸 (上半身の向きで影が動く)" };
        public static readonly string[] FollowEN = { "Body (whole avatar)", "Head (shadows move with the head)", "Chest (shadows move with the upper body)" };
        // where the light sits, seen from the avatar
        public enum Aim { FrontAbove = 0, Above = 1, LeftFrontAbove = 2, RightFrontAbove = 3, FrontLow = 4 }
        public static readonly string[] AimJP = { "前の上", "真上", "左前の上", "右前の上", "正面 (やや上)" };
        public static readonly string[] AimEN = { "Front, above", "Straight above", "Front left, above", "Front right, above", "Front (slightly above)" };

        [MenuItem("Tools/MitToon/影ライトを追加 (Add Shadow Light)")]
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

        public static void AddForMaterials(Material[] materials)
        {
            var roots = MitToonSceneUtil.AvatarsUsing(materials);
            if (roots.Count == 0) { MitToonSceneUtil.NotFound(); return; }
            if (!MitToonSceneUtil.Confirm("次のアバターに影ライトを追加します (ライト数 +1)。", "Add a shadow light to (+1 light):", roots)) return;
            foreach (var r in roots) AddToRoot(r);
        }

        // materials set up after the light was added (converted from lilToon, presets, new copies): the shadow light needs
        // PCSS on, so it is turned on for the avatars in the open scenes that use them and have a shadow light
        public static int EnablePCSSWhereShadowLight(Material[] materials)
        {
            bool Needs(Material m) => m.GetFloat("_UsePCSS") < 0.5f || (m.HasProperty("_BlendOpAdd") && m.GetFloat("_BlendOpAdd") != 0 && MitToonShaderGUI.ShadowLightBlend(m));
            var mats = materials.Where(m => m != null && m.shader != null && m.shader.name.StartsWith("MitToon/") && m.HasProperty("_UsePCSS") && Needs(m)).Distinct().ToArray();
            if (mats.Length == 0) return 0;
            int n = 0;
            foreach (var root in MitToonSceneUtil.AvatarsUsing(mats))
            {
                if (FindLight(root) == null) continue;
                var used = new System.Collections.Generic.HashSet<Material>(root.GetComponentsInChildren<Renderer>(true).SelectMany(r => r.sharedMaterials));
                foreach (var m in mats)
                    if (used.Contains(m) && Needs(m)) { m.SetFloat("_UsePCSS", 1); MitToonShaderGUI.SyncKeywords(m); EditorUtility.SetDirty(m); n++; }
            }
            return n;
        }

        // all MitToon materials of the avatars that use these materials and have a shadow light
        public static int EnablePCSSOnAvatars(Material[] materials)
        {
            var roots = MitToonSceneUtil.AvatarsUsing(materials).Where(r => FindLight(r) != null).ToList();
            var all = roots.SelectMany(r => r.GetComponentsInChildren<Renderer>(true)).SelectMany(r => r.sharedMaterials).Where(m => m != null).Distinct().ToArray();
            Undo.RecordObjects(all, "MitToon PCSS");
            return EnablePCSSWhereShadowLight(all);
        }

        static readonly System.Collections.Generic.Dictionary<Material, (double t, bool v)> lightCache = new System.Collections.Generic.Dictionary<Material, (double, bool)>();
        // cached for the inspector: does an avatar using this material have a shadow light
        public static bool HasShadowLight(Material m)
        {
            double now = EditorApplication.timeSinceStartup;
            if (lightCache.TryGetValue(m, out var c) && now - c.t < 2.0) return c.v;
            bool v = LightsFor(new[] { m }).Length > 0;
            lightCache[m] = (now, v);
            return v;
        }

        public static Light FindLight(Transform root) =>
            root == null ? null : root.GetComponentsInChildren<Light>(true).FirstOrDefault(l => l.name == LightName);

        // the shadow lights of the avatars using these materials
        public static Light[] LightsFor(Material[] materials) =>
            MitToonSceneUtil.AvatarsUsing(materials).Select(FindLight).Where(l => l != null).ToArray();

        // selects the shadow lights of the avatars using these materials (to move or aim them)
        public static void SelectForMaterials(Material[] materials)
        {
            var lights = LightsFor(materials).Select(l => (Object)l.gameObject).ToArray();
            if (lights.Length == 0) { NoLight(); return; }
            Selection.objects = lights;
            EditorGUIUtility.PingObject(lights[0]);
        }

        static void NoLight() =>
            EditorUtility.DisplayDialog("MitToon", "影ライトが見つかりません。先に「影ライトを追加」を押してください。\nNo Shadow Light found. Add one first.", "OK");

        public static void Apply(Light l)
        {
            l.type = LightType.Spot;
            l.lightmapBakeType = LightmapBakeType.Realtime;
            l.renderMode = LightRenderMode.ForcePixel;
            l.range = 6f;
            l.spotAngle = 45f;
            l.innerSpotAngle = 30f;
            l.color = Color.white;
            l.intensity = 0.01f;   // MitToon reads a shadowed spot this dim as the shadow light (it adds no light anywhere)
            l.shadows = LightShadows.Soft;
            l.shadowStrength = 1f;
            l.shadowResolution = UnityEngine.Rendering.LightShadowResolution.VeryHigh;
            l.shadowCustomResolution = 4096;   // fixed: does not drop when the avatar is small on screen
            l.shadowBias = 0.001f;        // small: close shadows (bangs on the face, chin on the neck) must stay
            l.shadowNormalBias = 0.1f;
            l.shadowNearPlane = 0.1f;
            l.cullingMask = CullingMask;
        }

        static Transform Bone(Transform root, HumanBodyBones b)
        {
            var anim = root.GetComponentInChildren<Animator>();
            return anim != null && anim.isHuman ? anim.GetBoneTransform(b) : null;
        }

        // the follow mode of an existing light, read from its parent
        public static Follow CurrentFollow(Light l)
        {
            var root = MitToonSceneUtil.AvatarRoot(l.transform);
            var p = l.transform.parent;
            if (p != null && p.name == PivotName) p = p.parent;
            if (p != null && p == Bone(root, HumanBodyBones.Head)) return Follow.Head;
            if (p != null && (p == Bone(root, HumanBodyBones.UpperChest) || p == Bone(root, HumanBodyBones.Chest))) return Follow.Chest;
            return Follow.Body;
        }

        public static bool CurrentLock(Light l)
        {
            var p = l.transform.parent;
            return p != null && p.name == PivotName && HasRotationLock != null && HasRotationLock(p);
        }

        public static float CurrentDistance(Light l)
        {
            var root = MitToonSceneUtil.AvatarRoot(l.transform);
            var head = Bone(root, HumanBodyBones.Head);
            Vector3 hp = head != null ? head.position : root.position + root.up * 1.4f;
            return Vector3.Distance(hp, l.transform.position);
        }

        // moves the light to the aim / distance and parents it to what it follows. The aim is taken from the avatar's
        // rest facing (root), so it is the same whatever the pose in the scene.
        public static void Place(Light l, Follow follow, Aim aim, float distance, float spotAngle, bool lockRotation = false)
        {
            if (lockRotation && AddRotationLock == null)
            {
                EditorUtility.DisplayDialog("MitToon", "回転の固定には VRChat SDK (Avatars) が必要です。\nLocking the rotation needs the VRChat Avatars SDK.", "OK");
                lockRotation = false;
            }
            var oldPivot = l.transform.parent != null && l.transform.parent.name == PivotName ? l.transform.parent : null;
            var root = MitToonSceneUtil.AvatarRoot(l.transform);
            var head = Bone(root, HumanBodyBones.Head);
            var chest = Bone(root, HumanBodyBones.UpperChest) ?? Bone(root, HumanBodyBones.Chest);
            Vector3 hp = head != null ? head.position : root.position + root.up * 1.4f;
            Vector3 dir;
            switch (aim)
            {
                case Aim.Above: dir = new Vector3(0, 1, 0.15f); break;
                case Aim.LeftFrontAbove: dir = new Vector3(-0.7f, 1, 0.7f); break;
                case Aim.RightFrontAbove: dir = new Vector3(0.7f, 1, 0.7f); break;
                case Aim.FrontLow: dir = new Vector3(0, 0.35f, 1); break;
                default: dir = new Vector3(0, 1, 1); break;
            }
            dir = root.TransformDirection(dir.normalized);
            Transform parent = root;
            if (follow == Follow.Head && head != null) parent = head;
            if (follow == Follow.Chest && chest != null) parent = chest;
            if (lockRotation)
            {
                // the light hangs from a pivot at the head height whose world rotation is frozen when the avatar loads
                var pv = new GameObject(PivotName);
                Undo.RegisterCreatedObjectUndo(pv, "MitToon ShadowLight Follow");
                pv.transform.SetParent(parent, false);
                pv.transform.position = hp;
                pv.transform.rotation = root.rotation;
                AddRotationLock(pv.transform, root);
                parent = pv.transform;
            }
            Undo.RecordObject(l, "MitToon ShadowLight Follow");
            Undo.SetTransformParent(l.transform, parent, "MitToon ShadowLight Follow");
            Undo.RecordObject(l.transform, "MitToon ShadowLight Follow");
            l.transform.position = hp + dir * distance;
            l.transform.rotation = Quaternion.LookRotation((hp - root.up * 0.45f) - l.transform.position, root.up);
            l.spotAngle = spotAngle;
            l.innerSpotAngle = Mathf.Min(l.innerSpotAngle, spotAngle);
            EditorUtility.SetDirty(l);
            if (oldPivot != null) Undo.DestroyObjectImmediate(oldPivot.gameObject);
        }

        public static void PlaceForMaterials(Material[] materials, Follow follow, Aim aim, float distance, float spotAngle, bool lockRotation)
        {
            var lights = LightsFor(materials);
            if (lights.Length == 0) { NoLight(); return; }
            foreach (var l in lights) Place(l, follow, aim, distance, spotAngle, lockRotation);
        }

        public static void AddToRoot(Transform root)
        {
            var l = FindLight(root);
            bool created = l == null;
            if (created)
            {
                var go = new GameObject(LightName);
                Undo.RegisterCreatedObjectUndo(go, "Add MitToon ShadowLight");
                go.transform.SetParent(root, false);
                l = Undo.AddComponent<Light>(go);
            }
            Undo.RecordObject(l, "Setup MitToon ShadowLight");
            Apply(l);
            if (created) Place(l, Follow.Body, Aim.FrontAbove, 2f, 45f);

            // turn PCSS on in the avatar's MitToon materials
            var mats = root.GetComponentsInChildren<Renderer>(true).SelectMany(r => r.sharedMaterials)
                .Where(m => m != null && m.shader != null && m.shader.name.StartsWith("MitToon/") && m.HasProperty("_UsePCSS")).Distinct().ToArray();
            if (mats.Length > 0)
            {
                Undo.RecordObjects(mats, "MitToon PCSS");
                foreach (var m in mats) { m.SetFloat("_UsePCSS", 1); MitToonShaderGUI.SyncKeywords(m); EditorUtility.SetDirty(m); }
            }
            EditorGUIUtility.PingObject(l.gameObject);
            Debug.Log($"[MitToon] ShadowLight を追加しました (Lights +1, PCSS: {mats.Length} materials)。 / ShadowLight added.");
        }
    }
}
