# Step 4: Standalone Module (wiVolumeVis)

Create `WickedEngine/wiVolumeVis.h` and `WickedEngine/wiVolumeVis.cpp`.
This is the GPU-side logic that drives the compute and render passes.

**Primary reference**: Read `wiOcean.h` and `wiOcean.cpp` — your module follows the
exact same structure but is simpler (no FFT, no index buffers, no readback).

---

## 4a. `WickedEngine/wiVolumeVis.h`

```cpp
#pragma once
#include "CommonInclude.h"
#include "wiGraphicsDevice.h"
#include "wiScene_Decl.h"

namespace wi::volumevis
{
    void Initialize();

    // Compute pass: updates the 3D density texture
    void UpdateDensityField(
        wi::scene::VolumeVisualizerComponent& vis,
        wi::graphics::CommandList cmd
    );

    // Render pass: rasterizes the volume box and ray-marches
    void Render(
        const wi::scene::VolumeVisualizerComponent& vis,
        const wi::scene::TransformComponent& transform,
        wi::graphics::CommandList cmd
    );
}
```

---

## 4b. `WickedEngine/wiVolumeVis.cpp`

### Includes

```cpp
#include "wiVolumeVis.h"
#include "wiRenderer.h"
#include "wiScene.h"
#include "wiEventHandler.h"
#include "wiTimer.h"
#include "shaders/ShaderInterop_VolumeVis.h"

using namespace wi::graphics;
using namespace wi::scene;
```

### Internal Namespace (shader objects + PSO)

```cpp
namespace wi::volumevis
{
    namespace volumevis_internal
    {
        // Shaders:
        Shader densityCS;       // analytical mode compute
        Shader diffusionCS;     // iterative mode compute
        Shader volumeVisVS;     // vertex shader (cube rasterization)
        Shader volumeVisPS;     // pixel shader (ray-march)

        // Render states:
        RasterizerState rasterizerState;
        DepthStencilState depthStencilState;
        BlendState blendState;

        // Pipeline state:
        PipelineState PSO;

        void LoadShaders()
        {
            // TODO: Load all 4 shaders
            // Pattern from wiOcean.cpp:
            //   wi::renderer::LoadShader(ShaderStage::CS, densityCS, "volumeVisDensityCS.cso");
            //   wi::renderer::LoadShader(ShaderStage::CS, diffusionCS, "volumeVisDiffusionCS.cso");
            //   wi::renderer::LoadShader(ShaderStage::VS, volumeVisVS, "volumeVisVS.cso");
            //   wi::renderer::LoadShader(ShaderStage::PS, volumeVisPS, "volumeVisPS.cso");

            // TODO: Create PipelineState (VS + PS + render states)
            // Pattern:
            //   GraphicsDevice* device = wi::graphics::GetDevice();
            //   PipelineStateDesc desc;
            //   desc.vs = &volumeVisVS;
            //   desc.ps = &volumeVisPS;
            //   desc.bs = &blendState;
            //   desc.rs = &rasterizerState;
            //   desc.dss = &depthStencilState;
            //   device->CreatePipelineState(&desc, &PSO);
        }
    }
    using namespace volumevis_internal;
```

### Initialize()

```cpp
    void Initialize()
    {
        wi::Timer timer;

        // TODO: Set up rasterizer state
        // KEY: cull FRONT faces (not back!)
        // This is the volume rendering trick - when camera is INSIDE the box,
        // the front faces are behind you, but back faces are visible.
        // Culling front faces ensures the PS fires from inside the volume.
        //
        //   RasterizerState ras_desc;
        //   ras_desc.fill_mode = FillMode::SOLID;
        //   ras_desc.cull_mode = CullMode::FRONT;    // <-- FRONT, not BACK!
        //   ras_desc.front_counter_clockwise = true;
        //   ras_desc.depth_clip_enable = true;
        //   rasterizerState = ras_desc;

        // TODO: Set up depth stencil state
        // Depth TEST enabled (so volume is occluded by solid objects)
        // Depth WRITE disabled (volume is transparent, shouldn't block other things)
        //
        //   DepthStencilState depth_desc;
        //   depth_desc.depth_enable = true;
        //   depth_desc.depth_write_mask = DepthWriteMask::ZERO;  // <-- no write!
        //   depth_desc.depth_func = ComparisonFunc::GREATER;     // reversed-Z in Wicked
        //   depthStencilState = depth_desc;

        // TODO: Set up blend state (alpha blending for transparency)
        //   BlendState blend_desc;
        //   blend_desc.render_target[0].blend_enable = true;
        //   blend_desc.render_target[0].src_blend = Blend::SRC_ALPHA;
        //   blend_desc.render_target[0].dest_blend = Blend::INV_SRC_ALPHA;
        //   blend_desc.render_target[0].blend_op = BlendOp::ADD;
        //   blend_desc.render_target[0].src_blend_alpha = Blend::ONE;
        //   blend_desc.render_target[0].dest_blend_alpha = Blend::ZERO;
        //   blend_desc.render_target[0].blend_op_alpha = BlendOp::ADD;
        //   blend_desc.render_target[0].render_target_write_mask = ColorWrite::ENABLE_ALL;
        //   blendState = blend_desc;

        // Subscribe to shader reload event (hot-reload support):
        //   wi::eventhandler::Subscribe_Internal(wi::eventhandler::EVENT_RELOAD_SHADERS, [](uint64_t) {
        //       LoadShaders();
        //   });

        // Load shaders:
        //   LoadShaders();

        // Log initialization time:
        //   wi::backlog::post("wi::volumevis initialized (" + std::to_string((int)std::round(timer.elapsed())) + " ms)");
    }
```

