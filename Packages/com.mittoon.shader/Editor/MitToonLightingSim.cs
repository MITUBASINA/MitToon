// MitToon - World lighting simulator: preview the avatar under typical VRChat world lighting without leaving the scene.
// Every change is temporary: Restore (or closing the window) puts the scene lighting back exactly as it was.
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace MitToon.Editor
{
    public class MitToonLightingSim : EditorWindow
    {
        struct PointDef { public Vector3 offset; public Color color; public float intensity; public float range; }
        class Preset
        {
            public string jp, en;
            public Color sky, ground;
            public bool sun; public Color sunColor; public float sunIntensity; public Vector3 sunEuler;
            public PointDef[] points = new PointDef[0];
        }

        static readonly Preset[] Presets =
        {
            new Preset { jp = "晴れた屋外", en = "Sunny Outdoor", sky = new Color(0.55f, 0.68f, 0.95f), ground = new Color(0.33f, 0.3f, 0.26f),
                         sun = true, sunColor = new Color(1f, 0.96f, 0.88f), sunIntensity = 1.2f, sunEuler = new Vector3(50, -30, 0) },
            new Preset { jp = "夕方", en = "Sunset", sky = new Color(0.32f, 0.28f, 0.4f), ground = new Color(0.16f, 0.11f, 0.08f),
                         sun = true, sunColor = new Color(1f, 0.58f, 0.32f), sunIntensity = 1f, sunEuler = new Vector3(10, -70, 0) },
            new Preset { jp = "夜の屋外 (月明かり)", en = "Night (moonlight)", sky = new Color(0.05f, 0.07f, 0.13f), ground = new Color(0.02f, 0.02f, 0.03f),
                         sun = true, sunColor = new Color(0.6f, 0.7f, 1f), sunIntensity = 0.25f, sunEuler = new Vector3(40, 120, 0) },
            new Preset { jp = "室内 (暖色照明)", en = "Indoor (warm lamps)", sky = new Color(0.42f, 0.37f, 0.32f), ground = new Color(0.22f, 0.18f, 0.15f),
                         points = new[] { new PointDef { offset = new Vector3(0.6f, 2.2f, 0.8f), color = new Color(1f, 0.8f, 0.6f), intensity = 1.2f, range = 5 } } },
            new Preset { jp = "暗いクラブ (色付きライト)", en = "Dark Club (coloured lights)", sky = new Color(0.03f, 0.02f, 0.05f), ground = new Color(0.01f, 0.01f, 0.02f),
                         points = new[] {
                             new PointDef { offset = new Vector3(-1.2f, 1.6f, 0.9f), color = new Color(1f, 0.2f, 0.8f), intensity = 2f, range = 4 },
                             new PointDef { offset = new Vector3(1.3f, 1.2f, -0.6f), color = new Color(0.2f, 0.7f, 1f), intensity = 2f, range = 4 } } },
            new Preset { jp = "環境光だけ (ライト無しのワールド)", en = "Ambient Only (no lights)", sky = new Color(0.75f, 0.75f, 0.78f), ground = new Color(0.55f, 0.53f, 0.5f) },
            new Preset { jp = "ほぼ真っ暗", en = "Almost Dark", sky = new Color(0.008f, 0.008f, 0.01f), ground = new Color(0.004f, 0.004f, 0.005f) },
        };

        // saved scene state
        bool saved;
        AmbientMode sMode; Color sSky, sEq, sGround, sAmb; float sAmbInt; SphericalHarmonicsL2 sProbe;
        Light sSun; bool sSunEnabled; Color sSunColor; float sSunIntensity; Quaternion sSunRot;
        readonly List<GameObject> temp = new List<GameObject>();
        int active = -1;

        static bool JP => EditorPrefs.GetBool("MitToon.JP", true);
        static string T(string jp, string en) => MitToonShaderGUI.Bare(JP ? jp : en);

        [MenuItem("Tools/MitToon/ワールド照明シミュレーター (Lighting Simulator)")]
        public static void Open() => GetWindow<MitToonLightingSim>(true, "MitToon Lighting Simulator").minSize = new Vector2(300, 330);

        void OnGUI()
        {
            for (int i = 0; i < Presets.Length; i++)
            {
                var p = Presets[i];
                var style = new GUIStyle(GUI.skin.button) { fontStyle = i == active ? FontStyle.Bold : FontStyle.Normal };
                if (GUILayout.Button((i == active ? "> " : "") + T(p.jp, p.en), style, GUILayout.Height(24))) Apply(p, i);
            }
            EditorGUILayout.Space(6);
            using (new EditorGUI.DisabledScope(!saved))
                if (GUILayout.Button(T("元に戻す", "Restore"), GUILayout.Height(28))) Restore();
        }

        void OnDestroy() => Restore();

        void Save()
        {
            if (saved) return;
            sMode = RenderSettings.ambientMode; sSky = RenderSettings.ambientSkyColor; sEq = RenderSettings.ambientEquatorColor;
            sGround = RenderSettings.ambientGroundColor; sAmb = RenderSettings.ambientLight; sAmbInt = RenderSettings.ambientIntensity;
            sProbe = RenderSettings.ambientProbe;
            sSun = RenderSettings.sun;
            if (sSun == null)
                foreach (var l in Object.FindObjectsOfType<Light>())
                    if (l.type == LightType.Directional && l.isActiveAndEnabled) { sSun = l; break; }
            if (sSun != null) { sSunEnabled = sSun.enabled; sSunColor = sSun.color; sSunIntensity = sSun.intensity; sSunRot = sSun.transform.rotation; }
            saved = true;
        }

        void ClearTemp()
        {
            foreach (var g in temp) if (g != null) DestroyImmediate(g);
            temp.Clear();
        }

        GameObject TempLight(string name, LightType type, Color c, float intensity)
        {
            var g = new GameObject(name) { hideFlags = HideFlags.DontSave };
            var l = g.AddComponent<Light>();
            l.type = type; l.color = c; l.intensity = intensity;
            // worlds rarely give point lights realtime shadows (heavy); match that
            l.shadows = type == LightType.Directional ? LightShadows.Soft : LightShadows.None;
            temp.Add(g);
            return g;
        }

        static Vector3 Center()
        {
            var sv = SceneView.lastActiveSceneView;
            return sv != null ? sv.pivot : Vector3.zero;
        }

        void Apply(Preset p, int index)
        {
            Save();
            ClearTemp();
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = p.sky;
            RenderSettings.ambientEquatorColor = Color.Lerp(p.sky, p.ground, 0.5f);
            RenderSettings.ambientGroundColor = p.ground;
            // ambient probe directly: avatars without baked probes read it immediately
            var sh = new SphericalHarmonicsL2();
            sh.AddAmbientLight(Color.Lerp(p.sky, p.ground, 0.5f));
            var grad = (p.sky - p.ground) * 0.5f;
            sh.AddDirectionalLight(Vector3.up, new Color(Mathf.Max(grad.r, 0), Mathf.Max(grad.g, 0), Mathf.Max(grad.b, 0)), 1f);
            sh.AddDirectionalLight(Vector3.down, new Color(Mathf.Max(-grad.r, 0), Mathf.Max(-grad.g, 0), Mathf.Max(-grad.b, 0)), 1f);
            RenderSettings.ambientProbe = sh;

            if (sSun != null) sSun.enabled = false;
            if (p.sun)
            {
                var g = TempLight("MitToon Sim Sun", LightType.Directional, p.sunColor, p.sunIntensity);
                g.transform.rotation = Quaternion.Euler(p.sunEuler);
            }
            var c = Center();
            foreach (var pt in p.points)
            {
                var g = TempLight("MitToon Sim Point", LightType.Point, pt.color, pt.intensity);
                g.GetComponent<Light>().range = pt.range;
                g.transform.position = c + pt.offset;
            }
            active = index;
            SceneView.RepaintAll();
        }

        void Restore()
        {
            ClearTemp();
            if (!saved) return;
            RenderSettings.ambientMode = sMode; RenderSettings.ambientSkyColor = sSky; RenderSettings.ambientEquatorColor = sEq;
            RenderSettings.ambientGroundColor = sGround; RenderSettings.ambientLight = sAmb; RenderSettings.ambientIntensity = sAmbInt;
            RenderSettings.ambientProbe = sProbe;
            if (sSun != null) { sSun.enabled = sSunEnabled; sSun.color = sSunColor; sSun.intensity = sSunIntensity; sSun.transform.rotation = sSunRot; }
            saved = false;
            active = -1;
            SceneView.RepaintAll();
        }
    }
}
