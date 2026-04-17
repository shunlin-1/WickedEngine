# Step 8: IoT Data Interface

How external IoT data feeds into the system. This is the last step — once the
rendering works, you can connect it to real data.

---

## Architecture

```
IoT Sensor (physical)
    |
    v
[Transport: MQTT / HTTP / Serial / File]
    |
    v
Lua Script (or C++ callback)
    |
    v
IoTSensorComponent.sensorValue = newReading
    |
    v (each frame, RunVolumeVisualizerUpdateSystem reads this)
VolumeVisualizerComponent.currentSensorValue
    |
    v (compute shader uses this)
3D Density Texture
    |
    v (pixel shader reads this)
Rendered Volume
```

The engine doesn't handle network transport — that's intentional. The component
is a passive data holder. You push data into it from outside.

---

## Option A: Lua Script (easiest to start with)

Attach a `ScriptComponent` to the same entity as the IoTSensorComponent.
The script runs every frame.

### Simple test script (hardcoded oscillation)
```lua
-- test_iot.lua
-- Attach this to an entity that has both IoTSensorComponent and TransformComponent

local entity = GetEntity()  -- gets this script's entity
local sensor = entity:GetIoTSensorComponent()

-- Oscillate temperature for testing:
local t = GetTime()
local temp = 24.0 + 60.0 * math.sin(t * 0.5)
sensor:SetSensorValue(temp)
```

### Network polling script (production)
```lua
-- iot_mqtt.lua
-- Poll an HTTP endpoint every N seconds

local entity = GetEntity()
local sensor = entity:GetIoTSensorComponent()
local pollInterval = 2.0  -- seconds
local lastPoll = 0

function Update()
    local t = GetTime()
    if t - lastPoll > pollInterval then
        lastPoll = t
        -- Use wi::network or external HTTP if available
        -- For now, read from a local file that another process updates:
        local f = io.open("iot_data.json", "r")
        if f then
            local data = f:read("*all")
            f:close()
            -- Parse temperature from JSON (simple pattern match)
            local temp = data:match('"temperature":(%d+%.?%d*)')
            if temp then
                sensor:SetSensorValue(tonumber(temp))
            end
        end
    end
end
```

### Lua Binding (you need to expose IoTSensorComponent to Lua)

This requires adding bindings in `WickedEngine/wiScene_BindLua.h/.cpp`.
Search for how `SoundComponent_BindLua` is implemented — it's a simple pattern:

1. Define `IoTSensorComponent_BindLua` class wrapping the component
2. Register methods: `SetSensorValue`, `GetSensorValue`, `SetEnabled`, `IsEnabled`
3. Register getter on entity: `entity:GetIoTSensorComponent()`

This is optional for the first build — you can test with the editor slider first.

---

## Option B: Direct C++ API

If you're writing a custom application (not using the editor):

```cpp
// Get the scene
auto& scene = myApp.GetScene();

// Find or create the sensor entity
Entity sensorEntity = scene.Entity_CreateSensor("Temperature Sensor 1");

// Push new data (e.g., from a network callback)
IoTSensorComponent* sensor = scene.iot_sensors.GetComponent(sensorEntity);
if (sensor)
{
    sensor->SetSensorValue(85.5f);  // 85.5 degrees
}

// Move the sensor (e.g., tracking a person)
TransformComponent* transform = scene.transforms.GetComponent(sensorEntity);
if (transform)
{
    transform->Translate(XMFLOAT3(newX, newY, newZ));
    transform->UpdateTransform();
}
```

---

## Option C: File Watcher (simplest production pattern)

Write a small external program that:
1. Reads from your IoT broker (MQTT, HTTP, etc.)
2. Writes a simple CSV/JSON file: `iot_data.csv`
3. The Lua script reads this file every frame

This decouples the IoT transport completely from the engine.

```
iot_data.csv format:
sensor_id,value,x,y,z
sensor_01,85.5,0.0,1.0,0.0
sensor_02,72.3,2.0,1.0,-1.0
```

---

## Testing Without Real IoT

Before connecting real sensors, test with:

1. **Editor slider**: Use the sensorValueSlider in IoTSensorWindow to manually set values
2. **Lua oscillation script**: Attach the test script above for animated testing
3. **Moving the sensor entity**: Use the editor gizmo to drag the sensor around and
   watch the heat source move in the volume

---

## Multiple Sensors

The current design supports one sensor per visualizer (`sensorEntity` field).
For multiple sensors feeding the same volume:

**Quick approach**: In iterative mode, have multiple IoT sensor entities.
The update system loops through all sensors linked to a visualizer and injects
each one into the density field at its position. Modify the diffusion compute
shader to accept a structured buffer of source positions/values instead of
a single source in the constant buffer.

**Future enhancement**: Add a `wi::vector<Entity> sensorEntities` field to
VolumeVisualizerComponent instead of a single `sensorEntity`.

This is a natural evolution — get single-sensor working first, then extend.
