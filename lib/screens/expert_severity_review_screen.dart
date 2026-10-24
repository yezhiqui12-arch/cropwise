import '../localization/app_language.dart';
import 'package:flutter/material.dart';
import '../models/da_severity.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_text.dart';
import '../services/cloud/expert_review_service.dart';
import '../theme/app_colors.dart';

String formatDavisScore(double value) =>
    value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

// Match the descriptions used by the expert dashboard.
const _davisDescriptions = [
  'No visible leaf damage',
  'Only pin-hole damage to leaves',
  'Pin-hole and shot-hole damage',
  'Small elongated lesions (5–10 mm) on 1–3 leaves',
  'Mid-sized lesions (10–30 mm) on 4–7 leaves',
  'Long lesions (>30 mm) or small portions eaten on 3–5 leaves',
  'Long lesions (>30 mm) and large portions eaten on 3–5 leaves',
  'Elongated lesions and about 50% of leaf eaten',
  'Elongated lesions and about 70% of leaf eaten',
  'Long lesions on most leaves with complete defoliation',
];

class ExpertSeverityReviewScreen extends StatefulWidget {
  const ExpertSeverityReviewScreen({super.key, required this.caseId});
  final String caseId;

  @override
  State<ExpertSeverityReviewScreen> createState() =>
      _ExpertSeverityReviewScreenState();
}

class _ExpertSeverityReviewScreenState
    extends State<ExpertSeverityReviewScreen> {
  late Future<List<ExpertPlantRating>> _ratings;

  @override
  void initState() {
    super.initState();
    _ratings = context.read<ExpertReviewService>().loadSeverityRatings(
      widget.caseId,
    );
  }

  Future<void> _reload() async {
    final next = context.read<ExpertReviewService>().loadSeverityRatings(
      widget.caseId,
    );
    setState(() => _ratings = next);
    // FutureBuilder displays the failure and offers a retry.
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExpertReviewService>();
    final matches = service.cases.where((item) => item.id == widget.caseId);
    final reviewCase = matches.isEmpty ? null : matches.first;
    final summary = reviewCase?.severitySummary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const AppText(
          'Expert review',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: AppWords.of(
              context,
            ).translate('Refresh photos and scores'),
            onPressed: summary == null ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: summary == null
          ? const Center(
              child: AppText('This finalized review is no longer available.'),
            )
          : FutureBuilder<List<ExpertPlantRating>>(
              future: _ratings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 40,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 12),
                          const AppText(
                            'Photos and scores could not be loaded. Check your connection and try again.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _reload,
                            child: const AppText('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ExpertSeverityReviewContent(
                  reviewCase: reviewCase!,
                  ratings: snapshot.data ?? const <ExpertPlantRating>[],
                  onRefresh: _reload,
                );
              },
            ),
    );
  }
}

class _ReviewPhoto extends StatelessWidget {
  const _ReviewPhoto({
    required this.photo,
    required this.label,
    this.aspectRatio = 4 / 3,
  });
  final ExpertPlantPhoto photo;
  final String label;
  final double aspectRatio;

