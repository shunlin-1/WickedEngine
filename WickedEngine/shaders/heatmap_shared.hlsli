#ifndef WI_HEATMAP_SHARED_HLSLI
#define WI_HEATMAP_SHARED_HLSLI

// Density-texture encoding shared by heatmapCS (writer) and heatmapPS (reader).
//
//   empty voxel (no sensor nearby)  → 0.0
//   sensor-touched voxel, value t01 → DENSITY_MIN + t01 * DENSITY_RANGE
//
// The offset keeps even a t01 = 0 sensor's encoded density safely above
// DENSITY_GATE so the PS doesn't mistake a legitimate cold sensor for
// empty space. Without the offset, low-value sensors produce asymmetric
// visible regions because the gate clips them at the edges.

static const float DENSITY_MIN   = 0.02;  // encoded density of a t01 = 0 sensor
static const float DENSITY_RANGE = 0.98;  // 1.0 - DENSITY_MIN
static const float DENSITY_GATE  = 0.005; // PS treats below this as empty

float EncodeDensity(float t01)
{
	return DENSITY_MIN + saturate(t01) * DENSITY_RANGE;
}

float DecodeDensity(float encoded)
{
	return saturate((encoded - DENSITY_MIN) / DENSITY_RANGE);
}

#endif
