// MitToon - Tessellation settings applied non-destructively at avatar build (NDMF).
// Put it on the avatar (or any object inside it). At upload the MitToon materials of the target renderers are
// cloned, switched to the Tessellation shader variant and given these settings. The original materials never change.
using System;
using System.Collections.Generic;
using UnityEngine;

namespace MitToon
{
    [DisallowMultipleComponent]
    [AddComponentMenu("MitToon/MitToon Tessellation")]
    public class MitToonTessellation : MonoBehaviour
#if MITTOON_VRCSDK
        , VRC.SDKBase.IEditorOnly
#endif
    {
        public enum TargetScope { Children = 0, ListedRenderers = 1 }

        [Serializable]
        public class MaterialMask
        {
            public Material material;
            public Texture2D mask;
        }

        [Tooltip("Children: every renderer under this object. ListedRenderers: only the renderers in the list.")]
        public TargetScope scope = TargetScope.Children;
        public List<Renderer> renderers = new List<Renderer>();
        [Tooltip("Materials that stay without tessellation")]
        public List<Material> excludeMaterials = new List<Material>();

        [Tooltip("Off: only switch the shader and keep the values set on each material")]
        public bool overrideSettings = true;
        [Range(2, 50)] public float edgeLength = 12;
        [Range(1, 32)] public float maxSubdivision = 8;
        [Range(0, 1)] public float smoothing = 0.5f;
        [Range(0, 20)] public float fadeStart = 2;
        [Range(0, 50)] public float fadeEnd = 8;

        [Tooltip("Mask (R) used for every material. Empty: keep each material's own mask")]
        public Texture2D mask;
        [Tooltip("Mask per material (wins over the common mask)")]
        public List<MaterialMask> materialMasks = new List<MaterialMask>();
    }
}
