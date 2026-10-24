import '../services/map_view_policy.dart';
import 'dart:ui' as ui;
import '../localization/app_text.dart';
import '../localization/app_language.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_history_repository.dart';
import '../data/repositories/field_repository.dart';
import '../models/assessment_history_models.dart';
import '../providers/field_workspace_provider.dart';
import '../services/polygon_calculator.dart';
import '../services/evidence_storage_service.dart';
import '../screens/assess/assessment_details_screen.dart';
import '../screens/assess/assessment_results_screen.dart';
import '../screens/assess/assessments_screen.dart';
import '../screens/fields_screen.dart';
import '../theme/app_colors.dart';

class HomeActiveFieldHero extends StatelessWidget {
  const HomeActiveFieldHero({super.key, this.enableMap = true});

  final bool enableMap;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FieldWorkspaceProvider>();
    if (provider.isLoading) {
      return const SizedBox(
        height: 250,
        child: Card(child: Center(child: CircularProgressIndicator())),
      );
    }
    final workspace = provider.activeWorkspace;
    if (workspace == null) {
      return _HomeCard(
        child: Column(
          children: [
            const Icon(
              Icons.landscape_outlined,
              size: 42,
              color: AppColors.primary,
            ),
            const SizedBox(height: 10),
            const AppText(
              'Set up your first maize field',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const AppText(
              'Add a field to start assessments and keep its records together.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('home_add_first_field_button'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const FieldsScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const AppText('Add your first field'),
            ),
          ],
        ),
      );
    }
    return _ActiveFieldContent(
      key: ValueKey(
        'home-active-field-${workspace.field.id}-${workspace.boundary?.id}',
      ),
      workspace: workspace,
      enableMap: enableMap,
    );
  }
}

class _ActiveFieldContent extends StatelessWidget {
  const _ActiveFieldContent({
    super.key,
    required this.workspace,
    required this.enableMap,
  });
  final FieldWorkspaceRecord workspace;
  final bool enableMap;

  @override
  Widget build(BuildContext context) {
    final field = workspace.field;
    final cycle = workspace.cropCycle;
    final area = workspace.boundary?.areaHectares;
    final location = [
      field.barangay,
      field.municipalityCity,
      field.province,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    final planted = cycle?.plantingDate?.toLocal();
    final age = planted == null
        ? null
        : DateTime.now().difference(planted).inDays.clamp(0, 99999);
    return _HomeCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 168,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: enableMap
                        ? _ActiveFieldMap(
                            key: ValueKey(
                              'home-active-map-${workspace.field.id}-${workspace.boundary?.id}',
                            ),
                            workspace: workspace,
                          )
                        : const ColoredBox(color: AppColors.surfaceContainer),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEFFFFFFF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const AppText(
                        'ACTIVE FIELD',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 13),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FieldFact(
                          'AREA',
                          area == null
                              ? 'Not entered'
                              : '${area.toStringAsFixed(2)} ha',
                        ),
                      ),
                      Expanded(
                        child: _FieldFact(
                          'PLANTED',
                          planted == null
                              ? 'Not entered'
                              : DateFormat('MMM d').format(planted),
                        ),
                      ),
                      Expanded(
                        child: _FieldFact(
                          'CROP AGE',
                          age == null ? '—' : AppWords.of(context).days(age),
                        ),
                      ),
                    ],
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

class _FieldFact extends StatelessWidget {
  const _FieldFact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 3),
      AppText(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );
}

class _ActiveFieldMap extends StatelessWidget {
  const _ActiveFieldMap({super.key, required this.workspace});

  final FieldWorkspaceRecord workspace;

