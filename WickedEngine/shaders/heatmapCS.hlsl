#include "globals.hlsli"
#include "heatmap_shared.hlsli"

// Heatmap density field compute pass.
//
// For each voxel in the visualizer box, compute two values:
//   .r = presence — saturate(sum of raw Gaussian weights). Drives the PS gate.
//   .g = t01      — edge-sharpened weighted average of normalized sensor values.
//                   Computed UNCONDITIONALLY (even for low-presence voxels) so
//                   linear filtering between neighbors never blends through a
//                   "cold" fake value and produces blue halos around hot sensors.
//
// See heatmap_shared.hlsli for the rationale.
//
// Sensor reach and diffusion control the *extent* of each sensor's influence;
// edge sharpness controls only the *blend* between overlapping sensors. The
// two responsibilities are intentionally decoupled — see WEIGHT split below.
RWTexture3D<float2> output : register(u0);

// Floor on Gaussian sigma so sensors remain at least pixel-sized even
// right after a Reset Diffusion Time (avoids a 1-frame invisible blip).
static const float SIGMA_FLOOR = 0.05;

[numthreads(8, 8, 8)]
void main(uint3 DTid : SV_DispatchThreadID)
{
	const ShaderScene::ShaderHeatmap heatmap = GetScene().heatmap;

	if (heatmap.enabled == 0 || heatmap.sensor_count == 0)
	{
		output[DTid] = float2(0.0, 0.0);
		return;
	}

	if (DTid.x >= heatmap.resolution || DTid.y >= heatmap.resolution || DTid.z >= heatmap.resolution)
		return;

	// Voxel coordinate → local [-1, 1] → world
	float3 uvw = (float3(DTid) + 0.5) / float(heatmap.resolution);
	float3 localPos = uvw * 2.0 - 1.0;
	float3 worldPos = mul(heatmap.world_matrix, float4(localPos, 1.0)).xyz;

	// Gaussian sigma from heat diffusion equation: sigma = sqrt(2 * alpha * t),
	// capped by sensor_reach so a single sensor's influence stays localized
	// even at long run-time (prevents "every change looks like ambient shift").
	float sg = min(heatmap.sensor_reach, sqrt(2.0 * heatmap.diffusion_alpha * max(heatmap.elapsed_time, 0.001)));
	sg = max(SIGMA_FLOOR, sg);
	float s2 = 2.0 * sg * sg;

	// ==========================================================================
	// Weight split (the subtle part): we need TWO independent things per voxel
	//   (A) presence — raw Gaussian sum, drives the "does this voxel render?" gate
	//   (B) t01      — edge-sharpened weighted average, drives the color
	//
	// Naive approach (OLD): sharp = pow(gauss, edge_sharpness). That under-
	// flows to 0 for far voxels at high sharpness (pow(1e-6, 100) ≈ 10^-540),
	// leaving blendTotal = weightedSum = 0, t01 fallback = 0 → BLUE halo.
	//
	// Fix: compute sharp RELATIVE to the closest sensor using the identity
	//       pow(exp(x), k) == exp(k·x)  ⇒
	//       relSharp[s] = exp(-edge_sharpness * (dist[s]² - dist_min²) / s²)
	// The closest sensor always has relSharp = 1. Others decay smoothly toward 0.
	// Blend ratios are identical to the naive version (a common scale cancels),
	// but now nothing underflows — t01 is meaningful at every voxel, everywhere.
	// ==========================================================================

	// Pass 1: distances + raw Gaussian (for presence), and find closest sensor.
	float dists2[8];
	float totalPresence = 0.0;
	float min_dist2 = 1e20;

	for (uint s = 0; s < 8; s++)
	{
		if (s >= heatmap.sensor_count) break;

		float3 diff = worldPos - heatmap.sensors[s].xyz;
		float d2 = dot(diff, diff);
		dists2[s] = d2;
		min_dist2 = min(min_dist2, d2);
		totalPresence += exp(-d2 / s2);
	}

	// Pass 2: relative sharpened weights for the temperature blend.
	float blendTotal  = 0.0;
	float weightedSum = 0.0;

	// Quadratic response curve so the slider 1→10 covers the full useful range:
	//   k=1  → effective 2  → smooth gradient across overlap
	//   k=5  → effective 50 → tight blend band, each sensor mostly owns its half
	//   k=10 → effective 200 → near-Voronoi, razor-thin yellow seam
	const float effective_k = heatmap.edge_sharpness * heatmap.edge_sharpness * 2.0;

	[unroll]
	for (uint s2_i = 0; s2_i < 8; s2_i++)
	{
		if (s2_i >= heatmap.sensor_count) break;

		// Relative to closest: the closest sensor has relSharp = 1, others decay.
		float relSharp = exp(-effective_k * (dists2[s2_i] - min_dist2) / s2);
		blendTotal  += relSharp;
		weightedSum += relSharp * heatmap.sensors[s2_i].w;
	}

	// blendTotal is guaranteed ≥ 1.0 (closest sensor contributes exp(0) = 1), so
	// this division is always well-conditioned — no NaN, no fallback to blue.
	float presence = saturate(totalPresence);
	float t01      = saturate(weightedSum / blendTotal);

	output[DTid] = float2(presence, t01);
}
