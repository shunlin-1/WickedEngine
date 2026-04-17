#include "globals.hlsli"
#include "heatmap_shared.hlsli"

struct VertexToPixel
{
	float4 pos : SV_POSITION;
	float3 worldPos : WORLDPOSITION;
};

// ============================================================
// Tunables — adjust these to change the overall look, not the
// editor-exposed per-visualizer values.
// ============================================================
static const uint  RAY_MAX_STEPS        = 64;
static const float EARLY_OUT_ALPHA      = 0.95;  // stop marching once fog is this opaque
static const float DISCARD_ALPHA        = 0.001; // final pixel-cull threshold
static const float DENSITY_STRENGTH_MAX = 30.0;  // internal multiplier on density_scale^2

// ============================================================
// Inferno-like colormap with HDR tails. t ∈ [0, 1] → RGB.
// The *1.2 / *1.5 values in the top ends push pixel brightness
// over 1.0, which Wicked's tonemap + bloom picks up.
// ============================================================
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

// Fast min-distance from sample to any active sensor in world space.
// Used as a proximity gate so empty-space sampler bleed doesn't render.
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

	// World-space ray from camera through this pixel's cube-face position.
	float3 camPos = GetCamera().position;
	float3 rayDirWorld = normalize(input.worldPos - camPos);

	// Local-space ray for box intersection and texture lookup.
	float3 localCamPos = mul(heatmap.world_matrix_inverse, float4(camPos, 1.0)).xyz;
	float3 localRayDir = normalize(mul((float3x3)heatmap.world_matrix_inverse, rayDirWorld));

	float tNear, tFar;
	if (!RayBoxIntersect(localCamPos, localRayDir, tNear, tFar))
		discard;
	tNear = max(tNear, 0.0);

	Texture3D heatmapTex = bindless_textures3D[descriptor_index(heatmap.texture_index)];

	float stepSize = (tFar - tNear) / float(RAY_MAX_STEPS);
	float jitter = frac(sin(dot(input.pos.xy, float2(12.9898, 78.233))) * 43758.5453);

	// Pre-computed density strength (squared curve for fine control at the low end).
	float densityStrength = heatmap.density_scale * heatmap.density_scale * DENSITY_STRENGTH_MAX;
	float visibilitySigma2 = heatmap.sensor_reach * heatmap.sensor_reach * 2.0;

	float4 accum = float4(0, 0, 0, 0);

	[loop]
	for (uint i = 0; i < RAY_MAX_STEPS; i++)
	{
		if (accum.a >= EARLY_OUT_ALPHA) break;

		float t = tNear + (float(i) + jitter) * stepSize;
		float3 samplePosLocal = localCamPos + localRayDir * t;
		float3 uvw = samplePosLocal * 0.5 + 0.5;

		float encoded = heatmapTex.SampleLevel(sampler_linear_clamp, uvw, 0).r;
		if (encoded <= DENSITY_GATE)
			continue;

		// Decode → colormap → HDR boost
		float  t01   = DecodeDensity(encoded);
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

	// Final opacity multiplier — fades the whole fog uniformly without changing shape.
	return accum * heatmap.opacity_scale;
}
