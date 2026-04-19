#ifndef WI_DISSOLVE_SHARED_HLSLI
#define WI_DISSOLVE_SHARED_HLSLI

// ============================================================================
// Dissolve (X-ray / section-cut) — shared math for the object shaders.
//
// The active cut plane lives in frame.scene.dissolve, populated by
// wi::renderer::UpdateDissolveFrameCB from the first enabled
// DissolvePlaneComponent in the scene + its TransformComponent:
//
//   plane.xyz = world-space unit normal (entity's rotated local +Y axis)
//   plane.w   = signed offset (−dot(normal, entity.position))
//
// Plane equation:  dot(worldPos, plane.xyz) + plane.w
//   < 0  → solid side    (no fade)
//   = 0  → on the plane
//   > 0  → fade side     (alpha ramps to 0 across edge_width world units)
//
// When no plane is active (`enabled = 0`), the function returns 1.0 → zero
// cost, zero visual effect. Per-material opt-in via the DISSOLVE flag.
// ============================================================================

half DissolveAlpha(float3 worldPos)
{
	if (GetFrame().scene.dissolve.enabled == 0)
		return (half)1.0;

	const float4 plane = GetFrame().scene.dissolve.plane;
	const float  edge  = GetFrame().scene.dissolve.edge_width;
	const float  signedDist = dot(worldPos, plane.xyz) + plane.w;
	// smoothstep(0, edge, signedDist) ramps 0 → 1 as the sample crosses above
	// the plane. Invert so "below / on the solid side = 1 (solid)".
	return (half)(1.0 - smoothstep(0.0, edge, signedDist));
}

// For shadow shaders — clips the pixel when the active dissolve plane is in
// pass-light mode AND the surface is past the fade band.
//
// The threshold is SIGNED-DISTANCE-based (not alpha-based) with a safety
// margin: we only drop the shadow once the pixel is clearly on the "faded"
// side of the plane by more than one edge-width. That gives the atlas a
// stable boundary so sub-pixel camera jitter between frames doesn't flip
// the clip on and off — no more flicker at the cut line.
void ClipShadowForDissolve(float3 worldPos)
{
	if (GetFrame().scene.dissolve.enabled == 0 || GetFrame().scene.dissolve.pass_light == 0)
		return;

	const float4 plane = GetFrame().scene.dissolve.plane;
	const float  edge  = GetFrame().scene.dissolve.edge_width;
	const float  signedDist = dot(worldPos, plane.xyz) + plane.w;
	// Clip once the pixel is fully past the edge band (one edge-width above
	// the plane). Pixels inside the fade band keep casting — they're still
	// visible in the forward pass, so their shadow should remain too.
	if (signedDist > edge)
		clip(-1);
}

#endif // WI_DISSOLVE_SHARED_HLSLI
