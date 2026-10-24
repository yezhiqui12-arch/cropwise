import 'dart:math' as math;

/// Product limits and workload calculations for formal field assessments.
///
/// A field may be larger than a single sampling block, but the protocol keeps
/// each block at no more than one hectare. The total-area ceiling is an
/// operational product limit and can be revised independently after field
/// validation.
abstract final class AssessmentAreaPolicy {
  static const double maxBlockAreaHectares = 1.0;
  static const double maxAssessmentAreaHectares = 5.0;
  static const double areaToleranceHectares = 0.0001;

  static bool isPositive(double areaHectares) => areaHectares > 0;

  static bool isWithinAssessmentLimit(double areaHectares) =>
      isPositive(areaHectares) &&
      areaHectares <= maxAssessmentAreaHectares + areaToleranceHectares;

  static int requiredBlockCount(double areaHectares) {
    if (!isPositive(areaHectares)) return 0;
    return math.max(1, (areaHectares / maxBlockAreaHectares).ceil());
  }

  static bool isValidBlockArea(double areaHectares) =>
      isPositive(areaHectares) &&
      areaHectares <= maxBlockAreaHectares + areaToleranceHectares;
}
