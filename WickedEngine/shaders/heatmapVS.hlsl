#include "globals.hlsli"
#include "cube.hlsli"

struct VertexToPixel
{
	float4 pos : SV_POSITION;
	float3 worldPos : WORLDPOSITION;
};

VertexToPixel main(uint vertexID : SV_VERTEXID)
{
	VertexToPixel Out;

	// CUBE[] from cube.hlsli is a unit cube in [-1, 1]
	float4 localPos = CUBE[vertexID];

	// Transform to world using the visualizer's matrix from the heat map data
	float4 worldPos = mul(GetScene().heatmap.world_matrix, localPos);

	// Project to screen
	Out.pos = mul(GetCamera().view_projection, worldPos);
	Out.worldPos = worldPos.xyz;

	return Out;
}
