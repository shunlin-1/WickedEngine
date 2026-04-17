# Step 3: ECS Components

You're adding TWO components and modifying 4 files.

---

## 3a. IoTSensorComponent

### Add to `WickedEngine/wiScene_Components.h`

Place after the last component struct (before the closing namespace brace).
Follow the WeatherComponent/SoundComponent pattern.

```cpp
struct IoTSensorComponent
{
    enum FLAGS
    {
        EMPTY = 0,
        ENABLED = 1 << 0,
    };
    uint32_t _flags = ENABLED;

    // What kind of data this sensor provides:
    enum class SensorType : uint32_t
    {
        TEMPERATURE = 0,    // degrees Celsius
        HUMIDITY = 1,       // percentage 0-100
        CROWD_DENSITY = 2,  // people per unit area
        CUSTOM = 3,         // user-defined
        COUNT
    };
    SensorType sensorType = SensorType::TEMPERATURE;

    // The current sensor reading (updated by IoT feed / Lua / C++ API):
    float sensorValue = 0.0f;

    // Accessors (follow engine pattern):
    constexpr bool IsEnabled() const { return _flags & ENABLED; }
    constexpr void SetEnabled(bool value) { set_flag(_flags, ENABLED, value); }

    // Call this to push new IoT data:
    void SetSensorValue(float value) { sensorValue = value; }

    void Serialize(wi::Archive& archive, wi::ecs::EntitySerializer& seri);
};
```

**Design note**: The sensor's POSITION comes from the TransformComponent on the
same entity. You don't store position here — just attach a Transform and move it.

### Add to `WickedEngine/wiScene.h` (after gaussian_splats registration ~line 68)

```cpp
wi::ecs::ComponentManager<IoTSensorComponent>& iot_sensors = componentLibrary.Register<IoTSensorComponent>("wi::scene::Scene::iot_sensors");
```

---

## 3b. VolumeVisualizerComponent

### Add to `WickedEngine/wiScene_Components.h`

This is the bigger component — it owns the GPU resources and rendering settings.

```cpp
struct VolumeVisualizerComponent
{
    enum FLAGS
    {
        EMPTY = 0,
        ENABLED = 1 << 0,
    };
    uint32_t _flags = ENABLED;

    // Simulation mode:
    enum class SimulationMode : uint32_t
    {
        ANALYTICAL = 0,   // Stateless Gaussian - cheap
        ITERATIVE = 1,    // Heat equation solver - physically accurate
        COUNT
    };
    SimulationMode simulationMode = SimulationMode::ANALYTICAL;

    // Gradient/colormap:
    enum class GradientMode : uint32_t
    {
        INFERNO = 0,      // heat visualization
        VIRIDIS = 1,      // general scientific
        COOL_WARM = 2,    // diverging (blue-white-red)
        COUNT
    };
    GradientMode gradientMode = GradientMode::INFERNO;

    // === Serialized properties ===

    float ambientValue = 24.0f;       // baseline value (e.g., room temp in Celsius)
    float diffusionAlpha = 0.15f;     // diffusivity coefficient
    float opacityScale = 50.0f;       // controls visual density
    uint32_t maxRaySteps = 128;       // ray-march quality
    uint32_t densityResolution = 64;  // 3D texture resolution (32, 64, or 128)
    float valueRangeMin = 0.0f;       // for normalizing display
    float valueRangeMax = 100.0f;     // for normalizing display

    // Entity reference: which IoT sensor feeds this visualizer
    // (use INVALID_ENTITY if none; the update system will look this up)
    wi::ecs::Entity sensorEntity = wi::ecs::INVALID_ENTITY;

    // === Non-serialized runtime state ===

    float elapsedTime = 0.0f;

    // GPU resources (created lazily in the update system):
    // densityTexture[0] = current output (both modes)
    // densityTexture[1] = previous frame (iterative mode only, for ping-pong)
    wi::graphics::Texture densityTexture[2];
    uint32_t pingPongIndex = 0;    // which texture is "current" in iterative mode
    wi::graphics::GPUBuffer constantBuffer;
    bool gpuResourcesCreated = false;

    // Cached sensor data (written by update system each frame):
    float currentSensorValue = 0.0f;
    XMFLOAT3 sensorPositionLocal = XMFLOAT3(0, 0, 0);

    // Accessors:
    constexpr bool IsEnabled() const { return _flags & ENABLED; }
    constexpr void SetEnabled(bool value) { set_flag(_flags, ENABLED, value); }

    void Serialize(wi::Archive& archive, wi::ecs::EntitySerializer& seri);
};
```

### Add to `WickedEngine/wiScene.h` (right after iot_sensors)

```cpp
wi::ecs::ComponentManager<VolumeVisualizerComponent>& volume_visualizers = componentLibrary.Register<VolumeVisualizerComponent>("wi::scene::Scene::volume_visualizers");
```

---

## 3c. Serialization - `WickedEngine/wiScene_Serializers.cpp`

Add Serialize() implementations at the end of the file (before the closing namespace brace).

### IoTSensorComponent::Serialize

