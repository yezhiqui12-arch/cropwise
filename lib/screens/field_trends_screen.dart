import '../localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import '../data/repositories/assessment_history_repository.dart';
import '../localization/app_text.dart';
import '../providers/field_workspace_provider.dart';
import '../theme/app_colors.dart';

class FieldTrendsScreen extends StatefulWidget {
  const FieldTrendsScreen({super.key, this.initialFieldId});
  final String? initialFieldId;

  @override
  State<FieldTrendsScreen> createState() => _FieldTrendsScreenState();
}

class _FieldTrendsScreenState extends State<FieldTrendsScreen> {
  AssessmentHistoryRepository? _repository;
  Stream<List<FieldRecord>>? _fields;
  String? _selectedFieldId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = AssessmentHistoryRepository(context.read<AppDatabase>());
      _fields = _repository!.watchFields();
      _selectedFieldId =
          widget.initialFieldId ??
          context.read<FieldWorkspaceProvider>().activeFieldId;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const AppText('Field trends')),
    body: SafeArea(
      child: StreamBuilder<List<FieldRecord>>(
        stream: _fields,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: AppText('Field history is unavailable.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final fields = snapshot.data!;
          if (fields.isEmpty) {
            return const Center(child: AppText('No saved fields yet.'));
          }
          final fieldId = fields.any((field) => field.id == _selectedFieldId)
              ? _selectedFieldId!
              : fields.first.id;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(fieldId),
                initialValue: fieldId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppWords.of(context).translate('Field'),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                items: [
                  for (final field in fields)
                    DropdownMenuItem(
                      value: field.id,
                      child: Text(field.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _selectedFieldId = value),
              ),
              const SizedBox(height: 16),
              _FieldMonthlyTrend(fieldId: fieldId, repository: _repository!),
            ],
          );
        },
      ),
    ),
  );
}

class _FieldMonthlyTrend extends StatefulWidget {
  const _FieldMonthlyTrend({required this.fieldId, required this.repository});
  final String fieldId;
  final AssessmentHistoryRepository repository;

  @override
  State<_FieldMonthlyTrend> createState() => _FieldMonthlyTrendState();
}

class _TrendAssessment {
  _TrendAssessment(this.sample);
  final FieldInfestationSample sample;
  int positive = 0;
  int assessable = 0;
  double get percent => positive / assessable * 100;
}

class _FieldMonthlyTrendState extends State<_FieldMonthlyTrend> {
  String? _stage;
  String? _cycle;
  late Stream<List<FieldInfestationSample>> _samples;
  static const _stages = [
    've',
    'v1',
    'v2',
    'v3_v6',
    'v7_v12',
    'vt_r2',
    'r3_r6',
  ];

  String _label(String stage) => switch (stage) {
    've' => 'VE',
    'v1' => 'V1',
    'v2' => 'V2',
    'v3_v6' => 'V3–V6',
    'v7_v12' => 'V7–V12',
    'vt_r2' => 'VT–R2',
    'r3_r6' => 'R3–R6',
    _ => stage,
  };
  String _metric(String stage) => switch (stage) {
    'vt_r2' => DatabaseCodes.vtR2InfestedPlantPercent,
    'r3_r6' => DatabaseCodes.activeEarInfestationPercent,
    _ => DatabaseCodes.vegetativeCurrentInfestationPercent,
  };
  String _metricLabel(String stage) =>
      stage == 'r3_r6' ? 'Active ear infestation' : 'Current plant infestation';

  @override
  void initState() {
    super.initState();
    _samples = widget.repository.watchFieldInfestationSamples(widget.fieldId);
  }

