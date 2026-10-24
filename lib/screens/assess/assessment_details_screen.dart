import 'assessment_results_screen.dart';
import '../../localization/app_text.dart';
import 'ribbon_ticket_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../data/services/assessment_validation_types.dart';
import '../../models/assessment_history_models.dart';
import '../../providers/app_data_mode.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/evidence_storage_service.dart';
import '../../services/scouting_sampling_protocol.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import 'assessment_resume_screen.dart';
import 'assessment_summary_card.dart';
import 'assessment_status_badge.dart';
import 'station_details_screen.dart';
import 'retired_assessment_notice.dart';

class AssessmentDetailsScreen extends StatefulWidget {
  const AssessmentDetailsScreen({super.key, required this.assessmentId});
  final String assessmentId;
  @override
  State<AssessmentDetailsScreen> createState() =>
      _AssessmentDetailsScreenState();
}

class _AssessmentDetailsScreenState extends State<AssessmentDetailsScreen> {
  late final AssessmentHistoryRepository _repository;
  late final EvidenceStorageService _storage;
  late Stream<AssessmentHistoryDetail?> _record;
  @override
  void initState() {
    super.initState();
    _repository = AssessmentHistoryRepository(context.read<AppDatabase>());
    final mode = context.read<AppDataMode?>();
    _storage = EvidenceStorageService(
      rootDirectory: mode?.isTestMode == true
          ? mode!.evidenceRootDirectory
          : null,
    );
    _record = _repository.watchDetail(widget.assessmentId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Assessment details')),
    body: SafeArea(
      child: StreamBuilder<AssessmentHistoryDetail?>(
        stream: _record,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppText(
                      'Could not load this assessment. Your saved records have not been changed.',
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(
                        () => _record = _repository.watchDetail(
                          widget.assessmentId,
                        ),
                      ),
                      child: const AppText('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppText(
                  'This assessment is no longer available. Return to Assess to see your saved records.',
                ),
              ),
            );
          }
          final assessment = detail.assessment;
          if (ScoutingSamplingProtocol.isRetired(
            assessment.protocolVersion,
            pattern: assessment.scoutingPattern,
          )) {
            return RetiredAssessmentNotice(fieldId: detail.workspace.field.id);
          }
          final isSeedling = const {
            've',
            'v1',
            'v2',
          }.contains(assessment.growthStage);
          final reviewed = detail.stations
              .where((s) => s.reviewIsCurrent)
              .length;
          final plantCount = detail.stations.fold<int>(
            0,
            (count, s) => count + s.plants.length,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.workflowMaxWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _AssessmentHero(detail: detail),
                  const SizedBox(height: 10),
                  _AssessmentMetadata(detail: detail),
                  const SizedBox(height: 8),
                  const Center(
                    child: AppText('Saved on this phone · Read-only record'),
                  ),
                  const SizedBox(height: 16),
                  if (assessment.status == 'safety_blocked')
                    const _RecordNotice(
                      'Field entry is blocked. Review the saved safety situation before continuing scouting.',
                    ),
                  if (detail.workspace.field.isArchived)
                    const _RecordNotice(
                      'This field is in Recently Deleted. Its records can be viewed, but scouting cannot be resumed here.',
                    ),
                  if (!detail.workspace.hasApproximateOutline)
                    const _RecordNotice(
                      'The boundary saved with this assessment is not confirmed. Review the field outline in Assess before resuming.',
                    ),
                  if (detail.missingBlocks > 0)
                    const _RecordNotice(
                      'Some block definitions are unavailable. The progress shown below may be incomplete.',
                    ),
                  AssessmentSummaryCard(detail: detail),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('assessment_results_button'),
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssessmentResultsScreen(
                          assessmentId: assessment.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.analytics_outlined),
                    label: Text(
                      assessment.status == DatabaseCodes.completed
                          ? 'View recorded results'
                          : detail.metrics.isNotEmpty
                          ? 'View preliminary saved metrics'
                          : 'Why results are unavailable',
                    ),
                  ),
                  if (detail.canResume) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('assessment_details_resume_button'),
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssessmentResumeScreen(
                              assessmentId: assessment.id,
                            ),
                          ),
                        ),
                        icon: Icon(
                          assessment.status == 'safety_blocked'
                              ? Icons.health_and_safety_outlined
                              : Icons.play_arrow_outlined,
                        ),
                        label: AppText(
                          assessmentResumeLabel(assessment.status)!,
                        ),
                      ),
                    ),
                  ],
                  if (assessment.status != DatabaseCodes.completed &&
                      _requiredWorkGroups(detail).isNotEmpty)
                    _RequiredWorkSection(detail: detail),
                  _DetailSection(
                    title: 'Sampling progress',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.stations.isEmpty
                              ? 'No sampling stations prepared yet'
                              : '${detail.stations.where((s) => s.station != null).length} station records saved · $reviewed current reviews',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isSeedling
                              ? '${detail.units.length} planting positions · $plantCount living-seedling records'
                              : '$plantCount plant records',
                        ),
                        if (detail.stations.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _StationProgress(stations: detail.stations),
                        ],
                      ],
                    ),
                  ),
                  if (detail.stations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppText(
                              'Station observations',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Flexible(
                            child: AppText(
                              '$reviewed current reviews',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.highContrastGreen,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final stations in _stationsByBlock(detail.stations))
                    _StationObservationBoard(
                      detail: detail,
                      stations: stations,
                      storage: _storage,
                      isSeedling: isSeedling,
                    ),
                  const _RecordNotice(
                    'These are saved observations. This view does not infer a diagnosis, rerun the image model, or change the assessment.',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _AssessmentHero extends StatelessWidget {
  const _AssessmentHero({required this.detail});

  final AssessmentHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final assessment = detail.assessment;
    return ClipRRect(
      key: const Key('assessment_details_option_b_hero'),
      borderRadius: AppRadii.prominentBorder,
      child: SizedBox(
        height: 164,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _detailStageImage(assessment.growthStage),
              fit: BoxFit.cover,
              cacheWidth: 960,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0xB8000000)],
                  stops: [0.2, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.workspace.field.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      shadows: const [Shadow(blurRadius: 5)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AssessmentStatusBadge(status: assessment.status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentMetadata extends StatelessWidget {
  const _AssessmentMetadata({required this.detail});

  final AssessmentHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final assessment = detail.assessment;
    final date = assessment.startedAt ?? assessment.createdAt;
    final area = detail.workspace.boundary?.areaHectares;
    final entries = <({IconData icon, String value, String label})>[
      (
        icon: Icons.agriculture_outlined,
        value: AssessmentProtocolSelector.growthStageLabel(
          assessment.growthStage,
        ),
        label: 'Growth stage',
      ),
      (icon: Icons.person_outline, value: detail.evaluator, label: 'Evaluator'),
      (
        icon: Icons.calendar_today_outlined,
        value: DateFormat.yMMMd().format(date.toLocal()),
        label: assessment.startedAt == null ? 'Created' : 'Started',
      ),
      (
        icon: Icons.map_outlined,
        value: area == null ? 'Not recorded' : '${area.toStringAsFixed(2)} ha',
        label: 'Field size',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Icon(entry.icon, size: 21, color: AppColors.primary),
                      const SizedBox(height: 4),
                      Text(
                        entry.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StationProgress extends StatelessWidget {
  const _StationProgress({required this.stations});

  final List<StationSnapshot> stations;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var index = 0; index < stations.length; index++) ...[
          if (index > 0)
            Container(
              width: 24,
              height: 3,
              color: stations[index - 1].reviewIsCurrent
                  ? AppColors.primary
                  : AppColors.outlineVariant,
            ),
          _StationProgressNode(snapshot: stations[index]),
        ],
      ],
    ),
  );
}

class _StationProgressNode extends StatelessWidget {
  const _StationProgressNode({required this.snapshot});

  final StationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final complete = snapshot.reviewIsCurrent;
    final started = snapshot.station != null;
    final background = complete
        ? AppColors.primary
        : started
        ? AppColors.primaryLight
        : AppColors.surfaceCard;
    final foreground = complete
        ? Colors.white
        : started
        ? AppColors.highContrastGreen
        : AppColors.textMuted;
    return Semantics(
      label:
          'Block ${snapshot.prepared.run.blockSequence}, Station ${snapshot.stationNumber}',
      value: complete
          ? 'Saved; review current'
          : started
          ? 'Saved; review required'
          : 'Pending',
      child: SizedBox(
        width: 54,
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
                border: Border.all(
                  color: complete
                      ? AppColors.primary
                      : AppColors.outlineVariant,
                  width: 2,
                ),
              ),
              child: complete
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : AppText(
                      '${snapshot.stationNumber}',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              stationsLabel(snapshot),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String stationsLabel(StationSnapshot snapshot) =>
    'B${snapshot.prepared.run.blockSequence} · S${snapshot.stationNumber}';

String _detailStageImage(String growthStage) => switch (growthStage) {
  've' || 'v1' || 'v2' => 'assets/images/growth_stages/maize_emergence.jpg',
  'v3_v6' => 'assets/images/growth_stages/maize_young_vegetative.jpg',
  'v7_v12' => 'assets/images/growth_stages/maize_tall_vegetative.jpg',
  'vt_r2' => 'assets/images/growth_stages/maize_silks.jpg',
  'r3_r6' => 'assets/images/growth_stages/maize_mature_kernels.jpg',
  _ => 'assets/images/growth_stages/maize_young_vegetative.jpg',
};

class _RequiredWorkSection extends StatelessWidget {
  const _RequiredWorkSection({required this.detail});

  final AssessmentHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final groups = _requiredWorkGroups(detail);
    return _DetailSection(
      title: 'Required work',
      child: groups.isEmpty
          ? Container(
              key: const Key('assessment_completion_checks_passed'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: AppRadii.cardBorder,
                border: Border.all(color: const Color(0xFFC9E4C6)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.task_alt, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      'Completion checks passed. No required work remains.',
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppText(
                  '${groups.length} ${groups.length == 1 ? 'area needs' : 'areas need'} attention',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RequiredWorkTask(detail: detail, group: group),
                  ),
              ],
            ),
    );
  }
}

class _RequiredWorkTask extends StatelessWidget {
  const _RequiredWorkTask({required this.detail, required this.group});

  final AssessmentHistoryDetail detail;
  final _RequiredWorkGroup group;

  @override
  Widget build(BuildContext context) {
    final canOpenWorkflow =
        detail.canResume &&
        group.stationNumber != null &&
        group.station?.reviewedAt != null;
    final actionLabel = canOpenWorkflow
        ? 'Fix Station ${group.stationNumber}'
        : null;
    return Material(
      key: Key(
        'required_work_${group.blockRunId ?? 'assessment'}_${group.stationNumber ?? 0}',
      ),
      color: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardBorder,
        side: BorderSide(color: group.color.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          minTileHeight: 64,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: group.color.withValues(alpha: .11),
            ),
            child: Icon(group.icon, size: 19, color: group.color),
          ),
          title: AppText(
            group.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: AppText(
            '${group.status} · ${group.messages.length} ${group.messages.length == 1 ? 'item' : 'items'}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: group.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            for (final message in group.messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: group.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (actionLabel != null) ...[
              const SizedBox(height: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key(
                    'required_work_action_${group.blockRunId ?? 'assessment'}_${group.stationNumber ?? 0}',
                  ),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssessmentResumeScreen(
                        assessmentId: detail.assessment.id,
                        blockRunId: group.blockRunId,
                        stationNumber: group.stationNumber,
                        openForReview:
                            canOpenWorkflow && group.station?.station != null,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.build_outlined),
                  label: AppText(actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequiredWorkGroup {
  const _RequiredWorkGroup({
    required this.blockRunId,
    required this.blockSequence,
    required this.stationNumber,
    required this.station,
    required this.issues,
  });

  final String? blockRunId;
  final int? blockSequence;
  final int? stationNumber;
  final StationSnapshot? station;
  final List<ValidationIssue> issues;

  String get title => blockSequence == null
      ? 'Assessment setup'
      : stationNumber == null
      ? 'Block $blockSequence'
      : 'Block $blockSequence · Station $stationNumber';

  Set<_WorkKind> get kinds => issues.map(_workKind).toSet();

  String get status {
    if (kinds.length != 1) return 'Review required';
    return switch (kinds.single) {
      _WorkKind.observations => 'Observations needed',
      _WorkKind.evidence => 'Evidence needed',
      _WorkKind.photoReview => 'Photo review needed',
      _WorkKind.review => 'Review outdated',
      _WorkKind.setup => 'Setup needed',
    };
  }

  Color get color => switch (kinds.length == 1 ? kinds.single : null) {
    _WorkKind.review => const Color(0xFFAA7624),
    _WorkKind.photoReview => const Color(0xFF7B5AA6),
    _WorkKind.evidence => const Color(0xFFB35A35),
    _WorkKind.observations => const Color(0xFF2875A4),
    _ => const Color(0xFF8A5B25),
  };

  IconData get icon => switch (kinds.length == 1 ? kinds.single : null) {
    _WorkKind.review => Icons.rate_review_outlined,
    _WorkKind.photoReview => Icons.image_search_outlined,
    _WorkKind.evidence => Icons.add_a_photo_outlined,
    _WorkKind.observations => Icons.assignment_late_outlined,
    _ => Icons.checklist_rounded,
  };

  List<String> get messages {
    final result = <String>[];
    final observationIssues = issues
        .where((issue) => _workKind(issue) == _WorkKind.observations)
        .toList();
    final evidenceIssues = issues
        .where((issue) => _workKind(issue) == _WorkKind.evidence)
        .toList();
    final photoReviewIssues = issues
        .where((issue) => _workKind(issue) == _WorkKind.photoReview)
        .toList();
    if (observationIssues.isNotEmpty) {
      result.add(_observationSummary(observationIssues));
    }
    if (evidenceIssues.isNotEmpty) {
      result.add(_evidenceSummary(evidenceIssues));
    }
    if (photoReviewIssues.isNotEmpty) {
      final positions = _plantPositions(photoReviewIssues);
      result.add(
        positions.isEmpty
            ? 'Photo review: verify the saved photos, then tap Save and return to review.'
            : 'Photo review: open ${_positionLabel(positions)}, verify the saved photos, then tap Save and return to review.',
      );
    }
    if (kinds.contains(_WorkKind.review)) {
      result.add(
        'Final check: review the updated station information, then tap Complete Station.',
      );
    }
    if (kinds.contains(_WorkKind.setup)) {
      result.addAll(
        issues
            .where((issue) => _workKind(issue) == _WorkKind.setup)
            .map(
              (issue) =>
                  issue.message.replaceFirst(RegExp(r'^Block \d+:\s*'), ''),
            )
            .toSet(),
      );
    }
    return List.unmodifiable(result);
  }
}

enum _WorkKind { observations, evidence, photoReview, review, setup }

String _observationSummary(List<ValidationIssue> issues) {
  final positions = _plantPositions(issues);
  if (positions.isNotEmpty) {
    return 'Observations: complete or correct ${_positionLabel(positions)}.';
  }
  return issues.any((issue) => issue.code == 'station_missing')
      ? 'Observations: record this station and its required plant observations.'
      : 'Observations: complete the missing station details and plant records.';
}

String _evidenceSummary(List<ValidationIssue> issues) {
  final positions = _plantPositions(issues);
  final parts = <String>[];
  if (issues.any((issue) => issue.code.contains('station_context'))) {
    parts.add('station context');
  }
  if (positions.isNotEmpty) parts.add(_positionLabel(positions));
  final target = parts.isEmpty ? 'required photos' : parts.join(' and ');
  return 'Evidence: check the attachment and completion of $target.';
}

List<int> _plantPositions(List<ValidationIssue> issues) {
  final values = <int>{};
  final expression = RegExp(
    r'(?:Plant|Living plant) (\d+)',
    caseSensitive: false,
  );
  for (final issue in issues) {
    final match = expression.firstMatch(issue.message);
    final value = match == null ? null : int.tryParse(match.group(1)!);
    if (value != null) values.add(value);
  }
  return values.toList()..sort();
}

String _positionLabel(List<int> positions) {
  if (positions.length == 10 && positions.first == 1 && positions.last == 10) {
    return 'Plants 1–10';
  }
  return '${positions.length == 1 ? 'Plant' : 'Plants'} ${positions.join(', ')}';
}

_WorkKind _workKind(ValidationIssue issue) {
  final code = issue.code;
  if (code == 'evidence_review_required') return _WorkKind.photoReview;
  if (code.contains('review')) return _WorkKind.review;
  if (code.contains('evidence') ||
      code.contains('capture') ||
      code.contains('primary_view') ||
      code.contains('station_context')) {
    return _WorkKind.evidence;
  }
  if (issue.stationNumber != null || issue.stationId != null) {
    return _WorkKind.observations;
  }
  return _WorkKind.setup;
}

List<_RequiredWorkGroup> _requiredWorkGroups(AssessmentHistoryDetail detail) {
  final grouped = <String, List<ValidationIssue>>{};
  for (final issue in detail.readiness.issues) {
    final key =
        '${issue.blockRunId ?? 'assessment'}:${issue.stationNumber ?? 0}';
    grouped.putIfAbsent(key, () => []).add(issue);
  }
  final result = <_RequiredWorkGroup>[];
  for (final issues in grouped.values) {
    final first = issues.first;
    StationSnapshot? snapshot;
    for (final candidate in detail.stations) {
      if (candidate.prepared.run.id == first.blockRunId &&
          candidate.stationNumber == first.stationNumber) {
        snapshot = candidate;
        break;
      }
    }
    int? blockSequence = snapshot?.prepared.run.blockSequence;
    if (blockSequence == null && first.blockRunId != null) {
      for (final candidate in detail.stations) {
        if (candidate.prepared.run.id == first.blockRunId) {
          blockSequence = candidate.prepared.run.blockSequence;
          break;
        }
      }
    }
    result.add(
      _RequiredWorkGroup(
        blockRunId: first.blockRunId,
        blockSequence: blockSequence,
        stationNumber: first.stationNumber,
        station: snapshot,
        issues: List.unmodifiable(issues),
      ),
    );
  }
  result.sort((a, b) {
    final block = (a.blockSequence ?? 0).compareTo(b.blockSequence ?? 0);
    return block != 0
        ? block
        : (a.stationNumber ?? 0).compareTo(b.stationNumber ?? 0);
  });
  return List.unmodifiable(result);
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _StationObservationBoard extends StatelessWidget {
  const _StationObservationBoard({
    required this.detail,
    required this.stations,
    required this.storage,
    required this.isSeedling,
  });

  final AssessmentHistoryDetail detail;
  final List<StationSnapshot> stations;
  final EvidenceStorageService storage;
  final bool isSeedling;

  @override
  Widget build(BuildContext context) {
    final ordered = [...stations]
      ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final station in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FeaturedStationCard(
                detail: detail,
                station: station,
                storage: storage,
                isSeedling: isSeedling,
              ),
            ),
        ],
      ),
    );
  }
}

class _FeaturedStationCard extends StatelessWidget {
  const _FeaturedStationCard({
    required this.detail,
    required this.station,
    required this.storage,
    required this.isSeedling,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final EvidenceStorageService storage;
  final bool isSeedling;

  @override
  Widget build(BuildContext context) {
    final stationId = station.station?.id;
    final photos = stationId == null
        ? 0
        : detail.evidence
              .where(
                (entry) =>
                    entry.stationId == stationId &&
                    entry.media.storageState ==
                        DatabaseCodes.evidenceStorageReady,
              )
              .length;
    final hasStation = station.station != null;
    final hasAllRecords = station.plants.length >= 10;
    final status = !hasStation
        ? 'Not started'
        : station.reviewIsCurrent
        ? 'Saved · review complete'
        : hasAllRecords
        ? 'Saved · review required'
        : 'In progress';
    final color = !hasStation
        ? AppColors.textMuted
        : station.reviewIsCurrent
        ? const Color(0xFF35893E)
        : hasAllRecords
        ? const Color(0xFFAA7624)
        : const Color(0xFF2875A4);
    return RibbonTicketCard(
      key: Key(
        'open_station_${station.prepared.run.id}_${station.stationNumber}',
      ),
      status: status,
      title:
          'Block ${station.prepared.run.blockSequence} · Station ${station.stationNumber}',
      description:
          '${station.plants.length} of 10 ${isSeedling ? 'seedling' : 'plant'} records saved',
      photos: photos,
      color: color,
      icon: !hasStation
          ? Icons.radio_button_unchecked
          : station.reviewIsCurrent
          ? Icons.fact_check_outlined
          : hasAllRecords
          ? Icons.pending_actions_outlined
          : Icons.edit_note_outlined,
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StationDetailsScreen(
            detail: detail,
            station: station,
            storage: storage,
          ),
        ),
      ),
    );
  }
}

List<List<StationSnapshot>> _stationsByBlock(List<StationSnapshot> stations) {
  final groups = <String, List<StationSnapshot>>{};
  for (final station in stations) {
    groups.putIfAbsent(station.prepared.run.id, () => []).add(station);
  }
  return groups.values.toList(growable: false)..sort(
    (a, b) => a.first.prepared.run.blockSequence.compareTo(
      b.first.prepared.run.blockSequence,
    ),
  );
}

class _RecordNotice extends StatelessWidget {
  const _RecordNotice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: AppRadii.controlBorder,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 10),
        Expanded(child: AppText(text)),
      ],
    ),
  );
}
