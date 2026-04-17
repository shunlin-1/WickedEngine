# Step 7: Build System & Includes

Wire everything into the build so it compiles.

---

## 7a. `WickedEngine/WickedEngine.h`

Add the include for the new module. Find the block of `#include` statements and add:

```cpp
#include "wiVolumeVis.h"
```

---

## 7b. `WickedEngine/shaders/ShaderInterop.h`

Add the CB slot definition. Two places:

**Non-PS5 section** (~line 106, after `CBSLOT_OTHER_OCEAN`):
```cpp
#define CBSLOT_OTHER_VOLUMEVIS				3
```

**PS5 section** (~line 133, after `CBSLOT_OTHER_OCEAN`):
```cpp
#define CBSLOT_OTHER_VOLUMEVIS				4
```

---

## 7c. `WickedEngine/shaders/Shaders_SOURCE.vcxitems`

This is the Visual Studio shared items file for shaders. Open it and add entries
for each new shader file. Search for an existing `.hlsl` entry to see the XML format.

Compute shaders use `<ShaderType>Compute</ShaderType>`.
Vertex shaders use `<ShaderType>Vertex</ShaderType>`.
Pixel shaders use `<ShaderType>Pixel</ShaderType>`.
Include files (.hlsli) use `<ClInclude>`.

Add these entries:

```xml
<!-- In the <ItemGroup> with other .hlsl files: -->
<FxCompile Include="$(MSBuildThisFileDirectory)volumeVisDensityCS.hlsl">
  <ShaderType>Compute</ShaderType>
</FxCompile>
<FxCompile Include="$(MSBuildThisFileDirectory)volumeVisDiffusionCS.hlsl">
  <ShaderType>Compute</ShaderType>
</FxCompile>
<FxCompile Include="$(MSBuildThisFileDirectory)volumeVisVS.hlsl">
  <ShaderType>Vertex</ShaderType>
</FxCompile>
<FxCompile Include="$(MSBuildThisFileDirectory)volumeVisPS.hlsl">
  <ShaderType>Pixel</ShaderType>
</FxCompile>

<!-- In the <ItemGroup> with other .hlsli files: -->
<ClInclude Include="$(MSBuildThisFileDirectory)volumeVisHF.hlsli" />
<ClInclude Include="$(MSBuildThisFileDirectory)ShaderInterop_VolumeVis.h" />
```

---

## 7d. `WickedEngine/shaders/Shaders_SOURCE.vcxitems.filters`

Add filter entries so the files appear in the right VS Solution Explorer folder.
Match the pattern of existing entries.

---

## 7e. `WickedEngine/CMakeLists.txt` (the one inside WickedEngine/ subfolder)

Find the list of source files and add:

```cmake
wiVolumeVis.h
wiVolumeVis.cpp
```

Also add the shader interop header if it's listed separately:
```cmake
shaders/ShaderInterop_VolumeVis.h
```

---

## 7f. `Editor/Editor_SOURCE.vcxitems`

Add the editor window files:

```xml
<ClCompile Include="$(MSBuildThisFileDirectory)IoTSensorWindow.cpp" />
<ClCompile Include="$(MSBuildThisFileDirectory)VolumeVisWindow.cpp" />
<ClInclude Include="$(MSBuildThisFileDirectory)IoTSensorWindow.h" />
<ClInclude Include="$(MSBuildThisFileDirectory)VolumeVisWindow.h" />
```

---

## 7g. `Editor/Editor_SOURCE.vcxitems.filters`

Add filter entries for the editor files.

---

## Verification Build Order

1. Build `OfflineShaderCompiler` first (to verify shaders compile)
2. Run shader compilation from `WickedEngine/` directory:
   ```
   ../BUILD/x64/Release/OfflineShaderCompiler/OfflineShaderCompiler.exe hlsl6
   ```
3. Fix any shader compilation errors
4. Build `WickedEngine` library (verifies C++ compiles)
5. Build `Editor_Windows` (verifies everything links)

---

## Common Build Errors

- **"undefined CBSLOT_OTHER_VOLUMEVIS"**: You forgot to add it to ShaderInterop.h
- **"unresolved external"**: You forgot to add the .cpp to CMakeLists or vcxitems
- **"cannot open include file 'wiVolumeVis.h'"**: Check the include path or add to WickedEngine.h
- **Shader compilation errors**: The offline compiler gives line numbers — check your HLSL syntax
- **"CBUFFER alignment"**: Total struct size must be multiple of 16 bytes — add padding
