# Step 2: HLSL Shaders

## Files to create (5 total)

### 2a. `WickedEngine/shaders/volumeVisHF.hlsli` - Shared Header

Shared between VS and PS. Contains:

```hlsl
#ifndef WI_VOLUMEVIS_HF
#define WI_VOLUMEVIS_HF
#include "ShaderInterop_VolumeVis.h"

// Vertex shader output / Pixel shader input
struct VertexToPixel
{
    float4 pos : SV_POSITION;
    float3 worldPos : WORLDPOSITION;
};

// Ray-box intersection in local space [-1,1]^3
// Returns true if ray hits, sets tNear/tFar to entry/exit distances
// This is the same algorithm as your GLSL boxHit() but returns bool
bool RayBoxIntersect(float3 ro, float3 rd, out float tNear, out float tFar)
{
    // TODO: implement
    // Hint: compute t1 = (-1 - ro) / rd, t2 = (1 - ro) / rd
    //       tNear = max of all min(t1,t2) components
    //       tFar  = min of all max(t1,t2) components
    //       return tNear < tFar && tFar > 0
}

// Gradient colormaps - return float3 color for normalized value t in [0,1]
//
// You need at least these:
//   InfernoColormap(t)  - black->purple->red->orange->yellow->white (heat)
//   ViridisColormap(t)  - purple->blue->teal->green->yellow (general scientific)
//   CoolWarmColormap(t) - blue->white->red (diverging, good for +/- values)
//
// Your GLSL prototype has the inferno implementation with 5 breakpoints.
// Port it to HLSL (mix -> lerp, clamp -> saturate/clamp, vec3 -> float3).
//
// Then create a dispatcher that uses the gradient_mode from the CB:
float3 ApplyGradient(float t, uint gradientMode)
{
    // TODO: switch on gradientMode and call the right colormap
}

#endif // WI_VOLUMEVIS_HF
```

### 2b. `WickedEngine/shaders/volumeVisDensityCS.hlsl` - Analytical Mode Compute

This is the STATELESS mode. Recomputes the entire density field each frame from formula.

```hlsl
#include "ShaderInterop_VolumeVis.h"

// Output: the 3D density texture
RWTexture3D<float> densityTexture : register(u0);

[numthreads(VOLUMEVIS_DENSITY_TILESIZE, VOLUMEVIS_DENSITY_TILESIZE, VOLUMEVIS_DENSITY_TILESIZE)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    // TODO: implement
    //
    // 1. Convert DTid to normalized [0,1] UVW:
    //    float3 uvw = (float3(DTid) + 0.5) / xVolumeVisDensityResolution;
    //
    // 2. Convert to local space [-1,1]:
    //    float3 localPos = uvw * 2.0 - 1.0;
    //
    // 3. Compute distance from source:
    //    float3 diff = localPos - xVolumeVisSourcePosition;
    //    float dist2 = dot(diff, diff);
    //
    // 4. Gaussian diffusion (from your GLSL prototype):
    //    float sg = sqrt(2.0 * xVolumeVisDiffusionAlpha * max(xVolumeVisElapsedTime, 0.001));
    //    float density = exp(-dist2 / (2.0 * sg * sg));
    //
    // 5. Map to normalized value [0,1]:
    //    float range = xVolumeVisSourceValue - xVolumeVisAmbientValue;
    //    float t = saturate(density * sign(range));
    //    // (sign handles case where source < ambient, e.g., cold source)
    //
    // 6. Write to 3D texture:
    //    densityTexture[DTid] = t;
}
```

### 2c. `WickedEngine/shaders/volumeVisDiffusionCS.hlsl` - Iterative Mode Compute

This is the STATEFUL mode. Reads previous frame, applies heat equation, writes new frame.

```hlsl
#include "ShaderInterop_VolumeVis.h"

// Previous frame's density (read-only)
Texture3D<float> prevDensity : register(t0);

// New frame's density (write)
RWTexture3D<float> nextDensity : register(u0);

[numthreads(VOLUMEVIS_DENSITY_TILESIZE, VOLUMEVIS_DENSITY_TILESIZE, VOLUMEVIS_DENSITY_TILESIZE)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    // TODO: implement the 3D heat equation
    //
    // 1. Boundary check:
    //    uint res = xVolumeVisDensityResolution;
    //    if (DTid.x >= res || DTid.y >= res || DTid.z >= res) return;
    //
    // 2. Read the 6 neighbors + center (3D Laplacian):
    //    float center = prevDensity[DTid];
    //    float xp = prevDensity[min(DTid + uint3(1,0,0), res-1)];
    //    float xn = prevDensity[max(DTid - uint3(1,0,0), 0)];  // careful with uint underflow!
    //    float yp = prevDensity[min(DTid + uint3(0,1,0), res-1)];
    //    float yn = prevDensity[max(DTid - uint3(0,1,0), 0)];
    //    float zp = prevDensity[min(DTid + uint3(0,0,1), res-1)];
    //    float zn = prevDensity[max(DTid - uint3(0,0,1), 0)];
    //
    // 3. Compute discrete Laplacian:
    //    float laplacian = (xp + xn + yp + yn + zp + zn - 6.0 * center);
    //
    // 4. Apply heat equation: T_new = T_old + alpha * dt * laplacian
    //    float newVal = center + xVolumeVisDiffusionAlpha * xVolumeVisDeltaTime * laplacian;
    //
    // 5. Inject source: if this voxel is near the source position, set it to source value
    //    float3 uvw = (float3(DTid) + 0.5) / res;
    //    float3 localPos = uvw * 2.0 - 1.0;
    //    float3 diff = localPos - xVolumeVisSourcePosition;
    //    float dist = length(diff);
    //    if (dist < 2.0 / res)  // within ~1 voxel of source
    //    {
    //        float range = abs(xVolumeVisSourceValue - xVolumeVisAmbientValue);
    //        newVal = saturate((xVolumeVisSourceValue - xVolumeVisAmbientValue) / max(range, 0.001));
    //    }
    //
    // 6. Clamp and write:
    //    nextDensity[DTid] = saturate(newVal);
}
```

