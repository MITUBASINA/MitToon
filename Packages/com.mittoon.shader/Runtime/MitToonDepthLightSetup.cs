// MitToon - shared settings of the depth light (added by hand with the editor tool, opt in).
// Not added automatically: in VRChat a shadowed directional light makes every camera that sees the avatar render
// the depth of the whole world once more, which costs a lot of frame time in heavy worlds.
using UnityEngine;

namespace MitToon
{
    // Unity renders _CameraDepthTexture for the normal view and mirrors only while a directional light with shadows
    // is present. This black light (intensity 0.01, hard shadows, not important) makes it render; it adds no light.
    public static class MitToonDepthLightSetup
    {
        public const string LightName = "MitToon DepthLight";
        // StereoLeft (15) + MirrorReflection (18); fixed bits so projects without VRChat layer names still work
        public const int CullingMask = (1 << 15) | (1 << 18);

        public static void Apply(Light l)
        {
            l.type = LightType.Directional;
#if UNITY_EDITOR
            l.lightmapBakeType = LightmapBakeType.Realtime;
#endif
            l.renderMode = LightRenderMode.ForceVertex;
            l.color = Color.black;
            l.intensity = 0.01f;
            l.shadows = LightShadows.Hard;
            l.shadowStrength = 1f;
            l.shadowResolution = UnityEngine.Rendering.LightShadowResolution.Low;
            l.cullingMask = CullingMask;
        }

        // true when the material reads the camera depth texture
        public static bool UsesDepth(Material m)
        {
            if (m == null || m.shader == null || !m.shader.name.StartsWith("MitToon/")) return false;
            if (m.IsKeywordEnabled("_LUMI_SSAO") || m.IsKeywordEnabled("_LUMI_CONTACTSHADOW") ||
                m.IsKeywordEnabled("_LUMI_SOFTSHADOW") || m.IsKeywordEnabled("_LUMI_DEPTHSHADOW") ||
                m.IsKeywordEnabled("_LUMI_OFFSETRIM")) return true;
            if (m.IsKeywordEnabled("_LUMI_RIM") && m.HasProperty("_RimMode") && m.GetFloat("_RimMode") > 0.5f) return true;
            return false;
        }

        // a directional light with shadows already in the avatar (this tool's, or one added by hand)
        public static bool HasDepthLight(Transform root)
        {
            foreach (var l in root.GetComponentsInChildren<Light>(true))
                if (l.type == LightType.Directional && l.shadows != LightShadows.None && l.cullingMask != 0) return true;
            return false;
        }
    }
}
