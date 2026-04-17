#include "globals.hlsli"
#include "heatmap_shared.hlsli"

// Writes a 3D scalar field of normalized sensor values [0,1] mapped
// into [DENSITY_MIN, 1.0] for "sensor-touched" voxels and 0.0 for
// "empty" voxels. The offset lets the PS gate on a simple > DENSITY_GATE
// check to distinguish presence without false-rejecting low-value sensors.
RWTexture3D<float> output : register(u0);

// Floor on Gaussian sigma so sensors remain at least pixel-sized even
// right after a Reset Diffusion Time (avoids a 1-frame invisible blip).
static const float SIGMA_FLOOR = 0.05;

// Minimum totalWeight to count a voxel as "sensor-touched". Below this,
// the voxel is treated as empty. Chosen tiny so the rendered region
// reaches ~3 sigma from the nearest sensor before cutting off.
static const float EMPTY_WEIGHT_THRESHOLD = 0.0001;

[numthreads(8, 8, 8)]
void main(uint3 DTid : SV_DispatchThreadID)
{
	const ShaderScene::ShaderHeatmap heatmap = GetScene().heatmap;

	if (heatmap.enabled == 0)
	{
		output[DTid] = 0.0;
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

	// Weighted-blend of all active sensors using power-weighted Gaussian.
	// edge_sharpness = 1 → pure Gaussian (soft). >1 → narrow blend zones (sensors
	// hold color, sharp territory boundaries). <1 → very soft smear.
	float totalWeight = 0.0;
	float weightedSum = 0.0;
	[unroll]
	for (uint s = 0; s < 8; s++)
	{
		if (s >= heatmap.sensor_count) break;

		float3 diff = worldPos - heatmap.sensors[s].xyz;
		float dist2 = dot(diff, diff);
		float w = pow(exp(-dist2 / s2), heatmap.edge_sharpness);

		totalWeight += w;
		weightedSum += w * heatmap.sensors[s].w;
	}

	// Remap [0, 1] value into [DENSITY_MIN, 1] to keep low-value sensors
	// safely above the PS gate; empty voxels write pure 0.
	if (totalWeight > EMPTY_WEIGHT_THRESHOLD)
	{
		float t = saturate(weightedSum / totalWeight);
		output[DTid] = EncodeDensity(t);
	}
	else
	{
		output[DTid] = 0.0;
	}
}
