class ValidationIssue {
  const ValidationIssue(
    this.code,
    this.message, {
    this.stationId,
    this.blockRunId,
    this.stationNumber,
  });

  final String code;
  final String message;
  final String? stationId, blockRunId;
  final int? stationNumber;
  @override
  String toString() => '$code: $message';
}

class BlockValidationResult {
  const BlockValidationResult(this.issues);

  final List<ValidationIssue> issues;
  bool get isValid => issues.isEmpty;
}

class AssessmentValidationException implements Exception {
  const AssessmentValidationException(this.issues);

  final List<ValidationIssue> issues;

  @override
  String toString() => issues.map((issue) => issue.message).join('; ');
}
