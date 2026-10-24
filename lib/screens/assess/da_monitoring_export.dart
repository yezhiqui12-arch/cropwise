import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../localization/app_text.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/da_monitoring_repository.dart';
import '../../data/repositories/advisor_model_results_reader.dart';
import '../../models/assessment_history_models.dart';
import '../../models/da_assessment_results.dart';
import '../../services/da_monitoring_pdf_export_service.dart';
import '../../services/evidence_storage_service.dart';

Future<void> exportDaMonitoringPdf(
  BuildContext context,
  AppDatabase database,
  AssessmentHistoryDetail detail,
) async {
  if (!DaSampleResults.fromDetail(detail).sampleComplete) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: AppText('Complete the assessment to export the DA form.'),
      ),
    );
    return;
  }
  try {
    final repository = DaMonitoringRepository(database);
    final saved = await repository.load(detail.assessment.id);
    final profile = await repository.loadProfile(detail.assessment.cropCycleId);
    final initial = {...profile, ...saved.fields};
    final ownerId = detail.workspace.field.ownerPersonId;
    final owner = ownerId == null
        ? null
        : await (database.select(
            database.people,
          )..where((p) => p.id.equals(ownerId))).getSingleOrNull();
    final cycle = detail.workspace.cropCycle;
    final defaults = <String, String>{
      'province': detail.workspace.field.province ?? '',
      'municipality': detail.workspace.field.municipalityCity ?? '',
      'barangay': detail.workspace.field.barangay ?? '',
      'field_id': detail.workspace.field.fieldCode ?? '',
      'farmer': owner?.displayName ?? '',
      'collector': detail.evaluator,
      'variety': cycle?.varietyName ?? '',
      'planting_pattern': cycle?.plantingArrangement ?? '',
      'planting_date': cycle?.plantingDate == null
          ? ''
          : DateFormat('dd MMM yyyy').format(cycle!.plantingDate!.toLocal()),
      'spacing': cycle?.intendedWithinRowSpacingCm == null
          ? ''
          : '${cycle!.intendedWithinRowSpacingCm} cm within row',
    };
    if (!context.mounted) return;
    final input = await showDialog<_DaExportInput>(
      context: context,
      builder: (_) => DaExportDetails(initial: {...defaults, ...initial}),
    );
    if (input == null) return;
    await repository.saveFields(detail.assessment.id, input.fields);
    await repository.saveProfile(detail.assessment.cropCycleId, input.fields);
    final models = await AdvisorModelResultsReader(database).load(
      assessmentId: detail.assessment.id,
      stations: detail.stations
          .map((s) => s.station)
          .whereType<StationRecord>()
          .toList(),
      plants: [
        for (final s in detail.stations)
          for (final p in s.plants) p.plant,
      ],
    );
    final bytes = await const DaMonitoringPdfExportService().build(
      detail: detail,
      record: await repository.load(detail.assessment.id),
      models: models,
      includeCoordinates: input.coordinates,
      includePhotos: true,
      evidenceStorage: EvidenceStorageService(),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'wormwise-da-monitoring-${detail.assessment.id}.pdf',
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not create the DA PDF. Try again.'),
        ),
      );
    }
  }
}

class _DaExportInput {
  const _DaExportInput(this.fields, this.coordinates);
  final Map<String, dynamic> fields;
  final bool coordinates;
}

const _labels = {
  'farmer': 'Farmer / representative',
  'collector': 'Data collector',
  'region': 'Region',
  'province': 'Province',
  'municipality': 'Municipality',
  'barangay': 'Barangay',
  'field_id': 'Field ID',
  'land_tenure': 'Land tenure',
  'topography': 'Topography',
  'soil_texture': 'Soil texture',
  'previous_crop': 'Previous crop',
  'adjacent_crop': 'Adjacent crop',
  'planting_pattern': 'Planting pattern',
  'planting_date': 'Planting date',
  'planting_material_source': 'Planting material source',
  'corn_type': 'Corn type',
  'variety': 'Variety',
  'spacing': 'Plant spacing',
  'fertilizer': 'Fertilizer application',
  'remarks': 'Remarks',
};

class DaExportDetails extends StatefulWidget {
  const DaExportDetails({super.key, required this.initial});
  final Map<String, dynamic> initial;
  @override
  State<DaExportDetails> createState() => _DaExportDetailsState();
}

class _DaExportDetailsState extends State<DaExportDetails> {
  late final controllers = {
    for (final key in _labels.keys)
      key: TextEditingController(text: widget.initial[key]?.toString() ?? ''),
  };
  late int week =
      int.tryParse(widget.initial['week']?.toString() ?? '')?.clamp(1, 12) ?? 1;
  bool coordinates = false;
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget input(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: Key('da_report_$key'),
      controller: controllers[key],
      maxLength: key == 'remarks' ? 240 : 100,
      maxLines: key == 'remarks' ? 2 : 1,
      decoration: InputDecoration(labelText: _labels[key], counterText: ''),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const AppText('DA monitoring PDF'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppText(
              'Assessment findings, saved rainfall and supporting photos are included automatically.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: week,
              decoration: const InputDecoration(labelText: 'Monitoring week'),
              items: [
                for (var i = 1; i <= 12; i++)
                  DropdownMenuItem(value: i, child: Text('L$i - Week $i')),
              ],
              onChanged: (v) => week = v ?? 1,
            ),
            const SizedBox(height: 12),
            input('farmer'),
            input('collector'),
            ExpansionTile(
              title: const AppText('Field and planting details'),
              subtitle: const AppText('Optional'),
              tilePadding: EdgeInsets.zero,
              children: [
                for (final key in _labels.keys.where(
                  (k) => k != 'farmer' && k != 'collector',
                ))
                  input(key),
              ],
            ),
            CheckboxListTile(
              value: coordinates,
              title: const AppText('Include field coordinates'),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => coordinates = v ?? false),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('Cancel'),
      ),
      FilledButton(
        key: const Key('da_create_pdf'),
        onPressed: () => Navigator.pop(
          context,
          _DaExportInput({
            for (final e in controllers.entries) e.key: e.value.text.trim(),
            'week': week,
          }, coordinates),
        ),
        child: const AppText('Create PDF'),
      ),
    ],
  );
}
