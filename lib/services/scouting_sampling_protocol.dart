/// Sampling dimensions are tied to the assessment, never to a global UI count.
/// Retired records retain their original dimensions for stored history.
abstract final class ScoutingSamplingProtocol {
  static const daVersion = 'wormwise-da-scattered-20-v1';
  static const retiredFiveStationVersion = 'wormwise-maize-faw-2026.1-draft';
  static const daPattern = 'da_scattered_20';
  static const daAlgorithm = 'da_manual_scattered_points_walk_v2';
  static const plantsPerBlock = 20;
  static const edgeMarginMeters = 3.0;

  static bool isDa(String version) => version == daVersion;
  static bool isRetired(String version, {String? pattern}) =>
      version == retiredFiveStationVersion ||
      pattern == 'w' ||
      pattern == 'ladder';
  static int locationCount(String version) => isDa(version) ? 20 : 5;
  static int plantsPerLocation(String version) => isDa(version) ? 1 : 10;
}
