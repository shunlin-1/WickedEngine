#define OBJECTSHADER_LAYOUT_SHADOW_TEX
#define OBJECTSHADER_USE_COLOR
#include "objectHF.hlsli"

[earlydepthstencil]
float4 main(PixelInput input) : SV_TARGET
{
	ShaderMaterial material = GetMaterial();

	// Dissolve pass-through: dissolve-flagged casters fade their shadow smoothly
	// across edge_width, matching the forward-pass mesh fade. No clip → no
	// frame-to-frame flicker at the cut plane boundary.
	half dissolve_atten = (half)1.0;
	[branch]
	if (material.IsDissolveEnabled())
	{
		dissolve_atten = DissolveShadowAttenuation(input.GetPos3D());
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

	// Dissolve pass-through: scale opacity by the plane attenuation so the
	// shadow fades in lockstep with the visible geometry. atten=1 → unchanged,
	// atten=0 → opacity=0 → tint=1 (full light). Smooth across edge_width.
	opacity *= dissolve_atten;

	color.rgb *= 1 - opacity; // if fully opaque, then black (not let through any light)

	color.a = input.pos.z; // secondary depth

	return color;
}
