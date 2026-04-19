#define OBJECTSHADER_LAYOUT_SHADOW_TEX
#define OBJECTSHADER_USE_COLOR
#include "objectHF.hlsli"

[earlydepthstencil]
float4 main(PixelInput input) : SV_TARGET
{
	ShaderMaterial material = GetMaterial();

	// Dissolve pass-through: dissolve-tagged pixels past the fade midpoint drop
	// their shadow contribution so light "passes through" the faded geometry.
	[branch]
	if (material.IsDissolveEnabled())
	{
		ClipShadowForDissolve(input.GetPos3D());
	}

	float4 uvsets = input.GetUVSets();
	half4 color;
	[branch]
	if (material.textures[BASECOLORMAP].IsValid())
	{
		color = material.textures[BASECOLORMAP].Sample(sampler_objectshader, uvsets);
	}
	else
	{
		color = 1;
	}
	
	[branch]
	if (material.textures[TRANSPARENCYMAP].IsValid())
	{
		color.a *= material.textures[TRANSPARENCYMAP].Sample(sampler_objectshader, uvsets).r;
	}
	
	color *= input.color;
	
	ShaderMeshInstance meshinstance = load_instance(input.GetInstanceIndex());

	clip(color.a - material.GetAlphaTest() - meshinstance.GetAlphaTest());

	half opacity = color.a;
	
	half transmission = lerp(material.GetTransmission(), 1, material.GetCloak());
	color.rgb = lerp(color.rgb, 1, material.GetCloak());

	[branch]
	if (transmission > 0)
	{
		[branch]
		if (material.textures[TRANSMISSIONMAP].IsValid())
		{
			half transmissionMap = material.textures[TRANSMISSIONMAP].Sample(sampler_objectshader, uvsets).r;
			transmission *= transmissionMap;
		}
		opacity *= 1 - transmission;
	}
	
	opacity = lerp(opacity, 0.5, material.GetCloak());

	color.rgb *= 1 - opacity; // if fully opaque, then black (not let through any light)

	color.a = input.pos.z; // secondary depth

	return color;
}