### UpdateDensityField()

This is the compute dispatch. The most critical GPU code.

```cpp
    void UpdateDensityField(VolumeVisualizerComponent& vis, CommandList cmd)
    {
        if (!vis.gpuResourcesCreated || !vis.IsEnabled()) return;

        GraphicsDevice* device = wi::graphics::GetDevice();
        device->EventBegin("VolumeVis Density Update", cmd);

        // TODO: Fill the constant buffer with current data
        //
        // VolumeVisCB cb = {};
        // cb.xVolumeVisSourcePosition = vis.sensorPositionLocal;  // float3
        // cb.xVolumeVisSourceValue = vis.currentSensorValue;
        // cb.xVolumeVisAmbientValue = vis.ambientValue;
        // cb.xVolumeVisDiffusionAlpha = vis.diffusionAlpha;
        // cb.xVolumeVisElapsedTime = vis.elapsedTime;
        // cb.xVolumeVisDeltaTime = /* get from scene dt or pass as param */;
        // cb.xVolumeVisDensityResolution = vis.densityResolution;
        // ... fill all fields

        // TODO: Update constant buffer (barrier pattern from wiOcean):
        //
        // device->Barrier(GPUBarrier::Buffer(&vis.constantBuffer,
        //     ResourceState::CONSTANT_BUFFER, ResourceState::COPY_DST), cmd);
        // device->UpdateBuffer(&vis.constantBuffer, &cb, cmd);
        // device->Barrier(GPUBarrier::Buffer(&vis.constantBuffer,
        //     ResourceState::COPY_DST, ResourceState::CONSTANT_BUFFER), cmd);

        // TODO: Bind constant buffer
        //   device->BindConstantBuffer(&vis.constantBuffer, CB_GETBINDSLOT(VolumeVisCB), cmd);

        // TODO: Choose compute shader based on simulation mode
        if (vis.simulationMode == VolumeVisualizerComponent::SimulationMode::ANALYTICAL)
        {
            // Analytical: just write to texture[0]
            //
            // Transition texture to UAV:
            //   device->Barrier(GPUBarrier::Image(&vis.densityTexture[0],
            //       vis.densityTexture[0].desc.layout, ResourceState::UNORDERED_ACCESS), cmd);
            //
            // Bind and dispatch:
            //   device->BindComputeShader(&densityCS, cmd);
            //   device->BindUAV(&vis.densityTexture[0], 0, cmd);
            //
            //   uint32_t groups = (vis.densityResolution + VOLUMEVIS_DENSITY_TILESIZE - 1) / VOLUMEVIS_DENSITY_TILESIZE;
            //   device->Dispatch(groups, groups, groups, cmd);  // 3D dispatch!
            //
            // Transition back to shader resource:
            //   device->Barrier(GPUBarrier::Image(&vis.densityTexture[0],
            //       ResourceState::UNORDERED_ACCESS, vis.densityTexture[0].desc.layout), cmd);
        }
        else // ITERATIVE
        {
            // Iterative: read from texture[pingPongIndex], write to texture[1-pingPongIndex]
            //
            // uint readIdx = vis.pingPongIndex;
            // uint writeIdx = 1 - vis.pingPongIndex;
            //
            // Transition both textures:
            //   GPUBarrier barriers[] = {
            //       GPUBarrier::Image(&vis.densityTexture[readIdx],
            //           vis.densityTexture[readIdx].desc.layout, ResourceState::SHADER_RESOURCE_COMPUTE),
            //       GPUBarrier::Image(&vis.densityTexture[writeIdx],
            //           vis.densityTexture[writeIdx].desc.layout, ResourceState::UNORDERED_ACCESS),
            //   };
            //   device->Barrier(barriers, arraysize(barriers), cmd);
            //
            // Bind and dispatch:
            //   device->BindComputeShader(&diffusionCS, cmd);
            //   device->BindResource(&vis.densityTexture[readIdx], 0, cmd);  // SRV t0
            //   device->BindUAV(&vis.densityTexture[writeIdx], 0, cmd);      // UAV u0
            //
            //   uint32_t groups = (vis.densityResolution + VOLUMEVIS_DENSITY_TILESIZE - 1) / VOLUMEVIS_DENSITY_TILESIZE;
            //   device->Dispatch(groups, groups, groups, cmd);
            //
            // Transition both back:
            //   barriers[0] = GPUBarrier::Image(&vis.densityTexture[readIdx],
            //       ResourceState::SHADER_RESOURCE_COMPUTE, vis.densityTexture[readIdx].desc.layout);
            //   barriers[1] = GPUBarrier::Image(&vis.densityTexture[writeIdx],
            //       ResourceState::UNORDERED_ACCESS, vis.densityTexture[writeIdx].desc.layout);
            //   device->Barrier(barriers, arraysize(barriers), cmd);
            //
            // Flip ping-pong:
            //   vis.pingPongIndex = writeIdx;
        }

        device->EventEnd(cmd);
    }
```