  @override
  Widget build(BuildContext context) {
    final boundary = workspace.boundary;
    final outline = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    ).toList(growable: false);
    final fallback =
        boundary?.centroidLatitude != null &&
            boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : const LatLng(17.7905, 121.4781);
    final center = outline.isEmpty
        ? fallback
        : PolygonCalculator.calculateCenter(outline);
    return Semantics(
      image: true,
      label: 'ArcGIS map of ${workspace.field.name} and its saved boundary',
      child: FlutterMap(
        key: ValueKey('arcgis-${workspace.field.id}-${workspace.boundary?.id}'),
        options: MapOptions(
          minZoom: MapViewPolicy.minZoom,
          maxZoom: MapViewPolicy.maxZoom,
          initialCenter: MapViewPolicy.initialCenter(center),
          initialZoom: outline.isEmpty ? 15 : 17,
          initialCameraFit: outline.length >= 3
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(outline),
                  padding: const EdgeInsets.all(22),
                  maxZoom: 18,
                )
              : null,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
          backgroundColor: AppColors.surfaceContainer,
        ),
        children: [
          TileLayer(
            tileUpdateTransformer: TileUpdateTransformers.debounce(
              const Duration(milliseconds: 160),
            ),
            panBuffer: 0,
            keepBuffer: 3,
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.wormwise.app.wormwise',
            maxNativeZoom: 18,
          ),
          TileLayer(
            tileUpdateTransformer: TileUpdateTransformers.debounce(
              const Duration(milliseconds: 160),
            ),
            panBuffer: 0,
            keepBuffer: 3,
            urlTemplate:
                'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.wormwise.app.wormwise',
            maxNativeZoom: 19,
          ),
          if (outline.length >= 3)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: outline,
                  color: const Color(0x2419C85A),
                  borderColor: const Color(0xAA8DFF63),
                  borderStrokeWidth: 7,
                ),
                Polygon(
                  points: outline,
                  color: Colors.transparent,
                  borderColor: const Color(0xFF064D2B),
                  borderStrokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [9, 6]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class HomeRecentAssessmentsCard extends StatelessWidget {
  const HomeRecentAssessmentsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final fieldId = context.watch<FieldWorkspaceProvider>().activeFieldId;
    final records = AssessmentHistoryRepository(
      context.read<AppDatabase>(),
    ).watchPage(fieldId: fieldId, limit: 3);
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Recent Assessments',
            action: 'View all',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const AssessmentsScreen()),
            ),
          ),
          StreamBuilder<List<AssessmentHistoryEntry>>(
            stream: records,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <AssessmentHistoryEntry>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: AppText(
                    'Completed and in-progress assessments will appear here.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _RecentAssessmentRow(record: entries[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecentAssessmentRow extends StatelessWidget {
  const _RecentAssessmentRow({required this.record});
  final AssessmentHistoryEntry record;
  @override
  Widget build(BuildContext context) {
    final active = assessmentResumeLabel(record.status) != null;
    return InkWell(
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => record.status == DatabaseCodes.completed
              ? AssessmentResultsScreen(assessmentId: record.id)
              : AssessmentDetailsScreen(assessmentId: record.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            _AssessmentEvidenceThumbnail(localUri: record.evidenceThumbnailUri),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fieldName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    '${DateFormat('MMM d, yyyy').format(record.date.toLocal())}  •  ${record.growthStage.toUpperCase().replaceAll('_', '–')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFFFFEAB0)
                    : const Color(0xFFDDF4E3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AppText(
                active ? 'In progress' : 'Completed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? const Color(0xFF805800)
                      : const Color(0xFF075E2F),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AssessmentEvidenceThumbnail extends StatefulWidget {
  const _AssessmentEvidenceThumbnail({this.localUri});

  final String? localUri;

  @override
  State<_AssessmentEvidenceThumbnail> createState() =>
      _AssessmentEvidenceThumbnailState();
}

class _AssessmentEvidenceThumbnailState
    extends State<_AssessmentEvidenceThumbnail> {
  Future<File?>? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AssessmentEvidenceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localUri != widget.localUri) _resolve();
  }

  void _resolve() {
    final uri = widget.localUri;
    _file = uri == null
        ? Future<File?>.value()
        : EvidenceStorageService()
              .resolve(uri)
              .then((file) async {
                return await file.exists() ? file : null;
              })
              .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 54,
      height: 46,
      child: FutureBuilder<File?>(
        future: _file,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file != null) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _EvidenceFallback(),
            );
          }
          return const _EvidenceFallback();
        },
      ),
    ),
  );
}

class _EvidenceFallback extends StatelessWidget {
  const _EvidenceFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF174F2B), Color(0xFF7DAA48)]),
    ),
    child: Icon(Icons.agriculture_rounded, color: Colors.white),
  );
}

