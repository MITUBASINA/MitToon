using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // RayTrace shader: the blurred copies of the screen are built once per camera render and shared (MitToonRTPyramid.hlsl).
    // A render is told apart by time, camera and a few pixels; the editor can render one camera twice in a frame (scene
    // view repaints, previews) with all of these the same, so it numbers every camera render here. (In VRChat the time
    // alone moves on every frame.)
    [InitializeOnLoad]
    static class MitToonRenderSerial
    {
        static float serial;
        static readonly int Id = Shader.PropertyToID("_LumiRTSerial");

        static MitToonRenderSerial()
        {
            Camera.onPreRender -= Tick;
            Camera.onPreRender += Tick;
        }

        static void Tick(Camera c)
        {
            serial = serial >= 1000000f ? 1f : serial + 1f;
            Shader.SetGlobalFloat(Id, serial);
        }
    }
}
