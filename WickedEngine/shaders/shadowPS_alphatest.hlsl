#define OBJECTSHADER_LAYOUT_SHADOW_TEX
#include "objectHF.hlsli"

void main(PixelInput input)
{
	ShaderMaterial material = GetMaterial();

	// Dissolve pass-through: if the active cut plane is in pass-light mode and
	// this (dissolve-tagged) surface is past the fade midpoint, drop the shadow.
	[branch]
	if (material.IsDissolveEnabled())
	{
		ClipShadowForDissolve(input.GetPos3D());
	}

	half alpha = 1;

	[branch]
	if (material.textures[BASECOLORMAP].IsValid())
	{
		alpha = material.textures[BASECOLORMAP].Sample(sampler_point_wrap, input.GetUVSets()).a;
	}

	[branch]
	if (material.textures[TRANSPARENCYMAP].IsValid())
	{
		alpha *= material.textures[TRANSPARENCYMAP].Sample(sampler_point_wrap, input.GetUVSets()).r;
	}

	ShaderMeshInstance meshinstance = load_instance(input.GetInstanceIndex());

	clip(alpha - material.GetAlphaTest() - meshinstance.GetAlphaTest());
}
