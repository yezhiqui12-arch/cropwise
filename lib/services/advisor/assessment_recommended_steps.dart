/// Practical checks from saved facts. These remain available without AI and
/// never turn model indications into confirmed pest findings.
class RecordedAssessmentStep {
  const RecordedAssessmentStep(
    this.title,
    this.description,
    this.type, [
    this.references = const [],
  ]);
  final String title, description, type;
  final List<String> references;
}

List<RecordedAssessmentStep> recommendedAssessmentChecks(
  Map<String, dynamic> facts, {
  required bool entryBlocked,
  int recordIssues = 0,
}) {
  final steps = <RecordedAssessmentStep>[];
  final plants = (facts['plants'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  final expert = facts['finalized_expert_findings'] as Map?;
  List<String> refs(bool Function(Map) predicate) => plants
      .where(predicate)
      .map((p) => p['reference'])
      .whereType<String>()
      .toSet()
      .toList();
  final damage = refs((p) => p['damage_screen'] == 'FAW damage');
  final unscreened = refs((p) => p['damage_screen'] == 'Unavailable');
  final missingPhotos = refs((p) => p['photo_count'] == 0);
  final remaining = facts['remaining_plants'] as num? ?? 0;
  final infestation = facts['sampled_infestation'] as Map? ?? const {};
  final unknown = infestation['unavailable_count'] as num? ?? 0;

  if (entryBlocked) {
    steps.add(
      const RecordedAssessmentStep(
        'Confirm field-entry safety first',
        'Check the saved treatment record and re-entry requirements before returning to the field. You can review existing photos while entry is unconfirmed.',
        'safety_review',
      ),
    );
  }
  if (remaining > 0 || facts['sampling_complete'] == false) {
    steps.add(
      RecordedAssessmentStep(
        'Complete the saved sample',
        remaining > 0
            ? '$remaining planned plants have not been recorded. Once field entry is confirmed safe, continue the existing assessment and sample dispersed plants, including plants without visible damage.'
            : 'The recorded plants are not all saved and confirmed. Check the unfinished plant records before submitting this assessment.',
        'protocol_guidance',
      ),
    );
  }
  if (missingPhotos.isNotEmpty) {
    steps.add(
      RecordedAssessmentStep(
        'Check missing plant photos',
        '${missingPhotos.length} plant records have no available saved photos, even if a screening result was saved. Check the records and ask the expert which replacement views are needed. Keep the new capture date separate from this assessment.',
        'review_evidence',
        missingPhotos,
      ),
    );
  }
  if (unscreened.isNotEmpty || recordIssues > 0) {
    steps.add(
      RecordedAssessmentStep(
        'Check unavailable plant evidence',
        'Open the listed plant records and check whether photos are missing, unclear, or no longer match their saved screening. Unavailable results do not mean an unaffected plant. Resolve saved record issues before relying on the sample.',
        'review_evidence',
        unscreened,
      ),
    );
  }
  if (expert != null) {
    final distribution = expert['score_distribution'] as List?;
    final severe = distribution != null && distribution.length == 10
        ? distribution.skip(7).whereType<num>().fold<num>(0, (a, b) => a + b)
        : 0;
    steps.add(
      RecordedAssessmentStep(
        severe > 0
            ? 'Check the plants rated Davis 7–9'
            : 'Read the finalized expert findings',
        severe > 0
            ? '$severe scored plants received Davis ratings 7–9. Open the individual expert ratings and associated photos; the field average can hide these plants. Use the expert findings when discussing follow-up with your local agriculture office.'
            : 'Open the finalized Davis ratings and recorded damage freshness. Use the expert guidance to plan follow-up for the reviewed plants.',
        'expert_review',
      ),
    );
    if (unknown > 0 || (expert['insufficient_plants'] as num? ?? 0) > 0) {
      steps.add(
        const RecordedAssessmentStep(
          'Ask which evidence needs follow-up',
          'Some finalized findings remain unavailable. Open the expert review and messages to identify the plants needing clearer photos or a new observation. Do not replace an unknown expert finding with a model prediction.',
          'expert_review',
        ),
      );
    }
    if (damage.isNotEmpty && infestation['percent'] == 0) {
      steps.add(
        RecordedAssessmentStep(
          'Compare screening with the expert review',
          'Compare the saved images and app screening with the finalized Davis ratings and freshness notes for these plants.',
          'review_evidence',
          damage,
        ),
      );
    }
  } else {
    if (damage.isNotEmpty) {
      steps.add(
        RecordedAssessmentStep(
          'Review the damage flagged by the app',
          'Open these plant photos and check the visible injury against the saved screening. Keep a clear close-up and wider view for the expert to assess severity and freshness.',
          'review_evidence',
          damage,
        ),
      );
    }
    for (final sign in ['larvae', 'eggs', 'frass']) {
      final locations = refs(
        (p) => (p['model_suggestions'] as Map?)?[sign] == true,
      );
      if (locations.isEmpty) continue;
      final description = switch (sign) {
        'larvae' =>
          'Check the marked photos for a recognizable larva and its location on the plant. If the image is unclear, ask the expert what close-up is needed before making a management decision.',
        'eggs' =>
          'Review the potential egg mass in the marked area. Keep a clear close-up and a wider view of the same plant for expert identification.',
        _ =>
          'Review the potential frass in the marked area. A clear close-up and a view of the surrounding whorl help the expert assess the finding.',
      };
      steps.add(
        RecordedAssessmentStep(
          'Verify potential $sign',
          description,
          'review_evidence',
          locations,
        ),
      );
    }
    if (unknown > 0) {
      steps.add(
        const RecordedAssessmentStep(
          'Check missing sign detection',
          'Some plants have no usable eggs, larvae or frass detection. Check their saved photos and detection status. A damage classification may still be available when sign detection was skipped or failed.',
          'review_evidence',
          [],
        ),
      );
    }
    final review = facts['expert_review'] as Map? ?? const {};
    final cases = review['cases'] as List? ?? const [];
    steps.add(
      RecordedAssessmentStep(
        cases.isEmpty
            ? 'Request an expert review'
            : 'Check your expert review and messages',
        cases.isEmpty
            ? 'Submit the assessment with its saved plant photos so an expert can assess damage severity and freshness. The app detections are provisional.'
            : 'Open the submitted case for review updates and any requested replacement photos. Finalized ratings will provide the severity interpretation.',
        'expert_review',
      ),
    );
  }
  if (!entryBlocked && remaining == 0) {
    final stage = '${facts['growth_stage']}'.toLowerCase();
    final inspection = switch (stage) {
      'vt_r2' => 'the tassel, silks, ear base and leaf axils',
      'r3_r6' => 'the ear exterior, husk, tip, base and leaf axils',
      've' || 'v1' || 'v2' => 'the whole seedling and newest leaves',
      _ => 'the newest leaves and whorl',
    };
    steps.add(
      RecordedAssessmentStep(
        'Use this assessment as your comparison record',
        'At the next protocol-guided assessment, inspect $inspection and compare new findings with this dated record. Sample different dispersed plants rather than selecting only damaged plants. Record new observations separately from these saved results.',
        'field_monitoring',
      ),
    );
  }
  return steps;
}

String readableAssessmentReferences(String text, {bool da = true}) =>
    text.replaceAllMapped(
      RegExp(r'\bB(\d+)-S(\d+)\b'),
      (m) => 'Block ${m[1]} · ${da ? 'Plant' : 'Station'} ${m[2]}',
    );

String readableAssessmentLocations(List<String> refs) {
  final blocks = <String, List<String>>{};
  for (final ref in refs) {
    final match = RegExp(r'^B(\d+)-S(\d+)$').firstMatch(ref);
    if (match != null) (blocks[match[1]!] ??= []).add(match[2]!);
  }
  return blocks.entries
      .map((b) {
        final numbers = b.value.map(int.parse).toSet().toList()..sort();
        final contiguous =
            numbers.length > 4 &&
            numbers.last - numbers.first + 1 == numbers.length;
        final label = contiguous
            ? '${numbers.first}–${numbers.last}'
            : numbers.join(', ');
        return 'Block ${b.key} · ${numbers.length == 1 ? 'Plant' : 'Plants'} $label';
      })
      .join('; ');
}
