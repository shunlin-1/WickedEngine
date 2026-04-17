# Volumetric Visualization System - Implementation Guide

## What You're Building

Two decoupled ECS components + a standalone GPU module:

```
IoTSensorComponent          VolumeVisualizerComponent
(data source)               (rendering volume)
  - sensorValue               - references sensor entities
  - sensorType                - gradientMode (inferno/viridis/cool-warm)
  - position via Transform    - simulationMode (analytical/iterative)
       |                      - 3D density texture(s)
       |                      - ray-march settings
       +----> feeds into ---->+
                              |
                        wiVolumeVis module
                        (compute + render)
```

## File Checklist

Create these NEW files:
- [ ] `WickedEngine/shaders/ShaderInterop_VolumeVis.h` (Step 1)
- [ ] `WickedEngine/shaders/volumeVisHF.hlsli` (Step 2)
- [ ] `WickedEngine/shaders/volumeVisDensityCS.hlsl` (Step 2)
- [ ] `WickedEngine/shaders/volumeVisDiffusionCS.hlsl` (Step 2)
- [ ] `WickedEngine/shaders/volumeVisVS.hlsl` (Step 2)
- [ ] `WickedEngine/shaders/volumeVisPS.hlsl` (Step 2)
- [ ] `WickedEngine/wiVolumeVis.h` (Step 4)
- [ ] `WickedEngine/wiVolumeVis.cpp` (Step 4)
- [ ] `Editor/IoTSensorWindow.h` (Step 6)
- [ ] `Editor/IoTSensorWindow.cpp` (Step 6)
- [ ] `Editor/VolumeVisWindow.h` (Step 6)
- [ ] `Editor/VolumeVisWindow.cpp` (Step 6)

Modify these EXISTING files:
- [ ] `WickedEngine/wiScene_Components.h` (Step 3 - add 2 component structs)
- [ ] `WickedEngine/wiScene.h` (Step 3 - register components)
- [ ] `WickedEngine/wiScene.cpp` (Step 3 - update systems)
- [ ] `WickedEngine/wiScene_Serializers.cpp` (Step 3 - serialization)
- [ ] `WickedEngine/wiRenderPath3D.cpp` (Step 5 - render integration)
- [ ] `WickedEngine/shaders/ShaderInterop.h` (Step 7 - CB slot)
- [ ] `WickedEngine/WickedEngine.h` (Step 7 - include)
- [ ] `Editor/ComponentsWindow.h` (Step 6 - wire windows)
- [ ] `Editor/ComponentsWindow.cpp` (Step 6 - wire windows)
- [ ] Build files: CMakeLists.txt, vcxitems, etc. (Step 7)

## Recommended Build Order

1. ShaderInterop (CPU/GPU shared struct) - foundation everything depends on
2. HLSL Shaders - can compile-test with OfflineShaderCompiler
3. ECS Components - the data layer
4. wiVolumeVis module - the GPU logic
5. RenderPath3D integration - wire compute + render into the pipeline
6. Editor windows - UI for tweaking
7. Build system - make it all compile together

## Reference Files to Study

Before writing each step, read these files as patterns to follow:
- `WickedEngine/shaders/ShaderInterop_Ocean.h` - ShaderInterop pattern
- `WickedEngine/wiOcean.h` + `wiOcean.cpp` - standalone module pattern
- `WickedEngine/wiScene_Components.h` lines 1819-1902 - WeatherComponent (complex component example)
- `WickedEngine/wiScene.h` lines 29-68 - component registration
- `WickedEngine/wiScene.cpp` - RunLightUpdateSystem (update system pattern)
- `WickedEngine/wiRenderPath3D.cpp` lines 2062-2237 - transparent render pass
- `Editor/VoxelGridWindow.h/.cpp` - simple editor window pattern
- `WickedEngine/shaders/cube.hlsli` - the 36-vertex unit cube you'll rasterize