class HomeEvidenceNotice extends StatefulWidget {
  const HomeEvidenceNotice({super.key});
  @override
  State<HomeEvidenceNotice> createState() => _HomeEvidenceNoticeState();
}

class _HomeEvidenceNoticeState extends State<HomeEvidenceNotice> {
  Future<_TrendData>? _trend;
  String? _fieldId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.watch<FieldWorkspaceProvider>().activeFieldId;
    if (next != _fieldId) {
      _fieldId = next;
      _trend = _loadTrend(next);
    }
  }

  Future<_TrendData> _loadTrend(String? fieldId) async {
    if (fieldId == null) return const _TrendData(0, []);
    final repository = AssessmentHistoryRepository(context.read<AppDatabase>());
    final entries = await repository
        .watchPage(fieldId: fieldId, status: 'completed', limit: 3)
        .first;
    if (entries.length < 3) return _TrendData(entries.length, const []);
    final points = <_TrendPoint>[];
    for (final entry in entries.reversed) {
      final detail = await repository.loadDetail(entry.id);
      if (detail == null) continue;
      AssessmentMetricRollup? metric;
      for (final candidate in detail.resultSummary.metrics) {
        if (candidate.unit == 'percent' && candidate.isAvailable) {
          metric = candidate;
          break;
        }
      }
      final value = metric?.value;
      if (value != null) {
        points.add(_TrendPoint(entry.date, value.clamp(0, 100)));
      }
    }
    return _TrendData(entries.length, points);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TrendData>(
    future: _trend,
    builder: (context, snapshot) {
      final trend = snapshot.data;
      if (trend == null || trend.completedCount < 3) {
        return const SizedBox.shrink();
      }
      final points = trend.points;
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _HomeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText(
                'FAW Evidence Trend',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              AppText(
                'Last ${points.length} completed assessments',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              if (points.isEmpty)
                const SizedBox(
                  height: 90,
                  child: Center(
                    child: AppText(
                      'Complete an assessment to begin the evidence trend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 105,
                  width: double.infinity,
                  child: CustomPaint(painter: _TrendPainter(points)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        points.length > 1 &&
                                points.last.value <=
                                    points[points.length - 2].value
                            ? Icons.south
                            : Icons.north,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: AppText(
                          points.length < 2
                              ? 'First recorded evidence baseline saved.'
                              : points.last.value <=
                                    points[points.length - 2].value
                              ? 'Recorded evidence decreased since the previous assessment.'
                              : 'Recorded evidence increased since the previous assessment.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _TrendData {
  const _TrendData(this.completedCount, this.points);

  final int completedCount;
  final List<_TrendPoint> points;
}

class _TrendPoint {
  const _TrendPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points);
  final List<_TrendPoint> points;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE3E9E5)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(0, i * 24), Offset(size.width, i * 24), grid);
    }
    final maxValue = points.fold<double>(
      10,
      (max, p) => p.value > max ? p.value : max,
    );
    final coordinates = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
      coordinates.add(Offset(x, 74 - (points[i].value / maxValue * 58)));
    }
    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (coordinates.length > 1) {
      canvas.drawPoints(ui.PointMode.polygon, coordinates, line);
    }
    for (var i = 0; i < coordinates.length; i++) {
      canvas.drawCircle(coordinates[i], 6, Paint()..color = AppColors.primary);
      final percent = TextPainter(
        text: TextSpan(
          text: '${points[i].value.toStringAsFixed(0)}%',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      percent.paint(
        canvas,
        Offset(
          (coordinates[i].dx - percent.width / 2).clamp(
            0,
            size.width - percent.width,
          ),
          coordinates[i].dy - 20,
        ),
      );
      final date = TextPainter(
        text: TextSpan(
          text: DateFormat('MMM d').format(points[i].date),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      date.paint(
        canvas,
        Offset(
          (coordinates[i].dx - date.width / 2).clamp(
            0,
            size.width - date.width,
          ),
          88,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppText(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      TextButton(onPressed: onTap, child: AppText(action)),
      const Icon(Icons.chevron_right, size: 19, color: AppColors.textSecondary),
    ],
  );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE7EEE9)),
      boxShadow: AppColors.cardShadow,
    ),
    child: child,
  );
}

