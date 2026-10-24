import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/assessment_history_models.dart';
import '../models/da_monitoring.dart';
import '../data/repositories/advisor_model_results_reader.dart';
import '../data/repositories/scouting_workflow_repository.dart';
import '../data/local/database_codes.dart';
import 'evidence_storage_service.dart';

class DaMonitoringPdfExportService {
  const DaMonitoringPdfExportService();
  Future<Uint8List> build({
    required AssessmentHistoryDetail detail,
    required DaMonitoringRecord record,
    required AdvisorModelResults models,
    bool includeCoordinates = false,
    bool includePhotos = true,
    EvidenceStorageService? evidenceStorage,
  }) async {
    final pdf = pw.Document(
      title: 'Porma 1. Pagsubaybay sa Harabas',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
        ),
        bold: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
        ),
      ),
    );
    final fields = record.fields;
    final cycle = detail.workspace.cropCycle;
    final date =
        detail.assessment.completedAt ??
        detail.assessment.startedAt ??
        detail.assessment.createdAt;
    final rain = DaReportRain.fromContext(detail.assessment.weatherContext);
    final blocks = <String, List<StationSnapshot>>{};
    for (final point in detail.stations) {
      (blocks[point.prepared.run.id] ??= []).add(point);
    }
    if (blocks.isEmpty) {
      throw StateError('No DA sampling blocks are available.');
    }
    String value(String key, [String? fallback]) =>
        (fields[key]?.toString().trim().isNotEmpty == true
            ? fields[key].toString().trim()
            : fallback) ??
        '';
    final stage = switch (detail.assessment.growthStage) {
      've' => 'Punla (VE)',
      'v1' || 'v2' => 'Punla (V1-V2)',
      'v3_v6' || 'v7_v12' => 'Paglago',
      'vt_r2' || 'r3_r6' => 'Pamumunga',
      _ => detail.assessment.growthStage,
    };
    final week = int.tryParse(value('week'))?.clamp(1, 12) ?? 1;
    pw.Widget text(String s, {double size = 8, bool bold = false}) => pw.Text(
      s,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    String total(Map<int, DaPlantFinding> values, String key) {
      final assessed = values.values.where((f) => f.values[key] != null).length;
      return assessed == 0
          ? '-'
          : '${values.values.where((f) => f.values[key] == true).length} / $assessed';
    }

    pw.Widget mark(bool? v, {bool corrected = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        if (v == null)
          text('-', size: 10)
        else
          pw.Container(
            width: 10,
            height: 10,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(border: pw.Border.all(width: .7)),
            child: v ? text('X', size: 8, bold: true) : null,
          ),
        if (corrected) text('*', size: 7),
      ],
    );
    pw.Widget pair(String label, String s) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 5),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 8),
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: s.isEmpty ? '________________' : s),
          ],
        ),
      ),
    );
    final entries = <(String, String)>[
      ('Rehiyon', value('region')),
      ('Probinsya', value('province', detail.workspace.field.province)),
      (
        'Munisipalidad',
        value('municipality', detail.workspace.field.municipalityCity),
      ),
      ('Barangay', value('barangay', detail.workspace.field.barangay)),
      ('ID ng Bukid', value('field_id', detail.workspace.field.fieldCode)),
      ('Pangalan', value('farmer')),
      ('Panahanan sa Lupa', value('land_tenure')),
      ('Topograpiya', value('topography')),
      ('Tekstura ng Lupa', value('soil_texture')),
      ('Nakaraang Tanim', value('previous_crop')),
      ('Katabing Tanim', value('adjacent_crop')),
      (
        'Tularan ng Pagtatanim',
        value('planting_pattern', cycle?.plantingArrangement),
      ),
      (
        'Petsa ng Pagtatanim',
        value(
          'planting_date',
          cycle?.plantingDate == null
              ? ''
              : DateFormat(
                  'dd MMM yyyy',
                ).format(cycle!.plantingDate!.toLocal()),
        ),
      ),
      ('Pinagmulan ng Materyales', value('planting_material_source')),
      ('Uri ng Mais', value('corn_type')),
      ('Barayti', value('variety', cycle?.varietyName)),
      (
        'Distansya ng Tanim',
        value(
          'spacing',
          cycle?.intendedWithinRowSpacingCm == null
              ? null
              : '${cycle!.intendedWithinRowSpacingCm} cm sa hanay',
        ),
      ),
      ('Pag-aplay ng Pataba', value('fertilizer')),
      ('Kolektor ng Datos', value('collector', detail.evaluator)),
      ('Mga Pansin', value('remarks')),
    ];
    for (final entry in blocks.entries) {
      final points = entry.value
        ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber));
      final sequence = points.first.prepared.run.blockSequence;
      final area = points.first.prepared.block.areaHectares;
      final findings = <int, DaPlantFinding>{};
      for (final point in points) {
        final sample = models.samples
            .where((s) => s.stationId == point.station?.id && s.position == 1)
            .firstOrNull;
        final model = sample?.eligible == true ? sample!.result : null;
        findings[point.stationNumber] = DaPlantFinding.fromModel(model)
            .withCorrections(
              record.plant(entry.key, point.stationNumber),
              daPhotoSignature(sample?.images ?? const []),
            );
      }
      final enemies = record.enemies(entry.key) ?? ['not_recorded'];
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              text('Porma 1. Pagsubaybay sa Harabas', size: 14, bold: true),
              pw.SizedBox(height: 4),
              text(
                '${detail.workspace.field.name}  |  Block $sequence  |  ${area.toStringAsFixed(2)} ha',
                size: 9,
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.green800),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text('WormWise - adapted DA monitoring form', size: 7),
              text('${context.pageNumber} / ${context.pagesCount}', size: 7),
            ],
          ),
          build: (context) => [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
              children: [
                for (var i = 0; i < entries.length; i += 2)
                  pw.TableRow(
                    children: [
                      pair(entries[i].$1, entries[i].$2),
                      pair(entries[i + 1].$1, entries[i + 1].$2),
                    ],
                  ),
                if (includeCoordinates)
                  pw.TableRow(
                    children: [
                      pair(
                        'Latitud',
                        detail.workspace.boundary?.centroidLatitude
                                ?.toStringAsFixed(6) ??
                            '',
                      ),
                      pair(
                        'Longhitud',
                        detail.workspace.boundary?.centroidLongitude
                                ?.toStringAsFixed(6) ??
                            '',
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
            text(
              'Lingguhang Monitoring - L$week    Petsa: ${DateFormat('dd MMM yyyy').format(date.toLocal())}',
              size: 10,
              bold: true,
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.4),
                for (var i = 1; i < 5; i++) i: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.green50),
                  children: [
                    for (final label in [
                      'Napiling Halaman',
                      'Itlog',
                      'Larba',
                      'Pupa',
                      'Pinsala',
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Center(child: text(label, bold: true)),
                      ),
                  ],
                ),
                for (var n = 1; n <= 20; n++)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3),
                        child: pw.Center(child: text('$n')),
                      ),
                      for (final key in daSignLabels.keys)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          child: mark(
                            findings[n]?.values[key],
                            corrected: findings[n]?.corrected[key] == true,
                          ),
                        ),
                    ],
                  ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: text('Kabuuan', bold: true),
                    ),
                    for (final key in daSignLabels.keys)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Center(
                          child: text(total(findings, key), bold: true),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 7),
            text(
              'X = detected/present; empty box = not detected/not present; - = not assessed; * = farmer correction.',
              size: 7,
            ),
            text(
              'Kabuuan = checked plants / plants with a recorded result. Egg and larva entries are presence indicators, not individual pest counts.',
              size: 7,
            ),
            pw.SizedBox(height: 8),
            pair('Yugto ng Paglaki', stage),
            pair(
              'Pag-ulan (nakaraang 48 oras)',
              rain.rained == null
                  ? 'Hindi naitala'
                  : rain.rained!
                  ? 'May ulan${rain.millimeters == null ? '' : ' - ${rain.millimeters!.toStringAsFixed(2)} mm'}'
                  : 'Walang ulan${rain.millimeters == null ? '' : ' - 0 mm'}',
            ),
            if (rain.rained != null)
              text(
                'Source: ${rain.source}${rain.periodEnd == null ? '' : ' | Period ending ${DateFormat('dd MMM yyyy HH:mm').format(rain.periodEnd!.toUtc())} UTC'}',
                size: 7,
              ),
            pair(
              'Likas na mga Kaaway',
              enemies.map((e) => daEnemyLabels[e] ?? e).join(', '),
            ),
            pw.SizedBox(height: 4),
            text(
              'Checkboxes use saved model detections or optional farmer observations. Pinsala records damage presence; it is not a Davis severity rating.',
              size: 7,
            ),
          ],
        ),
      );
    }
    if (includePhotos) {
      final storage = evidenceStorage ?? EvidenceStorageService();
      final locations = {
        for (final point in detail.stations)
          if (point.station != null)
            point.station!.id: (
              block: point.prepared.run.blockSequence,
              sample: point.stationNumber,
            ),
      };
      final seen = <String>{};
      final evidence =
          detail.evidence
              .where(
                (entry) =>
                    entry.media.assessmentId == detail.assessment.id &&
                    entry.media.deletedAt == null &&
                    entry.media.isCanonicalEvidence &&
                    entry.media.mediaType == 'image' &&
                    entry.media.storageState ==
                        DatabaseCodes.evidenceStorageReady &&
                    seen.add(entry.media.id),
              )
              .toList()
            ..sort((a, b) {
              final left = locations[a.stationId],
                  right = locations[b.stationId];
              final block = (left?.block ?? 999).compareTo(right?.block ?? 999);
              if (block != 0) return block;
              final sample = (left?.sample ?? 999).compareTo(
                right?.sample ?? 999,
              );
              if (sample != 0) return sample;
              final captured = (a.media.capturedAt ?? a.media.createdAt)
                  .compareTo(b.media.capturedAt ?? b.media.createdAt);
              return captured != 0
                  ? captured
                  : a.media.id.compareTo(b.media.id);
            });
      // Process one appendix page at a time, so full-resolution photo bytes
      // are not all kept in memory during a multi-block export.
      final pageCount = math.max(1, (evidence.length / 4).ceil());
      for (var appendix = 0; appendix < pageCount; appendix++) {
        final start = appendix * 4;
        final end = math.min(start + 4, evidence.length);
        final images = <pw.ImageProvider?>[];
        for (var index = start; index < end; index++) {
          try {
            final file = await storage.resolve(evidence[index].media.localUri);
            images.add(
              await file.exists()
                  ? pw.MemoryImage(await file.readAsBytes())
                  : null,
            );
          } on Exception {
            images.add(null);
          }
        }
        pw.Widget tile(int index) {
          if (index >= end) return pw.SizedBox(width: 255, height: 315);
          final entry = evidence[index];
          final location = locations[entry.stationId];
          final image = images[index - start];
          final label = location == null
              ? 'Assessment photo'
              : 'Block ${location.block} - Sample ${location.sample}';
          return pw.Container(
            width: 255,
            height: 315,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: .5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text('${index + 1}. $label', size: 10, bold: true),
                pw.SizedBox(height: 3),
                text(
                  '${entry.scope}${entry.media.capturedAt == null ? '' : ' | ${DateFormat('dd MMM yyyy HH:mm').format(entry.media.capturedAt!.toLocal())}'}',
                  size: 8,
                ),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: pw.Center(
                    child: image == null
                        ? text('Photo unavailable on this device', size: 10)
                        : pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                ),
              ],
            ),
          );
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                text('Supporting evidence / Mga Larawan', size: 17, bold: true),
                pw.SizedBox(height: 5),
                text(
                  '${detail.workspace.field.name} | ${DateFormat('dd MMM yyyy').format(date.toLocal())}',
                  size: 10,
                ),
                pw.SizedBox(height: 5),
                text('Assessment ID: ${detail.assessment.id}', size: 7),
                pw.SizedBox(height: 4),
                text(
                  'Multiple views of a sample are supporting photos, not additional sampled plants.',
                  size: 8,
                ),
                pw.SizedBox(height: 12),
                if (evidence.isEmpty)
                  text('No saved assessment photos available.', size: 10)
                else ...[
                  text(
                    'Photos ${start + 1}-$end of ${evidence.length}',
                    size: 9,
                    bold: true,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(children: [tile(start), pw.Spacer(), tile(start + 1)]),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [tile(start + 2), pw.Spacer(), tile(start + 3)],
                  ),
                ],
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    text('WormWise - DA monitoring evidence', size: 7),
                    text(
                      '${context.pageNumber} / ${context.pagesCount}',
                      size: 7,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }
    return pdf.save();
  }
}