### Render()

```cpp
    void Render(const VolumeVisualizerComponent& vis, const TransformComponent& transform, CommandList cmd)
    {
        if (!vis.gpuResourcesCreated || !vis.IsEnabled()) return;

        GraphicsDevice* device = wi::graphics::GetDevice();
        device->EventBegin("VolumeVis Render", cmd);

        // TODO: Bind the pipeline state
        //   device->BindPipelineState(&PSO, cmd);

        // TODO: Bind constant buffer (already updated in UpdateDensityField)
        //   device->BindConstantBuffer(&vis.constantBuffer, CB_GETBINDSLOT(VolumeVisCB), cmd);

        // TODO: Bind the current density texture as SRV
        // For analytical mode: always texture[0]
        // For iterative mode: texture[pingPongIndex] (the one just written)
        //   uint texIdx = (vis.simulationMode == VolumeVisualizerComponent::SimulationMode::ITERATIVE)
        //       ? vis.pingPongIndex : 0;
        //   device->BindResource(&vis.densityTexture[texIdx], 0, cmd);

        // TODO: Draw the cube (36 vertices from cube.hlsli)
        //   device->Draw(36, 0, cmd);

        device->EventEnd(cmd);
    }

} // namespace wi::volumevis
```

### GPU Resource Creation

Add a helper function (or put it in the update system) for creating the 3D textures
and constant buffer:

```cpp
// Call this once when GPU resources are needed:
void CreateGPUResources(VolumeVisualizerComponent& vis)
{
    GraphicsDevice* device = wi::graphics::GetDevice();
    uint32_t res = vis.densityResolution;

    // Create 3D density texture(s):
    TextureDesc desc;
    desc.type = TextureDesc::Type::TEXTURE_3D;  // KEY: 3D texture!
    desc.width = res;
    desc.height = res;
    desc.depth = res;
    desc.mip_levels = 1;
    desc.format = Format::R16_FLOAT;   // single channel, 16-bit precision
    desc.bind_flags = BindFlag::SHADER_RESOURCE | BindFlag::UNORDERED_ACCESS;
    desc.layout = ResourceState::SHADER_RESOURCE_COMPUTE;

    device->CreateTexture(&desc, nullptr, &vis.densityTexture[0]);
    device->SetName(&vis.densityTexture[0], "VolumeVis_Density0");

    // Second texture only needed for iterative (ping-pong) mode:
    device->CreateTexture(&desc, nullptr, &vis.densityTexture[1]);
    device->SetName(&vis.densityTexture[1], "VolumeVis_Density1");

    // Create constant buffer:
    GPUBufferDesc buf_desc;
    buf_desc.size = sizeof(VolumeVisCB);
    buf_desc.usage = Usage::DEFAULT;
    buf_desc.bind_flags = BindFlag::CONSTANT_BUFFER;
    device->CreateBuffer(&buf_desc, nullptr, &vis.constantBuffer);
    device->SetName(&vis.constantBuffer, "VolumeVis_CB");

    vis.gpuResourcesCreated = true;
}
```

**Memory cost at different resolutions:**
- 32^3 x 2 bytes x 2 textures = 64 KB
- 64^3 x 2 bytes x 2 textures = 1 MB
- 128^3 x 2 bytes x 2 textures = 8 MB

## Key Patterns to Remember

1. **Barrier sandwich for CB update**: CONSTANT_BUFFER -> COPY_DST -> update -> COPY_DST -> CONSTANT_BUFFER
2. **Image barriers for textures**: layout -> UNORDERED_ACCESS (before compute) -> layout (after compute)
3. **3D dispatch**: `Dispatch(groups, groups, groups, cmd)` — three dimensions!
4. **desc.layout**: Set to `SHADER_RESOURCE_COMPUTE` — this is the "home" state the texture returns to
5. **Cull FRONT faces**: The most important render state choice. Without this, camera inside volume = invisible.
6. **Reversed-Z depth**: Wicked Engine uses reversed-Z, so depth comparison is GREATER, not LESS.