  @override
  void didUpdateWidget(covariant _FieldMonthlyTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldId != widget.fieldId) {
      _samples = widget.repository.watchFieldInfestationSamples(widget.fieldId);
      _cycle = null;
      _stage = null;
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<FieldInfestationSample>>(
    stream: _samples,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _empty('Field history is unavailable.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final grouped = <String, _TrendAssessment>{};
      for (final sample in snapshot.data!) {
        if (!_stages.contains(sample.growthStage) ||
            sample.metricCode != _metric(sample.growthStage) ||
            sample.assessable <= 0) {
          continue;
        }
        final entry = grouped.putIfAbsent(
          sample.assessmentId,
          () => _TrendAssessment(sample),
        );
        entry.positive += sample.positive;
        entry.assessable += sample.assessable;
      }
      final all = grouped.values.toList()
        ..sort((a, b) {
          final date = a.sample.completedAt.compareTo(b.sample.completedAt);
          return date != 0
              ? date
              : a.sample.assessmentId.compareTo(b.sample.assessmentId);
        });
      if (all.isEmpty) {
        return _empty(
          'Your field story starts here.\nComplete an assessment to see results by growth stage.',
        );
      }
      final cycles = all.reversed
          .map((e) => e.sample.cropCycleId)
          .toSet()
          .toList();
      final cycle = cycles.contains(_cycle) ? _cycle! : cycles.first;
      final season = all.where((e) => e.sample.cropCycleId == cycle).toList();
      final available = _stages
          .where((s) => season.any((e) => e.sample.growthStage == s))
          .toList();
      final stage = available.contains(_stage)
          ? _stage!
          : season.last.sample.growthStage;
      final entries = season
          .where((e) => e.sample.growthStage == stage)
          .toList();
      final latest = entries.last;
      final previous = entries.length > 1 ? entries[entries.length - 2] : null;
      final delta = previous == null ? null : latest.percent - previous.percent;
      final unchanged = delta != null && delta.abs() < 0.05;
      final changeColor = delta == null || unchanged
          ? const Color(0xFF567063)
          : delta > 0
          ? const Color(0xFF9C521E)
          : const Color(0xFF247552);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppText(
            'A clearer view of your field',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF233D2E),
            ),
          ),
          const SizedBox(height: 8),
          const AppText(
            'Compare completed assessments from the same growth stage and crop season.',
            style: TextStyle(height: 1.5, color: Color(0xFF647B6B)),
          ),
          const SizedBox(height: 20),
          if (cycles.length > 1) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('cycle-${widget.fieldId}-$cycle'),
              initialValue: cycle,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Crop season',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final id in cycles)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      _seasonLabel(
                        all.where((e) => e.sample.cropCycleId == id).toList(),
                        cycles.indexOf(id) == 0,
                      ),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _cycle = value;
                _stage = null;
              }),
            ),
            const SizedBox(height: 16),
          ],
          const AppText(
            'GROWTH STAGE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: Color(0xFF647B6B),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in available)
                ChoiceChip(
                  label: Text(_label(s)),
                  selected: stage == s,
                  selectedColor: const Color(0xFFD9EBDD),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _stage = s),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF234F39),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_label(stage)} · ${_metricLabel(stage)}',
                  style: const TextStyle(
                    color: Color(0xFFCDE4D3),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${latest.percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Latest assessment · ${DateFormat('MMM d, yyyy').format(latest.sample.completedAt.toLocal())}',
                  style: const TextStyle(color: Color(0xFFCDE4D3)),
                ),
                const SizedBox(height: 8),
                Text(
                  '${latest.positive} of ${latest.assessable} assessed ${stage == 'r3_r6' ? 'ears' : 'plants'}',
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      delta == null
                          ? Icons.history
                          : unchanged
                          ? Icons.drag_handle
                          : delta > 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: changeColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppText(
                        delta == null
                            ? 'One assessment so far'
                            : unchanged
                            ? 'Similar to the previous assessment'
                            : delta > 0
                            ? 'Infestation increased'
                            : 'Infestation decreased',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: changeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (previous == null)
                  const AppText(
                    'Another assessment at this growth stage is needed to show a trend.',
                    style: TextStyle(height: 1.5),
                  )
                else ...[
                  Text(
                    '${delta!.abs().toStringAsFixed(1)} percentage points ${unchanged
                        ? 'difference'
                        : delta > 0
                        ? 'higher'
                        : 'lower'}',
                    style: TextStyle(
                      color: changeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Previous: ${previous.percent.toStringAsFixed(1)}% · ${DateFormat('MMM d, yyyy').format(previous.sample.completedAt.toLocal())}',
                    style: const TextStyle(color: Color(0xFF647B6B)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText(
                  'Assessment trend',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_label(stage)} only · ${entries.length} completed assessments',
                  style: const TextStyle(color: Color(0xFF647B6B)),
                ),
                if (entries.length > 1) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 180,
                    child: CustomPaint(
                      painter: _TrendPainter(entries),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat(
                          'MMM d, yy',
                        ).format(entries.first.sample.completedAt.toLocal()),
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        DateFormat(
                          'MMM d, yy',
                        ).format(entries.last.sample.completedAt.toLocal()),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const AppText(
                    'Each dot is a dated assessment. Missing dates are not zero infestation.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF647B6B),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final entry in entries.reversed) _assessmentRow(entry),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const AppText(
            'Season timeline',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF233D2E),
            ),
          ),
          const SizedBox(height: 6),
          const AppText(
            'Results are grouped by growth stage. Different stages use different observations and are not compared.',
            style: TextStyle(height: 1.5, color: Color(0xFF647B6B)),
          ),
          const SizedBox(height: 14),
          for (final s in available)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.insights_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _label(s),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _metricLabel(s),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF647B6B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final entry
                        in season
                            .where((e) => e.sample.growthStage == s)
                            .toList()
                            .reversed)
                      _assessmentRow(entry),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          const AppText(
            'These percentages describe sampled observations, not every plant in the field. Sampling conditions and assessed blocks can vary.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF647B6B),
            ),
          ),
        ],
      );
    },
  );

  String _seasonLabel(List<_TrendAssessment> entries, bool latest) =>
      '${latest ? 'Latest season' : 'Earlier season'} · ${DateFormat('MMM yyyy').format(entries.first.sample.completedAt.toLocal())} – ${DateFormat('MMM yyyy').format(entries.last.sample.completedAt.toLocal())}';

  Widget _assessmentRow(_TrendAssessment entry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat(
                  'MMM d, yyyy · h:mm a',
                ).format(entry.sample.completedAt.toLocal()),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.positive}/${entry.assessable} assessed',
                style: const TextStyle(fontSize: 12, color: Color(0xFF647B6B)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${entry.percent.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    ),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDDE7E0)),
    ),
    child: child,
  );

  Widget _empty(String message) => _panel(
    Column(
      children: [
        const Icon(Icons.insights_outlined, size: 44, color: AppColors.primary),
        const SizedBox(height: 14),
        AppText(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6),
        ),
      ],
    ),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.entries);
  final List<_TrendAssessment> entries;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    final width = size.width - left - 8;
    final height = size.height - 16;
    final grid = Paint()
      ..color = const Color(0xFFE7EEEA)
      ..strokeWidth = 1;
    for (final percent in [0, 25, 50, 75, 100]) {
      final y = 8 + height * (1 - percent / 100);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: '$percent%',
          style: const TextStyle(fontSize: 10, color: Color(0xFF647B6B)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - label.height / 2));
    }
    final first = entries.first.sample.completedAt.millisecondsSinceEpoch;
    final span = entries.last.sample.completedAt.millisecondsSinceEpoch - first;
    final points = [
      for (var i = 0; i < entries.length; i++)
        Offset(
          left +
              width *
                  (span == 0
                      ? i / (entries.length - 1)
                      : (entries[i].sample.completedAt.millisecondsSinceEpoch -
                                first) /
                            span),
          8 + height * (1 - entries[i].percent.clamp(0, 100) / 100),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, 8 + height)
      ..lineTo(points.first.dx, 8 + height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x14247552));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF247552)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3.5, Paint()..color = const Color(0xFF247552));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.entries != entries;
}
