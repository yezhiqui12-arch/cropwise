import '../../data/local/database_codes.dart';
import '../../data/repositories/advisor_context_repository.dart';
import 'advisor_knowledge_service.dart';
import 'advisor_assessment_contract.dart';
import '../../models/da_severity.dart';

class AdvisorAssessmentExplanationService {
  const AdvisorAssessmentExplanationService();

  AdvisorAnswer explainField(AdvisorFieldContextSnapshot? context) {
    if (context == null) {
      return const AdvisorAnswer(
        topicId: 'field_context',
        title: 'No maize field is selected',
        summary:
            'Add or select a field before asking for field-specific context. General scouting guidance is still available offline.',
        details: [],
        nextAction: 'Open Home or Assess to add or select a maize field.',
        source: _localDataSource,
      );
    }

    final assessment = context.assessment;
    return AdvisorAnswer(
      topicId: 'field_context',
      title: context.fieldName,
      summary: assessment == null
          ? 'This field is saved on this phone, but it has no assessment to explain yet.'
          : 'The latest saved assessment is ${_statusLabel(assessment.status)} at growth stage ${_growthStageLabel(assessment.growthStage)}.',
      details: [
        if (context.barangay != null) 'Barangay: ${context.barangay}',
        if (context.areaHectares != null)
          'Recorded area: ${_decimal(context.areaHectares!)} hectares',
        if (context.varietyName != null)
          'Maize variety: ${context.varietyName}',
        if (context.plantingDate != null)
          'Planting date: ${_date(context.plantingDate!)}',
        'Field outline: ${context.hasConfirmedOutline ? 'confirmed approximate outline' : 'not yet confirmed'}',
        if (assessment != null)
          'Recorded progress: ${assessment.stationRecords} station records and ${assessment.plantRecords} plant records',
      ],
      nextAction: assessment == null
          ? 'Open Assess to set up an assessment.'
          : assessment.isCompleted
          ? 'Ask “Explain my latest assessment” to review its stored results.'
          : 'Open Assess to continue the saved assessment.',
      source: _localDataSource,
    );
  }

  AdvisorAnswer explainAssessment(AdvisorFieldContextSnapshot? context) {
    if (context == null) return explainField(null);
    final assessment = context.assessment;
    if (assessment == null) {
      return AdvisorAnswer(
        topicId: 'assessment_explanation',
        title: 'No assessment is available to explain',
        summary:
            '${context.fieldName} is selected, but no saved assessment was found for its active crop cycle.',
        details: const [],
        nextAction: 'Open Assess to set up an assessment.',
        source: _localDataSource,
      );
    }

    final screen = assessment.findingSummary['automatic_damage_screen'] as Map?;
    final eligible = screen?['eligible_count'] as int? ?? 0;
    final positive = screen?['positive_count'] as int? ?? 0;
    final expert = AdvisorAssessmentContract.finalized(assessment.expertReview);
    final details = <String>[
      'Status: ${_statusLabel(assessment.status)}',
      'Growth stage: ${_growthStageLabel(assessment.growthStage)}${assessment.growthStageUncertain ? ' (recorded as uncertain)' : ''}',
      'Sampling: ${assessment.sampling['method']}${assessment.sampling['plants_per_block'] == null ? '' : ' · ${assessment.sampling['plants_per_block']} plants per block of at most 1 hectare'}',
      'Progress: ${assessment.completedBlocks}/${assessment.totalBlocks} blocks complete; ${assessment.stationRecords} station records; ${assessment.plantRecords} plant records',
      if (assessment.weatherContext?.trim().isNotEmpty == true)
        'Recorded weather context: ${assessment.weatherContext!.trim()}',
      if (eligible > 0)
        'Model 1 damage screening: $positive of $eligible successfully screened plants were positive (${_decimal(100 * positive / eligible)}%); ${eligible - positive} were negative. This is sampled model-detected damage, not confirmed active infestation.',
      if (eligible == 0 && assessment.plantRecords > 0)
        'Saved Model 1 results are unavailable for these records. This does not establish that the model was never run, and no screening rate can be calculated.',
      if ((screen?['missing_result_count'] as int? ?? 0) > 0)
        'Plants without saved model output: ${screen!['missing_result_count']}',
      if ((screen?['stale_result_count'] as int? ?? 0) > 0)
        'Plants whose saved output no longer matches their evidence: ${screen!['stale_result_count']}',
      if (expert != null) daSeverityExplanation,
      'Canonical evidence photos: ${assessment.evidencePhotoCount}',
      if (expert != null && expert['mean_davis_score'] is num)
        'DA severity classification: ${daSeverityClassification(expert['mean_davis_score'] as num)}; mean Davis ${_decimal((expert['mean_davis_score'] as num).toDouble())}/9 across ${expert['scored_plants']} scored plants, including zero scores',
      '${expert == null ? 'Provisional sampled infestation' : 'Current sampled infestation'}: ${assessment.sampledInfestation['case_label']} (${assessment.sampledInfestation['source']}); ${assessment.sampledInfestation['eligible_count']} assessable plants${assessment.sampledInfestation['percent'] == null ? '' : ', ${_decimal((assessment.sampledInfestation['percent'] as num).toDouble())}%'}',
    ];

    return AdvisorAnswer(
      topicId: 'assessment_explanation',
      title: assessment.isCompleted
          ? 'Latest completed assessment'
          : 'Assessment in progress',
      summary: assessment.isCompleted
          ? 'This explanation uses saved CV model findings and sample coverage for ${context.fieldName}. It describes the record; it is not a treatment recommendation.'
          : 'This assessment is not complete. The counts below describe saved progress and must not be interpreted as final field results.',
      details: details,
      nextAction: assessment.isCompleted
          ? 'Use these results with qualified local guidance before making a consequential management decision.'
          : 'Open Assess to complete the remaining fieldwork.',
      source: AdvisorKnowledgeSource(
        label: 'Recorded assessment data',
        reference: 'Saved locally for ${context.fieldName}',
        version:
            '${assessment.protocolVersion} · formula ${assessment.formulaVersion}',
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    DatabaseCodes.completed => 'completed',
    DatabaseCodes.inProgress => 'in progress',
    DatabaseCodes.safetyBlocked => 'blocked pending field-entry safety review',
    DatabaseCodes.draft => 'saved as a draft',
    DatabaseCodes.incomplete => 'incomplete',
    _ => status.replaceAll('_', ' '),
  };

  static String _growthStageLabel(String stage) => switch (stage) {
    've' => 'VE',
    'v1' => 'V1',
    'v2' => 'V2',
    'v3_v6' => 'V3-V6',
    'v7_v12' => 'V7-V12',
    'vt_r2' => 'VT-R2',
    'r3_r6' => 'R3-R6',
    _ => stage.toUpperCase().replaceAll('_', '-'),
  };

  static String _decimal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static const _localDataSource = AdvisorKnowledgeSource(
    label: 'Recorded field data',
    reference: 'Saved on this phone',
    version: 'read-only local context v1',
  );
}
