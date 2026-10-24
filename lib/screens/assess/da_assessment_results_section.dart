import 'da_findings_overview.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/scouting_workflow_repository.dart';
import '../../localization/app_text.dart';
import '../../models/assessment_history_models.dart';
import '../../models/da_assessment_results.dart';
import '../../models/sampled_infestation.dart';
import '../../models/da_severity.dart';
import '../../services/cloud/expert_review_service.dart';
import '../../services/evidence_storage_service.dart';
import '../../theme/app_colors.dart';
import '../assessment_session_screen.dart';
import '../expert_review_screen.dart';
import '../expert_severity_review_screen.dart';
import 'plant_details_screen.dart';
import 'station_details_screen.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/plant_action_repository.dart';
import '../scan/plant_action_summary.dart';

class DaAssessmentResultsSection extends StatelessWidget {
  const DaAssessmentResultsSection({
    super.key,
    required this.detail,
    required this.storage,
    required this.reportStatus,
    required this.onSubmit,
    required this.onRecommendations,
  });
  final AssessmentHistoryDetail detail;
  final EvidenceStorageService storage;
  final int reportStatus;
  final VoidCallback onSubmit, onRecommendations;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExpertReviewService?>();
    final cases =
        service?.cases
            .where((c) => c.assessmentId == detail.assessment.id)
            .toList() ??
        <ExpertReviewCase>[];
    cases.sort(
      (a, b) => (b.severitySummary?.finalizedAt ?? b.createdAt).compareTo(
        a.severitySummary?.finalizedAt ?? a.createdAt,
      ),
    );
    final finalized = cases.where((c) => c.severitySummary != null).firstOrNull;
    return DaAssessmentResultsView(
      detail: detail,
      storage: storage,
      reportStatus: reportStatus,
      onSubmit: onSubmit,
      onRecommendations: onRecommendations,
      reviewCase: finalized ?? cases.firstOrNull,
      expertLoading: service?.loading ?? false,
      expertError: service?.error,
      loadRatings: finalized == null || service == null
          ? null
          : () => service.loadSeverityRatings(finalized.id),
    );
  }
}

/// Kept separate from legacy station results and independently testable offline.
class DaAssessmentResultsView extends StatefulWidget {
  const DaAssessmentResultsView({
    super.key,
    required this.detail,
    required this.storage,
    required this.reportStatus,
    required this.onSubmit,
    required this.onRecommendations,
    this.reviewCase,
    this.expertLoading = false,
    this.expertError,
    this.loadRatings,
  });
  final AssessmentHistoryDetail detail;
  final EvidenceStorageService storage;
  final int reportStatus;
  final VoidCallback onSubmit, onRecommendations;
  final ExpertReviewCase? reviewCase;
  final bool expertLoading;
  final String? expertError;
  final Future<List<ExpertPlantRating>> Function()? loadRatings;
  @override
  State<DaAssessmentResultsView> createState() =>
      _DaAssessmentResultsViewState();
}

class _DaAssessmentResultsViewState extends State<DaAssessmentResultsView> {
  String? _reviewKey;
  Future<List<ExpertPlantRating>>? _ratings;
  String _filter = 'All';
  bool _gridView = true;

