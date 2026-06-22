Texture2D<float4> srv2DTextures[65536] : register(t0, space1);

cbuffer cbTaaConstants : register(b0) {
  float4 tcHistoryTexelSize : packoffset(c000.x);
  float4 tcTargetTexelSize : packoffset(c001.x);
  float4 tcSourceTexelSize : packoffset(c002.x);
  float4 tcVelocityTexelSize : packoffset(c003.x);
  float4 tcJitterOffset : packoffset(c004.x);
  float tcBlendValue : packoffset(c005.x);
  float tcVariableBlending : packoffset(c005.y);
  float tcDepthOcclusion : packoffset(c005.z);
  float tcTransparentsMasking : packoffset(c005.w);
  float tcAntiFlicker : packoffset(c006.x);
  float tcHistorySharpness : packoffset(c006.y);
  int tcZoneClip : packoffset(c006.z);
  int tcDebugMode : packoffset(c006.w);
  float2 tcWindowSize : packoffset(c007.x);
  float2 tcWindowOffset : packoffset(c007.z);
  float2 tcInverseWindowSize : packoffset(c008.x);
  float2 tcScaledWindowOffset : packoffset(c008.z);
  uint4 tcVelocityBounds : packoffset(c009.x);
  int2 tcPixelOffset : packoffset(c010.x);
  uint2 tcPixelSize : packoffset(c010.z);
  int4 tcWindowClamp : packoffset(c011.x);
  uint texIndexDepth : packoffset(c012.x);
  uint texIndexVelocity : packoffset(c012.y);
  uint texIndexPresent : packoffset(c012.z);
  uint texIndexHistory : packoffset(c012.w);
  uint texIndexHistoryAux : packoffset(c013.x);
  uint texIndexCompressedDepth : packoffset(c013.y);
  uint texIndexStencil : packoffset(c013.z);
  uint uavIndexVelocity : packoffset(c013.w);
  uint uavIndexOutColor : packoffset(c014.x);
  uint uavIndexOutAux : packoffset(c014.y);
  uint uavIndexOutDebug : packoffset(c014.z);
  uint uavIndexCompressedDepth : packoffset(c014.w);
  float compressionScale : packoffset(c015.x);
  float tcAntiFlickerHistoryBias : packoffset(c015.y);
  float ditheredBlendValue : packoffset(c015.z);
  float ditheredAntiflicker : packoffset(c015.w);
  int ditheredZoneclip : packoffset(c016.x);
  uint texIndexDofTileData : packoffset(c016.y);
  float2 tileTexCoordMult : packoffset(c016.z);
  float dofHistoryDepthTolerance : packoffset(c017.x);
  float tcMovingBlendValue : packoffset(c017.y);
  float tcOccludedBlendValue : packoffset(c017.z);
  float tcMovingOccludedBlendValue : packoffset(c017.w);
  float velocityThresholdStart : packoffset(c018.x);
  float velocityThresholdRangeInv : packoffset(c018.y);
  float imageAspectRatio : packoffset(c018.z);
  float taaFovChange : packoffset(c018.w);
};

SamplerState g_staticSampler_BilinearClamp : register(s18);

// DXIL FirstbitHi: returns bit position counting from MSB (leading zeros count)
uint firstbithigh_msb(int value) { return (value == 0) ? 0xFFFFFFFF : (31u - firstbithigh(value)); }
uint firstbithigh_msb(uint value) { return (value == 0) ? 0xFFFFFFFF : (31u - firstbithigh(value)); }

static const float3 kLumaWeights = float3(0.3086000084877014f, 0.6093999743461609f, 0.0820000022649765f);

uint GetBindlessTextureIndex(uint packedIndex) {
  return (uint)(select(((packedIndex & -1048576) == -1018167296), (packedIndex & 1048575), 17)) + 0u;
}

float Luma(float3 color) {
  return dot(color, kLumaWeights);
}

