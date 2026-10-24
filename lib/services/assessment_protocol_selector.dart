import 'scouting_sampling_protocol.dart';
import '../data/local/database_codes.dart';

class GrowthStageOption {
  const GrowthStageOption({
    required this.code,
    required this.label,
    required this.help,
  });

  final String code;
  final String label;
  final String help;
}

abstract final class AssessmentProtocolSelector {
  static const growthStages = <GrowthStageOption>[
    GrowthStageOption(
      code: 've',
      label: 'VE - emergence',
      help: 'The shoot is just emerging from the soil.',
    ),
    GrowthStageOption(
      code: 'v1',
      label: 'V1 - one visible leaf collar',
      help:
          'The lowest leaf has one visible collar and usually has a rounded tip.',
    ),
    GrowthStageOption(
      code: 'v2',
      label: 'V2 - two visible leaf collars',
      help:
          'The two lowest leaves have visible collars; the second leaf has a pointed tip.',
    ),
    GrowthStageOption(
      code: 'v3_v6',
      label: 'V3-V6 - three to six leaf collars',
      help:
          'Count from the lowest rounded-tip leaf: three to six leaves have visible collars.',
    ),
    GrowthStageOption(
      code: 'v7_v12',
      label: 'V7-V12 - seven to twelve leaf collars',
      help:
          'Count seven to twelve visible leaf collars. Do not use plant height alone.',
    ),
    GrowthStageOption(
      code: 'vt_r2',
      label: 'VT-R2 - tasseling to blister stage',
      help:
          'VT: the lowest tassel branch is visible. R1: silks extend outside the husk. R2: blister-like kernels contain clear liquid.',
    ),
    GrowthStageOption(
      code: 'r3_r6',
      label: 'R3-R6 - milk stage to maturity',
      help:
          'Open an ear: milky fluid means R3, doughy contents R4, kernel dents R5, and a black layer at the kernel base R6.',
    ),
  ];

  static String assessmentModeFor(String growthStage) {
    return switch (growthStage) {
      've' || 'v1' || 'v2' || 'v3_v6' => DatabaseCodes.modeVeV6,
      'v7_v12' => DatabaseCodes.modeV7V12,
      'vt_r2' => DatabaseCodes.modeVtR2,
      'r3_r6' => DatabaseCodes.modeR3R6,
      _ => throw ArgumentError.value(
        growthStage,
        'growthStage',
        'Unsupported maize growth stage.',
      ),
    };
  }

  static String recommendedPatternFor(String growthStage) =>
      ScoutingSamplingProtocol.daPattern;

  static String growthStageLabel(String code) {
    for (final stage in growthStages) {
      if (stage.code == code) return stage.label;
    }
    return code.toUpperCase();
  }

  static String growthStageHelp(String code) {
    for (final stage in growthStages) {
      if (stage.code == code) return stage.help;
    }
    return '';
  }

  static String patternLabel(String code) {
    return switch (code) {
      ScoutingSamplingProtocol.daPattern => 'DA guided scouting · 20 plants',
      'w' || 'ladder' => 'Outdated scouting method',
      _ => code,
    };
  }

  static String patternHelp(String code) {
    return switch (code) {
      ScoutingSamplingProtocol.daPattern =>
        'Select 20 separate plants spread across the sampling block, at least 3 m from the field edge. Inspect the upper 3–4 leaves and record natural enemies.',
      _ => '',
    };
  }
}
