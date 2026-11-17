using UnityEngine;
using VRC.SDKBase.Editor.BuildPipeline;

namespace MitToon.VRC
{
    // The shadow light also lights the Default layer so the avatar shows its shadows in the editor (avatars sit on
    // Default there). VRChat moves the avatar to Player / PlayerLocal at runtime, so on upload the light is limited to
    // the avatar layers again and does not light the world.
    public class MitToonShadowLightBuildHook : IVRCSDKPreprocessAvatarCallback
    {
        const string LightName = "MitToon ShadowLight";   // MitToon.Editor.MitToonShadowLight.LightName
        const int AvatarLayers = (1 << 9) | (1 << 10) | (1 << 18);   // Player, PlayerLocal, MirrorReflection

        public int callbackOrder => 0;

        public bool OnPreprocessAvatar(GameObject avatarGameObject)
        {
            if (Application.isPlaying) return true;   // play mode emulators keep the editor layers
            foreach (var l in avatarGameObject.GetComponentsInChildren<Light>(true))
                if (l.name == LightName) l.cullingMask &= AvatarLayers;
            return true;
        }
    }
}