float3 CatmullRomCross(float3 center, float3 up, float3 right, float3 down, float3 left,
                       float3 rightUp, float3 rightDown, float3 leftDown, float3 leftUp,
                       float2 halfOneMinusSquared, float2 halfFracSquared, float2 centerWeight) {
  float3 middleRow = (right * halfFracSquared.x) + (center * centerWeight.x) + (left * halfOneMinusSquared.x);
  float3 topRow = (leftUp * halfOneMinusSquared.x) + (rightUp * halfFracSquared.x) + (up * centerWeight.x);
  float3 bottomRow = (leftDown * halfOneMinusSquared.x) + (rightDown * halfFracSquared.x) + (down * centerWeight.x);
  return (middleRow * centerWeight.y) + (topRow * halfFracSquared.y) + (bottomRow * halfOneMinusSquared.y);
}

float3 CubicCross(float3 center, float3 up, float3 right, float3 down, float3 left,
                  float3 rightUp, float3 rightDown, float3 leftDown, float3 leftUp,
                  float2 oneMinusCubic, float2 fracCubic, float2 centerWeight) {
  float3 middleRow = (right * fracCubic.x) + (center * centerWeight.x) + (left * oneMinusCubic.x);
  float3 topRow = (leftUp * oneMinusCubic.x) + (rightUp * fracCubic.x) + (up * centerWeight.x);
  float3 bottomRow = (leftDown * oneMinusCubic.x) + (rightDown * fracCubic.x) + (down * centerWeight.x);
  return (middleRow * centerWeight.y) + (topRow * fracCubic.y) + (bottomRow * oneMinusCubic.y);
}

void ProjectHistoryToNeighbor(float3 centerColor, float3 historyColor, float3 neighborColor,
                              float clipRadius, float clipSoftening,
                              out float3 projectedColor, out float distanceSq) {
  float3 colorDelta = neighborColor - centerColor;
  float deltaLengthSq = dot(colorDelta, colorDelta);
  float projectionT = 0.0f;

  if (deltaLengthSq > 9.999999747378752e-06f) {
    projectionT = min(max(dot(colorDelta, historyColor - centerColor) * asfloat(2129859010 - asint(deltaLengthSq)), (-0.0f - clipRadius)), (clipSoftening + 4.0f));
  }

  projectedColor = (projectionT * colorDelta) + centerColor;
  float3 historyDelta = projectedColor - historyColor;
  distanceSq = dot(historyDelta, historyDelta);
}

struct OutputSignature {
  float4 SV_Target : SV_Target;
  float4 SV_Target_1 : SV_Target1;
};

