#include "globals.hlsli"
#include "heatmap_shared.hlsli"

struct VertexToPixel
{
	float4 pos : SV_POSITION;
	float3 worldPos : WORLDPOSITION;
};

// ============================================================
// Samples the two-channel Shepard-weighted density field written by heatmapCS.
//   .r = presence (alpha gate) — sum of raw Gaussians. Linear-filtering-safe.
//   .g = t01      (color)       — edge-sharpened weighted average of sensor values.
// Each voxel has ONE temperature value, computed once per frame in the CS and
// read back here — a true interpolated temperature field "like a real heat map".
// edge_sharpness in the CS controls how strongly the closest sensor dominates
// the color blend; high k → razor Voronoi territories; low k → smooth gradient.
// ============================================================
static const uint  RAY_MAX_STEPS        = 64;
static const float EARLY_OUT_ALPHA      = 0.95;
static const float DISCARD_ALPHA        = 0.001;
static const float DENSITY_STRENGTH_MAX = 30.0;

float3 HeatColormap(float t)
{
	t = saturate(t);
	float3 color;
	if      (t < 0.25) color = lerp(float3(0.30, 0.60, 1.20), float3(0.40, 1.10, 0.80),  t        * 4.0);
	else if (t < 0.50) color = lerp(float3(0.40, 1.10, 0.80), float3(1.20, 1.20, 0.40), (t - 0.25)* 4.0);
	else if (t < 0.75) color = lerp(float3(1.20, 1.20, 0.40), float3(1.40, 0.70, 0.15), (t - 0.50)* 4.0);
	else               color = lerp(float3(1.40, 0.70, 0.15), float3(1.50, 0.20, 0.20), (t - 0.75)* 4.0);
	return color;
}

// Slab-method AABB intersection in the volume's local [-1, 1] space.
bool RayBoxIntersect(float3 ro, float3 rd, out float tNear, out float tFar)
{
	float3 t1 = (-1.0 - ro) / rd;
	float3 t2 = ( 1.0 - ro) / rd;
	float3 tmin = min(t1, t2);
	float3 tmax = max(t1, t2);
	tNear = max(max(tmin.x, tmin.y), tmin.z);
	tFar  = min(min(tmax.x, tmax.y), tmax.z);
	return tNear < tFar && tFar > 0.0;
}

// Closest-sensor distance — used as a proximity gate so that sampler bleed
// through "empty" cells doesn't paint faint fog between far-apart sensors.
float MinDistSqToSensor(float3 worldPos, ShaderScene::ShaderHeatmap hm)
{
	float minDistSq = 1e20;
	for (uint s = 0; s < hm.sensor_count; s++)
	{
		float3 d = worldPos - hm.sensors[s].xyz;
		minDistSq = min(minDistSq, dot(d, d));
	}
	return minDistSq;
}

float4 main(VertexToPixel input) : SV_TARGET
{
	const ShaderScene::ShaderHeatmap heatmap = GetScene().heatmap;

	if (heatmap.enabled == 0 || heatmap.texture_index < 0)
		discard;

	float3 camPos = GetCamera().position;
	float3 rayDirWorld = normalize(input.worldPos - camPos);

	float3 localCamPos = mul(heatmap.world_matrix_inverse, float4(camPos, 1.0)).xyz;
	float3 localRayDir = normalize(mul((float3x3)heatmap.world_matrix_inverse, rayDirWorld));

	float tNear, tFar;
	if (!RayBoxIntersect(localCamPos, localRayDir, tNear, tFar))
		discard;
	tNear = max(tNear, 0.0);

	Texture3D heatmapTex = bindless_textures3D[descriptor_index(heatmap.texture_index)];

	float stepSize = (tFar - tNear) / float(RAY_MAX_STEPS);
	float jitter = frac(sin(dot(input.pos.xy, float2(12.9898, 78.233))) * 43758.5453);

	float densityStrength   = heatmap.density_scale * heatmap.density_scale * DENSITY_STRENGTH_MAX;
	float visibilitySigma2  = heatmap.sensor_reach * heatmap.sensor_reach * 2.0;

	float4 accum = float4(0, 0, 0, 0);

	[loop]
	for (uint i = 0; i < RAY_MAX_STEPS; i++)
	{
		if (accum.a >= EARLY_OUT_ALPHA) break;

		float rayT = tNear + (float(i) + jitter) * stepSize;
		float3 samplePosLocal = localCamPos + localRayDir * rayT;
		float3 uvw = samplePosLocal * 0.5 + 0.5;

		// Two-channel sample: .r = presence (alpha gate), .g = t01 (color).
		// t01 is populated for every voxel in the CS so linear filtering stays
		// within the plausible temperature range — no fake blue halos.
		float2 sample = heatmapTex.SampleLevel(sampler_linear_clamp, uvw, 0).rg;
		float presence = sample.r;
		if (presence <= DENSITY_GATE)
			continue;

		float  t01   = sample.g;
		float3 color = HeatColormap(t01) * heatmap.emissive_power;

		// Proximity-based visibility: empty cells that bled through the sampler
		// stay transparent; cells near a sensor are fully visible.
		float3 samplePosWorld = mul(heatmap.world_matrix, float4(samplePosLocal, 1.0)).xyz;
		float minDistSq = MinDistSqToSensor(samplePosWorld, heatmap);
		float intensity = saturate(exp(-minDistSq / visibilitySigma2));

		float alpha = saturate(intensity * densityStrength * stepSize);

		accum.rgb += (1.0 - accum.a) * color * alpha;
		accum.a   += (1.0 - accum.a) * alpha;
	}

	if (accum.a < DISCARD_ALPHA) discard;

	return accum * heatmap.opacity_scale;
}
