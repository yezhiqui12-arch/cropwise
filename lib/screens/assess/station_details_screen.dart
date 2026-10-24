import '../../models/automatic_screening.dart';
import 'ribbon_ticket_card.dart';
import '../../localization/app_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/scouting_workflow_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../services/assessment_protocol_selector.dart';
import '../../services/evidence_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import 'plant_evidence_support.dart';
import 'plant_details_screen.dart';

/// Read-only presentation of one saved station in assessment history.
///
/// This screen deliberately consumes the history projection instead of a live
/// workflow provider. It never repairs evidence, reruns image analysis, or
/// writes an observation review.
class StationDetailsScreen extends StatelessWidget {
  const StationDetailsScreen({
    super.key,
    required this.detail,
    required this.station,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    final stationRecord = station.station;
    final stage = detail.assessment.growthStage;
    final isSeedling = _isSeedlingStage(stage);
    final units = stationRecord == null
        ? const <PlantingUnitObservationRecord>[]
        : detail.units
              .where((unit) => unit.stationId == stationRecord.id)
              .toList(growable: false);
    final evidence = stationRecord == null
        ? const <AssessmentEvidenceEntry>[]
        : detail.evidence
              .where((entry) => entry.stationId == stationRecord.id)
              .toList(growable: false);
    final readyEvidence = evidence
        .where(
          (entry) =>
              entry.media.storageState == DatabaseCodes.evidenceStorageReady,
        )
        .toList(growable: false);
    final missingEvidence = evidence.length - readyEvidence.length;

    return Scaffold(
      key: const Key('station_details_screen'),
      appBar: AppBar(
        centerTitle: true,
        title: AppText(
          '${station.requiredPlantCount == 1 ? 'Plant' : 'Station'} ${station.stationNumber} details',
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _StationHero(detail: detail, station: station),
                const SizedBox(height: 12),
                _LocationAndReviewCard(station: station),
                const SizedBox(height: 16),
                AppText(
                  station.requiredPlantCount == 1
                      ? 'Plant summary'
                      : 'Station summary',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                _StationSummaryGrid(
                  station: station,
                  units: units,
                  readyPhotoCount: readyEvidence.length,
                  isSeedling: isSeedling,
                  stage: stage,
                ),
                if (missingEvidence > 0) ...[
                  const SizedBox(height: 10),
                  _RecordNotice(
                    icon: Icons.broken_image_outlined,
                    text:
                        '$missingEvidence ${missingEvidence == 1 ? 'evidence file is' : 'evidence files are'} marked missing and not counted as available photos.',
                  ),
                ],
                const SizedBox(height: 18),
                _RecordedContext(detail: detail, stationRecord: stationRecord),
                const SizedBox(height: 14),
                const _ProvenanceNotice(),
                const SizedBox(height: 20),
                _PlantAssessmentGrid(
                  detail: detail,
                  station: station,
                  storage: storage,
                  isSeedling: isSeedling,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationHero extends StatelessWidget {
  const _StationHero({required this.detail, required this.station});

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;

  @override
  Widget build(BuildContext context) {
    final stage = detail.assessment.growthStage;
    final status = _stationStatus(station);
    final cropCode = detail.workspace.cropCycle?.cropCode.trim();
    final crop = cropCode == null || cropCode.isEmpty
        ? 'Crop not recorded'
        : _codeLabel(cropCode);
    return ClipRRect(
      key: const Key('station_details_option_b_hero'),
      borderRadius: AppRadii.prominentBorder,
      child: SizedBox(
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Image.asset(
                _stageImage(stage),
                fit: BoxFit.cover,
                cacheWidth: 960,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0xD8000000)],
                  stops: [0.2, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xCC07100F),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const AppText(
                  'Illustrative growth-stage image',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppText(
                        'Station ${station.stationNumber}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              shadows: const [Shadow(blurRadius: 5)],
                            ),
                      ),
                      _StatusPill(presentation: status),
                    ],
                  ),
                  const SizedBox(height: 7),
                  AppText(
                    'Block ${station.prepared.run.blockSequence} · ${detail.workspace.field.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: const [Shadow(blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    '$crop · ${AssessmentProtocolSelector.growthStageLabel(stage)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFF2F5F0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationAndReviewCard extends StatelessWidget {
  const _LocationAndReviewCard({required this.station});

  final StationSnapshot station;

  @override
  Widget build(BuildContext context) {
    final record = station.station;
    final facts = <_BandFact>[
      _BandFact(
        icon: Icons.calendar_today_outlined,
        label: record?.capturedAt == null
            ? 'Location time not recorded'
            : 'Location captured\n${_dateTime(record!.capturedAt!)}',
      ),
      _BandFact(
        icon: Icons.location_on_outlined,
        label: _stationLocation(record),
      ),
      _BandFact(
        icon: Icons.fact_check_outlined,
        label: station.reviewedAt == null
            ? 'Review not recorded'
            : '${station.reviewIsCurrent ? 'Review current' : 'Review needs updating'}\n${_dateTime(station.reviewedAt!)}',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: AppRadii.cardBorder,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          if (!wide) {
            return Column(
              children: [
                for (var index = 0; index < facts.length; index++) ...[
                  _BandFactTile(fact: facts[index]),
                  if (index < facts.length - 1) const Divider(height: 1),
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < facts.length; index++) ...[
                  Expanded(child: _BandFactTile(fact: facts[index])),
                  if (index < facts.length - 1) const VerticalDivider(width: 1),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BandFactTile extends StatelessWidget {
  const _BandFactTile({required this.fact});

  final _BandFact fact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(fact.icon, size: 20, color: AppColors.highContrastGreen),
        const SizedBox(width: 10),
        Expanded(
          child: AppText(
            fact.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _StationSummaryGrid extends StatelessWidget {
  const _StationSummaryGrid({
    required this.station,
    required this.units,
    required this.readyPhotoCount,
    required this.isSeedling,
    required this.stage,
  });

  final StationSnapshot station;
  final List<PlantingUnitObservationRecord> units;
  final int readyPhotoCount;
  final bool isSeedling;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final scores =
        station.plants
            .map((item) => item.vegetativeOrNull?.daBafsLeafDamageScore)
            .whereType<int>()
            .toList()
          ..sort();
    final attention = _stationAttentionMetric(station, stage);
    final metrics = isSeedling
        ? <_SummaryMetric>[
            _SummaryMetric(
              Icons.format_list_numbered,
              '${units.length}',
              'Planting positions recorded',
            ),
            _SummaryMetric(
              Icons.fact_check_outlined,
              '${station.plants.length}',
              'Living-seedling records',
            ),
            _SummaryMetric(
              Icons.photo_camera_outlined,
              '$readyPhotoCount',
              'Available photos',
            ),
            _SummaryMetric(
              Icons.fact_check_outlined,
              _stationStatus(station).label,
              'Station review',
            ),
          ]
        : <_SummaryMetric>[
            _SummaryMetric(
              Icons.fact_check_outlined,
              '${station.plants.length}',
              'Plant records',
            ),
            _SummaryMetric(
              Icons.flag_outlined,
              '${attention.count}',
              attention.label,
            ),
            _SummaryMetric(
              Icons.photo_camera_outlined,
              '$readyPhotoCount',
              'Available photos',
            ),
            scores.isEmpty
                ? _SummaryMetric(
                    Icons.fact_check_outlined,
                    _stationStatus(station).label,
                    'Station review',
                  )
                : _SummaryMetric(
                    Icons.analytics_outlined,
                    _median(scores).toStringAsFixed(
                      _median(scores) == _median(scores).roundToDouble()
                          ? 0
                          : 1,
                    ),
                    'Median DA-BAFS · ${scores.length} scored',
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
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _SummaryTile(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.metric});

  final _SummaryMetric metric;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 104),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(metric.icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 7),
        AppText(
          metric.value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        AppText(
          metric.label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _RecordedContext extends StatelessWidget {
  const _RecordedContext({required this.detail, required this.stationRecord});

  final AssessmentHistoryDetail detail;
  final StationRecord? stationRecord;

  @override
  Widget build(BuildContext context) {
    final facts = _contextFacts(detail, stationRecord);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          'Recorded context',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: AppRadii.cardBorder,
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: facts.isEmpty
              ? const AppText(
                  'No station accessibility notes or assessment-level field conditions were recorded.',
                )
              : Column(
                  children: [
                    for (var index = 0; index < facts.length; index++) ...[
                      _ContextFactRow(fact: facts[index]),
                      if (index < facts.length - 1) const Divider(height: 18),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 7),
        AppText(
          'Weather and season entries are assessment- or crop-cycle-level context, not station measurements.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _ContextFactRow extends StatelessWidget {
  const _ContextFactRow({required this.fact});

  final _ContextFact fact;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(fact.icon, color: AppColors.primary, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fact.label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              fact.value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ProvenanceNotice extends StatelessWidget {
  const _ProvenanceNotice();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('station_details_read_only_notice'),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: AppRadii.controlBorder,
      border: Border.all(color: const Color(0xFFC9E4C6)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.visibility_outlined, size: 21, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: AppText(
            'Read-only saved observations. The current record does not store model suggestions separately, so this view does not attribute findings to AI or show diagnostic certainty. Station review status is shown separately.',
          ),
        ),
      ],
    ),
  );
}

class _PlantAssessmentGrid extends StatelessWidget {
  const _PlantAssessmentGrid({
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AppText(
              '${isSeedling ? 'Seedling' : 'Plant'} assessments (${station.requiredPlantCount})',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          AppText(
            '${station.plants.length} recorded',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          const columns = 1;
          const gap = 10.0;
          final width = columns == 2
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;
          return Wrap(
            key: const Key('plant_assessment_card_grid'),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (
                var position = 1;
                position <= station.requiredPlantCount;
                position++
              )
                SizedBox(
                  width: width,
                  child: _PlantAssessmentCard(
                    key: Key('station_position_$position'),
                    detail: detail,
                    station: station,
                    position: position,
                    record: _plantAt(station.plants, position),
                    storage: storage,
                    isSeedling: isSeedling,
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _PlantAssessmentCard extends StatelessWidget {
  const _PlantAssessmentCard({
    super.key,
    required this.detail,
    required this.station,
    required this.position,
    required this.record,
    required this.storage,
    required this.isSeedling,
  });

  final AssessmentHistoryDetail detail;
  final StationSnapshot station;
  final int position;
  final StationPlantRecord? record;
  final EvidenceStorageService storage;
  final bool isSeedling;

  @override
  Widget build(BuildContext context) {
    final item = record;
    final evidence = item == null
        ? const <AssessmentEvidenceEntry>[]
        : assessmentEvidenceForPlant(
            detail: detail,
            station: station,
            plantObservationId: item.plant.id,
            plantPosition: item.plant.sequenceNumber,
            availableOnly: true,
          );
    final status = item == null
        ? const _RecordPresentation(
            'Not recorded',
            Color(0xFFF0F1F2),
            Color(0xFF535A61),
            Icons.remove,
          )
        : _recordStatus(item, detail.assessment.growthStage);
    final subject = isSeedling ? 'Seedling' : 'Plant';
    final summary = item == null
        ? 'No ${subject.toLowerCase()} observation is saved.'
        : _plantSummary(item, detail.assessment.growthStage);
    final positive =
        item != null &&
        item.plant.plantStatus == DatabaseCodes.plantCurrentPositive;
    final negative =
        item != null && item.plant.plantStatus == DatabaseCodes.plantNegative;
    final color = positive
        ? const Color(0xFFC83E5C)
        : negative
        ? const Color(0xFF35893E)
        : status.foreground;
    return RibbonTicketCard(
      plant: true,
      status: status.label,
      title:
          '$subject ${station.requiredPlantCount == 1 ? station.stationNumber : position}',
      description: summary,
      photos: evidence.length,
      color: color,
      icon: positive
          ? Icons.flag_outlined
          : negative
          ? Icons.check_circle_outline
          : status.icon,
      onTap: item == null
          ? null
          : () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => PlantAssessmentDetailsScreen(
                  detail: detail,
                  station: station,
                  record: item,
                  storage: storage,
                ),
              ),
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.presentation});

  final _RecordPresentation presentation;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: presentation.background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Wrap(
      spacing: 5,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(presentation.icon, size: 15, color: presentation.foreground),
        Text(
          presentation.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: presentation.foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _RecordNotice extends StatelessWidget {
  const _RecordNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1CF),
      borderRadius: AppRadii.controlBorder,
      border: Border.all(color: const Color(0xFFF2D896)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFFA65E00)),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

List<_ContextFact> _contextFacts(
  AssessmentHistoryDetail detail,
  StationRecord? station,
) {
  final facts = <_ContextFact>[];
  final accessibility = station?.accessibilityNotes?.trim();
  if (accessibility != null && accessibility.isNotEmpty) {
    facts.add(
      _ContextFact(
        Icons.accessible_outlined,
        'Station accessibility notes',
        accessibility,
      ),
    );
  }
  final weather = _parseContext(detail.assessment.weatherContext);
  final rainAnswer = weather['rain_wet_field_last_48h'];
  if (rainAnswer != null) {
    facts.add(
      _ContextFact(
        Icons.water_drop_outlined,
        'Rain wet the field in the previous 48 hours',
        switch (rainAnswer) {
          'yes' => 'Yes',
          'no' => 'No',
          'not_sure' => 'Not sure',
          _ => _codeLabel(rainAnswer),
        },
      ),
    );
  }
  final precipitation = weather['open_meteo_precipitation_last_48h_mm'];
  if (precipitation != null) {
    facts.add(
      _ContextFact(
        Icons.water_drop_outlined,
        'Assessment weather context',
        '$precipitation mm precipitation in the previous 48 hours (Open-Meteo)',
      ),
    );
  }
  final surface = weather['field_surface'];
  if (surface != null) {
    facts.add(
      _ContextFact(
        Icons.landscape_outlined,
        'Recorded field surface',
        switch (surface) {
          'dry' => 'Mostly dry and firm',
          'damp' => 'Damp but easy to walk',
          'muddy' => 'Muddy or slippery',
          'standing_water' => 'Standing water is present',
          'not_sure' => 'Not sure',
          _ => _codeLabel(surface),
        },
      ),
    );
  }
  final heavyRain = detail.assessment.recentHeavyRainAt;
  if (heavyRain != null) {
    facts.add(
      _ContextFact(
        Icons.thunderstorm_outlined,
        'Recent heavy rain recorded',
        _dateTime(heavyRain),
      ),
    );
  }
  final season = detail.workspace.cropCycle?.seasonConditions?.trim();
  if (season != null && season.isNotEmpty) {
    facts.add(
      _ContextFact(
        Icons.calendar_view_month_outlined,
        'Crop-cycle season conditions',
        season,
      ),
    );
  }
  return facts;
}

Map<String, String> _parseContext(String? encoded) {
  if (encoded == null || encoded.trim().isEmpty) return const {};
  final values = <String, String>{};
  for (final part in encoded.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0 || separator == part.length - 1) continue;
    values[part.substring(0, separator).trim()] = part
        .substring(separator + 1)
        .trim();
  }
  return values;
}

String _stationLocation(StationRecord? station) {
  if (station == null) return 'Station not started';
  if (station.latitude != null && station.longitude != null) {
    final accuracy = station.gpsAccuracyM;
    return '${station.latitude!.toStringAsFixed(5)}, ${station.longitude!.toStringAsFixed(5)}${accuracy == null ? '' : '\nAccuracy ±${accuracy.toStringAsFixed(0)} m'}';
  }
  final reason = station.notLocatedReason;
  if (reason == null || reason.trim().isEmpty) return 'Location not recorded';
  return 'Location unavailable\n${switch (reason) {
    DatabaseCodes.stationLocationServicesOff => 'Location services were off',
    DatabaseCodes.stationPermissionDenied => 'Location permission was denied',
    DatabaseCodes.stationPermissionBlocked => 'Location permission was blocked',
    DatabaseCodes.stationNoCurrentFix => 'No current GPS fix',
    DatabaseCodes.stationUnsafeToWait => 'Unsafe to wait for GPS',
    DatabaseCodes.stationLocationDeviceError => 'Device or location error',
    DatabaseCodes.stationLocationOther => 'Other recorded reason',
    _ => _codeLabel(reason),
  }}';
}

_RecordPresentation _stationStatus(StationSnapshot station) {
  if (station.station == null) {
    return const _RecordPresentation(
      'Not started',
      Color(0xFFF0F1F2),
      Color(0xFF535A61),
      Icons.radio_button_unchecked,
    );
  }
  if (station.reviewIsCurrent) {
    return const _RecordPresentation(
      'Review current',
      Color(0xFFDDF1DB),
      AppColors.highContrastGreen,
      Icons.check_circle_outline,
    );
  }
  if (station.reviewedAt != null) {
    return const _RecordPresentation(
      'Review needs updating',
      Color(0xFFFFE8B8),
      Color(0xFF755100),
      Icons.update_outlined,
    );
  }
  return const _RecordPresentation(
    'Review not recorded',
    Color(0xFFE3EDF7),
    Color(0xFF24547A),
    Icons.pending_actions_outlined,
  );
}

_RecordPresentation _plantStatus(String status) => switch (status) {
  AutomaticScreening.positiveStatus => const _RecordPresentation(
    'Damage detected',
    Color(0xFFFDE8E8),
    Color(0xFFB3261E),
    Icons.image_search_outlined,
  ),
  AutomaticScreening.negativeStatus => const _RecordPresentation(
    'No damage detected',
    Color(0xFFEAF6EE),
    Color(0xFF176B3A),
    Icons.check_circle_outline,
  ),
  AutomaticScreening.unavailableStatus => const _RecordPresentation(
    'Not assessed',
    Color(0xFFF1F5F9),
    Color(0xFF64748B),
    Icons.help_outline,
  ),
  DatabaseCodes.plantCurrentPositive => const _RecordPresentation(
    'Current-positive',
    Color(0xFFFFD9DE),
    Color(0xFF8B1E2D),
    Icons.flag_outlined,
  ),
  DatabaseCodes.plantNegative => const _RecordPresentation(
    'No current signs',
    Color(0xFFDDF1DB),
    AppColors.highContrastGreen,
    Icons.check_circle_outline,
  ),
  DatabaseCodes.plantOldDamageOnly => const _RecordPresentation(
    'Old damage only',
    Color(0xFFFFE8B8),
    Color(0xFF755100),
    Icons.history_outlined,
  ),
  DatabaseCodes.plantPossibleNonFaw => const _RecordPresentation(
    'Possible non-FAW',
    Color(0xFFFFE8B8),
    Color(0xFF755100),
    Icons.help_outline,
  ),
  DatabaseCodes.plantUncertain => const _RecordPresentation(
    'Uncertain',
    Color(0xFFE6E7EB),
    Color(0xFF42464D),
    Icons.help_center_outlined,
  ),
  DatabaseCodes.plantNotAssessable => const _RecordPresentation(
    'Not assessable',
    Color(0xFFE6E7EB),
    Color(0xFF42464D),
    Icons.not_interested_outlined,
  ),
  _ => _RecordPresentation(
    _codeLabel(status),
    AppColors.primaryLight,
    AppColors.highContrastGreen,
    Icons.description_outlined,
  ),
};

_RecordPresentation _recordStatus(StationPlantRecord item, String stage) {
  if (AutomaticScreening.parse(item.plant.wholePlantContextNote) != null)
    return _plantStatus(item.plant.plantStatus);
  if (!item.plant.assessable) {
    return const _RecordPresentation(
      'Not assessable',
      Color(0xFFE6E7EB),
      Color(0xFF42464D),
      Icons.not_interested_outlined,
    );
  }
  if (stage == 'vt_r2') {
    return switch (item.reproductive?.classification) {
      DatabaseCodes.reproductiveInfested => const _RecordPresentation(
        'Currently infested',
        Color(0xFFFFD9DE),
        Color(0xFF8B1E2D),
        Icons.flag_outlined,
      ),
      DatabaseCodes.reproductiveNotInfested => const _RecordPresentation(
        'Not currently infested',
        Color(0xFFDDF1DB),
        AppColors.highContrastGreen,
        Icons.check_circle_outline,
      ),
      DatabaseCodes.reproductiveUncertain => const _RecordPresentation(
        'Uncertain',
        Color(0xFFE6E7EB),
        Color(0xFF42464D),
        Icons.help_center_outlined,
      ),
      DatabaseCodes.reproductiveNotAssessable => const _RecordPresentation(
        'Not assessable',
        Color(0xFFE6E7EB),
        Color(0xFF42464D),
        Icons.not_interested_outlined,
      ),
      _ => const _RecordPresentation(
        'Stage record unavailable',
        Color(0xFFE3EDF7),
        Color(0xFF24547A),
        Icons.description_outlined,
      ),
    };
  }
  if (stage == 'r3_r6') {
    final classification = item.ear?.externalClassification;
    return switch (classification) {
      DatabaseCodes.earExternalActive => const _RecordPresentation(
        'Active ear evidence',
        Color(0xFFFFD9DE),
        Color(0xFF8B1E2D),
        Icons.flag_outlined,
      ),
      DatabaseCodes.earExternalNegative => const _RecordPresentation(
        'No relevant ear evidence',
        Color(0xFFDDF1DB),
        AppColors.highContrastGreen,
        Icons.check_circle_outline,
      ),
      DatabaseCodes.earExternalUncertain => const _RecordPresentation(
        'Uncertain',
        Color(0xFFE6E7EB),
        Color(0xFF42464D),
        Icons.help_center_outlined,
      ),
      DatabaseCodes.earExternalNotAssessable => const _RecordPresentation(
        'Not assessable',
        Color(0xFFE6E7EB),
        Color(0xFF42464D),
        Icons.not_interested_outlined,
      ),
      null => const _RecordPresentation(
        'Stage record unavailable',
        Color(0xFFE3EDF7),
        Color(0xFF24547A),
        Icons.description_outlined,
      ),
      _ => _RecordPresentation(
        _codeLabel(classification),
        const Color(0xFFFFE8B8),
        const Color(0xFF755100),
        Icons.warning_amber_outlined,
      ),
    };
  }
  return _plantStatus(item.plant.plantStatus);
}

({int count, String label}) _stationAttentionMetric(
  StationSnapshot station,
  String stage,
) {
  final screens = station.plants
      .map((p) => AutomaticScreening.parse(p.plant.wholePlantContextNote))
      .whereType<AutomaticScreening>()
      .toList();
  if (screens.isNotEmpty)
    return (
      count: screens.where((s) => s.available && s.positive).length,
      label: 'Damage detected',
    );
  if (stage == 'vt_r2') {
    return (
      count: station.plants
          .where(
            (item) =>
                item.reproductive?.classification ==
                DatabaseCodes.reproductiveInfested,
          )
          .length,
      label: 'Currently infested records',
    );
  }
  if (stage == 'r3_r6') {
    return (
      count: station.plants
          .where(
            (item) =>
                item.ear?.externalClassification ==
                DatabaseCodes.earExternalActive,
          )
          .length,
      label: 'Active-ear records',
    );
  }
  return (
    count: station.plants
        .where(
          (item) =>
              item.plant.plantStatus == DatabaseCodes.plantCurrentPositive,
        )
        .length,
    label: 'Current-positive records',
  );
}

String _plantSummary(StationPlantRecord item, String stage) {
  final screening = AutomaticScreening.parse(item.plant.wholePlantContextNote);
  if (screening != null) return screening.label;
  final plant = item.plant;
  if (!plant.assessable) {
    final reason = plant.notAssessableReason?.trim();
    return reason == null || reason.isEmpty
        ? 'Saved as not assessable.'
        : 'Not assessable · $reason';
  }
  if (stage == 'vt_r2') {
    final observation = item.reproductive;
    if (observation == null) return 'Stage observation is not available.';
    final signs = <String>[
      if (observation.freshFeedingPresent) 'fresh feeding',
      if (observation.larvaPresent) 'larva present',
      if (observation.frassPresent) 'frass',
      if (observation.earHuskPenetrationVisible) 'husk penetration',
    ];
    return signs.isEmpty ? 'No listed signs recorded' : signs.join(', ');
  }
  if (stage == 'r3_r6') {
    final ear = item.ear;
    if (ear == null) return 'Ear observation is not available.';
    final opening = ear.opened
        ? ear.internalClassification == null
              ? 'opened; internal classification not recorded'
              : 'opened · ${_codeLabel(ear.internalClassification)}'
        : 'external observation only';
    return opening;
  }
  final vegetative = item.vegetativeOrNull;
  if (vegetative == null) {
    return 'Stage observation is not available.';
  }
  final signs = <String>[
    if (vegetative.smallFreshWindowpanes) 'fresh windowpanes',
    if (vegetative.whorlFeedingSign) 'whorl-feeding sign',
    if (vegetative.freshFrass) 'fresh frass',
    if (vegetative.larvaVisible) 'larva visible',
  ];
  return signs.isEmpty ? 'No listed signs recorded' : signs.join(', ');
}

StationPlantRecord? _plantAt(List<StationPlantRecord> plants, int position) {
  for (final item in plants) {
    if (item.plant.sequenceNumber == position) return item;
  }
  return null;
}

bool _isSeedlingStage(String stage) => const {'ve', 'v1', 'v2'}.contains(stage);

String _stageImage(String stage) => switch (stage) {
  've' || 'v1' || 'v2' => 'assets/images/growth_stages/maize_emergence.jpg',
  'v3_v6' => 'assets/images/growth_stages/maize_young_vegetative.jpg',
  'v7_v12' => 'assets/images/growth_stages/maize_tall_vegetative.jpg',
  'vt_r2' => 'assets/images/growth_stages/maize_silks.jpg',
  'r3_r6' => 'assets/images/growth_stages/maize_mature_kernels.jpg',
  _ => 'assets/images/growth_stages/maize_young_vegetative.jpg',
};

String _dateTime(DateTime value) =>
    DateFormat.yMMMd().add_jm().format(value.toLocal());

String _codeLabel(String? value) {
  if (value == null || value.trim().isEmpty) return 'Not recorded';
  final words = value.trim().replaceAll('_', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

double _median(List<int> sorted) {
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

class _BandFact {
  const _BandFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _SummaryMetric {
  const _SummaryMetric(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;
}

class _ContextFact {
  const _ContextFact(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _RecordPresentation {
  const _RecordPresentation(
    this.label,
    this.background,
    this.foreground,
    this.icon,
  );

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
}