```cpp
void IoTSensorComponent::Serialize(wi::Archive& archive, wi::ecs::EntitySerializer& seri)
{
    if (archive.IsReadMode())
    {
        archive >> _flags;
        archive >> (uint32_t&)sensorType;
        archive >> sensorValue;
    }
    else
    {
        archive << _flags;
        archive << (uint32_t)sensorType;
        archive << sensorValue;
    }
}
```

### VolumeVisualizerComponent::Serialize

```cpp
void VolumeVisualizerComponent::Serialize(wi::Archive& archive, wi::ecs::EntitySerializer& seri)
{
    if (archive.IsReadMode())
    {
        archive >> _flags;
        archive >> (uint32_t&)simulationMode;
        archive >> (uint32_t&)gradientMode;
        archive >> ambientValue;
        archive >> diffusionAlpha;
        archive >> opacityScale;
        archive >> maxRaySteps;
        archive >> densityResolution;
        archive >> valueRangeMin;
        archive >> valueRangeMax;
        SerializeEntity(archive, sensorEntity, seri);  // handles entity remapping!
    }
    else
    {
        archive << _flags;
        archive << (uint32_t)simulationMode;
        archive << (uint32_t)gradientMode;
        archive << ambientValue;
        archive << diffusionAlpha;
        archive << opacityScale;
        archive << maxRaySteps;
        archive << densityResolution;
        archive << valueRangeMin;
        archive << valueRangeMax;
        SerializeEntity(archive, sensorEntity, seri);
    }
}
```

**Important**: Use `SerializeEntity()` for entity references (not raw archive >>).
This handles entity remapping when scenes are merged or duplicated.

---

## 3d. Update Systems - `WickedEngine/wiScene.cpp`

### Declare in wiScene.h

Add to the Scene struct's public methods (find the other RunXxxUpdateSystem declarations):

```cpp
void RunIoTSensorUpdateSystem(wi::jobsystem::context& ctx);
void RunVolumeVisualizerUpdateSystem(wi::jobsystem::context& ctx);
```

### Call in Scene::Update() (~line 405 area)

Add after `RunForceUpdateSystem(ctx);` and before `RunLightUpdateSystem(ctx);`:

```cpp
RunIoTSensorUpdateSystem(ctx);
RunVolumeVisualizerUpdateSystem(ctx);
```

### Implement in wiScene.cpp

Add at the end of the file (before the closing namespace brace).

**RunIoTSensorUpdateSystem**: Simple — sensors are passive data holders.
Nothing to compute unless you want to add auto-polling later.

```cpp
void Scene::RunIoTSensorUpdateSystem(wi::jobsystem::context& ctx)
{
    // Currently a no-op. IoT values are pushed externally (Lua/API).
    // Future: could poll network endpoints here.
}
```

**RunVolumeVisualizerUpdateSystem**: This is where you:
1. Accumulate elapsed time
2. Read the linked sensor entity's value and position
3. Create GPU resources if not yet created

```cpp
void Scene::RunVolumeVisualizerUpdateSystem(wi::jobsystem::context& ctx)
{
    // TODO: implement
    // Iterate all volume visualizers:
    for (size_t i = 0; i < volume_visualizers.GetCount(); ++i)
    {
        VolumeVisualizerComponent& vis = volume_visualizers[i];
        if (!vis.IsEnabled()) continue;

        // Accumulate time:
        vis.elapsedTime += dt;

        // Read sensor data:
        if (vis.sensorEntity != wi::ecs::INVALID_ENTITY)
        {
            const IoTSensorComponent* sensor = iot_sensors.GetComponent(vis.sensorEntity);
            if (sensor != nullptr && sensor->IsEnabled())
            {
                vis.currentSensorValue = sensor->sensorValue;

                // Get sensor world position from its transform:
                const TransformComponent* sensorTransform = transforms.GetComponent(vis.sensorEntity);
                if (sensorTransform != nullptr)
                {
                    // Get visualizer's own transform (to convert sensor pos to local space):
                    Entity visEntity = volume_visualizers.GetEntity(i);
                    const TransformComponent* visTransform = transforms.GetComponent(visEntity);
                    if (visTransform != nullptr)
                    {
                        // TODO: Transform sensor world position into visualizer local space
                        // Hint: multiply sensor world pos by inverse of visualizer world matrix
                        // Then store in vis.sensorPositionLocal
                    }
                }
            }
        }

        // Create GPU resources lazily:
        if (!vis.gpuResourcesCreated)
        {
            // TODO: Create the 3D texture(s) and constant buffer
            // See guide 04_StandaloneModule.md for the CreateGPUResources pattern
        }
    }
}
```

## Tips
- `dt` is available as `this->dt` in Scene methods — it's set each frame
- `transforms.GetComponent(entity)` returns nullptr if entity has no transform
- The world position is in `transform->GetPosition()` after RunTransformUpdateSystem
- For sensor → local space: you need the INVERSE of the visualizer's world matrix.
  Use `XMMatrixInverse(nullptr, XMLoadFloat4x4(&visTransform->world))` then
  `XMVector3Transform(sensorWorldPos, inverseMatrix)`
