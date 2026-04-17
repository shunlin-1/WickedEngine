#include "globals.hlsli"

// Output: the 3D heat map texture (R16_FLOAT, 64^3)
// Each voxel stores normalized [0,1] value mapping to the colormap.
// The ENTIRE box gets filled — empty areas use the ambient value.
RWTexture3D<float> output : register(u0);

[numthreads(8, 8, 8)]
void main(uint3 DTid : SV_DispatchThreadID)
{
	const ShaderScene::ShaderHeatmap heatmap = GetScene().heatmap;

	// Skip if no visualizer at all
	if (heatmap.enabled == 0)
	{
		output[DTid] = 0.0;
		return;
	}

	if (DTid.x >= heatmap.resolution || DTid.y >= heatmap.resolution || DTid.z >= heatmap.resolution)
		return;

	// Convert voxel coordinate to LOCAL space [-1, 1]
	float3 uvw = (float3(DTid) + 0.5) / float(heatmap.resolution);
	float3 localPos = uvw * 2.0 - 1.0;

	// Convert to world space to compare against sensor world positions
	float3 worldPos = mul(heatmap.world_matrix, float4(localPos, 1.0)).xyz;

	// Gaussian spread: starts as a tiny dot at the sensor and grows over time.
	// Following the heat diffusion equation: sigma = sqrt(2 * alpha * t).
	// Capped by heatmap.sensor_reach (editor slider) so a single sensor's
	// influence stays localized even after long run-time.
	float sg = min(heatmap.sensor_reach, sqrt(2.0 * heatmap.diffusion_alpha * max(heatmap.elapsed_time, 0.001)));
	sg = max(0.05, sg);
	float s2 = 2.0 * sg * sg;

	// No ambient fill — empty space stays empty. Sensor values blend naturally
	// where they meet, and voxels far from any sensor get totalWeight ~= 0
	// which we collapse to 0 output (PS proximity check makes them transparent).
	float totalWeight = 0.0;
	float weightedSum = 0.0;

	[unroll]
	for (uint s = 0; s < 8; s++)
	{
		if (s >= heatmap.sensor_count) break;

		float3 diff = worldPos - heatmap.sensors[s].xyz;
		float dist2 = dot(diff, diff);
		// pow(gaussian, sharpness): sharpness=1 gives pure Gaussian (soft),
		// sharpness>1 narrows blend zones (sensors hold color with sharper edges),
		// sharpness<1 widens them (very soft, everything blends).
		float w = pow(exp(-dist2 / s2), heatmap.edge_sharpness);

		totalWeight += w;
		weightedSum += w * heatmap.sensors[s].w;
	}

	// Guard: voxels with no sensor nearby stay at 0 (pure "empty" sentinel).
	// Otherwise remap the [0,1] value into [0.02, 1.0] so even a value-0 sensor
	// writes density well above the PS gate threshold (0.005). Without this
	// offset, a low-value sensor's density sits right on top of the threshold
	// and its visible region shrinks asymmetrically vs high-value sensors.
	if (totalWeight > 0.0001)
	{
		float t = saturate(weightedSum / totalWeight);
		output[DTid] = 0.02 + t * 0.98;
	}
	else
	{
		output[DTid] = 0.0;
	}
}
