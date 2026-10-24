import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../../data/local/app_database.dart';
import '../../models/assessment_history_models.dart';
import '../../models/da_assessment_results.dart';
import '../../models/expert_findings_report.dart';
import '../../services/cloud/expert_review_service.dart';
import '../../services/expert_findings_pdf_export_service.dart';
import 'da_monitoring_export.dart';

Future<void> showDaReportExportOptions(
  BuildContext context,
  AssessmentHistoryDetail detail,
) => showModalBottomSheet<void>(
  context: context,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (sheetContext) {
    final service = sheetContext.watch<ExpertReviewService?>();
    final review = finalizedCaseForAssessment(
      detail.assessment.id,
      service?.cases ?? [],
    );
    return DaReportExportOptions(
      assessmentFinished: DaSampleResults.fromDetail(detail).sampleComplete,
      expertFinalized: review != null,
      onDaExport: () {
        Navigator.pop(sheetContext);
        exportDaMonitoringPdf(context, context.read<AppDatabase>(), detail);
      },
      onExpertExport: () {
        Navigator.pop(sheetContext);
        exportFinalizedExpertFindings(context, detail);
      },
    );
  },
);

class DaReportExportOptions extends StatelessWidget {
  const DaReportExportOptions({
    super.key,
    required this.assessmentFinished,
    required this.expertFinalized,
    required this.onDaExport,
    required this.onExpertExport,
  });
  final bool assessmentFinished, expertFinalized;
  final VoidCallback onDaExport, onExpertExport;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export report',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('export_da_pdf_option'),
            enabled: assessmentFinished,
            leading: const Icon(Icons.description_outlined),
            title: const Text('DA monitoring form'),
            subtitle: Text(
              assessmentFinished
                  ? 'DA observations with supporting photos'
                  : 'Complete the assessment to export',
            ),
            onTap: assessmentFinished ? onDaExport : null,
          ),
          ListTile(
            key: const Key('export_expert_pdf_option'),
            enabled: expertFinalized,
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('Expert findings PDF'),
            subtitle: Text(
              expertFinalized
                  ? 'Finalized findings, field summary and analytics'
                  : 'Available after expert finalization',
            ),
            onTap: expertFinalized ? onExpertExport : null,
          ),
        ],
      ),
    ),
  );
}

Future<void> exportFinalizedExpertFindings(
  BuildContext context,
  AssessmentHistoryDetail detail,
) async {
  final service = context.read<ExpertReviewService?>();
  final review = finalizedCaseForAssessment(
    detail.assessment.id,
    service?.cases ?? [],
  );
  if (service == null || review == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Available after expert finalization.')),
    );
    return;
  }
  final userId = service.currentUserId;
  var busy = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Preparing expert PDF…'),
          ],
        ),
      ),
    ),
  );
  void closeProgress() {
    if (context.mounted && busy) {
      Navigator.of(context, rootNavigator: true).pop();
      busy = false;
    }
  }

  try {
    final ratings = await service.loadSeverityRatings(review.id);
    final guidance = await service.loadReportGuidance(review.id);
    final current = finalizedCaseForAssessment(
      detail.assessment.id,
      service.cases,
    );
    if (userId != service.currentUserId ||
        current?.id != review.id ||
        current?.severitySummary?.finalizedAt !=
            review.severitySummary!.finalizedAt) {
      throw StateError('Review changed while preparing the report.');
    }
    final report = ExpertFindingsReport(
      detail: detail,
      review: review,
      ratings: ratings,
      guidance: guidance,
    );
    final bytes = await const ExpertFindingsPdfExportService().build(report);
    closeProgress();
    if (!context.mounted || userId != service.currentUserId) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'wormwise-expert-findings-${detail.assessment.id}.pdf',
    );
  } catch (_) {
    closeProgress();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load finalized findings. Refresh the expert review and try again.',
          ),
        ),
      );
    }
  }
}
