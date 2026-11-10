import 'dart:typed_data';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/local/database_codes.dart';
import '../models/assessment_history_models.dart';
import 'polygon_calculator.dart';
import 'evidence_storage_service.dart';
import '../localization/app_language.dart';

class AssessmentPdfStation {
  const AssessmentPdfStation({
    required this.blockNumber,
    required this.stationNumber,
    required this.recorded,
    required this.assessable,
    required this.positive,
    required this.damage,
    required this.frass,
    required this.larvae,
    required this.eggs,
    required this.photoCount,
    required this.locationSource,
    this.latitude,
    this.longitude,
  });

  final int blockNumber;
  final int stationNumber;
  final int recorded;
  final int assessable;
  final int positive;
  final int damage;
  final int frass;
  final int larvae;
  final int eggs;
  final int photoCount;
  final String? locationSource;
  final double? latitude;
  final double? longitude;
}

class AssessmentPdfData {
  const AssessmentPdfData({
    required this.primaryMetricTitle,
    required this.primaryUnit,
    required this.primaryNumerator,
    required this.primaryDenominator,
    required this.primaryValue,
    required this.primaryDenominatorLabel,
    required this.screeningMode,
    required this.stations,
  });

  final String primaryMetricTitle;
  final String primaryUnit;
  final double primaryNumerator;
  final double primaryDenominator;
  final double primaryValue;
  final String primaryDenominatorLabel;
  final bool screeningMode;
  final List<AssessmentPdfStation> stations;
}

class AssessmentPdfExportService {
  const AssessmentPdfExportService();

  Future<Uint8List> build({
    AppLanguage language = AppLanguage.english,
    required AssessmentHistoryDetail detail,
    required AssessmentPdfData data,
    required bool includeCoordinates,
    required bool includeMap,
    required bool includePhotos,
    required EvidenceStorageService evidenceStorage,
  }) => _AssessmentPdfWriter(AppWords(language)).build(
    detail: detail,
    data: data,
    includeCoordinates: includeCoordinates,
    includeMap: includeMap,
    includePhotos: includePhotos,
    evidenceStorage: evidenceStorage,
  );
}

class _AssessmentPdfWriter {
  const _AssessmentPdfWriter(this.words);
  final AppWords words;
  String t(String text) => words.translate(text);

