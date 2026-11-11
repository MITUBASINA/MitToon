// MitToon - NDMF preview: the same crack free tessellation borders as the build, shown in the scene without
// touching the scene objects or assets (works on the preview proxies only).
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Threading.Tasks;
using nadena.dev.ndmf.preview;
using UnityEngine;

namespace MitToon.NDMF
{
    internal class MitToonTessBorderPreview : IRenderFilter
    {
        public ImmutableList<RenderGroup> GetTargetGroups(ComputeContext context)
        {
            var list = new List<RenderGroup>();
            foreach (var root in context.GetAvatarRoots())
            {
                foreach (var r in context.GetComponentsInChildren<Renderer>(root, true))
                {
                    if (!(r is SkinnedMeshRenderer) && !(r is MeshRenderer)) continue;
                    var mats = context.Observe(r, x => x.sharedMaterials, (a, b) => a.SequenceEqual(b));
                    bool tess = false;
                    foreach (var m in mats)
                    {
                        if (m == null) continue;
                        context.Observe(m, x => x.shader);
                        if (MitToonNdmfPlugin.IsTess(m)) tess = true;
                    }
                    if (tess) list.Add(RenderGroup.For(r));
                }
            }
            return list.ToImmutableList();
        }

        public Task<IRenderFilterNode> Instantiate(RenderGroup group, IEnumerable<(Renderer, Renderer)> proxyPairs, ComputeContext context)
        {
            Mesh baked = null;
            foreach (var (original, proxy) in proxyPairs)
            {
                var smr = proxy as SkinnedMeshRenderer;
                var mf = smr == null ? proxy.GetComponent<MeshFilter>() : null;
                var mesh = smr != null ? smr.sharedMesh : mf != null ? mf.sharedMesh : null;
                if (mesh != null) context.Observe(mesh);
                baked = MitToonNdmfPlugin.BuildBorderMesh(mesh, proxy.sharedMaterials, original);
                break;
            }
            return Task.FromResult<IRenderFilterNode>(new Node(baked));
        }

        class Node : IRenderFilterNode
        {
            readonly Mesh mesh;
            public Node(Mesh m) { mesh = m; }

            public RenderAspects WhatChanged => RenderAspects.Mesh;

            public Task<IRenderFilterNode> Refresh(IEnumerable<(Renderer, Renderer)> proxyPairs, ComputeContext context, RenderAspects updatedAspects)
            {
                // a new mesh or new materials upstream: rebuild
                if ((updatedAspects & (RenderAspects.Mesh | RenderAspects.Material)) != 0) return Task.FromResult<IRenderFilterNode>(null);
                return Task.FromResult<IRenderFilterNode>(this);
            }

            public void OnFrame(Renderer original, Renderer proxy)
            {
                if (mesh == null) return;
                if (proxy is SkinnedMeshRenderer smr) smr.sharedMesh = mesh;
                else
                {
                    var mf = proxy.GetComponent<MeshFilter>();
                    if (mf != null) mf.sharedMesh = mesh;
                }
            }

            public void Dispose()
            {
                if (mesh != null) Object.DestroyImmediate(mesh);
            }
        }
    }
}
