#include "globals.hlsli"

struct VertexToPixel
{
	float4 pos : SV_POSITION;
	float3 worldPos : WORLDPOSITION;
};

// Inferno-like colormap with emissive boost: t in [0,1] -> color
// 0=cool (blue), 0.5=warm (yellow), 1=hot (red)
// The emissive boost makes the fog look self-illuminating instead of flat lit.
float3 HeatColormap(float t)
{
	t = saturate(t);
	float3 color;
	if (t < 0.25)      color = lerp(float3(0.30, 0.60, 1.20), float3(0.40, 1.10, 0.80), t * 4.0);
	else if (t < 0.50) color = lerp(float3(0.40, 1.10, 0.80), float3(1.20, 1.20, 0.40), (t - 0.25) * 4.0);
	else if (t < 0.75) color = lerp(float3(1.20, 1.20, 0.40), float3(1.40, 0.70, 0.15), (t - 0.50) * 4.0);
	else               color = lerp(float3(1.40, 0.70, 0.15), float3(1.50, 0.20, 0.20), (t - 0.75) * 4.0);
	return color;
}

// Ray-box intersection in local space [-1, 1]
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

float4 main(VertexToPixel input) : SV_TARGET
{
	const ShaderScene::ShaderHeatmap heatmap = GetScene().heatmap;

	if (heatmap.enabled == 0 || heatmap.texture_index < 0)
		discard;

	// Build ray in world space
	float3 camPos = GetCamera().position;
	float3 rayDirWorld = normalize(input.worldPos - camPos);

	// === Scene depth (kept for later surface-glow use; not used to clip anymore) ===
	// Previously we stopped ray-marching at the nearest solid surface. That
	// made meshes INSIDE the volume hide the fog behind them — the "emission
	// didn't cover the model" problem. Letting the ray march through the
	// whole volume lets the fog visibly envelop meshes placed inside, which
	// is the "shiny fog on the model" look we want.
	float2 screenUV = input.pos.xy * GetCamera().internal_resolution_rcp;
	float sceneDepth = texture_depth.SampleLevel(sampler_point_clamp, screenUV, 0);
	float3 sceneWorldPos = reconstruct_position(screenUV, sceneDepth);
	float sceneDistance = distance(camPos, sceneWorldPos);

	// Convert ray to local box space [-1, 1]
	float3 localCamPos = mul(heatmap.world_matrix_inverse, float4(camPos, 1.0)).xyz;
	float3 localRayDir = normalize(mul((float3x3)heatmap.world_matrix_inverse, rayDirWorld));

	float tNear, tFar;
	if (!RayBoxIntersect(localCamPos, localRayDir, tNear, tFar))
		discard;
	tNear = max(tNear, 0.0);

	// To convert local-space distance back to world distance, account for the matrix scale.
	// The local ray dir is normalized in local space; we need its length in world space:
	float3 worldStep = mul((float3x3)heatmap.world_matrix, localRayDir);
	float localToWorldScale = length(worldStep);

	// Bindless 3D texture lookup (sample as float4, take .r — engine bindless arrays default to float4)
	Texture3D heatmapTex = bindless_textures3D[descriptor_index(heatmap.texture_index)];

	const uint MAX_STEPS = 64;
	float stepSize = (tFar - tNear) / float(MAX_STEPS);
	float jitter = frac(sin(dot(input.pos.xy, float2(12.9898, 78.233))) * 43758.5453);

	float4 accum = float4(0, 0, 0, 0);

	[loop]
	for (uint i = 0; i < MAX_STEPS; i++)
	{
		if (accum.a >= 0.95) break;

		float t = tNear + (float(i) + jitter) * stepSize;

		// No scene-depth break: we march the full volume so fog envelops meshes
		// placed inside. The scene is rendered first and the fog is composited
		// with alpha, so dense fog dims the mesh (shiny wrap-around look) and
		// thin fog tints it without hiding it.

		float3 samplePosLocal = localCamPos + localRayDir * t;
		float3 uvw = samplePosLocal * 0.5 + 0.5; // [-1,1] -> [0,1] for texture

		float sampledDensity = heatmapTex.SampleLevel(sampler_linear_clamp, uvw, 0).r;

		if (sampledDensity > 0.005)
		{
			// CS writes [0.02, 1.0] for sensor-influenced voxels and 0.0 for empty.
			// Invert the CS's offset so t01 recovers the original [0,1] value.
			float t01 = saturate((sampledDensity - 0.02) / 0.98);
			// HDR emissive boost — color is already HDR (>1 at hot end), this pushes
			// it further into bloom range so the fog feels self-illuminated.
			float3 color = HeatColormap(t01) * heatmap.emissive_power;

			// Visibility = proximity to nearest sensor (kept so empty space is transparent
			// even though the density texture may be non-zero due to sampler bleed).
			float3 samplePosWorld = mul(heatmap.world_matrix, float4(samplePosLocal, 1.0)).xyz;
			float minDistSq = 1e20;
			for (uint s = 0; s < heatmap.sensor_count; s++)
			{
				float3 d = samplePosWorld - heatmap.sensors[s].xyz;
				minDistSq = min(minDistSq, dot(d, d));
			}
			float visibilityRadius = heatmap.sensor_reach;
			float proximity = exp(-minDistSq / (visibilityRadius * visibilityRadius * 2.0));
			float intensity = saturate(proximity);

			// DENSITY = per-step alpha contribution. Squared curve for fine low-end control.
			float densityStrength = heatmap.density_scale * heatmap.density_scale * 30.0;
			float alpha = intensity * densityStrength * stepSize;
			alpha = saturate(alpha);

			accum.rgb += (1.0 - accum.a) * color * alpha;
			accum.a   += (1.0 - accum.a) * alpha;
		}
	}

	if (accum.a < 0.001) discard;

	// OPACITY = final post-multiplier on accumulated fog. Applied to both RGB and A
	// because the accumulation is premultiplied. At 1.0 you see full fog; at 0.3
	// the same fog shape is 30% visible (everything fades uniformly).
	accum *= heatmap.opacity_scale;

	return accum;
}