  Future<Uint8List> build({
    required AssessmentHistoryDetail detail,
    required AssessmentPdfData data,
    required bool includeCoordinates,
    required bool includeMap,
    required bool includePhotos,
    required EvidenceStorageService evidenceStorage,
  }) async {
    final report = pw.Document(title: t('Cropwise field assessment record'));
    final assessment = detail.assessment;
    final field = detail.workspace.field;
    final cycle = detail.workspace.cropCycle;
    final boundary = detail.workspace.boundary;
    final summary = detail.resultSummary;
    final safety = detail.safety;
    final generatedAt = DateTime.now();
    final recordedPhotos = detail.evidence
        .where(
          (entry) =>
              entry.media.storageState == DatabaseCodes.evidenceStorageReady &&
              entry.media.mediaType == 'image',
        )
        .length;
    final photoAppendix =
        <({AssessmentEvidenceEntry entry, Uint8List bytes})>[];
    if (includePhotos) {
      for (final entry in detail.evidence) {
        if (entry.media.storageState != DatabaseCodes.evidenceStorageReady ||
            entry.media.mediaType != 'image') {
          continue;
        }
        try {
          final file = await evidenceStorage.resolve(entry.media.localUri);
          if (await file.exists()) {
            photoAppendix.add((entry: entry, bytes: await file.readAsBytes()));
          }
        } on Exception {
          // Missing or invalid local evidence is counted, never fabricated.
        }
      }
    }

    report.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.green800, width: 1),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'CROPWISE',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green800,
                ),
              ),
              pw.Text(
                t('FIELD ASSESSMENT RECORD'),
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              words.format('Generated {date}', {
                'date': _dateTime(generatedAt),
              }),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              words.format('Page {number} of {total}', {
                'number': context.pageNumber,
                'total': context.pagesCount,
              }),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Text(
            t('Assessment findings for professional review'),
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 7),
          _paragraph(
            'This report contains saved field observations and sample calculations. Expert leaf-damage severity is not included; check the Expert Review screen for any finalized rating. This report does not identify a pesticide, dose, or treatment decision.',
          ),
          _section('Field and assessment'),
          _fact('Field', field.name),
          _fact(
            'Location',
            [field.barangay, field.municipalityCity, field.province]
                .whereType<String>()
                .where((part) => part.trim().isNotEmpty)
                .join(', '),
          ),
          _fact('Maize variety', cycle?.varietyName),
          _fact(
            'Planting date',
            cycle?.plantingDate == null ? null : _date(cycle!.plantingDate!),
          ),
          _fact(
            'Growth stage',
            assessment.growthStage.toUpperCase().replaceAll('_', '-'),
          ),
          _fact('Evaluator', detail.evaluator),
          _fact(
            'Assessment completed',
            assessment.completedAt == null
                ? null
                : _dateTime(assessment.completedAt!.toLocal()),
          ),
          _fact(
            'Approximate field area',
            boundary == null
                ? null
                : '${boundary.areaHectares.toStringAsFixed(2)} ha',
          ),
          _fact('Scouting route', assessment.scoutingPattern.toUpperCase()),
          _fact('Assessment ID', assessment.id),
          _section('Sampled result'),
          _fact(
            'Result',
            data.primaryDenominator <= 0
                ? t('Unavailable - no valid denominator')
                : '${t(data.primaryMetricTitle)}: ${words.countOf(_number(data.primaryNumerator), _number(data.primaryDenominator))} ${t(data.primaryDenominatorLabel)} (${_value(data.primaryValue, data.primaryUnit)})',
          ),
          _paragraph(
            data.screeningMode
                ? 'This value is a model damage-screening result, not a measurement of current FAW infestation. Model signs are suggestions pending field or expert confirmation.'
                : 'This value describes the sampled observations only. It does not estimate a whole-field severity class or establish FAW identity.',
          ),
          _fact(
            'Reviewed stations',
            words.countOf(
              summary.currentReviewedStationCount,
              summary.expectedStationCount,
            ),
          ),
          _fact(
            'Assessable observations',
            words.countOf(
              summary.assessableObservationCount,
              summary.recordedObservationCount,
            ),
          ),
          _fact(
            'Record verification',
            detail.readiness.isValid
                ? t('Current checks passed')
                : words.format('Requires verification - {count} issue(s)', {
                    'count': summary.outstandingIssueCount,
                  }),
          ),
          _section('Station findings'),
          _paragraph(
            'Positive counts and visible-sign counts are distinct. Signs can overlap on the same sampled plant. Photo counts describe saved evidence files, not independently confirmed findings.',
          ),
          if (data.stations.isEmpty)
            _paragraph('No station observations are available.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Station',
                data.screeningMode
                    ? 'Damage + / assessed'
                    : 'Positive / assessed',
                'Recorded',
                'Rate',
                'Damage',
                'Frass',
                'Larva',
                'Egg',
                'Photos',
              ].map(t).toList(),
              data: [
                for (final station in data.stations)
                  [
                    'B${station.blockNumber}-S${station.stationNumber}',
                    '${station.positive} / ${station.assessable}',
                    '${station.recorded}',
                    station.assessable == 0
                        ? 'N/A'
                        : '${(station.positive / station.assessable * 100).toStringAsFixed(1)}%',
                    '${station.damage}',
                    '${station.frass}',
                    '${station.larvae}',
                    '${station.eggs}',
                    '${station.photoCount}',
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.green800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 6,
              ),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
          if (includeCoordinates) ...[
            _section('Recorded station coordinates'),
            _paragraph(
              'Only coordinates marked as captured by phone GPS are listed. All locations and field outlines are approximate.',
            ),
            for (final station in data.stations)
              _fact(
                'B${station.blockNumber}-S${station.stationNumber}',
                station.locationSource == 'phone_gps' &&
                        station.latitude != null &&
                        station.longitude != null
                    ? '${station.latitude!.toStringAsFixed(6)}, ${station.longitude!.toStringAsFixed(6)}'
                    : t('Phone GPS not recorded'),
              ),
          ],
          _section('Recent treatment and field-entry safety'),
          _fact('Saved safety result', _safetyStatus(safety?.resultStatus)),
          _fact(
            'Treatment application ended',
            safety?.applicationEndAtUsed == null
                ? null
                : _dateTime(safety!.applicationEndAtUsed!.toLocal()),
          ),
          _fact('Reported re-entry period', safety?.reiTextUsed),
          _fact('Period source', _source(safety?.reiSource)),
          _fact(
            'Calculated end of period',
            safety?.calculatedSafeEntryAt == null
                ? null
                : _dateTime(safety!.calculatedSafeEntryAt!.toLocal()),
          ),
          _fact('Reported treatment details', safety?.notes),
          _paragraph(
            'These are reported safety facts. A calculated end time does not verify the product label, protective equipment rules, or any other entry restriction.',
          ),
          // A screening report already states its applicable damage-screen
          // metric above. Do not mix in evaluator metrics from other saved
          // observation records or repeat raw database codes in the PDF.
          if (!data.screeningMode) ...[
            _section('Other saved metrics'),
            _paragraph(
              'Any evaluator-recorded leaf score below is separate from the later expert review.',
            ),
            if (summary.metrics.isEmpty)
              _paragraph('No additional block metrics are available.'),
            for (final metric in summary.metrics)
              _fact(
                metric.metricCode,
                metric.isAvailable
                    ? '${_number(metric.numerator ?? 0)} / ${_number(metric.denominator ?? 0)} = ${_value(metric.value!, metric.unit)}${metric.warningCodes.isEmpty ? '' : ' (warnings: ${metric.warningCodes.join(', ')})'}'
                    : '${t('Unavailable')} - ${t(metric.unavailableReason ?? 'incomplete data')}',
              ),
          ],
          _section('Evidence and review limits'),
          _fact(
            'Saved evidence photos',
            includePhotos
                ? words.format(
                    '{saved} saved; {included} included in the photo appendix',
                    {'saved': recordedPhotos, 'included': photoAppendix.length},
                  )
                : words.format('{saved} saved; photos excluded from this PDF', {
                    'saved': recordedPhotos,
                  }),
          ),
          _fact('Protocol version', assessment.protocolVersion),
          _fact('Formula version', assessment.formulaVersion),
          _paragraph(
            'Review the original observations and available photos for any expert determination. Current infestation, visible damage, and a later expert severity score are different findings. A pesticide decision requires professional review of current activity, crop stage, treatment history, and the applicable product label.',
          ),
        ],
      ),
    );
    if (includeMap) {
      report.addPage(_mapPage(detail: detail, data: data));
    }
    final stationLabels = {
      for (final station in detail.stations)
        if (station.station != null)
          station.station!.id:
              'B${station.prepared.run.blockSequence}-S${station.stationNumber}',
    };
    for (var start = 0; start < photoAppendix.length; start += 4) {
      final end = math.min(start + 4, photoAppendix.length);
      pw.Widget photoTile(int index) {
        if (index >= end) return pw.SizedBox(width: 248, height: 338);
        final photo = photoAppendix[index];
        final entry = photo.entry;
        final stationLabel =
            stationLabels[entry.stationId] ?? t('Station unknown');
        final plantLabel = entry.plantPosition == null
            ? ''
            : ' · ${words.format('Plant {number}', {'number': entry.plantPosition!})}';
        return pw.Container(
          width: 248,
          height: 338,
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${index + 1}. $stationLabel$plantLabel · ${t(entry.scope)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (entry.media.capturedAt != null)
                pw.Text(
                  _dateTime(entry.media.capturedAt!.toLocal()),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              pw.SizedBox(height: 4),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(photo.bytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      report.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(34),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _section(
                words.format('Evidence photos {start}-{end} of {total}', {
                  'start': start + 1,
                  'end': end,
                  'total': photoAppendix.length,
                }),
              ),
              pw.Row(
                children: [photoTile(start), pw.Spacer(), photoTile(start + 1)],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  photoTile(start + 2),
                  pw.Spacer(),
                  photoTile(start + 3),
                ],
              ),
              pw.SizedBox(height: 8),
              _paragraph(
                'Saved field evidence; image findings require expert review.',
              ),
            ],
          ),
        ),
      );
    }
    return report.save();
  }

  pw.Page _mapPage({
    required AssessmentHistoryDetail detail,
    required AssessmentPdfData data,
  }) {
    final outline = PolygonCalculator.fromGeoJson(
      detail.workspace.boundary?.geometryGeojson ?? '',
    );
    final positioned = data.stations
        .where(
          (station) =>
              station.locationSource == 'phone_gps' &&
              station.latitude != null &&
              station.longitude != null,
        )
        .toList();
    // The saved field outline sets the map frame. A distant station reading
    // must not shrink the field to a tiny shape on the exported page.
    final points = outline.length >= 3
        ? outline
        : [
            for (final station in positioned)
              LatLng(station.latitude!, station.longitude!),
          ];
    const mapWidth = 510.0;
    const mapHeight = 420.0;
    const margin = 40.0;
    final meanLatitude = points.isEmpty
        ? 0.0
        : points.map((point) => point.latitude).reduce((a, b) => a + b) /
              points.length;
    final longitudeScale = math.cos(meanLatitude * math.pi / 180).abs();
    double east(LatLng point) => point.longitude * longitudeScale;
    final eastValues = points.map(east).toList();
    final northValues = points.map((point) => point.latitude).toList();
    final minEast = eastValues.isEmpty ? 0.0 : eastValues.reduce(math.min);
    final maxEast = eastValues.isEmpty ? 1.0 : eastValues.reduce(math.max);
    final minNorth = northValues.isEmpty ? 0.0 : northValues.reduce(math.min);
    final maxNorth = northValues.isEmpty ? 1.0 : northValues.reduce(math.max);
    final rangeEast = math.max(maxEast - minEast, 0.0000001);
    final rangeNorth = math.max(maxNorth - minNorth, 0.0000001);
    final scale = math.min(
      (mapWidth - 2 * margin) / rangeEast,
      (mapHeight - 2 * margin) / rangeNorth,
    );
    final occupiedWidth = rangeEast * scale;
    final occupiedHeight = rangeNorth * scale;
    double x(LatLng point) =>
        (mapWidth - occupiedWidth) / 2 + (east(point) - minEast) * scale;
    double y(LatLng point) =>
        (mapHeight - occupiedHeight) / 2 + (point.latitude - minNorth) * scale;
    final plotted = positioned.where((station) {
      final point = LatLng(station.latitude!, station.longitude!);
      return x(point) >= 14 &&
          x(point) <= mapWidth - 14 &&
          y(point) >= 14 &&
          y(point) <= mapHeight - 14;
    }).toList();
    final unplotted = data.stations.length - plotted.length;
    final outsideFrame = positioned.length - plotted.length;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _section('Field map and sampled stations'),
          _paragraph(
            'North is up. This offline plot uses the saved approximate field outline and phone-GPS station positions; no aerial imagery is included.',
          ),
          pw.SizedBox(height: 12),
          pw.Stack(
            children: [
              pw.CustomPaint(
                size: const PdfPoint(mapWidth, mapHeight),
                painter: (canvas, size) {
                  canvas
                    ..setFillColor(PdfColors.grey100)
                    ..drawRect(0, 0, size.x, size.y)
                    ..fillPath();
                  if (outline.length >= 3) {
                    void traceOutline() {
                      canvas.moveTo(x(outline.first), y(outline.first));
                      for (final point in outline.skip(1)) {
                        canvas.lineTo(x(point), y(point));
                      }
                      canvas.lineTo(x(outline.first), y(outline.first));
                    }

                    canvas.setFillColor(PdfColors.green100);
                    traceOutline();
                    canvas.fillPath();
                    canvas
                      ..setStrokeColor(PdfColors.green800)
                      ..setLineWidth(2);
                    traceOutline();
                    canvas.strokePath();
                  }
                },
              ),
              pw.Positioned(
                right: 12,
                top: 10,
                child: pw.Text(
                  'N ↑',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              for (final station in plotted)
                pw.Positioned(
                  left: x(LatLng(station.latitude!, station.longitude!)) - 14,
                  top:
                      mapHeight -
                      y(LatLng(station.latitude!, station.longitude!)) -
                      14,
                  child: pw.Container(
                    width: 28,
                    height: 28,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: _stationColor(station),
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: PdfColors.white, width: 1.5),
                    ),
                    child: pw.Text(
                      'S${station.stationNumber}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          _paragraph(
            words.format(
                  '{plotted} of {total} stations plotted from phone GPS. {unplotted} station(s) remain in the findings table.',
                  {
                    'plotted': plotted.length,
                    'total': data.stations.length,
                    'unplotted': unplotted,
                  },
                ) +
                (outsideFrame == 0
                    ? ''
                    : ' ${words.format('{count} phone-GPS station(s) lie outside this field-focused map frame.', {'count': outsideFrame})}'),
          ),
          _paragraph(
            'Marker colors show sampled station rates only: green below 10%, amber 10-20%, red above 20%, gray when no assessable observations. They are display bands, not severity or pesticide-treatment thresholds.',
          ),
          if (outline.length < 3)
            _paragraph(
              'A saved field outline is unavailable; only located stations are shown.',
            ),
        ],
      ),
    );
  }

  static PdfColor _stationColor(AssessmentPdfStation station) {
    if (station.assessable <= 0) return PdfColors.grey600;
    final percent = station.positive / station.assessable * 100;
    if (percent > 20) return PdfColors.red600;
    if (percent >= 10) return PdfColors.orange600;
    return PdfColors.green600;
  }

  pw.Widget _section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 15, bottom: 6),
    child: pw.Text(
      t(title),
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.green800,
      ),
    ),
  );

  pw.Widget _paragraph(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Text(
      t(text),
      style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
    ),
  );

  pw.Widget _fact(String label, String? value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 145,
          child: pw.Text(
            t(label),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value == null || value.trim().isEmpty ? t('Not recorded') : value,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      ],
    ),
  );

  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  static String _value(double value, String unit) => unit == 'percent'
      ? '${value.toStringAsFixed(1)}%'
      : '${value.toStringAsFixed(1)} $unit';
  String _date(DateTime value) => DateFormat(
    'MMM d, yyyy',
    words.language == AppLanguage.filipino ? 'fil' : 'en',
  ).format(value.toLocal());
  String _dateTime(DateTime value) => DateFormat(
    'MMM d, yyyy h:mm a',
    words.language == AppLanguage.filipino ? 'fil' : 'en',
  ).format(value);
  String _source(String? value) => t(switch (value) {
    'product_label' => 'Product label (reported)',
    'spray_record' => 'Spray record (reported)',
    'agricultural_adviser' => 'Agricultural adviser (reported)',
    null || 'unknown' => 'Not recorded',
    _ => value,
  });
  String _safetyStatus(String? value) => t(switch (value) {
    DatabaseCodes.noRecentTreatment => 'No recent treatment reported',
    DatabaseCodes.safeIntervalCompleted => 'Reported re-entry period elapsed',
    DatabaseCodes.blockedReiActive => 'Re-entry period active - do not enter',
    DatabaseCodes.cannotConfirmSafety => 'Entry safety cannot be confirmed',
    _ => 'Not recorded',
  });
}