**Key difference from analytical mode:**
- Analytical: stateless, writes everything from formula
- Iterative: reads prev texture, computes physics step, writes new texture
- The ping-pong (prev/next swap) happens on the C++ side

### 2d. `WickedEngine/shaders/volumeVisVS.hlsl` - Vertex Shader

Rasterizes a unit cube transformed to world space.

```hlsl
#include "volumeVisHF.hlsli"
#include "globals.hlsli"  // for GetCamera()
#include "cube.hlsli"     // the 36-vertex unit cube in [-1,1]^3

VertexToPixel main(uint vertexID : SV_VERTEXID)
{
    VertexToPixel Out;

    // TODO: implement
    // 1. Get the cube vertex:       float4 localPos = CUBE[vertexID];
    // 2. Transform to world space:  float4 worldPos = mul(xVolumeVisWorldMatrix, localPos);
    // 3. Project to screen:         Out.pos = mul(GetCamera().view_projection, worldPos);
    // 4. Pass world position:       Out.worldPos = worldPos.xyz;

    return Out;
}
```

### 2e. `WickedEngine/shaders/volumeVisPS.hlsl` - Pixel Shader (Ray-March)

The main visualization shader. Marches a ray through the volume, samples the 3D density
texture, applies the colormap, and composites front-to-back.

```hlsl
#include "volumeVisHF.hlsli"
#include "globals.hlsli"   // for GetCamera()

// The 3D density texture generated by the compute shader
Texture3D<float> densityTexture : register(t0);
SamplerState sampler_linear_clamp : register(s0);  // already defined in globals

float4 main(VertexToPixel input) : SV_TARGET
{
    // TODO: implement ray-marching
    //
    // 1. Construct ray from camera through this pixel:
    //    float3 camPos = GetCamera().position;
    //    float3 rayDir = normalize(input.worldPos - camPos);
    //
    // 2. Transform ray into local box space [-1,1]^3:
    //    float3 localCamPos = mul(xVolumeVisWorldMatrixInverse, float4(camPos, 1.0)).xyz;
    //    float3 localRayDir = normalize(mul((float3x3)xVolumeVisWorldMatrixInverse, rayDir));
    //
    // 3. Ray-box intersection:
    //    float tNear, tFar;
    //    if (!RayBoxIntersect(localCamPos, localRayDir, tNear, tFar))
    //        discard;
    //    tNear = max(tNear, 0.0);  // clamp to camera (when inside the box)
    //
    // 4. Ray-march loop (front-to-back compositing):
    //    float stepSize = (tFar - tNear) / float(xVolumeVisMaxRaySteps);
    //    float4 accum = float4(0, 0, 0, 0);
    //
    //    for (uint i = 0; i < xVolumeVisMaxRaySteps; i++)
    //    {
    //        if (accum.a >= 0.99) break;  // early termination
    //
    //        float t = tNear + (float(i) + 0.5) * stepSize;
    //        float3 samplePos = localCamPos + localRayDir * t;
    //
    //        // Convert local [-1,1] to UVW [0,1] for texture sampling:
    //        float3 uvw = samplePos * 0.5 + 0.5;
    //
    //        // Sample density (trilinear filtered):
    //        float density = densityTexture.SampleLevel(sampler_linear_clamp, uvw, 0);
    //
    //        // Apply colormap:
    //        float3 color = ApplyGradient(density, xVolumeVisGradientMode);
    //
    //        // Compute opacity for this step:
    //        float alpha = density * xVolumeVisOpacityScale * stepSize;
    //
    //        // Front-to-back compositing:
    //        accum.rgb += (1.0 - accum.a) * color * alpha;
    //        accum.a   += (1.0 - accum.a) * alpha;
    //    }
    //
    //    return float4(accum.rgb, accum.a);
}
```

## Tips

- **sampler_linear_clamp** is already bound by the engine via globals.hlsli. Check
  `globals.hlsli` for the exact sampler name — it might be `sampler_linear_clamp`
  or accessed differently. Search for `SamplerState` in globals.hlsli.
- The **cube.hlsli** has 36 vertices (12 triangles, 6 faces). `Draw(36, 0, cmd)` renders it.
- **Jittered start**: For better quality, add a small random offset to `tNear` based on
  screen position. This reduces banding artifacts. Optional for first pass.
- Your GLSL prototype's `gri()` function is essentially what the ray-march loop does,
  but discretized as a step-by-step march instead of a closed-form integral.
