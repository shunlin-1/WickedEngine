# Step 1: ShaderInterop_VolumeVis.h

## File to create
`WickedEngine/shaders/ShaderInterop_VolumeVis.h`

## What this file does
Defines the CPU/GPU shared constant buffer struct. Both C++ code and HLSL shaders
include this file, so it must compile in both languages.

## Pattern to follow
Read `WickedEngine/shaders/ShaderInterop_Ocean.h` - it's only 34 lines.

## Structure

```
#ifndef WI_SHADERINTEROP_VOLUMEVIS_H
#define WI_SHADERINTEROP_VOLUMEVIS_H
#include "ShaderInterop.h"

// Compute shader thread group size for 3D dispatch
static const uint VOLUMEVIS_DENSITY_TILESIZE = 4;  // 4x4x4 = 64 threads per group

// The constant buffer - must be 16-byte aligned (the CBUFFER macro handles this)
CBUFFER(VolumeVisCB, CBSLOT_OTHER_VOLUMEVIS)
{
    // --- You fill in the fields ---
};

#endif
```

## Fields you need in VolumeVisCB

Think about what both the compute shader and the pixel shader need:

**For the compute shader (density field generation):**
- Source position in local space (float3) - where the IoT sensor is
- Source value (float) - the sensor reading (e.g., temperature)
- Ambient value (float) - the baseline (e.g., room temperature)
- Diffusion alpha (float) - thermal diffusivity coefficient
- Elapsed time (float) - for analytical mode Gaussian spread
- Delta time (float) - for iterative mode per-frame step
- Density resolution (uint) - 3D texture dimension (e.g., 64)
- Simulation mode (uint) - 0=analytical, 1=iterative

**For the pixel shader (ray-marching):**
- World matrix (float4x4) - transforms unit cube to world space
- Inverse world matrix (float4x4) - transforms world ray into local space
- Max ray steps (uint) - controls quality vs performance
- Step size (float) - ray march increment
- Opacity scale (float) - controls volume density appearance
- Gradient mode (uint) - which colormap to use (0=inferno, 1=viridis, etc.)
- Value range min/max (float, float) - for normalizing sensor values

**Alignment rules:**
- float4x4 = 64 bytes, must be first or aligned to 16-byte boundary
- float3 takes 12 bytes but occupies 16 in HLSL (pack a float after it)
- uint fields can be grouped in uint4 packs
- Total struct size must be multiple of 16 bytes
- Add padding fields if needed (name them `xVolumeVis_padding0` etc.)

## CB Slot Registration

You also need to add the slot to `WickedEngine/shaders/ShaderInterop.h`.

Find the "On demand buffers" section (~line 95-111) and add:

```c
// Non-PS5 section (~line 106):
#define CBSLOT_OTHER_VOLUMEVIS    3

// PS5 section (~line 133):
#define CBSLOT_OTHER_VOLUMEVIS    4
```

Slot 3/4 is the shared "on demand" range. Safe because your shaders never
dispatch concurrently with ocean/volumetric light shaders.

## Tips
- Use the `xVolumeVis` prefix for all fields (engine naming convention)
- Look at how OceanCB names everything with `xOcean` prefix
- The CBUFFER macro generates both a C++ struct and an HLSL cbuffer declaration
- CB_GETBINDSLOT(VolumeVisCB) gives you the slot number in C++ code
