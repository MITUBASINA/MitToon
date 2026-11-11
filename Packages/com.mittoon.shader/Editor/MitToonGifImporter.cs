using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace MitToon.Editor
{
    // GIF -> flipbook sprite sheet. Decodes the GIF (LZW, local / global palettes, transparency, disposal, interlace),
    // lays the frames out from the top left the way the flipbook reads them, saves a PNG under Assets/MitToon_UserData/GIF
    // (outside the MitToon package) and sets the flipbook of the selected materials.
    public static class MitToonGifImporter
    {
        const string OutRoot = "Assets/MitToon_UserData";
        const string OutDir = OutRoot + "/GIF";
        const int MaxSheet = 4096;     // sheet size limit (VRChat friendly)
        const int MaxFrames = 512;     // flipbook frame limit

        public class Gif
        {
            public int width, height;
            public List<Color32[]> frames = new List<Color32[]>();   // full canvas, rows top to bottom
            public List<int> delays = new List<int>();               // 1/100 s
        }

        static bool JP => MitToonShaderGUI.JP;
        static string T(string jp, string en) => JP ? jp : en;

        public static void ImportToFlipbook(Material[] mats)
        {
            var path = EditorUtility.OpenFilePanel(T("GIF を選択", "Select a GIF"), Application.dataPath, "gif");
            if (string.IsNullOrEmpty(path)) return;
            Gif gif;
            try { gif = Decode(File.ReadAllBytes(path)); }
            catch (System.Exception e)
            {
                EditorUtility.DisplayDialog("MitToon", T("GIF を読み込めませんでした。\n", "Could not read the GIF.\n") + e.Message, "OK");
                return;
            }
            var sheet = BuildSheet(gif, out int cols, out int rows, out int count, out float fps);
            if (!AssetDatabase.IsValidFolder(OutRoot)) AssetDatabase.CreateFolder("Assets", "MitToon_UserData");
            if (!AssetDatabase.IsValidFolder(OutDir)) AssetDatabase.CreateFolder(OutRoot, "GIF");
            var asset = AssetDatabase.GenerateUniqueAssetPath(OutDir + "/" + Path.GetFileNameWithoutExtension(path) + $"_{cols}x{rows}.png");   // columns x rows in the file name
            File.WriteAllBytes(asset, sheet.EncodeToPNG());
            int size = Mathf.Max(sheet.width, sheet.height);
            bool opaque = true; foreach (var fr in gif.frames) { foreach (var c in fr) if (c.a < 255) { opaque = false; break; } if (!opaque) break; }   // empty cells at the end do not count
            Object.DestroyImmediate(sheet);
            AssetDatabase.ImportAsset(asset, ImportAssetOptions.ForceUpdate);
            if (AssetImporter.GetAtPath(asset) is TextureImporter ti)
            {
                ti.textureType = TextureImporterType.Default;
                ti.sRGBTexture = true;
                ti.alphaSource = opaque ? TextureImporterAlphaSource.None : TextureImporterAlphaSource.FromInput;   // no alpha: DXT1 (half of DXT5)
                ti.alphaIsTransparency = !opaque;
                ti.mipmapEnabled = false;   // mips would mix neighbouring frames
                ti.wrapMode = TextureWrapMode.Clamp;
                ti.maxTextureSize = Mathf.Clamp(Mathf.NextPowerOfTwo(size), 32, MaxSheet);
                ti.npotScale = TextureImporterNPOTScale.None;
                ti.textureCompression = TextureImporterCompression.Compressed;   // DXT1 (opaque) / DXT5 (transparent): light on VRAM
                ti.SaveAndReimport();
            }
            var tex = AssetDatabase.LoadAssetAtPath<Texture2D>(asset);
            foreach (var m in mats)
            {
                Undo.RecordObject(m, "MitToon GIF");
                m.SetFloat("_UseFlipbook", 1);
                m.SetTexture("_FlipbookTex", tex);
                m.SetVector("_FlipbookGrid", new Vector4(cols, rows, count, fps));
                m.SetFloat("_FlipbookFrame", -1);
                MitToonShaderGUI.SyncKeywords(m);
                EditorUtility.SetDirty(m);
            }
            EditorGUIUtility.PingObject(tex);
            Debug.Log($"MitToon: GIF {Path.GetFileName(path)} -> {asset} ({gif.frames.Count} frames, sheet {cols}x{rows}, {count} cells at {fps:0.##} fps)");
        }

        // Frames with different delays: repeated so the flipbook (one speed) keeps the timing, when that stays small.
        public static Texture2D BuildSheet(Gif gif, out int cols, out int rows, out int count, out float fps)
        {
            var delays = new List<int>();
            foreach (var d in gif.delays) delays.Add(d <= 1 ? 10 : d);   // 0 / 1 = 100 ms, like browsers
            int total = 0; foreach (var d in delays) total += d;
            int g = 0; foreach (var d in delays) g = Gcd(g, d);
            g = Mathf.Max(g, 2);
            var order = new List<int>();
            int expanded = 0; foreach (var d in delays) expanded += Mathf.Max(1, Mathf.RoundToInt(d / (float)g));
            bool even = true; foreach (var d in delays) even &= d == delays[0];
            if (!even && expanded <= MaxFrames && expanded <= gif.frames.Count * 3)
            {
                for (int i = 0; i < delays.Count; i++) for (int k = 0; k < Mathf.Max(1, Mathf.RoundToInt(delays[i] / (float)g)); k++) order.Add(i);
                fps = 100f / g;
            }
            else
            {
                int n = Mathf.Min(gif.frames.Count, MaxFrames);
                for (int i = 0; i < n; i++) order.Add(i * gif.frames.Count / n);   // too many frames: evenly skip
                fps = order.Count / Mathf.Max(total / 100f, 0.01f);
            }
            count = order.Count;
            int w = gif.width, h = gif.height;
            cols = Mathf.Max(1, Mathf.CeilToInt(Mathf.Sqrt(count * h / (float)w)));
            rows = Mathf.CeilToInt(count / (float)cols);
            float scale = Mathf.Min(1f, MaxSheet / (float)(cols * w), MaxSheet / (float)(rows * h));
            int cw = Mathf.Max(1, Mathf.FloorToInt(w * scale)), ch = Mathf.Max(1, Mathf.FloorToInt(h * scale));
            var px = new Color32[cols * cw * rows * ch];
            int W = cols * cw;
            for (int k = 0; k < count; k++)
            {
                var f = gif.frames[order[k]];
                int cx = k % cols, cy = k / cols;
                for (int y = 0; y < ch; y++)
                    for (int x = 0; x < cw; x++)
                    {
                        // area average of the source pixels this cell pixel covers (alpha weighted), smooth when shrinking
                        int x0 = x * w / cw, x1 = Mathf.Max(x0 + 1, (x + 1) * w / cw), y0 = y * h / ch, y1 = Mathf.Max(y0 + 1, (y + 1) * h / ch);
                        float r = 0, gg = 0, bb = 0, a = 0; int n = 0;
                        for (int sy = y0; sy < y1; sy++)
                            for (int sx = x0; sx < x1; sx++)
                            {
                                var c = f[sy * w + sx]; float ca = c.a / 255f;
                                r += c.r * ca; gg += c.g * ca; bb += c.b * ca; a += ca; n++;
                            }
                        var o = a > 0 ? new Color32((byte)Mathf.RoundToInt(r / a), (byte)Mathf.RoundToInt(gg / a), (byte)Mathf.RoundToInt(bb / a), (byte)Mathf.RoundToInt(a / n * 255)) : new Color32(0, 0, 0, 0);
                        int ty = (rows - 1 - cy) * ch + (ch - 1 - y);   // texture rows go bottom up, frame 0 at the top left
                        px[ty * W + cx * cw + x] = o;
                    }
            }
            var t = new Texture2D(W, rows * ch, TextureFormat.RGBA32, false);
            t.SetPixels32(px); t.Apply();
            return t;
        }

        static int Gcd(int a, int b) { while (b != 0) { int t = a % b; a = b; b = t; } return a; }

        // ------------------------------------------------------------------ decoder
        public static Gif Decode(byte[] b)
        {
            int p = 0;
            string sig = System.Text.Encoding.ASCII.GetString(b, 0, 6);
            if (sig != "GIF87a" && sig != "GIF89a") throw new System.Exception("not a GIF file");
            p = 6;
            var gif = new Gif { width = b[p] | b[p + 1] << 8, height = b[p + 2] | b[p + 3] << 8 };
            int flags = b[p + 4]; int bgIndex = b[p + 5]; p += 7;
            Color32[] global = null;
            if ((flags & 0x80) != 0) { global = ReadPalette(b, ref p, 2 << (flags & 7)); }
            int W = gif.width, H = gif.height;
            var canvas = new Color32[W * H];
            Color32[] saved = null;
            int delay = 10, transIndex = -1, disposal = 0;
            while (p < b.Length)
            {
                int block = b[p++];
                if (block == 0x3B) break;   // trailer
                if (block == 0x21)
                {
                    int label = b[p++];
                    if (label == 0xF9)
                    {
                        int size = b[p];
                        int pf = b[p + 1];
                        disposal = (pf >> 2) & 7;
                        delay = b[p + 2] | b[p + 3] << 8;
                        transIndex = (pf & 1) != 0 ? b[p + 4] : -1;
                        p += size + 1;
                        SkipSubBlocks(b, ref p);
                    }
                    else SkipSubBlocks(b, ref p);
                    continue;
                }
                if (block != 0x2C) throw new System.Exception("broken GIF (block 0x" + block.ToString("X2") + ")");
                int ix = b[p] | b[p + 1] << 8, iy = b[p + 2] | b[p + 3] << 8, iw = b[p + 4] | b[p + 5] << 8, ih = b[p + 6] | b[p + 7] << 8;
                int iflags = b[p + 8]; p += 9;
                var pal = global;
                if ((iflags & 0x80) != 0) pal = ReadPalette(b, ref p, 2 << (iflags & 7));
                if (pal == null) throw new System.Exception("no colour table");
                bool interlace = (iflags & 0x40) != 0;
                int minCode = b[p++];
                var data = new List<byte>();
                while (true) { int n = b[p++]; if (n == 0) break; for (int k = 0; k < n; k++) data.Add(b[p + k]); p += n; }
                var idx = Lzw(data, minCode, iw * ih);

                if (disposal == 3) saved = (Color32[])canvas.Clone();
                var rowMap = new int[ih];
                if (interlace)
                {
                    int r = 0;
                    foreach (var (start, step) in new[] { (0, 8), (4, 8), (2, 4), (1, 2) })
                        for (int y = start; y < ih; y += step) rowMap[r++] = y;
                }
                else for (int y = 0; y < ih; y++) rowMap[y] = y;
                for (int r = 0; r < ih; r++)
                {
                    int y = iy + rowMap[r]; if (y >= H) continue;
                    for (int x = 0; x < iw; x++)
                    {
                        int cx = ix + x; if (cx >= W) continue;
                        int ci = idx[r * iw + x];
                        if (ci == transIndex || ci >= pal.Length) continue;
                        canvas[y * W + cx] = pal[ci];
                    }
                }
                gif.frames.Add((Color32[])canvas.Clone());
                gif.delays.Add(delay);
                // disposal for the next frame
                if (disposal == 2)
                    for (int y = iy; y < Mathf.Min(H, iy + ih); y++) for (int x = ix; x < Mathf.Min(W, ix + iw); x++) canvas[y * W + x] = new Color32(0, 0, 0, 0);
                else if (disposal == 3 && saved != null) canvas = saved;
                delay = 10; transIndex = -1; disposal = 0;
            }
            if (gif.frames.Count == 0) throw new System.Exception("no frames");
            return gif;
        }

        static Color32[] ReadPalette(byte[] b, ref int p, int n)
        {
            var c = new Color32[n];
            for (int i = 0; i < n; i++) { c[i] = new Color32(b[p], b[p + 1], b[p + 2], 255); p += 3; }
            return c;
        }

        static void SkipSubBlocks(byte[] b, ref int p) { while (p < b.Length) { int n = b[p++]; if (n == 0) break; p += n; } }

        static int[] Lzw(List<byte> data, int minCode, int count)
        {
            var output = new int[count];
            int clear = 1 << minCode, end = clear + 1;
            var prefix = new int[4096]; var suffix = new byte[4096]; var stack = new byte[4097];
            int codeSize = minCode + 1, next = end + 1, old = -1, first = 0, outPos = 0;
            for (int i = 0; i < clear; i++) suffix[i] = (byte)i;
            int bits = 0, buf = 0, dp = 0;
            while (outPos < count)
            {
                while (bits < codeSize) { if (dp >= data.Count) return output; buf |= data[dp++] << bits; bits += 8; }
                int code = buf & ((1 << codeSize) - 1); buf >>= codeSize; bits -= codeSize;
                if (code == clear) { codeSize = minCode + 1; next = end + 1; old = -1; continue; }
                if (code == end) break;
                if (old == -1) { output[outPos++] = suffix[code]; old = code; first = code; continue; }
                int sp = 0, cur = code;
                if (code >= next) { stack[sp++] = (byte)first; cur = old; }
                while (cur >= clear) { stack[sp++] = suffix[cur]; cur = prefix[cur]; }
                first = suffix[cur];
                stack[sp++] = (byte)first;
                while (sp > 0 && outPos < count) output[outPos++] = stack[--sp];
                if (next < 4096) { prefix[next] = old; suffix[next] = (byte)first; next++; if (next == (1 << codeSize) && codeSize < 12) codeSize++; }
                old = code;
            }
            return output;
        }
    }
}
