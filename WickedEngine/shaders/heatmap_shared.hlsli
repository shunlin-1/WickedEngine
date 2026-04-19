#ifndef WI_HEATMAP_SHARED_HLSLI
#define WI_HEATMAP_SHARED_HLSLI

// Density-texture encoding shared by heatmapCS (writer) and heatmapPS (reader).
//
// FORMAT: R16G16_FLOAT, two independent channels:
//   .r = presence   [0, 1]  → "how much sensor coverage here?" (density gate)
//   .g = t01        [0, 1]  → "what temperature is this voxel?" (colormap input)
//
// The channels are decoupled on purpose. With a single-channel encoding, linear
// filtering between a HOT voxel (encoded near 1) and an EMPTY voxel (encoded 0)
// samples through the full range, decoding to false "cold" values — so hot
// sensors appear with a fake blue halo.
//
// With two channels, even an "empty" voxel still carries a meaningful t01 (the
// Gaussian-weighted average of all sensors at that position, no matter how small
// the weights). Linear filtering of t01 between adjacent voxels therefore stays
// within the plausible color range of the scene. Presence is what gates whether
// the sample renders; temperature is what colors it.

static const float DENSITY_GATE = 0.005; // PS treats presence below this as empty

#endif
