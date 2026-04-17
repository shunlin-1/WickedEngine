# Step 5: RenderPath3D Integration

Modify `WickedEngine/wiRenderPath3D.cpp` to wire in the compute and render passes.

---

## Where in the pipeline

Open `wiRenderPath3D.cpp` and find `RenderTransparents()` (line ~2062).

The render pass flow is:
```
RenderTransparents():
  Water ripple rendering          (~2067)
  FSR2 pre-alpha copy             (~2084)
  Gaussian splat update           (~2105)
  Set viewport + scissor          (~2107)
  RenderPass setup (MSAA/non)     (~2117-2144)
  Ocean rendering                 (~2147-2162)
  MIP chain for transparents      (~2165-2168)
  === RenderPassBegin ===         (2170)   <-- render pass starts here
    Volumetric lights             (~2175-2186)
    Light shafts                  (~2190-2199)
    Transparent scene draw        (~2201-2237)
    ~~~ YOUR HEAT MAP RENDER HERE ~~~      <-- after transparent scene
    Foreground scene              (~2222-2232)
  ... continues with particles, etc.
```

You need to add TWO things:

---

## 5a. Compute Pass (BEFORE the render pass begins)

The compute dispatch must happen OUTSIDE the render pass (you can't dispatch compute
inside a render pass). Add it after the Gaussian splat update (~line 2105) and before
the RenderPassBegin (~line 2170):

```cpp
// === Volume Visualizer density update (compute pass) ===
{
    auto& visualizers = scene->volume_visualizers;
    for (size_t i = 0; i < visualizers.GetCount(); ++i)
    {
        VolumeVisualizerComponent& vis = visualizers[i];
        if (vis.IsEnabled() && vis.gpuResourcesCreated)
        {
            wi::volumevis::UpdateDensityField(vis, cmd);
        }
    }
}
```

You'll need to add `#include "wiVolumeVis.h"` at the top of the file.

---

## 5b. Render Pass (INSIDE the render pass, after transparent scene)

Find the transparent scene draw section (~line 2201-2237). After the transparent
scene is drawn (the `DrawScene` calls with `DRAWSCENE_TRANSPARENT`), add:

```cpp
// === Volume Visualizer rendering ===
{
    auto& visualizers = scene->volume_visualizers;
    for (size_t i = 0; i < visualizers.GetCount(); ++i)
    {
        const VolumeVisualizerComponent& vis = visualizers[i];
        if (vis.IsEnabled() && vis.gpuResourcesCreated)
        {
            Entity entity = visualizers.GetEntity(i);
            const TransformComponent* transform = scene->transforms.GetComponent(entity);
            if (transform != nullptr)
            {
                wi::volumevis::Render(vis, *transform, cmd);
            }
        }
    }
}
```

**Placement matters**: Rendering AFTER transparent objects means the volume is drawn
on top of transparent surfaces. If you want transparent objects to be visible through
the volume, you'd need to render the volume first — but for heat maps, rendering
on top is usually the right choice since you want the heat map to be the primary
visual element.

---

## Exact insertion points

After your edits, the flow should look like:

```
  Gaussian splat update           (~2105)

  // NEW: Volume vis compute pass (outside render pass)
  {
      for each visualizer: UpdateDensityField(...)
  }

  Set viewport + scissor          (~2107)
  ...
  === RenderPassBegin ===         (2170)
    Volumetric lights             (~2175)
    Light shafts                  (~2190)
    Transparent scene draw        (~2201)

    // NEW: Volume vis render pass (inside render pass)
    {
        for each visualizer: Render(...)
    }

    Foreground scene              (~2222)
  ...
```

## Tips

- Don't forget the `#include "wiVolumeVis.h"` at the top of wiRenderPath3D.cpp
- The `scene` pointer is available as `this->scene` in RenderPath3D methods
- The `cmd` (CommandList) is passed as parameter to RenderTransparents
- Use `device->EventBegin("VolumeVis", cmd)` / `EventEnd` for GPU profiler visibility
