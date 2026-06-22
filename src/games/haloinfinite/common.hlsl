#include "./shared.h"

float3 NeutwoStockmanSharpeLMS(float3 color_input, float peak, float clip = 100.f)
{
  float3 color_bt2020 = renodx::color::bt2020::from::BT709(color_input);
  float3 color_lms = renodx::color::lms::from::BT2020(color_bt2020);

  float3 peak_lms = renodx::color::lms::from::BT2020(peak.xxx);
  float3 clip_lms = renodx::color::lms::from::BT2020(clip.xxx);

  color_lms = renodx::tonemap::neutwo::PerChannel(max(color_lms, 0.f), peak_lms, clip_lms);
  color_bt2020 = renodx::color::bt2020::from::LMS(color_lms);

  return max(renodx::color::bt709::from::BT2020(color_bt2020), 0.f);
}

float HDRBoost(float color, float power = 0.20f, float normalization_point = 0.02f) {
  const float smoothing = power * 2.f;

  float boosted = max(color, lerp(color, normalization_point * pow(color / normalization_point, 1.f + power), renodx::tonemap::Reinhard(color, smoothing)));
  // float highlight_compression_scale = saturate(pow(saturate((color - highlight_compression_start) / (highlight_compression_peak - highlight_compression_start)), highlight_compression_curve));
  // float smoothed = lerp(boosted, color, highlight_compression_scale);
  return boosted;
  // return smoothed;
}

float3 HDRBoost(float3 color, float power = 0.20f, float normalization_point = 0.02f) {
  return float3(
      HDRBoost(color.r, power, normalization_point),
      HDRBoost(color.g, power, normalization_point),
      HDRBoost(color.b, power, normalization_point)
  );
}
