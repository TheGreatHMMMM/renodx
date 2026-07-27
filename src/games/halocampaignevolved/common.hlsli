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

float3 ShadowSaturation(float3 bt709, float shadow_saturation, float mid_gray = 0.18f) {
  if (shadow_saturation == 1.f) return bt709;

  float y = renodx::color::y::from::BT709(bt709);
  float shadow_floor = mid_gray / 16.f;
  float t = 1.f;
  if (y > shadow_floor) {
    t = saturate(log2(y / mid_gray) / log2(shadow_floor / mid_gray));
  }
  t = t * t * t * (t * (t * 6.f - 15.f) + 10.f);

  float3 perceptual = renodx::color::oklab::from::BT709(bt709);
  perceptual.yz *= lerp(1.f, shadow_saturation, t);
  float3 color = renodx::color::bt709::from::OkLab(perceptual);
  return renodx::color::bt709::clamp::AP1(color);
}

float3 PurityBT709(
    float3 bt709,
    float purity,
    float3 neutral_bt709 = 0.18f) {
  static const float EPSILON = 1e-6f;
  if (abs(purity - 1.f) <= 1e-5f) return bt709;

  float3 lms_in = renodx::color::lms::from::BT709(bt709);
  float3 lms_abs = abs(lms_in);
  float3 neutral_lms = renodx::color::lms::from::BT709(neutral_bt709);

  // Normalize weighted LMS by the adapted neutral, convert to MB chromaticity,
  // lerp x/y from the neutral point by "purity", then undo the normalization.
  float3 relative_weighted = renodx::math::DivideSafe(
      renodx::color::macleod_boynton::WeighLMS(lms_abs),
      neutral_lms,
      0.f.xxx);
  float3 mb =
      renodx::color::macleod_boynton::from::WeightedLMS(relative_weighted);
  float3 mb_neutral = renodx::color::macleod_boynton::from::LMS(1.f.xxx);
  float2 mb_xy = lerp(mb_neutral.xy, mb.xy, purity);
  float3 relative_weighted_out =
      renodx::color::macleod_boynton::WeightedLMSFromMacleodBoynton(
          float3(mb_xy, mb.z));
  float3 lms_out = renodx::color::macleod_boynton::UnweighLMS(
      relative_weighted_out * max(neutral_lms, EPSILON.xxx));

  return renodx::color::bt709::from::LMS(
      renodx::math::CopySign(lms_out, lms_in));
}

// ---------------------------------------------------------------------------
// Shadow purity: same MB purity, but the amount is weighted by a shadow ramp
// that is 0 at the neutral anchor and reaches 1 at range_stops below it.
// Mid-tones and highlights are left untouched.
// ---------------------------------------------------------------------------
float3 ShadowPurityBT709(
    float3 bt709,
    float shadow_purity,
    float3 neutral_bt709 = 0.18f,
    float range_stops = 4.f) {
  static const float EPSILON = 1e-6f;
  if (abs(shadow_purity - 1.f) <= 1e-5f) return bt709;

  float3 lms_in = renodx::color::lms::from::BT709(bt709);
  float3 lms_abs = abs(lms_in);
  float3 neutral_lms = renodx::color::lms::from::BT709(neutral_bt709);

  // Yf luminance of the pixel and of the neutral anchor.
  float3 w_pixel = renodx::color::macleod_boynton::WeighLMS(lms_abs);
  float yf = max(w_pixel.x + w_pixel.y, EPSILON);
  float3 w_anchor = renodx::color::macleod_boynton::WeighLMS(neutral_lms);
  float anchor_yf = max(w_anchor.x + w_anchor.y, EPSILON);

  // Shadow weight: 0 at the anchor, 1 at range_stops below it, held at 1
  // beyond the floor. Smoothed with the quintic ramp.
  float shadow_floor = anchor_yf * exp2(-range_stops);
  float t = 1.f;
  if (yf > shadow_floor) {
    t = saturate(log2(yf / anchor_yf) / log2(shadow_floor / anchor_yf));
  }
  t = t * t * t * (t * (t * 6.f - 15.f) + 10.f);

  float purity = lerp(1.f, shadow_purity, t);

  // MB purity with the shadow-weighted amount.
  float3 relative_weighted = renodx::math::DivideSafe(
      renodx::color::macleod_boynton::WeighLMS(lms_abs),
      neutral_lms,
      0.f.xxx);
  float3 mb =
      renodx::color::macleod_boynton::from::WeightedLMS(relative_weighted);
  float3 mb_neutral = renodx::color::macleod_boynton::from::LMS(1.f.xxx);
  float2 mb_xy = lerp(mb_neutral.xy, mb.xy, purity);
  float3 relative_weighted_out =
      renodx::color::macleod_boynton::WeightedLMSFromMacleodBoynton(
          float3(mb_xy, mb.z));
  float3 lms_out = renodx::color::macleod_boynton::UnweighLMS(
      relative_weighted_out * max(neutral_lms, EPSILON.xxx));

  return renodx::color::bt709::from::LMS(
      renodx::math::CopySign(lms_out, lms_in));
}

// ---------------------------------------------------------------------------
// Highlight purity: mirror of the shadow variant. Weight is 0 at the anchor
// and reaches 1 at reference_white (in Yf), leaving shadows/mids untouched.
// ---------------------------------------------------------------------------
float3 HighlightPurityBT709(
    float3 bt709,
    float highlight_purity,
    float3 neutral_bt709 = 0.18f,
    float reference_white = 1.f) {
  static const float EPSILON = 1e-6f;
  if (abs(highlight_purity - 1.f) <= 1e-5f) return bt709;

  float3 lms_in = renodx::color::lms::from::BT709(bt709);
  float3 lms_abs = abs(lms_in);
  float3 neutral_lms = renodx::color::lms::from::BT709(neutral_bt709);

  float3 w_pixel = renodx::color::macleod_boynton::WeighLMS(lms_abs);
  float yf = max(w_pixel.x + w_pixel.y, EPSILON);
  float3 w_anchor = renodx::color::macleod_boynton::WeighLMS(neutral_lms);
  float anchor_yf = max(w_anchor.x + w_anchor.y, EPSILON);

  // Highlight weight: 0 at the anchor, 1 at reference_white and above.
  float t = 0.f;
  if (yf > anchor_yf) {
    t = saturate(
        log2(yf / anchor_yf)
        / log2(max(reference_white, EPSILON) / anchor_yf));
  }
  t = t * t * t * (t * (t * 6.f - 15.f) + 10.f);

  float purity = lerp(1.f, highlight_purity, t);

  float3 relative_weighted = renodx::math::DivideSafe(
      renodx::color::macleod_boynton::WeighLMS(lms_abs),
      neutral_lms,
      0.f.xxx);
  float3 mb =
      renodx::color::macleod_boynton::from::WeightedLMS(relative_weighted);
  float3 mb_neutral = renodx::color::macleod_boynton::from::LMS(1.f.xxx);
  float2 mb_xy = lerp(mb_neutral.xy, mb.xy, purity);
  float3 relative_weighted_out =
      renodx::color::macleod_boynton::WeightedLMSFromMacleodBoynton(
          float3(mb_xy, mb.z));
  float3 lms_out = renodx::color::macleod_boynton::UnweighLMS(
      relative_weighted_out * max(neutral_lms, EPSILON.xxx));

  return renodx::color::bt709::from::LMS(
      renodx::math::CopySign(lms_out, lms_in));
}


#endif  // SRC_GAMES_HALOCAMPAIGNEVOLVED_COMMON_HLSLI_
