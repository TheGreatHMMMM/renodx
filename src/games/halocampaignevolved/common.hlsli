#ifndef SRC_GAMES_HALOCAMPAIGNEVOLVED_COMMON_HLSLI_
#define SRC_GAMES_HALOCAMPAIGNEVOLVED_COMMON_HLSLI_

#include "./shared.h"

float HDRBoost(float color, float power = 0.20f, float normalization_point = 0.02f) {
  const float smoothing = power * 2.f;

  float boosted = max(color, lerp(color, normalization_point * pow(color / normalization_point, 1.f + power), renodx::tonemap::Reinhard(color, smoothing)));
  return boosted;
}

float3 HDRBoost(float3 color, float power = 0.20f, float normalization_point = 0.02f) {
  return float3(
      HDRBoost(color.r, power, normalization_point),
      HDRBoost(color.g, power, normalization_point),
      HDRBoost(color.b, power, normalization_point)
  );
}


#endif  // SRC_GAMES_HALOCAMPAIGNEVOLVED_COMMON_HLSLI_
