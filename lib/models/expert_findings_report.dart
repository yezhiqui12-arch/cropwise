import 'assessment_history_models.dart';
import 'da_assessment_results.dart';
import 'sampled_infestation.dart';
import 'da_severity.dart';
import '../services/cloud/expert_review_service.dart';

ExpertReviewCase? finalizedCaseForAssessment(
  String assessmentId,
  Iterable<ExpertReviewCase> cases,
) {
  final matches =
      cases
          .where(
            (c) => c.assessmentId == assessmentId && c.severitySummary != null,
          )
          .toList()
        ..sort(
          (a, b) => b.severitySummary!.finalizedAt.compareTo(
            a.severitySummary!.finalizedAt,
          ),
        );
  return matches.firstOrNull;
}

/// A report contains uniquely matched finalized findings, never draft grades.
class ExpertFindingsReport {
  ExpertFindingsReport({
    required this.detail,
    required this.review,
    required List<ExpertPlantRating> ratings,
    List<ExpertMessage>? guidance,
  }) {
    final summary = review.severitySummary;
    if (review.assessmentId != detail.assessment.id || summary == null) {
      throw StateError(
        'The expert review has not been finalized for this assessment.',
      );
    }
    sample = DaSampleResults.fromDetail(detail);
    findings = DaExpertResults.fromRatings(
      sample: sample,
      summary: summary,
      ratings: ratings,
    );
    if (!findings.available ||
        summary.reviewedPlants <= 0 ||
        ratings.any((r) => r.associationAmbiguous)) {
      throw StateError(
        'Finalized findings could not be matched to the sampled plants.',
      );
    }
    for (final rating in findings.byLocation.values) {
      if (rating.outcome == 'scored') distribution[rating.davisScore!]++;
    }
    infestation = DaSampledInfestation(
      sample,
      finalized: true,
      expert: findings,
    );
    if (summary.monitoring['reporting_version'] == 3 && !completeCoverage) {
      throw StateError(
        'Complete all 20 plants per block before exporting final findings.',
      );
    }
    final reviewerIds = {review.expertId, summary.monitoring['finalized_by']}
      ..remove(null);
    responses =
        (guidance ?? review.messages)
            .where(
              (m) =>
                  reviewerIds.contains(m.senderId) &&
                  m.severityCaseId == null &&
                  m.body.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final finalizedDistribution = summary.monitoring['score_distribution'];
    if (finalizedDistribution is List &&
        (finalizedDistribution.length != 10 ||
            List.generate(
              10,
              (i) => i,
            ).any((i) => finalizedDistribution[i] != distribution[i]))) {
      throw StateError(
        'Ratings do not match the finalized score distribution.',
      );
    }
  }
  final AssessmentHistoryDetail detail;
  final ExpertReviewCase review;
  late final DaSampleResults sample;
  late final DaExpertResults findings;
  late final DaSampledInfestation infestation;
  late final List<ExpertMessage> responses;
  bool get completeCoverage =>
      sample.expectedPlants > 0 &&
      findings.scoredPlants == sample.expectedPlants &&
      infestation.assessable == sample.expectedPlants;
  String get classification => daSeverityClassification(findings.mean);
  int get scoreTotal => List.generate(
    10,
    (score) => score * distribution[score],
  ).fold(0, (sum, value) => sum + value);
  int get plantsRatedSevenToNine =>
      distribution.skip(7).fold(0, (sum, count) => sum + count);
  List<ExpertPlantRating> get highestRatedPlants {
    final blockSequence = {
      for (final plant in sample.plants)
        findings.ratingFor(plant)?.identityKey:
            plant.prepared.run.blockSequence,
    };
    final scored =
        findings.byLocation.values
            .where(
              (rating) =>
                  rating.outcome == 'scored' && (rating.davisScore ?? 0) > 0,
            )
            .toList()
          ..sort((a, b) {
            final score = b.davisScore!.compareTo(a.davisScore!);
            if (score != 0) return score;
            final block = (blockSequence[a.identityKey] ?? 0).compareTo(
              blockSequence[b.identityKey] ?? 0,
            );
            if (block != 0) return block;
            final station = a.stationNumber.compareTo(b.stationNumber);
            return station != 0
                ? station
                : a.plantNumber.compareTo(b.plantNumber);
          });
    return scored.take(3).toList();
  }

  DateTime get assessedAt =>
      DateTime.tryParse(
        '${review.severitySummary?.monitoring['assessed_at']}',
      ) ??
      detail.assessment.completedAt ??
      detail.assessment.startedAt ??
      detail.assessment.createdAt;

  final List<int> distribution = List.filled(10, 0);
  String get reviewerName {
    final savedName = review.severitySummary?.monitoring['reviewer_name'];
    if (savedName is String && savedName.trim().isNotEmpty) {
      return savedName.trim();
    }
    return review.expertName?.trim().isNotEmpty == true
        ? review.expertName!.trim()
        : 'Name not recorded';
  }

  int get damagedPlants => distribution.skip(1).fold(0, (a, b) => a + b);
  double? get damageIncidence => findings.scoredPlants == 0
      ? null
      : damagedPlants / findings.scoredPlants * 100;
}