  @override
  void didUpdateWidget(DaAssessmentResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.assessment.id != widget.detail.assessment.id) {
      _filter = 'All';
      _gridView = true;
    }
  }

  void _openReview() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => widget.reviewCase?.severitySummary == null
          ? const ExpertReviewScreen()
          : ExpertSeverityReviewScreen(caseId: widget.reviewCase!.id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sample = DaSampleResults.fromDetail(widget.detail);
    final summary = widget.reviewCase?.severitySummary;
    final key = summary == null
        ? null
        : '${widget.detail.assessment.id}:${widget.reviewCase!.id}:${summary.finalizedAt.toIso8601String()}';
    if (_reviewKey != key) {
      _reviewKey = key;
      _ratings = key == null ? null : widget.loadRatings?.call();
    }
    return FutureBuilder<List<ExpertPlantRating>>(
      future: _ratings,
      builder: (context, snapshot) {
        final expert =
            summary != null &&
                snapshot.hasData &&
                !snapshot.hasError &&
                snapshot.connectionState == ConnectionState.done
            ? DaExpertResults.fromRatings(
                sample: sample,
                summary: summary,
                ratings: snapshot.data!,
              )
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DaFindingsOverview(
              sample: sample,
              expert: expert,
              finalized: summary != null,
              loading:
                  snapshot.connectionState == ConnectionState.waiting ||
                  widget.expertLoading,
              failed: snapshot.hasError || widget.expertError != null,
              onReview: _openReview,
              onExplain: () => _explainFindings(sample, expert),
              onRetry: () =>
                  setState(() => _ratings = widget.loadRatings?.call()),
            ),
            const SizedBox(height: 20),
            _samplingBlocks(sample, expert),
            const SizedBox(height: 14),
            _nextAction(sample, expert),
            if (context.read<AppDatabase?>() case final database?)
              PlantActionSummary(
                repository: PlantActionRepository(
                  database,
                  widget.detail.assessment.evaluatorPersonId,
                ),
                assessmentId: widget.detail.assessment.id,
              ),
            const SizedBox(height: 20),
            _plants(sample, expert),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }

  void _explainFindings(DaSampleResults sample, DaExpertResults? expert) {
    final infestation = DaSampledInfestation(
      sample,
      finalized: widget.reviewCase?.severitySummary != null,
      expert: expert,
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('How the findings are calculated'),
        content: SingleChildScrollView(
          child: AppText(
            'Damage screening: ${sample.positivePlants} flagged plants ÷ '
            '${sample.assessablePlants} plants with a screening result × 100. '
            'Unavailable screening results are excluded.\n\n'
            'Sampled infestation: ${infestation.infested} plants with '
            '${infestation.finalized ? 'expert-assessed fresh damage' : 'potential eggs, larvae or frass'} ÷ '
            '${infestation.denominator} ${infestation.finalized ? 'assessable' : 'planned'} plants × 100. '
            '${infestation.unavailable} plants have no usable infestation finding; they are not confirmed unaffected.\n\n'
            '${expert?.available == true ? 'Mean Davis severity: sum of the finalized scores ÷ ${expert!.scoredPlants} scored plants. Scores range from 0 to 9.\n\nFAW damage incidence: ${expert.damagedPlants} plants with a score above zero ÷ ${expert.scoredPlants} scored plants × 100. Includes old and fresh damage.\n\n' : ''}'
            'Each plant counts once. Photo counts do not enter these denominators. Damage alone does not prove current infestation.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('Close'),
          ),
        ],
      ),
    );
  }

  Widget _nextAction(DaSampleResults sample, DaExpertResults? expert) {
    final submitted = widget.reportStatus == 2 || widget.reviewCase != null;
    final needsSample = !sample.sampleComplete;
    final finalized = widget.reviewCase?.severitySummary != null;
    final title = needsSample
        ? 'Continue your assessment'
        : finalized
        ? 'Your review is ready'
        : submitted
        ? 'Assessment submitted'
        : 'Ready to submit';
    final description = needsSample
        ? 'Finish recording and saving your sample.'
        : finalized
        ? 'View the ratings and recommended next steps.'
        : submitted
        ? 'View messages and updates for this assessment.'
        : 'Send this assessment for review.';
    return Container(
      key: const Key('da_next_action'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2E5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  needsSample
                      ? Icons.route_outlined
                      : submitted
                      ? Icons.forum_outlined
                      : Icons.send_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: widget.onRecommendations,
            icon: const Icon(Icons.assistant_direction_outlined, size: 18),
            label: const AppText('View recommended steps'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: needsSample
                ? widget.detail.canResume
                      ? () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssessmentSessionScreen(
                              assessmentId: widget.detail.assessment.id,
                            ),
                          ),
                        )
                      : null
                : submitted
                ? _openReview
                : widget.reportStatus == 1
                ? null
                : widget.onSubmit,
            icon: Icon(
              needsSample
                  ? Icons.arrow_forward_rounded
                  : submitted
                  ? Icons.open_in_new_rounded
                  : Icons.send_outlined,
              size: 18,
            ),
            label: AppText(
              needsSample
                  ? 'Continue scouting'
                  : finalized
                  ? 'Open expert review'
                  : submitted
                  ? 'View expert messages'
                  : widget.reportStatus == 1
                  ? 'Submitting…'
                  : 'Submit assessment',
            ),
          ),
        ],
      ),
    );
  }

  Widget _samplingBlocks(DaSampleResults sample, DaExpertResults? expert) {
    final blocks = <int, List<StationSnapshot>>{};
    for (final plant in sample.plants) {
      (blocks[plant.prepared.run.blockSequence] ??= []).add(plant);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppText(
          'Where the findings are',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const AppText(
          'Each block contains a planned sample of 20 plants.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final entry in blocks.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    AppText(
                      'Block ${entry.key}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    AppText(
                      '${entry.value.where(sample.isPositive).length} of ${entry.value.where(sample.isAssessable).length} screened plants flagged',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF956022),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Semantics(
                  label:
                      'Block ${entry.key}: ${entry.value.where(sample.isPositive).length} damage indications in the 20-plant plan',
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 1; i <= 20; i++)
                        Builder(
                          builder: (_) {
                            final matches = entry.value.where(
                              (p) => p.stationNumber == i,
                            );
                            final p = matches.isEmpty ? null : matches.first;
                            final color = p == null || !sample.isAssessable(p)
                                ? const Color(0xFFD9DED6)
                                : sample.isPositive(p)
                                ? const Color(0xFFAA702F)
                                : const Color(0xFF548269);
                            return ExcludeSemantics(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                if (expert?.available == true) ...[
                  const SizedBox(height: 6),
                  Builder(
                    builder: (_) {
                      final scores = entry.value
                          .map(expert!.ratingFor)
                          .whereType<ExpertPlantRating>()
                          .where((r) => r.outcome == 'scored')
                          .map((r) => r.davisScore!)
                          .toList();
                      final mean = scores.isEmpty
                          ? null
                          : scores.reduce((a, b) => a + b) / scores.length;
                      return AppText(
                        'Expert mean Davis: ${mean?.toStringAsFixed(2) ?? 'Unavailable'} / 9 · ${scores.length} scored',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        const AppText(
          'Amber: damage flagged · Green: no damage flagged · Gray: unavailable',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _plants(DaSampleResults sample, DaExpertResults? expert) {
    final infestation = DaSampledInfestation(
      sample,
      finalized: widget.reviewCase?.severitySummary != null,
      expert: expert,
    );
    final visible = sample.plants
        .where(
          (p) => switch (_filter) {
            'Infested' => infestation.forPlant(p) == true,
            'Unavailable' => infestation.forPlant(p) == null,
            _ => true,
          },
        )
        .toList();
    final blocks = visible.map((p) => p.prepared.run.blockSequence).toSet();
    final counts = <String, int>{
      'All': sample.plants.length,
      'Infested': infestation.infested,
      'Unavailable': infestation.values.values.where((v) => v == null).length,
    };
    return Column(
      key: const Key('da_sampled_plants'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    'Sample details',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    '${sample.recordedPlants} of ${sample.expectedPlants} plants recorded',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          key: const Key('da_sample_completion'),
          value: sample.expectedPlants == 0
              ? 0
              : (sample.savedPlants / sample.expectedPlants).clamp(0, 1),
          backgroundColor: const Color(0xFFE3EBDD),
          color: AppColors.primary,
          minHeight: 4,
          borderRadius: BorderRadius.circular(8),
        ),
        if (sample.recordedPlants != sample.savedPlants) ...[
          const SizedBox(height: 6),
          AppText(
            '${sample.recordedPlants - sample.savedPlants} records need saving',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in counts.keys)
              _plantFilter(label, counts[label]!),
          ],
        ),
        const SizedBox(height: 12),
        _plantViewToggle(),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Container(
            key: const Key('da_plants_empty'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  size: 32,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                AppText(
                  _filter == 'Infested'
                      ? 'No infested plants'
                      : _filter == 'Unavailable'
                      ? 'All recorded plants have results'
                      : 'No plants recorded',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const AppText(
                  'Choose another filter to view plants.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        for (final block in blocks) ...[
          if (sample.expectedPlants > 20)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: AppText(
                'Block $block',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final plants = visible
                  .where((p) => p.prepared.run.blockSequence == block)
                  .toList();
              if (!_gridView) {
                return Column(
                  key: Key('da_plant_list_$block'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final plant in plants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _plantCard(
                          sample,
                          plant,
                          expert?.ratingFor(plant),
                          horizontal: true,
                        ),
                      ),
                  ],
                );
              }
              final columns = constraints.maxWidth >= 960
                  ? 4
                  : constraints.maxWidth >= 650
                  ? 3
                  : 2;
              final scaler = MediaQuery.textScalerOf(context);
              // Budget two lines for compact labels. Keep a real grid even at
              // large text sizes, growing the tiles instead of switching views.
              final hasRating = plants.any((p) => expert?.ratingFor(p) != null);
              final hasNotes = plants.any(
                (p) =>
                    sample.observation(p)?.plant.evaluatorNotes?.isNotEmpty ==
                    true,
              );
              final height =
                  147 +
                  scaler.scale(17) * 3 +
                  scaler.scale(13) * 3 +
                  scaler.scale(12) * 3 +
                  (hasRating ? 6 + scaler.scale(12) * 3 : 0) +
                  (hasNotes ? 6 + scaler.scale(11) * 1.5 : 0);
              return GridView.builder(
                key: Key('da_plant_grid_$block'),
                primary: false,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: height,
                ),
                itemCount: plants.length,
                itemBuilder: (context, index) => _plantCard(
                  sample,
                  plants[index],
                  expert?.ratingFor(plants[index]),
                  horizontal: false,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _plantViewToggle() => Container(
    key: const Key('da_plant_view_toggle'),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (final grid in [false, true])
          Expanded(
            child: Semantics(
              button: true,
              selected: _gridView == grid,
              child: Material(
                color: _gridView == grid
                    ? AppColors.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('da_plant_view_${grid ? 'grid' : 'list'}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _gridView = grid),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          grid
                              ? Icons.grid_view_rounded
                              : Icons.view_list_rounded,
                          size: 18,
                          color: _gridView == grid
                              ? Colors.white
                              : AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: AppText(
                            grid ? 'Grid' : 'List',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _gridView == grid
                                  ? Colors.white
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _plantFilter(String label, int count) {
    final selected = _filter == label;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count plants',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('da_plant_filter_${label.toLowerCase()}'),
          borderRadius: BorderRadius.circular(30),
          onTap: () => setState(() => _filter = label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFE2E7DD),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AppText(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: .16)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _plantCard(
    DaSampleResults sample,
    StationSnapshot plant,
    ExpertPlantRating? rating, {
    required bool horizontal,
  }) {
    final observation = sample.observation(plant);
    final photos = sample.photos(plant);
    final value = widget.reviewCase?.severitySummary != null
        ? expertSampledInfestation(rating)
        : DaSampledInfestation(sample).forPlant(plant);
    final positive = value == true;
    final assessable = value != null;
    final status = observation == null
        ? 'Not recorded'
        : !assessable
        ? 'Unavailable'
        : positive
        ? 'Infested'
        : 'Not infested';
    final color = observation == null || !assessable
        ? const Color(0xFF68746F)
        : positive
        ? const Color(0xFF9A5717)
        : AppColors.primary;
    final tint = positive ? const Color(0xFFFFF3E5) : const Color(0xFFEDF3EA);
    final screening = sample.screening(plant);
    final canOpen = observation != null || plant.station != null;
    void openPlant() => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => observation == null
            ? StationDetailsScreen(
                detail: widget.detail,
                station: plant,
                storage: widget.storage,
              )
            : PlantAssessmentDetailsScreen(
                detail: widget.detail,
                station: plant,
                record: observation,
                storage: widget.storage,
              ),
      ),
    );
    Widget placeholder() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, const Color(0xFFF7F8F3)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.grass_rounded,
          size: horizontal ? 36 : 56,
          color: color.withValues(alpha: .45),
        ),
      ),
    );
    final image = SizedBox(
      height: horizontal ? 92 : 110,
      width: horizontal ? 80 : double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            placeholder()
          else
            FutureBuilder<File>(
              future: widget.storage.resolve(
                photos.first.media.thumbnailLocalUri ??
                    photos.first.media.localUri,
              ),
              builder: (_, image) => image.hasData
                  ? Image.file(
                      image.data!,
                      fit: BoxFit.cover,
                      frameBuilder: (_, child, frame, synchronouslyLoaded) =>
                          frame != null || synchronouslyLoaded
                          ? child
                          : placeholder(),
                      errorBuilder: (_, _, _) => placeholder(),
                    )
                  : placeholder(),
            ),
          Positioned(
            left: 10,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    photos.isEmpty
                        ? Icons.image_not_supported_outlined
                        : Icons.photo_library_outlined,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  AppText(
                    photos.isEmpty ? 'No photos' : '${photos.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final info = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  'Plant ${plant.stationNumber}',
                  maxLines: horizontal ? null : 2,
                  overflow: horizontal ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canOpen)
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppText(
                  status,
                  maxLines: horizontal ? null : 2,
                  overflow: horizontal ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          AppText(
            screening?.screeningSucceeded == true
                ? screening!.label
                : observation == null
                ? 'Awaiting capture'
                : 'No screening result',
            maxLines: horizontal ? null : 2,
            overflow: horizontal ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (rating != null) ...[
            const SizedBox(height: 6),
            AppText(
              rating.outcome == 'scored'
                  ? 'Davis ${rating.davisScore}/9 · ${daSeverityClassification(rating.davisScore)}'
                  : 'Insufficient evidence',
              maxLines: horizontal ? null : 2,
              overflow: horizontal ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (observation?.plant.evaluatorNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.notes_rounded,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                const Flexible(
                  child: AppText(
                    'Field notes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: canOpen,
      child: Material(
        key: Key(
          'da_plant_card_${plant.prepared.run.blockSequence}_${plant.stationNumber}',
        ),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5E9E0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canOpen ? openPlant : null,
          child: horizontal
              ? Row(
                  children: [
                    image,
                    Expanded(child: info),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [image, info],
                ),
        ),
      ),
    );
  }
}
