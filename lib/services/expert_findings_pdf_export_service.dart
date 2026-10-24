import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;
import 'package:image/image.dart' as image_lib;
import 'cloud/expert_review_service.dart';
import '../models/expert_findings_report.dart';
import '../models/da_severity.dart';
import '../data/repositories/scouting_workflow_repository.dart';

class ExpertFindingsPdfExportService {
  const ExpertFindingsPdfExportService();
  Future<Uint8List> build(
    ExpertFindingsReport report, {
    Future<pw.ImageProvider?> Function(ExpertPlantPhoto photo)? photoLoader,
  }) async {
    final highlights = report.highestRatedPlants;
    final highlightImages = <String, pw.ImageProvider>{};
    final highlightPhotoIds = <String, String>{};
    await Future.wait(
      highlights.map((rating) async {
        final candidates = rating.photos
            .where((photo) => photo.url?.isNotEmpty == true)
            .take(2);
        for (final photo in candidates) {
          try {
            final image = photoLoader != null
                ? await photoLoader(photo)
                : await printing
                      .networkImage(photo.url!, cache: false)
                      .timeout(const Duration(seconds: 15));
            if (image == null) continue;
            pw.ImageProvider prepared = image;
            if (image is pw.MemoryImage) {
              if (image.bytes.length > 20 * 1024 * 1024) continue;
              final decoded = image_lib.decodeImage(image.bytes);
              if (decoded == null) continue;
              var pixels = image_lib.bakeOrientation(decoded);
              if (math.max(pixels.width, pixels.height) > 1280) {
                pixels = pixels.width >= pixels.height
                    ? image_lib.copyResize(pixels, width: 1280)
                    : image_lib.copyResize(pixels, height: 1280);
              }
              // Embed visible pixels only: camera GPS/EXIF is not report data.
              final clean = image_lib.Image(
                width: pixels.width,
                height: pixels.height,
                numChannels: 3,
              );
              image_lib.fill(clean, color: image_lib.ColorRgb8(255, 255, 255));
              image_lib.compositeImage(clean, pixels);
              prepared = pw.MemoryImage(
                Uint8List.fromList(image_lib.encodeJpg(clean, quality: 85)),
              );
            }
            highlightImages[rating.identityKey] = prepared;
            highlightPhotoIds[rating.identityKey] = photo.id;
            break;
          } catch (_) {
            // Preserve finalized findings if a linked photo cannot be loaded.
          }
        }
      }),
    );
    final pdf = pw.Document(
      title: 'WormWise expert findings',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
        ),
        bold: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
        ),
      ),
    );
    const green = PdfColor.fromInt(0xff1f563f);
    const pale = PdfColor.fromInt(0xffedf4ef);
    const grey = PdfColor.fromInt(0xff63736b);
    final detail = report.detail;
    final summary = report.review.severitySummary!;
    final blocks = <String, List<StationSnapshot>>{};
    for (final plant in report.sample.plants) {
      (blocks[plant.prepared.run.id] ??= []).add(plant);
    }
    String date(DateTime value) => DateFormat(
      'dd MMM yyyy, HH:mm',
    ).format(value.toUtc().add(const Duration(hours: 8)));
    String mean(double? value) =>
        value == null ? 'Unavailable' : '${value.toStringAsFixed(2)} / 9';
    pw.Widget text(
      String value, {
      double size = 10,
      bool bold = false,
      PdfColor? color,
    }) => pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    );
    pw.Widget section(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 7),
      child: text(title, size: 13, bold: true, color: green),
    );
    pw.Widget table(
      List<String> headers,
      List<List<String>> rows, {
      double size = 9,
      List<double>? fractions,
    }) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      columnWidths: fractions == null
          ? null
          : {
              for (var i = 0; i < fractions.length; i++)
                i: pw.FlexColumnWidth(fractions[i]),
            },
      headerStyle: pw.TextStyle(
        fontSize: size,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      cellStyle: pw.TextStyle(fontSize: size),
      headerDecoration: const pw.BoxDecoration(color: green),
      oddRowDecoration: const pw.BoxDecoration(color: pale),
      cellPadding: const pw.EdgeInsets.all(5),
      border: null,
      cellAlignment: pw.Alignment.centerLeft,
    );
    pw.Widget footer(pw.Context context) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text('WormWise · Finalized expert findings', size: 8, color: grey),
          text(
            '${context.pageNumber} / ${context.pagesCount}',
            size: 8,
            color: grey,
          ),
        ],
      ),
    );
    pw.Widget header(pw.Context context) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text('WORMWISE', bold: true, color: green),
          text('EXPERT FINDINGS', size: 9, color: grey),
        ],
      ),
    );
    List<int> blockScores(List<StationSnapshot> plants) => [
      for (final p in plants)
        if (report.findings.ratingFor(p)?.outcome == 'scored')
          report.findings.ratingFor(p)!.davisScore!,
    ];
    String rate(int numerator, int denominator) => denominator == 0
        ? 'Unavailable'
        : '${(100 * numerator / denominator).toStringAsFixed(1)}% ($numerator/$denominator)';
    double? blockMean(List<StationSnapshot> plants) {
      final scores = blockScores(plants);
      return scores.isEmpty
          ? null
          : scores.reduce((a, b) => a + b) / scores.length;
    }

    int blockInfested(List<StationSnapshot> plants) =>
        plants.where((p) => report.infestation.forPlant(p) == true).length;
    int blockAssessable(List<StationSnapshot> plants) =>
        plants.where((p) => report.infestation.forPlant(p) != null).length;
    final assessedDate = date(report.assessedAt);
    final assessedPlants = report.findings.scoredPlants;
    final categoryCounts = <int>[
      for (var i = 0; i < daSeverityBands.length; i++)
        report.distribution
            .sublist(
              i == 0 ? 0 : daSeverityBands[i - 1].referenceRating + 1,
              daSeverityBands[i].referenceRating + 1,
            )
            .fold(0, (sum, count) => sum + count),
    ];
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: header,
        footer: footer,
        build: (_) => [
          text('Field assessment summary', size: 24, bold: true, color: green),
          pw.SizedBox(height: 8),
          text(detail.workspace.field.name, size: 16, bold: true),
          text(
            report.review.location.isEmpty
                ? 'Location not recorded'
                : report.review.location,
            color: grey,
          ),
          pw.SizedBox(height: 7),
          text('At assessment time: $assessedDate (Philippine time)', size: 10),
          text(
            'Finalized: ${date(summary.finalizedAt)} (Philippine time)',
            size: 9,
            color: grey,
          ),
          pw.SizedBox(height: 9),
          section('Assessment results'),
          table(
            ['Measure', 'Result', 'Plants assessed'],
            [
              [
                'DA Davis severity',
                '${report.classification}\n${mean(report.findings.mean)}',
                '${report.findings.scoredPlants} / ${report.sample.expectedPlants} scored',
              ],
              [
                'FAW damage incidence',
                report.damageIncidence == null
                    ? 'Unavailable'
                    : '${report.damageIncidence!.toStringAsFixed(1)}%',
                '${report.damagedPlants} / ${report.findings.scoredPlants} scored plants; includes old damage',
              ],
              [
                'Current sampled infestation',
                report.infestation.percent == null
                    ? 'Unavailable'
                    : '${report.infestation.percent!.toStringAsFixed(1)}%',
                '${report.infestation.infested} / ${report.infestation.assessable} assessable plants',
              ],
            ],
            fractions: [.34, .30, .36],
          ),
          pw.SizedBox(height: 5),
          text(
            'Evidence: Davis ${report.findings.scoredPlants}/${report.sample.expectedPlants}; infestation ${report.infestation.assessable}/${report.sample.expectedPlants}.${report.completeCoverage ? '' : ' Percentages exclude unavailable plants.'}',
            size: 9,
            color: grey,
          ),
          pw.SizedBox(height: 5),
          text(
            'Davis describes damage severity. Sampled infestation describes expert-assessed current feeding signs at assessment time.',
            size: 9,
            color: grey,
          ),
          pw.SizedBox(height: 5),
          text(
            report.findings.scoredPlants > 0
                ? 'Plants rated 7-9: ${report.plantsRatedSevenToNine} / ${report.findings.scoredPlants} scored plants.'
                : 'Plants rated 7-9: unavailable; no scored plants.',
            size: 9,
          ),
          section('Field and expert review'),
          table(
            ['Details', 'Saved record'],
            [
              ['Field ID', detail.workspace.field.id],
              [
                'Farmer / representative',
                detail.evaluator.isEmpty ? 'Not recorded' : detail.evaluator,
              ],
              [
                'Field area',
                detail.workspace.boundary == null ||
                        detail.workspace.boundary!.areaHectares <= 0 ||
                        !detail.workspace.boundary!.areaHectares.isFinite
                    ? 'Not recorded'
                    : '${detail.workspace.boundary!.areaHectares.toStringAsFixed(2)} ha',
              ],
              [
                'Crop stage',
                detail.assessment.growthStage.toUpperCase().replaceAll(
                  '_',
                  '-',
                ),
              ],
              ['Assessment date (Philippine time)', assessedDate],
              if (DateTime.tryParse(
                    '${summary.monitoring['latest_evidence_at']}',
                  )
                  case final receivedAt?)
                [
                  'Latest evidence received (Philippine time)',
                  date(receivedAt),
                ],
              ['Expert reviewer', report.reviewerName],
              ['Finalized (Philippine time)', date(summary.finalizedAt)],
              [
                'Sampling',
                '${report.sample.recordedPlants} / ${report.sample.expectedPlants} plants recorded - ${report.sample.expectedPlants ~/ 20} planned blocks; ${blocks.length} with records',
              ],
              [
                'Review coverage',
                '${summary.reviewedPlants} reviewed; ${report.findings.scoredPlants} scored; ${report.findings.insufficientPlants} insufficient; ${math.max(0, report.sample.expectedPlants - summary.reviewedPlants)} not reviewed',
              ],
            ],
            fractions: [.34, .66],
          ),
          section('DA Davis classification legend'),
          table(
            [
              'Mean-score display band / DA class',
              'Reference rating',
              'DA reference description',
            ],
            [
              for (final band in daSeverityBands)
                [
                  '${band.range} - ${band.label}',
                  '${band.referenceRating}',
                  band.referenceDescription,
                ],
            ],
            fractions: [.32, .13, .55],
          ),
          section('Plant counts by DA display category'),
          table(
            ['DA display category', 'Scored plants', 'Share of scored plants'],
            [
              for (var i = 0; i < daSeverityBands.length; i++)
                [
                  '${daSeverityBands[i].range} - ${daSeverityBands[i].label}',
                  '${categoryCounts[i]}',
                  rate(categoryCounts[i], report.findings.scoredPlants),
                ],
            ],
            fractions: [.46, .18, .36],
          ),
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                section('Davis score distribution'),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: List.generate(10, (score) {
                    final count = report.distribution[score];
                    return pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5),
                        child: pw.Column(
                          children: [
                            text(
                              assessedPlants > 0
                                  ? '$count/$assessedPlants'
                                  : '-',
                              size: 9,
                              bold: true,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Container(
                              height: 66,
                              alignment: pw.Alignment.bottomCenter,
                              decoration: const pw.BoxDecoration(color: pale),
                              child: pw.Container(
                                height: assessedPlants > 0
                                    ? 66 * count / assessedPlants
                                    : 0,
                                color: PdfColor.fromInt(
                                  daSeverityBand(score)!.color,
                                ),
                              ),
                            ),
                            pw.SizedBox(height: 5),
                            text('$score', size: 9),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                pw.SizedBox(height: 7),
                text(
                  'Davis rating 0-9; bar height and labels show plants at each rating / total assessed plants with a Davis score.',
                  size: 8,
                  color: grey,
                ),
              ],
            ),
          ),
          section('Summary per sampling block'),
          if (blocks.length < report.sample.expectedPlants ~/ 20)
            text(
              '${report.sample.expectedPlants ~/ 20 - blocks.length} planned block(s) have no available plant records. Their samples remain unavailable in field coverage.',
              size: 10,
              bold: true,
            ),
          for (final plants in blocks.values) ...[
            section(
              'Block ${plants.first.prepared.run.blockSequence} - ${daSeverityClassification(blockMean(plants))}',
            ),
            table(
              ['Measure', 'Result', 'Coverage / basis'],
              [
                [
                  'Mean Davis score',
                  mean(blockMean(plants)),
                  '${blockScores(plants).length}/20 scored plants; ${plants.where((p) => report.findings.ratingFor(p)?.outcome == 'insufficient_evidence').length} insufficient; ${20 - plants.where((p) => report.findings.ratingFor(p) != null).length} not reviewed',
                ],
                [
                  'FAW damage incidence',
                  rate(
                    blockScores(plants).where((score) => score > 0).length,
                    blockScores(plants).length,
                  ),
                  '${blockScores(plants).length}/20 plants scored; includes old damage',
                ],
                [
                  'Current sampled infestation',
                  rate(blockInfested(plants), blockAssessable(plants)),
                  '${blockAssessable(plants)}/20 plants assessable; ${20 - blockAssessable(plants)} unavailable',
                ],
                [
                  'Plants rated 7-9',
                  '${blockScores(plants).where((score) => score >= 7).length} / ${blockScores(plants).length} scored',
                  'Individual ratings, not an action threshold',
                ],
              ],
              fractions: [.32, .27, .41],
            ),
          ],
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                section('Calculation details'),
                table(
                  ['Measure', 'Calculation'],
                  [
                    [
                      'Mean Davis score',
                      report.findings.scoredPlants > 0
                          ? '${report.scoreTotal} / ${report.findings.scoredPlants} = ${report.findings.mean!.toStringAsFixed(2)} / 9'
                          : 'No scorable plant evidence',
                    ],
                    [
                      'FAW damage incidence',
                      report.findings.scoredPlants > 0
                          ? '(${report.damagedPlants} / ${report.findings.scoredPlants}) x 100 = ${report.damageIncidence!.toStringAsFixed(1)}%'
                          : 'No scorable plant evidence',
                    ],
                    [
                      'Current sampled infestation',
                      report.infestation.assessable > 0
                          ? '(${report.infestation.infested} / ${report.infestation.assessable}) x 100 = ${report.infestation.percent!.toStringAsFixed(1)}%'
                          : 'No assessable current-infestation evidence',
                    ],
                  ],
                  fractions: [.40, .60],
                ),
              ],
            ),
          ),
          text(daFormulaExplanation, size: 8, color: grey),
          pw.SizedBox(height: 8),
          text(
            'Assessment ID: ${detail.assessment.id}\nExpert case ID: ${report.review.id}',
            size: 8,
            color: grey,
          ),
        ],
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: header,
        footer: footer,
        build: (_) => [
          text(
            'Highest-rated sampled plants',
            size: 22,
            bold: true,
            color: green,
          ),
          pw.SizedBox(height: 8),
          text(
            'Up to three plants, ordered by finalized Davis score, then block and plant number. One linked view per plant; this selection does not show the whole field.',
            size: 10,
            color: grey,
          ),
          if (highlights.isEmpty)
            text(
              'No scored plants with visible damage are available for this selection.',
              color: grey,
            ),
          for (final rating in highlights) ...[
            pw.Inseparable(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(top: 14),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(
                      'Block ${report.sample.plants.firstWhere((plant) => report.findings.ratingFor(plant)?.identityKey == rating.identityKey).prepared.run.blockSequence} - Plant ${rating.stationNumber} - Davis ${rating.davisScore}/9',
                      size: 13,
                      bold: true,
                      color: green,
                    ),
                    pw.SizedBox(height: 7),
                    pw.Container(
                      height: 160,
                      width: double.infinity,
                      alignment: pw.Alignment.center,
                      decoration: const pw.BoxDecoration(color: pale),
                      child: highlightImages[rating.identityKey] == null
                          ? text(
                              'Linked photo unavailable',
                              size: 12,
                              color: grey,
                            )
                          : pw.Image(
                              highlightImages[rating.identityKey]!,
                              fit: pw.BoxFit.contain,
                              height: 160,
                            ),
                    ),
                    pw.SizedBox(height: 7),
                    text(
                      'DA classification: ${daSeverityClassification(rating.davisScore)}. Expert finding: ${rating.freshnessLabel}.',
                      size: 10,
                      bold: true,
                    ),
                    pw.SizedBox(height: 4),
                    text(
                      'DA reference description (rating ${daSeverityBand(rating.davisScore)!.referenceRating}): ${daSeverityBand(rating.davisScore)!.referenceDescription}',
                      size: 10,
                    ),
                    if (highlightPhotoIds[rating.identityKey]
                        case final photoId?) ...[
                      pw.SizedBox(height: 4),
                      text(
                        'Linked evidence ID: $photoId',
                        size: 8,
                        color: grey,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            if (rating.note.trim().isNotEmpty) ...[
              text('Saved expert note', bold: true),
              pw.SizedBox(height: 4),
              text(rating.note),
            ] else
              text('No saved expert note.', size: 9, color: grey),
          ],
        ],
      ),
    );
    for (final plants in blocks.values) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          header: header,
          footer: footer,
          build: (_) => [
            text(
              'Block ${plants.first.prepared.run.blockSequence} · Plant findings',
              size: 21,
              bold: true,
              color: green,
            ),
            pw.SizedBox(height: 7),
            text(
              'Saved expert ratings, classifications and notes',
              color: grey,
            ),
            pw.SizedBox(height: 14),
            table(
              [
                'Plant',
                'Davis / 9',
                'DA classification',
                'Finding',
                'Expert note',
              ],
              [
                for (final p in plants)
                  [
                    '${p.stationNumber}',
                    report.findings.ratingFor(p)?.davisScore?.toString() ?? '—',
                    report.findings.ratingFor(p)?.outcome == 'scored'
                        ? daSeverityClassification(
                            report.findings.ratingFor(p)?.davisScore,
                          )
                        : 'Unavailable',
                    report.findings.ratingFor(p)?.freshnessLabel ??
                        'Not reviewed',
                    report.findings.ratingFor(p)?.note.trim().isNotEmpty == true
                        ? (report.findings.ratingFor(p)!.note.length > 160
                              ? 'See note below'
                              : report.findings.ratingFor(p)!.note)
                        : '—',
                  ],
              ],
              size: 8,
              fractions: [.08, .11, .22, .21, .38],
            ),
            for (final p in plants)
              if ((report.findings.ratingFor(p)?.note.length ?? 0) > 160) ...[
                section('Plant ${p.stationNumber} · Expert note'),
                text(report.findings.ratingFor(p)!.note),
              ],
          ],
        ),
      );
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: header,
        footer: footer,
        build: (_) => [
          text(
            'Expert guidance and follow-up',
            size: 21,
            bold: true,
            color: green,
          ),
          pw.SizedBox(height: 12),
          if (report.responses.isEmpty)
            text('No saved expert guidance or follow-up date.', color: grey),
          for (final response in report.responses) ...[
            section(
              'Expert response · ${date(response.createdAt)} (Philippine time)',
            ),
            text(response.body),
          ],
        ],
      ),
    );
    return pdf.save();
  }
}
