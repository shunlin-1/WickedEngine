#include "globals.hlsli"
#include "heatmap_shared.hlsli"

// Heatmap density field compute pass.
//
// For each voxel in the visualizer box, compute a weighted average of the
// normalized sensor values using a power-weighted Gaussian. Sensor reach
// and diffusion control the *extent* of each sensor's influence; edge
// sharpness controls only the *blend* between overlapping sensors (the
// two responsibilities are intentionally decoupled — see WEIGHT split below).
//
// Output encoding (see heatmap_shared.hlsli):
//   sensor-touched voxel → [DENSITY_MIN, 1.0]  (via EncodeDensity)
//   empty voxel          → 0.0                 (sentinel)
// The offset keeps even value-0 sensors safely above the PS gate so low-
// temperature regions render with the same extent as high-temperature ones.
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

	// Weight computation is split so edge_sharpness affects ONLY the blend
	// zone between sensors, NOT how far each sensor reaches:
	//
	//   presenceWeight (raw Gaussian)  → decides "is a sensor near this voxel?"
	//                                    (controls the spread/reach of the field)
	//   blendWeight    (sharpened)     → decides "how much does each sensor
	//                                    contribute to this voxel's color?"
	//                                    (controls boundary sharpness between sensors)
	//
	// Using pow() on the raw Gaussian also scales sigma (mathematically
	// pow(exp(-x), k) == exp(-k·x)), so we'd see sharpness shrink the
	// field extent. Splitting the two responsibilities avoids that coupling.
	float totalPresence = 0.0;  // for emptiness check — independent of sharpness
	float blendTotal    = 0.0;  // denominator for color blend
	float weightedSum   = 0.0;  // numerator for color blend

	[unroll]
	for (uint s = 0; s < 8; s++)
	{
		if (s >= heatmap.sensor_count) break;

		float3 diff = worldPos - heatmap.sensors[s].xyz;
		float dist2 = dot(diff, diff);

		float gauss = exp(-dist2 / s2);
		float sharp = pow(gauss, heatmap.edge_sharpness);

		totalPresence += gauss;
		blendTotal    += sharp;
		weightedSum   += sharp * heatmap.sensors[s].w;
	}

	// Presence uses the raw Gaussian sum so the field extent is driven by
	// diffusion + sensor_reach only. Color comes from the sharpness-weighted
	// average, so edge_sharpness shapes the blend but doesn't shrink the field.
	if (totalPresence > EMPTY_WEIGHT_THRESHOLD)
	{
		float t = saturate(weightedSum / blendTotal);
		output[DTid] = EncodeDensity(t);
	}
	else
	{
		output[DTid] = 0.0;
	}
}