  static Widget _unavailable() => LayoutBuilder(
    builder: (context, constraints) {
      const icon = Icon(
        Icons.hide_image_outlined,
        size: 20,
        color: AppColors.textSecondary,
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: constraints.maxWidth < 100
              ? const Tooltip(message: 'Photo unavailable', child: icon)
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    SizedBox(height: 4),
                    AppText(
                      'Photo unavailable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: photo.url == null
        ? _unavailable()
        : InkWell(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: AppText(label),
                  ),
                  body: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: Image.network(
                        photo.url!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _unavailable(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: Image.network(
              photo.url!,
              fit: BoxFit.contain,
              semanticLabel: AppWords.of(
                context,
              ).format('{label} submitted evidence', {'label': label}),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) => _unavailable(),
            ),
          ),
  );
}

/// The same loaded review view is used by the live screen and focused previews.
class ExpertSeverityReviewContent extends StatelessWidget {
  const ExpertSeverityReviewContent({
    super.key,
    required this.reviewCase,
    required this.ratings,
    required this.onRefresh,
  });
  final ExpertReviewCase reviewCase;
  final List<ExpertPlantRating> ratings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final summary = reviewCase.severitySummary!;
    final scored = ratings.where(_hasScore).toList();
    final mean =
        !ratings.any((r) => r.associationAmbiguous) &&
            summary.monitoring['association_status'] != 'ambiguous' &&
            ratings.length == summary.reviewedPlants &&
            scored.length == summary.scoredPlants &&
            scored.isNotEmpty
        ? scored.fold<int>(0, (sum, r) => sum + r.davisScore!) / scored.length
        : null;
    final visible = [...ratings]
      ..sort((a, b) {
        final score = (_hasScore(b) ? b.davisScore! : -1).compareTo(
          _hasScore(a) ? a.davisScore! : -1,
        );
        if (score != 0) return score;
        final block = (a.blockSequence ?? 0).compareTo(b.blockSequence ?? 0);
        return block != 0 ? block : a.stationNumber.compareTo(b.stationNumber);
      });
    final multipleBlocks = ratings.map((r) => r.blockRunId).toSet().length > 1;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('expert_review_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ReviewOverview(
            reviewCase: reviewCase,
            mean: mean,
            scored: scored,
            loaded: ratings.length,
            high: scored.where((r) => r.davisScore! >= 7).length,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: AppText(
                  'Plant reviews',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${ratings.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const AppText(
            'Highest scores first · tap a photo to enlarge',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const AppText('Plant ratings are unavailable.'),
                  TextButton(
                    onPressed: onRefresh,
                    child: const AppText('Refresh review'),
                  ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
              final columns = largeText || constraints.maxWidth < 340
                  ? 1
                  : constraints.maxWidth >= 720
                  ? 3
                  : 2;
              return Column(
                children: [
                  for (var start = 0; start < visible.length; start += columns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0) const SizedBox(width: 12),
                            Expanded(
                              child: start + column < visible.length
                                  ? _PlantReviewCard(
                                      rating: visible[start + column],
                                      multipleBlocks: multipleBlocks,
                                    )
                                  : const SizedBox(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

bool _hasScore(ExpertPlantRating r) =>
    r.outcome == 'scored' &&
    r.davisScore != null &&
    r.davisScore! >= 0 &&
    r.davisScore! <= 9;

Color _scoreInk(num? score) => switch (daSeverityBand(score)?.referenceRating) {
  1 => const Color(0xFF2D6541),
  3 => const Color(0xFF21608C),
  5 => const Color(0xFF53700F),
  7 => const Color(0xFF8A570B),
  9 => const Color(0xFFB52626),
  _ => AppColors.textSecondary,
};

class _ReviewOverview extends StatelessWidget {
  const _ReviewOverview({
    required this.reviewCase,
    required this.mean,
    required this.scored,
    required this.loaded,
    required this.high,
    required this.onRefresh,
  });
  final ExpertReviewCase reviewCase;
  final double? mean;
  final List<ExpertPlantRating> scored;
  final int loaded, high;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final summary = reviewCase.severitySummary!;
    final facts = summary.monitoring;
    final assessed = DateTime.tryParse('${facts['assessed_at']}');
    final reviewer = facts['reviewer_name'] as String? ?? reviewCase.expertName;
    final ink = _scoreInk(mean);
    final groups = <int>[
      for (final band in daSeverityBands)
        scored
            .where((r) => daSeverityBand(r.davisScore)?.maximum == band.maximum)
            .length,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 17,
              color: Color(0xFF315B43),
            ),
            const AppText(
              'FINALIZED EXPERT REVIEW',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: .8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF315B43),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          reviewCase.fieldName,
          style: const TextStyle(
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        AppText(
          assessed == null
              ? 'Assessment date unavailable'
              : 'Assessment: ${DateFormat.yMMMd().format(assessed.toLocal())}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        Container(
          key: const Key('expert_severity_overview'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE4DD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: ink.withValues(alpha: .06),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppText(
                      'MEAN DAVIS SEVERITY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          mean == null
                              ? 'Unavailable'
                              : '${mean!.toStringAsFixed(2)} / 9',
                          key: const Key('expert_mean_score'),
                          style: TextStyle(
                            fontSize: mean == null ? 28 : 40,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        if (mean != null)
                          AppText(
                            daSeverityClassification(mean),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const AppText(
                      'DA classification of leaf injury',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppText(
                      '${summary.scoredPlants} plants scored${summary.insufficientPlants > 0 ? ' · ${summary.insufficientPlants} insufficient evidence' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (mean == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AppText(
                          scored.isEmpty
                              ? 'No usable plant scores are available.'
                              : 'The complete, matched ratings are needed to display the mean.',
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(12) > 18;
                    final damage = _ReviewMetric(
                      facts: facts,
                      metricKey: 'damage_percentage',
                      title: 'FAW damage',
                      note: 'Old and fresh injury',
                    );
                    final infestation = _ReviewMetric(
                      facts: facts,
                      metricKey: 'current_infestation_indicator',
                      title: 'Sampled infestation',
                      note: 'Expert-assessed fresh damage',
                    );
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              damage,
                              const Divider(height: 24),
                              infestation,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: damage),
                              const SizedBox(width: 18),
                              Expanded(child: infestation),
                            ],
                          );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppText(
                      '$loaded/${summary.reviewedPlants} ratings loaded',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showReviewExplanation(context, summary),
                      icon: const Icon(Icons.info_outline, size: 17),
                      label: const AppText('How to read this'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (scored.isNotEmpty) ...[
          const SizedBox(height: 18),
          const AppText(
            'Damage across sampled plants',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Semantics(
            label:
                'Loaded score distribution: ${[for (var i = 0; i < groups.length; i++) '${daSeverityBands[i].range}: ${groups[i]} plants'].join(', ')}',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      if (groups[i] > 0)
                        Expanded(
                          flex: groups[i],
                          child: Container(
                            height: 8,
                            color: _scoreInk(daSeverityBands[i].maximum),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var i = 0; i < groups.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _scoreInk(daSeverityBands[i].maximum),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${daSeverityBands[i].range}: ${groups[i]}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (high > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AppText(
                '$high ${high == 1 ? 'plant' : 'plants'} rated Davis 7–9. Check these individual findings.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A570B),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (reviewer != null && reviewer.trim().isNotEmpty)
              Text(
                'Reviewed by $reviewer',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            AppText(
              'Finalized ${DateFormat.yMMMd().add_jm().format(summary.finalizedAt.toLocal())}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (loaded != summary.reviewedPlants)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Expanded(
                  child: AppText(
                    'Some ratings are missing. Distribution shows loaded plants only.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF8A570B),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onRefresh,
                  child: const AppText('Refresh'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
    required this.facts,
    required this.metricKey,
    required this.title,
    required this.note,
  });
  final Map<String, dynamic> facts;
  final String metricKey, title, note;
  @override
  Widget build(BuildContext context) {
    final metric = facts[metricKey];
    final available = metric is Map && metric['value'] is num;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          available
              ? '${(metric['value'] as num).toStringAsFixed(1)}%'
              : 'Unavailable',
          style: TextStyle(
            fontSize: available ? 25 : 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243E32),
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          available
              ? '${metric['numerator']} of ${metric['denominator']} plants'
              : 'No usable recorded rate',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        AppText(
          note,
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

void _showReviewExplanation(
  BuildContext context,
  ExpertSeveritySummary summary,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText(
            'Reading the expert findings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          const AppText(
            'Davis severity',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const AppText(
            'The mean uses the saved scores from 0–9, including zero. Unscorable plants are excluded. The supplied DA labels describe leaf injury, not an infestation percentage.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 14),
          const AppText(
            'Damage and infestation',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const AppText(
            'FAW damage includes old and fresh injury. Sampled infestation uses expert-assessed fresh damage at the assessment date. Uncertain freshness and insufficient evidence are excluded from its denominator; unavailable plants are not counted as unaffected.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 14),
          AppText(
            '${summary.reviewedPlants} reviewed · ${summary.scoredPlants} scored · ${summary.insufficientPlants} insufficient evidence',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          AppText(
            summary.monitoring['monitoring_version'] == 2
                ? '${summary.monitoring['fresh_plants'] ?? 'Not recorded'} fresh · ${summary.monitoring['old_only_plants'] ?? 'Not recorded'} old only · ${summary.monitoring['uncertain_freshness_plants'] ?? 'Not recorded'} freshness uncertain'
                : 'Freshness was not recorded for this review.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const AppText(
            'Each plant shows its saved rating, description, expert note and submitted photos. Scale descriptions are reference guidance, not extra observations about the photo.',
            style: TextStyle(height: 1.5),
          ),
        ],
      ),
    ),
  ),
);

class _PlantReviewCard extends StatelessWidget {
  const _PlantReviewCard({required this.rating, required this.multipleBlocks});
  final ExpertPlantRating rating;
  final bool multipleBlocks;

  @override
  Widget build(BuildContext context) {
    final score = _hasScore(rating) ? rating.davisScore : null;
    final ink = _scoreInk(score);
    final label = rating.blockSequence != null
        ? 'Block ${rating.blockSequence} · ${rating.plantLabel}'
        : multipleBlocks
        ? 'Block not recorded · ${rating.plantLabel}'
        : rating.plantLabel;
    return Container(
      key: ValueKey('expert_plant_${rating.identityKey}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE4DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rating.photos.isEmpty)
            const AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(
                color: Color(0xFFF0F2EC),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: AppText(
                      'No photos available',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 140 &&
                        rating.photos.length > 1 &&
                        MediaQuery.textScalerOf(context).scale(11) <= 15
                    ? 2
                    : 1;
                return Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < rating.photos.length; i++)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 2) /
                            columns,
                        child: ColoredBox(
                          color: const Color(0xFFF0F2EC),
                          child: _ReviewPhoto(
                            photo: rating.photos[i],
                            label: '$label · Photo ${i + 1}',
                            aspectRatio: 4 / (3 * columns),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                AppText(
                  score == null
                      ? rating.outcome == 'insufficient_evidence'
                            ? 'Cannot be assessed'
                            : 'Rating unavailable'
                      : 'Davis $score / 9',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (score != null) ...[
                  const SizedBox(height: 3),
                  AppText(
                    daSeverityClassification(score),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                AppText(
                  rating.freshnessLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (rating.associationAmbiguous) ...[
                  const SizedBox(height: 6),
                  const AppText(
                    'Plant link needs checking',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8A570B)),
                  ),
                ],
                const Divider(height: 20),
                if (score != null) ...[
                  const AppText(
                    'Score guide',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                AppText(
                  score == null
                      ? rating.outcome == 'insufficient_evidence'
                            ? 'The submitted photos did not support a usable score.'
                            : 'No usable score is recorded.'
                      : _davisDescriptions[score],
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (rating.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const AppText(
                    'Expert note',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF315B43),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rating.note,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
