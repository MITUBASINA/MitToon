using UnityEditor;
using UnityEngine;
using VRC.Dynamics;
using VRC.SDK3.Dynamics.Constraint.Components;

namespace MitToon.VRC
{
    // "Lock rotation" of the shadow light: the pivot above the followed bone keeps the world rotation it has when the
    // avatar loads (VRC Rotation Constraint, Freeze To World), so the light direction stays fixed in the world while it
    // still moves along with the avatar.
    [InitializeOnLoad]
    static class MitToonShadowLightRotationLock
    {
        static MitToonShadowLightRotationLock()
        {
            MitToon.Editor.MitToonShadowLight.AddRotationLock = (pivot, root) =>
            {
                var c = Undo.AddComponent<VRCRotationConstraint>(pivot.gameObject);
                c.Sources.Add(new VRCConstraintSource(root, 1f, Vector3.zero, Vector3.zero));   // = avatar facing until frozen
                c.SolveInLocalSpace = false;
                c.FreezeToWorld = true;
                c.Locked = true;
                c.IsActive = true;
            };
            MitToon.Editor.MitToonShadowLight.HasRotationLock = pivot =>
            {
                var c = pivot.GetComponent<VRCRotationConstraint>();
                return c != null && c.FreezeToWorld && c.IsActive;
            };
        }
    }
}