OutputSignature main(
  precise noperspective float4 SV_Position : SV_Position,
  linear float2 TEXCOORD : TEXCOORD
) {
  const uint velocityTex = GetBindlessTextureIndex(texIndexVelocity);
  const uint presentTex = GetBindlessTextureIndex(texIndexPresent);
  const uint historyTex = GetBindlessTextureIndex(texIndexHistory);
  const uint historyAuxTex = GetBindlessTextureIndex(texIndexHistoryAux);
  const uint compressedDepthTex = GetBindlessTextureIndex(texIndexCompressedDepth);

  int2 targetPixel = int2(int(tcTargetTexelSize.z * TEXCOORD.x), int(tcTargetTexelSize.w * TEXCOORD.y));
  float2 targetUv = (float2(targetPixel) + 0.5f) * tcTargetTexelSize.xy;

  int2 initialVelocityPixel = int2(
    int((float(targetPixel.x) * tcTargetTexelSize.x) * tcSourceTexelSize.z),
    int((float(targetPixel.y) * tcTargetTexelSize.y) * tcSourceTexelSize.w)
  );
  float4 initialVelocity = srv2DTextures[velocityTex].Load(int3(initialVelocityPixel, 0));

  float transparentMask = select((initialVelocity.w == 0.0f), initialVelocity.z, 0.0f);
  bool isSkyPixel = (initialVelocity.w == 1.0f);

  float2 unjitteredUv = targetUv - ((1.0f - transparentMask) * tcJitterOffset.xy);
  int2 sourcePixel = min(max(int2(unjitteredUv * tcSourceTexelSize.zw), tcWindowClamp.xy), tcWindowClamp.zw);

  float3 currentColor = srv2DTextures[presentTex].Load(int3(sourcePixel, 0)).rgb;
  float currentLuma = Luma(currentColor);

  float3 upColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(0, 1), 0)).rgb;
  float upLuma = Luma(upColor);

  float3 rightColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(1, 0), 0)).rgb;
  float rightLuma = Luma(rightColor);

  float3 downColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(0, -1), 0)).rgb;
  float downLuma = Luma(downColor);

  float3 leftColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(-1, 0), 0)).rgb;
  float leftLuma = Luma(leftColor);

  float3 rightUpColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(1, 1), 0)).rgb;
  float3 rightDownColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(1, -1), 0)).rgb;
  float3 leftDownColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(-1, -1), 0)).rgb;
  float3 leftUpColor = srv2DTextures[presentTex].Load(int3(sourcePixel + int2(-1, 1), 0)).rgb;

  float2 sourceTexelPosition = tcSourceTexelSize.zw * unjitteredUv;
  float2 sourceFrac = sourceTexelPosition - floor(sourceTexelPosition);
  float2 sourceOneMinusFrac = 1.0f - sourceFrac;

  float2 oneMinusSquared = sourceOneMinusFrac * sourceOneMinusFrac;
  float2 halfOneMinusSquared = oneMinusSquared * 0.5f;
  float2 oneMinusCubic = halfOneMinusSquared * sourceOneMinusFrac;

  float2 fracSquared = sourceFrac * sourceFrac;
  float2 halfFracSquared = fracSquared * 0.5f;
  float2 fracCubic = halfFracSquared * sourceFrac;

  float2 cubicCenterWeight = (1.0f - fracCubic) - oneMinusCubic;
  float2 catmullCenterWeight = 1.0f - ((oneMinusSquared + fracSquared) * 0.5f);

  float3 smoothCurrentColor = CatmullRomCross(
    currentColor, upColor, rightColor, downColor, leftColor,
    rightUpColor, rightDownColor, leftDownColor, leftUpColor,
    halfOneMinusSquared, halfFracSquared, catmullCenterWeight
  );

  float4 velocityPacked = srv2DTextures[velocityTex].Load(int3(sourcePixel, 0));
  bool hasDitheredSurface = (velocityPacked.w == 0.3333333432674408f);
  bool useAuxDepthWithoutVelocity = isSkyPixel || (int)(velocityPacked.z == 0.0f);

  float4 compressedDepth = srv2DTextures[compressedDepthTex].Load(int3(sourcePixel, 0));

  float2 signedVelocity = (velocityPacked.xy * 1023.0f) + -512.0f;
  float2 absVelocity = abs(signedVelocity);
  float2 decodedVelocityUv = asfloat(asint((absVelocity * absVelocity) * 0.0009765625f) | (asint(signedVelocity) & -2147483648)) * tcVelocityTexelSize.xy;

  float velocityPixels = max(abs(decodedVelocityUv.x * tcSourceTexelSize.z), abs(decodedVelocityUv.y * tcSourceTexelSize.w));
  float2 historyUv = targetUv + decodedVelocityUv;

  float4 historyCenter = srv2DTextures[historyTex].SampleLevel(g_staticSampler_BilinearClamp, historyUv, 0.0f);
  float historyCenterLuma = Luma(historyCenter.rgb);

  float2 historySharpnessWeight = abs(frac(tcHistoryTexelSize.zw * historyUv) + -0.5f) * tcHistorySharpness;
  float4 historyUp = srv2DTextures[historyTex].SampleLevel(g_staticSampler_BilinearClamp, float2(historyUv.x, tcHistoryTexelSize.y + historyUv.y), 0.0f);
  float4 historyDown = srv2DTextures[historyTex].SampleLevel(g_staticSampler_BilinearClamp, float2(historyUv.x, historyUv.y - tcHistoryTexelSize.y), 0.0f);
  float4 historyRight = srv2DTextures[historyTex].SampleLevel(g_staticSampler_BilinearClamp, float2(tcHistoryTexelSize.x + historyUv.x, historyUv.y), 0.0f);
  float4 historyLeft = srv2DTextures[historyTex].SampleLevel(g_staticSampler_BilinearClamp, float2(historyUv.x - tcHistoryTexelSize.x, historyUv.y), 0.0f);

  float3 sharpenedHistoryColor = (((historyCenter.rgb - ((historyLeft.rgb + historyRight.rgb) * 0.5f)) * historySharpnessWeight.x) +
                                  ((historyCenter.rgb - ((historyDown.rgb + historyUp.rgb) * 0.5f)) * historySharpnessWeight.y) +
                                  (historyCenter.rgb * 2.0f)) * 0.5f;

  float4 historyAux = srv2DTextures[historyAuxTex].SampleLevel(g_staticSampler_BilinearClamp, historyUv, 0.0f);
  bool hasAuxHistory = (historyAux.w > 0.0f);
  bool useDitheredHistoryControls = hasDitheredSurface || hasAuxHistory;

  float currentAxisContrast = min(min(abs(rightLuma - currentLuma), abs(leftLuma - currentLuma)), abs(currentLuma - ((leftLuma + rightLuma) * 0.5f)));
  float currentVerticalContrast = min(min(abs(upLuma - currentLuma), abs(downLuma - currentLuma)), abs(currentLuma - ((downLuma + upLuma) * 0.5f)));
  float historyAxisContrast = min(abs(Luma(historyUp.rgb) - historyCenterLuma), abs(Luma(historyDown.rgb) - historyCenterLuma)) +
                              min(abs(Luma(historyRight.rgb) - historyCenterLuma), abs(Luma(historyLeft.rgb) - historyCenterLuma));
  float antiFlickerAmount = saturate((abs(currentAxisContrast - currentVerticalContrast) - (tcAntiFlickerHistoryBias * historyAxisContrast)) *
                                     select(useDitheredHistoryControls, ditheredAntiflicker, tcAntiFlicker));

  bool missingVelocity = (int)((int)(velocityPacked.x == 0.0f) || (int)(velocityPacked.y == 0.0f));
  bool reprojectedOutsideWindow = max(abs((tcInverseWindowSize.x * historyUv.x) + tcScaledWindowOffset.x), abs((tcInverseWindowSize.y * historyUv.y) + tcScaledWindowOffset.y)) > 0.5f;
  float baseBlend = min(1.0f, select((missingVelocity || (int)reprojectedOutsideWindow), 1.0f, select(useDitheredHistoryControls, ditheredBlendValue, tcBlendValue)) + taaFovChange);

  float depthOcclusionAmount = select(hasAuxHistory, 0.0f, tcDepthOcclusion);
  float historyDepth = select(useAuxDepthWithoutVelocity, historyAux.z, (historyAux.z + ((velocityPacked.z + -0.5004887580871582f) * 0.03125f)));
  float depthOcclusionThreshold = (select(useAuxDepthWithoutVelocity, (depthOcclusionAmount * 8.0f), depthOcclusionAmount) * compressedDepth.x) + 0.0009765625f;
  float resolvedBlend = baseBlend;

  if ((int)(transparentMask == 0.0f) && (int)(depthOcclusionAmount > 0.0f)) {
    if ((historyDepth - compressedDepth.x) > depthOcclusionThreshold) {
      resolvedBlend = 1.0f;
    }
  }

  float maskedBlend;
  float historyMask;
  if (!isSkyPixel) {
    historyMask = max(transparentMask, historyAux.y);
    maskedBlend = (historyMask * (1.0f - resolvedBlend)) + resolvedBlend;
  } else {
    maskedBlend = resolvedBlend;
    historyMask = 0.0f;
  }

  float blendFactor;
  float3 outputColor;

  if (!((int)(resolvedBlend == 1.0f) && (int)(historyMask < 0.5f))) {
    float clipSoftening = saturate((velocityPixels + -1.0f) * 0.5f) * -2.0f;
    float clipRadius = clipSoftening + 3.0f;
    float3 clippedHistoryColor;

    if ((int)(ditheredZoneclip == 1) || ((int)(!useDitheredHistoryControls))) {
      float3 minCross = min(currentColor, min(min(min(upColor, rightColor), downColor), leftColor));
      float3 maxCross = max(currentColor, max(max(max(upColor, rightColor), downColor), leftColor));

      float3 maxBox = max(maxCross, max(max(max(rightUpColor, rightDownColor), leftDownColor), leftUpColor));
      float3 minBox = min(minCross, min(min(min(rightUpColor, rightDownColor), leftDownColor), leftUpColor));

      float3 centerCross = (maxCross + minCross) * 0.5f;
      float3 extentCross = (maxCross - centerCross) * clipRadius;

      float3 centerBox = (maxBox + minBox) * 0.5f;
      float3 extentBox = (maxBox - centerBox) * clipRadius;

      float3 clippedCross = min(max(sharpenedHistoryColor, centerCross - extentCross), centerCross + extentCross);
      float3 clippedBox = min(max(sharpenedHistoryColor, centerBox - extentBox), centerBox + extentBox);

      clippedHistoryColor = ((clippedBox - clippedCross) * 0.6000000238418579f) + clippedCross;
    } else {
      if (ditheredZoneclip == 2) {
        float3 projectedUp;
        float projectedUpDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, upColor, clipRadius, clipSoftening, projectedUp, projectedUpDistance);

        float3 projectedRight;
        float projectedRightDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, rightColor, clipRadius, clipSoftening, projectedRight, projectedRightDistance);

        bool upIsCloserThanRight = (projectedUpDistance < projectedRightDistance);
        float3 bestCardinalA = select(upIsCloserThanRight, projectedUp, projectedRight);
        float bestCardinalADistance = select(upIsCloserThanRight, projectedUpDistance, projectedRightDistance);

        float3 projectedDown;
        float projectedDownDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, downColor, clipRadius, clipSoftening, projectedDown, projectedDownDistance);

        float3 projectedLeft;
        float projectedLeftDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, leftColor, clipRadius, clipSoftening, projectedLeft, projectedLeftDistance);

        bool downIsCloserThanLeft = (projectedDownDistance < projectedLeftDistance);
        float3 bestCardinalB = select(downIsCloserThanLeft, projectedDown, projectedLeft);
        float bestCardinalBDistance = select(downIsCloserThanLeft, projectedDownDistance, projectedLeftDistance);

        bool cardinalAIsCloser = (bestCardinalADistance < bestCardinalBDistance);
        float3 bestCardinal = select(cardinalAIsCloser, bestCardinalA, bestCardinalB);
        float bestCardinalDistance = select(cardinalAIsCloser, bestCardinalADistance, bestCardinalBDistance);

        float3 projectedRightUp;
        float projectedRightUpDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, rightUpColor, clipRadius, clipSoftening, projectedRightUp, projectedRightUpDistance);

        float3 projectedRightDown;
        float projectedRightDownDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, rightDownColor, clipRadius, clipSoftening, projectedRightDown, projectedRightDownDistance);

        bool rightUpIsCloserThanRightDown = (projectedRightUpDistance < projectedRightDownDistance);
        float3 bestDiagonalA = select(rightUpIsCloserThanRightDown, projectedRightUp, projectedRightDown);
        float bestDiagonalADistance = select(rightUpIsCloserThanRightDown, projectedRightUpDistance, projectedRightDownDistance);

        float3 projectedLeftDown;
        float projectedLeftDownDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, leftDownColor, clipRadius, clipSoftening, projectedLeftDown, projectedLeftDownDistance);

        float3 projectedLeftUp;
        float projectedLeftUpDistance;
        ProjectHistoryToNeighbor(currentColor, sharpenedHistoryColor, leftUpColor, clipRadius, clipSoftening, projectedLeftUp, projectedLeftUpDistance);

        bool leftDownIsCloserThanLeftUp = (projectedLeftDownDistance < projectedLeftUpDistance);
        float3 bestDiagonalB = select(leftDownIsCloserThanLeftUp, projectedLeftDown, projectedLeftUp);
        float bestDiagonalBDistance = select(leftDownIsCloserThanLeftUp, projectedLeftDownDistance, projectedLeftUpDistance);

        bool diagonalAIsCloser = (bestDiagonalADistance < bestDiagonalBDistance);
        float3 bestDiagonal = select(diagonalAIsCloser, bestDiagonalA, bestDiagonalB);
        float bestDiagonalDistance = select(diagonalAIsCloser, bestDiagonalADistance, bestDiagonalBDistance);

        bool keepCardinalOnly = (bestCardinalDistance < (((bestDiagonalDistance - bestCardinalDistance) * 0.6000000238418579f) + bestCardinalDistance));
        clippedHistoryColor = select(keepCardinalOnly, bestCardinal, (((bestDiagonal - bestCardinal) * 0.6000000238418579f) + bestCardinal));
      } else {
        clippedHistoryColor = sharpenedHistoryColor;
      }
    }

    float historyClipBlend;
    if (historyMask == 0.0f) {
      historyClipBlend = max(saturate((max(max(abs(clippedHistoryColor.x - sharpenedHistoryColor.x), abs(clippedHistoryColor.y - sharpenedHistoryColor.y)), abs(clippedHistoryColor.z - sharpenedHistoryColor.z)) * 30.0f) + maskedBlend),
                             (asfloat(2129859010 - asint(historyAux.x + 1.0f)) * historyAux.x));
    } else {
      historyClipBlend = maskedBlend;
    }

    if (historyClipBlend < 1.0f) {
      blendFactor = (1.0f - saturate(((velocityPixels * 0.03500000014901161f) * antiFlickerAmount) + antiFlickerAmount)) * historyClipBlend;
    } else {
      blendFactor = historyClipBlend;
    }

    float3 currentBlendColor;
    if (!(blendFactor > 0.5f)) {
      if (blendFactor > 0.20000000298023224f) {
        currentBlendColor = CubicCross(
          currentColor, upColor, rightColor, downColor, leftColor,
          rightUpColor, rightDownColor, leftDownColor, leftUpColor,
          oneMinusCubic, fracCubic, cubicCenterWeight
        );
      } else {
        currentBlendColor = currentColor;
      }
    } else {
      currentBlendColor = smoothCurrentColor;
    }

    outputColor = (currentBlendColor * blendFactor) + ((1.0f - blendFactor) * clippedHistoryColor);
  } else {
    blendFactor = maskedBlend;
    outputColor = smoothCurrentColor;
  }

  float auxOutputW = select(hasDitheredSurface, 1.0099999904632568f, (historyAux.w + -0.33000001311302185f));

  OutputSignature readableOutput;
  readableOutput.SV_Target = float4(outputColor, max(auxOutputW, 0.0f) + ((blendFactor * blendFactor) * 3.0f));
  readableOutput.SV_Target_1 = float4(blendFactor, transparentMask, compressedDepth.y + 0.0004887585528194904f, auxOutputW);
  return readableOutput;
}