/// Classification wording supplied in the DA Davis reference.
/// Decimal intervals are WormWise display bands around reference grades 1/3/5/7/9.
/// These labels describe Davis severity, never a sampled-infestation percentage.
class DaSeverityBand {
  const DaSeverityBand(this.maximum, this.range, this.label, this.color);
  final double maximum;
  final String range;
  final String label;
  final int color;
  int get referenceRating => maximum.toInt();
  String get referenceDescription => switch (referenceRating) {
    1 => 'No visible leaf injury.',
    3 =>
      'Small circular lesions and a few elongated rectangular lesions up to 2.5 cm on whorl and middle leaves.',
    5 =>
      'Several large elongated lesions over 2.5 cm and/or a few irregular holes eaten through whorl and middle leaves.',
    7 =>
      'Many elongated lesions of all sizes and many irregular holes eaten through whorl and middle leaves.',
    9 => 'Whorl and middle leaves almost totally destroyed.',
    _ => '',
  };
  int get textColor => maximum == 5
      ? 0xff4d7c0f
      : maximum == 7
      ? 0xffa16207
      : color;
}

const daSeverityBands = <DaSeverityBand>[
  DaSeverityBand(1, '0–1', 'No infestation', 0xff15803d),
  DaSeverityBand(3, '>1–3', 'Light infestation', 0xff0284c7),
  DaSeverityBand(5, '>3–5', 'Moderate infestation', 0xffa3c914),
  DaSeverityBand(7, '>5–7', 'Severe infestation', 0xffeab308),
  DaSeverityBand(9, '>7–9', 'Highly severe', 0xffdc2626),
];

DaSeverityBand? daSeverityBand(num? score) {
  if (score == null || !score.isFinite || score < 0 || score > 9) return null;
  return daSeverityBands.firstWhere((band) => score <= band.maximum);
}

String daSeverityClassification(num? score) =>
    daSeverityBand(score)?.label ?? 'Unavailable';

const daSeverityExplanation =
    'The DA Davis classification describes visible leaf-damage severity. '
    'Damage incidence includes old damage. Current sampled infestation uses '
    'expert-assessed signs of current feeding at the assessment date. '
    'A Davis classification is not an infestation percentage or confirmation of pest absence.';

const daSeverityBandExplanation =
    'Classification wording follows the supplied DA reference. Decimal intervals '
    'are Cropwise display bands around reference ratings 1, 3, 5, 7 and 9.';

const daFormulaExplanation =
    'For a complete block of 20 plants: FAW damage incidence = damaged plants / 20 × 100; '
    'current sampled infestation = plants with current feeding signs / 20 × 100; '
    'mean Davis = sum of all 20 scores / 20. For multiple complete blocks, use '
    '20 × number of blocks. Historical partial findings use their recorded '
    'scored/assessable counts; missing evidence is never counted as unaffected.';

const daReferenceSource =
    'FAW descriptions follow the supplied DA reference table, labeled Davis Scale. '
    'Descriptions refer to reference ratings 1, 3, 5, 7 and 9; they are not '
    'additional observations or lesion measurements from the exported photos.';
