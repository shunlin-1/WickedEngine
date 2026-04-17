# Step 6: Editor Integration

Create 4 new files and modify 2 existing files.

---

## 6a. `Editor/IoTSensorWindow.h`

Follow the `VoxelGridWindow.h` pattern (it's 31 lines).

```cpp
#pragma once
class EditorComponent;

class IoTSensorWindow : public wi::gui::Window
{
public:
    void Create(EditorComponent* editor);
    EditorComponent* editor = nullptr;
    wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
    void SetEntity(wi::ecs::Entity entity);

    // TODO: Add your widgets
    // Suggestions:
    //   wi::gui::CheckBox enabledCheckBox;
    //   wi::gui::ComboBox sensorTypeCombo;       // Temperature, Humidity, CrowdDensity, Custom
    //   wi::gui::Slider   sensorValueSlider;     // manual value for testing
    //   wi::gui::Label    infoLabel;              // shows current value + type

    void ResizeLayout() override;
};
```

## 6b. `Editor/IoTSensorWindow.cpp`

Follow `VoxelGridWindow.cpp` for the full pattern. Key structure:

```cpp
#include "stdafx.h"
#include "IoTSensorWindow.h"

using namespace wi::ecs;
using namespace wi::scene;

void IoTSensorWindow::Create(EditorComponent* _editor)
{
    editor = _editor;
    wi::gui::Window::Create(ICON_SENSOR " IoT Sensor",  // pick an icon from icons.h
        wi::gui::Window::WindowControls::COLLAPSE |
        wi::gui::Window::WindowControls::CLOSE |
        wi::gui::Window::WindowControls::FIT_ALL_WIDGETS_VERTICAL);
    SetSize(XMFLOAT2(400, 200));

    // Close button removes the component:
    closeButton.SetTooltip("Delete IoT Sensor");
    OnClose([=](wi::gui::EventArgs args) {
        wi::Archive& archive = editor->AdvanceHistory();
        archive << EditorComponent::HISTORYOP_COMPONENT_DATA;
        editor->RecordEntity(archive, entity);

        editor->GetCurrentScene().iot_sensors.Remove(entity);

        editor->RecordEntity(archive, entity);
        editor->componentsWnd.RefreshEntityTree();
    });

    // TODO: Create widgets (enabledCheckBox, sensorTypeCombo, sensorValueSlider)
    // Each widget follows this pattern:
    //   widget.Create("Label");
    //   widget.SetDescription("...");
    //   widget.OnXxx([=](wi::gui::EventArgs args) {
    //       Scene& scene = editor->GetCurrentScene();
    //       IoTSensorComponent* sensor = scene.iot_sensors.GetComponent(entity);
    //       if (sensor == nullptr) return;
    //       sensor->someProperty = args.fValue;  // or iValue, bValue
    //   });
    //   AddWidget(&widget);
}

void IoTSensorWindow::SetEntity(Entity _entity)
{
    entity = _entity;
    Scene& scene = editor->GetCurrentScene();
    const IoTSensorComponent* sensor = scene.iot_sensors.GetComponent(entity);
    if (sensor == nullptr) return;

    // TODO: Sync widgets from component state:
    //   enabledCheckBox.SetCheck(sensor->IsEnabled());
    //   sensorTypeCombo.SetSelected((int)sensor->sensorType);
    //   sensorValueSlider.SetValue(sensor->sensorValue);
}

void IoTSensorWindow::ResizeLayout()
{
    // TODO: Layout widgets vertically
    // See VoxelGridWindow::ResizeLayout() for the pattern
}
```

---

## 6c. `Editor/VolumeVisWindow.h`

Larger window — has more properties.

```cpp
#pragma once
class EditorComponent;

class VolumeVisWindow : public wi::gui::Window
{
public:
    void Create(EditorComponent* editor);
    EditorComponent* editor = nullptr;
    wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
    void SetEntity(wi::ecs::Entity entity);

    // TODO: Add your widgets:
    //   wi::gui::CheckBox enabledCheckBox;
    //   wi::gui::ComboBox simulationModeCombo;   // Analytical / Iterative
    //   wi::gui::ComboBox gradientModeCombo;     // Inferno / Viridis / Cool-Warm
    //   wi::gui::Slider   ambientValueSlider;
    //   wi::gui::Slider   diffusionAlphaSlider;
    //   wi::gui::Slider   opacityScaleSlider;
    //   wi::gui::Slider   valueRangeMinSlider;
    //   wi::gui::Slider   valueRangeMaxSlider;
    //   wi::gui::TextInputField maxRayStepsInput;
    //   wi::gui::TextInputField densityResolutionInput;
    //   wi::gui::Button   resetTimeButton;       // reset diffusion time + clear textures
    //   wi::gui::TextInputField sensorEntityInput; // entity ID of linked sensor

    void ResizeLayout() override;
};
```

## 6d. `Editor/VolumeVisWindow.cpp`

Same pattern as IoTSensorWindow but more widgets. Key points:

- **simulationModeCombo**: When changed, clear GPU resources so they're recreated
  with the right texture count
- **densityResolutionInput**: When changed, also clear GPU resources for resize
- **resetTimeButton**: Set `vis.elapsedTime = 0` and clear the density textures
- **sensorEntityInput**: Let user type an entity ID to link the sensor
  (or implement drag-and-drop later)

```cpp
// Example: simulation mode combo
simulationModeCombo.Create("Simulation");
simulationModeCombo.AddItem("Analytical (GPU cheap)");
simulationModeCombo.AddItem("Iterative (physical)");
simulationModeCombo.OnSelect([=](wi::gui::EventArgs args) {
    Scene& scene = editor->GetCurrentScene();
    VolumeVisualizerComponent* vis = scene.volume_visualizers.GetComponent(entity);
    if (vis == nullptr) return;
    vis->simulationMode = (VolumeVisualizerComponent::SimulationMode)args.iValue;
    // Force GPU resource recreation:
    vis->gpuResourcesCreated = false;
    vis->elapsedTime = 0;
});
AddWidget(&simulationModeCombo);
```

---

## 6e. Modify `Editor/ComponentsWindow.h`

Add includes and members:

```cpp
// Add to the #include list (after #include "GaussianSplatWindow.h"):
#include "IoTSensorWindow.h"
#include "VolumeVisWindow.h"

// Add members (after gaussiansplatWnd):
IoTSensorWindow iotSensorWnd;
VolumeVisWindow volumeVisWnd;

// Add to Filter enum (after GaussianSplat):
IoTSensor = 1ull << 33ull,
VolumeVisualizer = 1ull << 34ull,
```

---

## 6f. Modify `Editor/ComponentsWindow.cpp`

You need to add entries in several places. Search for "VoxelGrid" to find each spot:

### 1. Filter combo (~line 48 area)
```cpp
filterCombo.AddItem(ICON_SENSOR, (uint64_t)Filter::IoTSensor);
filterCombo.AddItem(ICON_VOLUMEVIS, (uint64_t)Filter::VolumeVisualizer);
```

### 2. ADD enum (~line 197 area)
```cpp
ADD_IOT_SENSOR,
ADD_VOLUME_VISUALIZER,
```

### 3. newComponentCombo items (~line 236 area)
```cpp
newComponentCombo.AddItem("IoT Sensor " ICON_SENSOR, ADD_IOT_SENSOR);
newComponentCombo.AddItem("Volume Visualizer " ICON_VOLUMEVIS, ADD_VOLUME_VISUALIZER);
```

### 4. Component creation switch (~line 367 area)
```cpp
case ADD_IOT_SENSOR:
    scene.iot_sensors.Create(entity);
    break;
case ADD_VOLUME_VISUALIZER:
    scene.volume_visualizers.Create(entity);
    break;
```

### 5. SetEntity routing (~line 489 area)
```cpp
case ADD_IOT_SENSOR:
    iotSensorWnd.SetEntity(entity);
    break;
case ADD_VOLUME_VISUALIZER:
    volumeVisWnd.SetEntity(entity);
    break;
```

### 6. Entity tree icon (~line 1271 area)
```cpp
if (scene.iot_sensors.Contains(entity))
    item.name += ICON_SENSOR " ";
if (scene.volume_visualizers.Contains(entity))
    item.name += ICON_VOLUMEVIS " ";
```

### 7. CheckEntityFilter (~line 1544 area)
```cpp
(has_flag(filter, Filter::IoTSensor) && scene.iot_sensors.Contains(entity)) ||
(has_flag(filter, Filter::VolumeVisualizer) && scene.volume_visualizers.Contains(entity)) ||
```

---

## Icons

You'll need to define icon constants. Check `Editor/icons.h` or wherever ICON_VOXELGRID
is defined. Add your own:

```cpp
#define ICON_SENSOR       "\xEF\x8B\xA8"   // pick a Unicode glyph from the font
#define ICON_VOLUMEVIS    "\xEF\x86\xA5"   // pick another glyph
```

Or search the existing icon definitions and pick unused glyphs from the icon font.

---

## Tips

- The `forEachSelected` lambda pattern (used in LightWindow) lets you apply changes
  to all selected entities at once. Consider using it for the VolumeVisWindow sliders.
- `editor->AdvanceHistory()` + `RecordEntity` before/after changes enables undo/redo.
- Window widgets auto-layout via `ResizeLayout()` — check VoxelGridWindow for the pattern.
