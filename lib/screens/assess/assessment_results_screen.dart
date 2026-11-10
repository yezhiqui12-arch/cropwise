import '../../services/assessment_evidence_stats.dart';
export '../../services/assessment_evidence_stats.dart'
    show AssessmentEvidenceStats, StationEvidenceStats;
import '../../services/advisor/assessment_recommended_steps.dart';
import '../../services/map_view_policy.dart';
import '../../models/automatic_screening.dart';
import '../../services/advisor/advisor_assessment_contract.dart';
import '../../services/advisor/assessment_result_ai_context.dart';
import '../../services/cloud/expert_review_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import '../../models/da_severity.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:drift/drift.dart' show Value;

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../providers/app_data_mode.dart';
import '../../services/evidence_storage_service.dart';
import '../../services/assessment_pdf_export_service.dart';
import 'expert_findings_export.dart';
import 'retired_assessment_notice.dart';
import '../../services/cloud/expert_case_submission_service.dart';
import '../../services/cloud/wormwise_cloud_sync_service.dart';
import '../../services/cloud/wormwise_identity_service.dart';
import '../../services/polygon_calculator.dart';
import '../../services/phone_location_service.dart';
import '../../services/advisor/advisor_gemini_settings.dart';
import '../../services/advisor/advisor_open_chat_service.dart';
import '../../services/advisor/gemini_advisor_open_chat_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../advisor/guidelines_redesign.dart';
import '../expert_review_screen.dart';
import '../expert_severity_review_screen.dart';
import 'assessment_assistant_screen.dart';
import 'station_details_screen.dart';
import 'plant_details_screen.dart';
import 'assessment_interpretation_panel.dart';
import 'assessment_action_modal.dart';
import '../../models/da_assessment_results.dart';
import 'da_assessment_results_section.dart';
import 'assessment_result_components.dart';
import 'assessment_map_screen.dart';
import '../../services/scouting_sampling_protocol.dart';

part 'assessment_result_evidence_widgets.dart';
part 'assessment_result_map_widgets.dart';

/// Read-only presentation of already persisted assessment results.
///
/// Designed with two main tabs:
/// 1. [ Stations ] (Default active tab) - Overall infestation, evidence breakdown,
///    evidence type chart, station cards, sampling quality, block metrics, map/export.
/// 2. [ Recommendations ] - AI/deterministic field interpretation, dynamic next steps,
///    LGU/DA reporting card, offline management guidance, and Ask WormWise assistant.
class AssessmentResultsScreen extends StatefulWidget {
  const AssessmentResultsScreen({
    super.key,
    required this.assessmentId,
    this.initialTab = 0,
    this.geminiSettingsStore,
  });

  final String assessmentId;
  final int initialTab;
  final AdvisorGeminiSettingsStore? geminiSettingsStore;

  @override
  State<AssessmentResultsScreen> createState() =>
      _AssessmentResultsScreenState();
}

class _AssessmentResultsScreenState extends State<AssessmentResultsScreen> {
  late final AssessmentHistoryRepository _repository;
  late final EvidenceStorageService _storage;
  late Stream<AssessmentHistoryDetail?> _record;

  late int _selectedTabIndex;
  final ScrollController _resultsScrollController = ScrollController();
  String? _aiInterpretation;
  List<AssessmentNextStep>? _aiRecommendations;
  bool _isLoadingAi = false;
  bool _isOfflineAi = false;
  bool _isCachedAi = false;
  String? _aiAvailabilityMessage;
  DateTime? _aiGeneratedAt;
  bool _shareAssessmentWithAi = false;
  int _reportStatus =
      0; // 0 = Ready to Queue, 1 = Queuing, 2 = Queued, 3 = Failed
  String? _reportError;
  AssessmentAssistantPreview? _assistantPreview;
  String? _loadedAssessmentId;
  String? _loadedAdviceContextKey;
  int _aiRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTab;
    _repository = AssessmentHistoryRepository(context.read<AppDatabase>());
    final mode = context.read<AppDataMode?>();
    _storage = EvidenceStorageService(
      rootDirectory: mode?.isTestMode == true
          ? mode!.evidenceRootDirectory
          : null,
    );
    _record = _repository.watchDetail(widget.assessmentId);
  }

  @override
  void dispose() {
    _resultsScrollController.dispose();
    super.dispose();
  }

  void _selectResultsTab(int index) {
    if (_selectedTabIndex == index) return;
    if (_resultsScrollController.hasClients) _resultsScrollController.jumpTo(0);
    setState(() => _selectedTabIndex = index);
  }

  Future<void> _setAssessmentAiSharing({
    required bool enabled,
    required AppDatabase database,
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
  }) async {
    final store =
        widget.geminiSettingsStore ?? const SecureAdvisorGeminiSettingsStore();
    try {
      final current = await store.loadPreferences();
      await store.savePreferences(
        AdvisorGeminiPreferences(
          enabled: current.enabled,
          shareFieldContext: enabled,
          shareLocation: current.shareLocation,
          allowPhotoUploads: current.allowPhotoUploads,
        ),
      );
      if (!mounted) return;
      setState(() => _shareAssessmentWithAi = enabled);
      await _loadOrGenerateAiResults(
        database: database,
        detail: detail,
        stats: stats,
        forceRegenerate: true,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not save the AI sharing setting.'),
        ),
      );
    }
  }

  Future<void> _loadOrGenerateAiResults({
    required AppDatabase database,
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
    bool forceRegenerate = false,
  }) async {
    final requestSerial = ++_aiRequestSerial;
    final safeFacts = AssessmentSafeFacts.fromDetailAndStats(
      detail,
      stats,
      expertReview:
          context.read<ExpertReviewService?>()?.assessmentReviewFacts(
            detail.assessment.id,
          ) ??
          const {},
    );
    if (mounted) {
      setState(() {
        _isLoadingAi = true;
        _aiAvailabilityMessage = null;
        _aiInterpretation = null;
        _aiRecommendations = null;
        _isOfflineAi = true;
        _isCachedAi = false;
        _aiGeneratedAt = null;
      });
    }
    final settingsStore =
        widget.geminiSettingsStore ?? const SecureAdvisorGeminiSettingsStore();
    AdvisorGeminiPreferences prefs;
    try {
      prefs = await settingsStore.loadPreferences();
    } catch (_) {
      prefs = const AdvisorGeminiPreferences();
    }
    if (!mounted || requestSerial != _aiRequestSerial) return;
    if (_shareAssessmentWithAi != prefs.shareFieldContext) {
      setState(() => _shareAssessmentWithAi = prefs.shareFieldContext);
    }
    final factsFingerprint = _assessmentAdviceFingerprint(safeFacts);
    // v7 refreshes saved advice after the concise recommendation wording update.
    final filipino = AppWords.of(context).language == AppLanguage.filipino;
    final cacheKey =
        'ai_assessment_result_screen_v7_${detail.assessment.id}${filipino ? '_fil' : ''}';

    if (!forceRegenerate) {
      try {
        final cached =
            await (database.select(database.appPreferences)
                  ..where((tbl) => tbl.preferenceKey.equals(cacheKey)))
                .getSingleOrNull();

        if (cached != null && cached.preferenceValue.trim().isNotEmpty) {
          final data = jsonDecode(cached.preferenceValue);
          if (data is Map<String, dynamic> &&
              data['recommendations'] is List &&
              data['factsFingerprint'] == factsFingerprint &&
              data['isOffline'] == !prefs.shareFieldContext &&
              (!prefs.shareFieldContext || prefs.enabled)) {
            final steps = <AssessmentNextStep>[];
            if (data['recommendations'] is List) {
              for (final r in data['recommendations']) {
                if (r is Map<String, dynamic>) {
                  steps.add(AssessmentNextStep.fromJson(r));
                }
              }
            }
            if (mounted && requestSerial == _aiRequestSerial) {
              setState(() {
                _aiInterpretation = data['interpretation'] as String?;
                _aiRecommendations = steps;
                _isOfflineAi = data['isOffline'] == true;
                _isCachedAi = data['isOffline'] != true;
                _aiGeneratedAt = DateTime.tryParse(
                  data['generatedAt']?.toString() ?? '',
                );
                _isLoadingAi = false;
                _aiAvailabilityMessage = null;
              });
              return;
            }
          }
        }
      } catch (_) {
        // A corrupt/stale cache must never prevent fresh generation.
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoadingAi = true;
      _aiInterpretation = null;
      _aiRecommendations = null;
      _isOfflineAi = true;
      _isCachedAi = false;
      _aiGeneratedAt = null;
      _aiAvailabilityMessage = null;
    });

    try {
      final isRunningInFlutterTest = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('Test');
      var serviceConfigured = false;
      if (widget.geminiSettingsStore != null || !isRunningInFlutterTest) {
        try {
          serviceConfigured = await settingsStore.isServiceConfigured();
        } catch (_) {
          serviceConfigured = false;
        }
      }

      Map<String, dynamic>? resultData;
      String? aiFailureMessage;
      if (!mounted || requestSerial != _aiRequestSerial) return;

      final requestedFreshAi =
          serviceConfigured && prefs.enabled && prefs.shareFieldContext;
      if (requestedFreshAi) {
        final prompt = buildAssessmentResultAiPrompt(
          safeFacts.currentContext,
          filipino: filipino,
          stationRefs: safeFacts.validStationRefs.toList(),
        );

        final responseText = await const _AssessmentResultAiClient().generate(
          prompt,
        );
        if (!mounted || requestSerial != _aiRequestSerial) return;
        String? rejectionReason;
        resultData = _validateAndSanitizeAiJson(
          responseText,
          safeFacts,
          onRejected: (reason) => rejectionReason = reason,
        );
        if (resultData == null) {
          aiFailureMessage =
              '${rejectionReason ?? 'The AI response could not be used.'} Showing local guidance. Tap Regenerate to try again.';
        }
      } else if (prefs.shareFieldContext && prefs.enabled) {
        aiFailureMessage =
            'The AI service is not configured for this build. Showing local guidance.';
      }

      resultData ??= {
        'interpretation': _buildDeterministicInterpretation(safeFacts),
        'recommendations': _buildDeterministicNextSteps(
          safeFacts,
        ).map((s) => s.toJson()).toList(),
        'isOffline': true,
        'generatedAt': DateTime.now().toIso8601String(),
      };
      resultData['factsFingerprint'] = factsFingerprint;

      if (!mounted || requestSerial != _aiRequestSerial) return;

      try {
        if (resultData['isOffline'] != true || !prefs.shareFieldContext) {
          await database
              .into(database.appPreferences)
              .insertOnConflictUpdate(
                AppPreferencesCompanion.insert(
                  preferenceKey: cacheKey,
                  preferenceValue: jsonEncode(resultData),
                  updatedAt: Value(DateTime.now()),
                ),
              );
        }
      } catch (_) {
        // The result is still usable for this session if cache persistence fails.
      }

      if (mounted && requestSerial == _aiRequestSerial) {
        final steps = (resultData['recommendations'] as List)
            .whereType<Map>()
            .map(
              (r) => AssessmentNextStep.fromJson(Map<String, dynamic>.from(r)),
            )
            .toList();
        setState(() {
          _aiInterpretation = resultData!['interpretation'] as String?;
          _aiRecommendations = steps;
          _isOfflineAi = resultData['isOffline'] == true;
          _isCachedAi = false;
          _aiGeneratedAt = DateTime.tryParse(
            resultData['generatedAt']?.toString() ?? '',
          );
          _isLoadingAi = false;
          _aiAvailabilityMessage = aiFailureMessage;
        });
      }
    } catch (error) {
      final fallbackSteps = _buildDeterministicNextSteps(safeFacts);
      final fallbackInterp = _buildDeterministicInterpretation(safeFacts);
      if (mounted && requestSerial == _aiRequestSerial) {
        setState(() {
          _aiInterpretation = fallbackInterp;
          _aiRecommendations = fallbackSteps;
          _isOfflineAi = true;
          _isCachedAi = false;
          _aiGeneratedAt = DateTime.now();
          _isLoadingAi = false;
          _aiAvailabilityMessage = prefs.shareFieldContext && prefs.enabled
              ? _assessmentAiFailureMessage(error)
              : null;
        });
      }
    }
  }

  Future<void> _loadReportStatus({
    required AppDatabase database,
    required String assessmentId,
  }) async {
    try {
      final row =
          await (database.select(database.syncOutbox)..where(
                (tbl) => tbl.id.equals('report_assessment_$assessmentId'),
              ))
              .getSingleOrNull();
      if (!mounted) return;
      setState(() {
        if (row == null) {
          _reportStatus = 0;
          _reportError = null;
          return;
        }
        final status = row.status.toLowerCase();
        if (status == 'queued' || status == 'pending' || status == 'sending') {
          // Legacy local-only queue entries do not prove remote delivery.
          _reportStatus = 0;
          _reportError = null;
        } else if (status == 'failed' || status == 'error') {
          _reportStatus = 3;
          _reportError = 'The previously queued report is marked as failed.';
        } else if (status == 'submitted' || status == 'synced') {
          _reportStatus = 2;
          _reportError = null;
        } else {
          _reportStatus = 0;
          _reportError = null;
        }
      });
    } catch (_) {
      // Keep the default state if the local queue cannot be inspected.
    }
  }

  Future<void> _loadAssistantPreview({
    required AppDatabase database,
    required String assessmentId,
  }) async {
    final preview = await loadAssessmentAssistantPreview(
      database,
      assessmentId,
    );
    if (!mounted) return;
    setState(() => _assistantPreview = preview);
  }

  Future<void> _openAssessmentAssistant({
    required AppDatabase database,
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
    String? initialQuestion,
  }) async {
    final contextSummary = _buildAssessmentAssistantContext(detail, stats);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentAssistantScreen(
          database: database,
          assessmentId: detail.assessment.id,
          fieldName: detail.workspace.field.name,
          assessmentContext: contextSummary,
          initialQuestion: initialQuestion,
          geminiSettingsStore: widget.geminiSettingsStore,
        ),
      ),
    );
    if (!mounted) return;
    await _loadAssistantPreview(
      database: database,
      assessmentId: detail.assessment.id,
    );
  }

  Future<void> _openRecommendedStep({
    required AssessmentNextStep step,
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
  }) async {
    final isDa = ScoutingSamplingProtocol.isDa(
      detail.assessment.protocolVersion,
    );
    if (step.type == 'expert_review') {
      final service = context.read<ExpertReviewService?>();
      final submitted =
          service?.cases.any((c) => c.assessmentId == detail.assessment.id) ==
          true;
      if (!submitted) {
        await _queueAssessmentReport(
          database: context.read<AppDatabase>(),
          detail: detail,
          stats: stats,
        );
      } else {
        final finalized =
            service!.cases
                .where(
                  (c) =>
                      c.assessmentId == detail.assessment.id &&
                      c.severitySummary != null,
                )
                .toList()
              ..sort(
                (a, b) => b.severitySummary!.finalizedAt.compareTo(
                  a.severitySummary!.finalizedAt,
                ),
              );
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => finalized.isEmpty
                ? const ExpertReviewScreen()
                : ExpertSeverityReviewScreen(caseId: finalized.first.id),
          ),
        );
      }
      return;
    }
    if (step.type == 'extension_consultation' ||
        step.type == 'report_assessment') {
      await _BottomActionButtons.exportExpertPdf(
        context,
        detail: detail,
        stats: stats,
        storage: _storage,
      );
      return;
    }
    if (step.type == 'safety_review') {
      if (!mounted) return;
      if (isDa) {
        await showResultInformation(
          context,
          title: 'Field-entry safety',
          icon: Icons.shield_outlined,
          body:
              'The saved assessment does not confirm that field entry is allowed. Check the treatment record, product label, and any other entry requirements before visiting a station.',
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const AppText('Field-entry safety'),
          content: const AppText(
            'The saved assessment does not confirm that field entry is allowed. Check the treatment record, product label, and any other entry requirements before visiting a station.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const AppText('Close'),
            ),
          ],
        ),
      );
      return;
    }
    if (step.stationRefs.isNotEmpty) {
      var targetRef = step.stationRefs.first;
      if (step.stationRefs.length > 1) {
        if (!mounted) return;
        final selected = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: AppText(isDa ? 'Choose a plant' : 'Choose a station'),
            children: [
              for (final ref in step.stationRefs)
                SimpleDialogOption(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, ref),
                  child: Text(readableAssessmentReferences(ref, da: isDa)),
                ),
            ],
          ),
        );
        if (selected == null) return;
        targetRef = selected;
      }
      for (final station in detail.stations) {
        final ref =
            'B${station.prepared.run.blockSequence}-S${station.stationNumber}';
        if (ref != targetRef) continue;
        if (!mounted) return;
        final observation = isDa
            ? DaSampleResults.fromDetail(detail).observation(station)
            : null;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => observation != null
                ? PlantAssessmentDetailsScreen(
                    detail: detail,
                    station: station,
                    record: observation,
                    storage: _storage,
                  )
                : StationDetailsScreen(
                    detail: detail,
                    station: station,
                    storage: _storage,
                  ),
          ),
        );
        return;
      }
    }
    if (step.type == 'review_evidence') {
      _selectResultsTab(0);
      return;
    }
    if (!mounted) return;
    if (const {
      'monitoring',
      'field_monitoring',
      'protocol_guidance',
    }.contains(step.type)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const AdvisorOfflineGuidesScreen(
            initialArticleId: 'scouting-systematic',
          ),
        ),
      );
      return;
    }
    if (isDa) {
      await showResultInformation(
        context,
        title: step.title,
        body: step.description,
        icon: Icons.assistant_direction_outlined,
        actionLabel: 'Offline scouting guide',
        onAction: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => const AdvisorOfflineGuidesScreen(
              initialArticleId: 'scouting-systematic',
            ),
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(step.title),
        content: AppText(step.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdvisorOfflineGuidesScreen(
                    initialArticleId: 'scouting-systematic',
                  ),
                ),
              );
            },
            child: const AppText('Offline scouting guide'),
          ),
        ],
      ),
    );
  }

  Future<void> _queueAssessmentReport({
    required AppDatabase database,
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final submission = await _showExpertSubmissionDialog(detail);
    if (submission == null || !mounted) return;
    final identity = context.read<WormWiseIdentityService>();
    final client = identity.client;
    if (client == null || !identity.hasCloudIdentity) {
      messenger.showSnackBar(
        const SnackBar(
          content: AppText(
            'Connect to the internet before sending this assessment.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _reportStatus = 1;
      _reportError = null;
    });
    try {
      final cloudSync = context.read<WormWiseCloudSyncService>();
      await cloudSync.synchronizeAssessmentForSubmission(detail.assessment.id);
      final result =
          await ExpertCaseSubmissionService(
            database: database,
            client: client,
            storage: _storage,
          ).submit(
            detail: detail,
            farmerDisplayName: submission.farmerName,
            shareLocation: true,
            shareEvidence: true,
            farmerQuestion: submission.question,
          );
      if (mounted) {
        setState(() => _reportStatus = 2);
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Color(0xFF1B4D3E),
            content: Text(
              result.existed
                  ? 'This assessment is already in the expert review queue.'
                  : 'Assessment sent securely to the expert review queue.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Expert case submission failed: $e');
      if (mounted) {
        setState(() {
          _reportStatus = 3;
          _reportError = _friendlySubmissionError(e);
        });
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Color(0xFF991B1B),
            content: Text(_reportError!),
          ),
        );
      }
    }
  }

  String _friendlySubmissionError(Object error) {
    if (error is ExpertSubmissionStageException) {
      return '${error.stage}: ${_friendlySubmissionError(error.cause)}';
    }
    final value = error.toString().toLowerCase();
    if (error is FileSystemException) {
      return 'An evidence photo is missing from this phone. Reopen the assessment and check its photos.';
    }
    if (error is StateError &&
        !value.contains('postgrestexception') &&
        !value.contains('storageexception')) {
      return _submissionErrorMessage(error.message.toString());
    }
    return _submissionErrorMessage(value, error: error);
  }

  String _submissionErrorMessage(String message, {Object? error}) {
    final value = message.toLowerCase();
    if (value.contains('infinite recursion') || value.contains('42p17')) {
      return 'The database security update has not been applied yet.';
    }
    if (value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection')) {
      return 'No connection to the expert service. Try again when online.';
    }
    if (value.contains('42501') || value.contains('row-level security')) {
      if (value.contains(
        'cloud synchronization failed before expert submission',
      )) {
        return 'Cloud synchronization was blocked by a server access policy before the assessment could be submitted. This does not establish that you are using the wrong account. Details: $message';
      }
      return 'The server rejected this operation under its access policy. This does not establish that you are using the wrong account. Details: ${error is PostgrestException
          ? '${error.message} (${error.code})'
          : error is StorageException
          ? error.message
          : message}';
    }
    if (value.contains('only a synchronized, completed assessment')) {
      return 'The completed assessment has not synchronized yet. Try again.';
    }
    if (value.contains('jwt') ||
        value.contains('authentication') ||
        value.contains('refresh token')) {
      return 'Your cloud session has expired. Sign in again, then retry.';
    }
    if (value.contains('pgrst202') ||
        value.contains('schema cache') ||
        value.contains('does not exist')) {
      return 'The expert service database needs an update before this assessment can be sent.';
    }
    if (error is StorageException) {
      return 'Photo upload failed: ${error.message}';
    }
    if (error is PostgrestException) {
      return 'Expert service rejected the assessment: ${error.message} (${error.code}).';
    }
    if (error == null) return message;
    return 'The assessment could not be sent. Please try again.';
  }

  Future<_ExpertSubmissionInput?> _showExpertSubmissionDialog(
    AssessmentHistoryDetail detail,
  ) => showDialog<_ExpertSubmissionInput>(
    context: context,
    builder: (_) => _ExpertSubmissionDialog(detail: detail),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: const AppText('Assessment results'),
      ),
      body: StreamBuilder<AssessmentHistoryDetail?>(
        stream: _record,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SafeArea(
              child: _ResultsMessage(
                icon: Icons.error_outline,
                title: 'Could not load results',
                message: 'Your saved assessment has not been changed.',
                action: TextButton(
                  onPressed: () => setState(
                    () =>
                        _record = _repository.watchDetail(widget.assessmentId),
                  ),
                  child: const AppText('Try again'),
                ),
              ),
            );
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (ScoutingSamplingProtocol.isRetired(
            detail.assessment.protocolVersion,
            pattern: detail.assessment.scoutingPattern,
          )) {
            return RetiredAssessmentNotice(fieldId: detail.workspace.field.id);
          }

          final isTestMode = context.watch<AppDataMode>().isTestMode;
          final stats = computeAssessmentEvidenceStats(detail);
          final database = context.read<AppDatabase>();

          final reviewFacts =
              context.watch<ExpertReviewService?>()?.assessmentReviewFacts(
                detail.assessment.id,
              ) ??
              const <String, dynamic>{};
          final adviceContextKey =
              '${detail.assessment.id}:${AppWords.of(context).language}:${_assessmentAdviceFingerprint(AssessmentSafeFacts.fromDetailAndStats(detail, stats, expertReview: reviewFacts))}';
          if (_loadedAdviceContextKey != adviceContextKey) {
            _loadedAdviceContextKey = adviceContextKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _loadedAdviceContextKey != adviceContextKey) {
                return;
              }
              unawaited(
                _loadOrGenerateAiResults(
                  database: database,
                  detail: detail,
                  stats: stats,
                ),
              );
            });
          }

          if (_loadedAssessmentId != detail.assessment.id) {
            _loadedAssessmentId = detail.assessment.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(
                _loadReportStatus(
                  database: database,
                  assessmentId: detail.assessment.id,
                ),
              );
              unawaited(
                _loadAssistantPreview(
                  database: database,
                  assessmentId: detail.assessment.id,
                ),
              );
            });
          }

          return Stack(
            children: [
              Column(
                children: [
                  if (isTestMode)
                    Material(
                      key: const Key('permanent_test_data_indicator'),
                      color: const Color(0xFF8B1E1E),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: AppText(
                                  'TEST DATA · Separate from farmer records',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _ResultsScrollableBody(
                      detail: detail,
                      stats: stats,
                      isTestMode: isTestMode,
                      storage: _storage,
                      selectedTabIndex: _selectedTabIndex,
                      onTabChanged: _selectResultsTab,
                      scrollController: _resultsScrollController,
                      aiInterpretation: _aiInterpretation,
                      aiRecommendations: _aiRecommendations,
                      isLoadingAi: _isLoadingAi,
                      isOfflineAi: _isOfflineAi,
                      isCachedAi: _isCachedAi,
                      aiAvailabilityMessage: _aiAvailabilityMessage,
                      aiGeneratedAt: _aiGeneratedAt,
                      shareAssessmentWithAi: _shareAssessmentWithAi,
                      onShareAssessmentWithAiChanged: (enabled) =>
                          _setAssessmentAiSharing(
                            enabled: enabled,
                            database: database,
                            detail: detail,
                            stats: stats,
                          ),
                      reportStatus: _reportStatus,
                      reportError: _reportError,
                      assistantPreview: _assistantPreview,
                      onOpenAssistant: () => _openAssessmentAssistant(
                        database: database,
                        detail: detail,
                        stats: stats,
                      ),
                      onOpenRecommendedStep: (step) => _openRecommendedStep(
                        step: step,
                        detail: detail,
                        stats: stats,
                      ),
                      onRegenerateAi: () => _loadOrGenerateAiResults(
                        database: database,
                        detail: detail,
                        stats: stats,
                        forceRegenerate: true,
                      ),
                      onSendReport: () => _queueAssessmentReport(
                        database: database,
                        detail: detail,
                        stats: stats,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PersistentResultsActionBar(
                  detail: detail,
                  stats: stats,
                  storage: _storage,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CALCULATION HELPER
// ─────────────────────────────────────────────────────────────────────────────

String _formatMetricCount(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _primaryMetricTitle(String code) {
  return switch (code) {
    AutomaticScreening.metric => 'Damage-screened plants',
    DatabaseCodes.vegetativeCurrentInfestationPercent => 'Current infestation',
    DatabaseCodes.vtR2InfestedPlantPercent => 'VT-R2 infested plants',
    DatabaseCodes.externalEarDamagePercent => 'External ear damage',
    DatabaseCodes.openedEarInternalDamagePercent =>
      'Opened-ear internal damage',
    DatabaseCodes.pooledDamagedKernelPercent => 'Pooled damaged kernels',
    DatabaseCodes.daBafsMedianScore => 'DA-BAFS median leaf-damage score',
    _ => code,
  };
}

String _primaryMetricDenominatorLabel(String code, String growthStage) {
  if (code == AutomaticScreening.metric) return 'sampled plants screened';

  if (code == DatabaseCodes.externalEarDamagePercent) {
    return 'externally assessable ears';
  }
  if (code == DatabaseCodes.openedEarInternalDamagePercent) {
    return 'opened ears';
  }
  if (code == DatabaseCodes.pooledDamagedKernelPercent) {
    return 'assessable kernels in opened ears';
  }
  if (code == DatabaseCodes.daBafsMedianScore) {
    return 'scored observations';
  }
  if ({'ve', 'v1', 'v2'}.contains(growthStage)) {
    return 'assessable seedlings';
  }
  return 'assessable plants';
}

String _formatPrimaryMetricValue(String unit, double value) {
  final valueText = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  if (unit == 'percent') return '$valueText%';
  if (unit == 'ordinal_score') return 'score $valueText';
  return '$valueText $unit';
}

String _buildAssessmentAssistantContext(
  AssessmentHistoryDetail detail,
  AssessmentEvidenceStats stats,
) {
  return '${AdvisorAssessmentContract.instruction}\n'
      'SAVED ASSESSMENT RESULTS:\n${jsonEncode(assessmentResultAiContext(detail))}';
}

// ─────────────────────────────────────────────────────────────────────────────
// SAFE FACTS & RECOMMENDATION PIPELINE
// ─────────────────────────────────────────────────────────────────────────────

class _AssessmentResultAiClient {
  const _AssessmentResultAiClient();

  Future<String> generate(String prompt) async {
    Object? lastFailure;
    for (final model in GeminiAdvisorOpenChatService.defaultModels) {
      try {
        return await _generateForModel(prompt, model);
      } on AdvisorGeminiApiException catch (error) {
        lastFailure = error;
        final message = error.message.toLowerCase();
        final canTryAnotherModel =
            error.statusCode == 404 ||
            error.statusCode == 429 ||
            error.statusCode == 503 ||
            (error.statusCode == 400 &&
                message.contains('invalid ai request')) ||
            message.contains('unsupported model') ||
            message.contains('not available');
        if (!canTryAnotherModel) rethrow;
      }
    }
    throw lastFailure ??
        const AdvisorGeminiApiException('No AI model could respond.');
  }

  Future<String> _generateForModel(String prompt, String model) async {
    final response = await const SupabaseAdvisorGeminiTransport().generate(
      model: model,
      body: {
        'system_instruction': {
          'parts': [
            {
              'text':
                  'Return only structured JSON for the supplied Cropwise assessment. Follow the factual and safety rules in the user request.',
            },
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.2,
          'maxOutputTokens': 1800,
          'responseMimeType': 'application/json',
        },
        'store': false,
      },
    );
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AdvisorGeminiApiException(
        'No assessment response was returned.',
      );
    }
    final parts = (candidates.first as Map?)?['content']?['parts'];
    if (parts is! List ||
        parts.isEmpty ||
        (parts.first as Map?)?['text'] is! String) {
      throw const AdvisorGeminiApiException(
        'The assessment response was unreadable.',
      );
    }
    return (parts.first as Map)['text'] as String;
  }
}

String _assessmentAiFailureMessage(Object error) {
  if (error is AdvisorGeminiApiException) {
    return 'AI request failed: ${error.message} Showing local guidance. Tap Regenerate to try again.';
  }
  if (error is AdvisorOnlineUnavailableException) {
    return 'The AI service could not be reached. Showing local guidance. Tap Regenerate to try again.';
  }
  return 'Could not load AI advice. Showing local guidance. Tap Regenerate to try again.';
}

class AssessmentSafeFacts {
  const AssessmentSafeFacts({
    this.screeningMode = false,
    this.currentContext = const {},
    required this.assessmentId,
    required this.fieldName,
    required this.growthStage,
    required this.formattedGrowthStage,
    required this.primaryMetricCode,
    required this.primaryMetricTitle,
    required this.primaryMetricValue,
    required this.primaryUnit,
    required this.primaryNumerator,
    required this.primaryDenominator,
    required this.primaryDenominatorLabel,
    required this.evidenceAssessableCount,
    required this.damageCount,
    required this.frassCount,
    required this.larvaCount,
    required this.eggCount,
    required this.highestEvidenceStations,
    required this.stationStats,
    required this.notAssessableCount,
    required this.outstandingIssueCount,
    required this.safetyStatus,
  });

  final bool screeningMode;
  final Map<String, dynamic> currentContext;
  final String assessmentId;
  final String fieldName;
  final String growthStage;
  final String formattedGrowthStage;
  final String primaryMetricCode;
  final String primaryMetricTitle;
  final double primaryMetricValue;
  final String primaryUnit;
  final double primaryNumerator;
  final double primaryDenominator;
  final String primaryDenominatorLabel;
  final int evidenceAssessableCount;
  final int damageCount;
  final int frassCount;
  final int larvaCount;
  final int eggCount;
  final List<String> highestEvidenceStations;
  final List<StationEvidenceStats> stationStats;
  final int notAssessableCount;
  final int outstandingIssueCount;
  final String? safetyStatus;

  bool get fieldEntryBlocked =>
      safetyStatus != DatabaseCodes.noRecentTreatment &&
      safetyStatus != DatabaseCodes.safeIntervalCompleted;

  bool get hasEggs => eggCount > 0;
  bool get hasLarvae => larvaCount > 0;
  bool get hasDamage => damageCount > 0;
  bool get hasFrass => frassCount > 0;
  bool get hasAnyEvidence =>
      damageCount > 0 || frassCount > 0 || larvaCount > 0 || eggCount > 0;

  int get affectedStationCount =>
      stationStats.where((station) => station.evidenceCount > 0).length;

  Set<String> get validStationRefs =>
      stationStats.map((station) => station.ref).toSet();

  factory AssessmentSafeFacts.fromDetailAndStats(
    AssessmentHistoryDetail detail,
    AssessmentEvidenceStats stats, {
    Map<String, dynamic> expertReview = const {},
  }) {
    var maxEvidenceCount = 0;
    for (final station in stats.stationStats) {
      maxEvidenceCount = math.max(maxEvidenceCount, station.evidenceCount);
    }
    final highestEvidenceStations = maxEvidenceCount == 0
        ? <String>[]
        : stats.stationStats
              .where((station) => station.evidenceCount == maxEvidenceCount)
              .map((station) => station.ref)
              .toList(growable: false);

    return AssessmentSafeFacts(
      currentContext: assessmentResultAiContext(
        detail,
        expertReview: expertReview,
      ),
      screeningMode: stats.screeningMode,
      assessmentId: detail.assessment.id,
      fieldName: detail.workspace.field.name,
      growthStage: detail.assessment.growthStage,
      formattedGrowthStage: _formatGrowthStage(detail.assessment.growthStage),
      primaryMetricCode: stats.primaryMetricCode,
      primaryMetricTitle: _primaryMetricTitle(stats.primaryMetricCode),
      primaryMetricValue: stats.overallInfestationPercent,
      primaryUnit: stats.primaryUnit,
      primaryNumerator: stats.primaryNumerator,
      primaryDenominator: stats.primaryDenominator,
      primaryDenominatorLabel: _primaryMetricDenominatorLabel(
        stats.primaryMetricCode,
        detail.assessment.growthStage,
      ),
      evidenceAssessableCount: stats.totalAssessable,
      damageCount: stats.damageCount,
      frassCount: stats.frassCount,
      larvaCount: stats.larvaCount,
      eggCount: stats.eggCount,
      highestEvidenceStations: highestEvidenceStations,
      stationStats: stats.stationStats,
      notAssessableCount: stats.screeningMode
          ? stats.totalRecorded - stats.totalAssessable
          : detail.resultSummary.notAssessableObservationCount,
      outstandingIssueCount: detail.resultSummary.outstandingIssueCount,
      safetyStatus:
          detail.safety?.resultStatus ?? detail.assessment.safetySummaryStatus,
    );
  }
}

String _assessmentAdviceFingerprint(AssessmentSafeFacts facts) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'current_context': AdvisorAssessmentContract.stableFacts(
            facts.currentContext,
          ),
          'contract_version': AdvisorAssessmentContract.version,
          'field': facts.fieldName,
          'stage': facts.growthStage,
          'metric': facts.primaryMetricCode,
          'value': facts.primaryMetricValue,
          'numerator': facts.primaryNumerator,
          'denominator': facts.primaryDenominator,
          'screening': facts.screeningMode,
          'safety': facts.safetyStatus,
          'notAssessable': facts.notAssessableCount,
          'issues': facts.outstandingIssueCount,
          'counts': [
            facts.damageCount,
            facts.frassCount,
            facts.larvaCount,
            facts.eggCount,
          ],
          'stations': [
            for (final station in facts.stationStats)
              [
                station.ref,
                station.assessableCount,
                station.recordedCount,
                station.highlightedPlants,
                station.infestationPercent,
                station.damageCount,
                station.frassCount,
                station.larvaCount,
                station.eggCount,
              ],
          ],
        }),
      ),
    )
    .toString();

class AssessmentNextStep {
  const AssessmentNextStep({
    required this.icon,
    required this.title,
    required this.description,
    this.type,
    this.stationRefs = const [],
    this.source = 'saved_findings',
  });

  final IconData icon;
  final String title;
  final String description;
  final String? type;
  final List<String> stationRefs;
  final String source;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'type': type,
    'stationRefs': stationRefs,
    'source': source,
  };

  factory AssessmentNextStep.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString();
    final desc = (json['description'] ?? '').toString();
    final type = json['type']?.toString();
    final rawStations = json['stationRefs'];
    final stations = <String>[];
    if (rawStations is List) {
      for (final s in rawStations) {
        if (s is String && RegExp(r'^B\d+-S\d+$').hasMatch(s)) stations.add(s);
      }
    }

    final icon = _resolveStepIcon(type, title);
    return AssessmentNextStep(
      icon: icon,
      title: title,
      description: desc,
      type: type,
      stationRefs: stations,
      source: json['source'] == 'saved_findings' ? 'saved_findings' : 'ai',
    );
  }
}

IconData _resolveStepIcon(String? type, String title) {
  final titleText = title.toLowerCase();
  if (titleText.contains('larva')) return Icons.pest_control_outlined;
  if (titleText.contains('egg')) return Icons.egg_outlined;
  if (titleText.contains('frass')) return Icons.scatter_plot_outlined;
  final t = (type ?? title).toLowerCase();
  if (t == 'safety_review') return Icons.shield_outlined;
  if (t == 'review_evidence') return Icons.image_search_outlined;
  if (t == 'expert_review') return Icons.rate_review_outlined;
  if (t == 'protocol_guidance') return Icons.checklist_outlined;
  if (t.contains('egg')) return Icons.egg_outlined;
  if (t.contains('larva') || t.contains('pest')) {
    return Icons.pest_control_outlined;
  }
  if (t.contains('revisit') ||
      t.contains('station') ||
      t.contains('location')) {
    return Icons.location_on_outlined;
  }
  if (t.contains('surround') || t.contains('search') || t.contains('inspect')) {
    return Icons.search_rounded;
  }
  if (t.contains('extension') ||
      t.contains('mao') ||
      t.contains('technician') ||
      t.contains('consult')) {
    return Icons.groups_outlined;
  }
  return Icons.bar_chart_rounded;
}

List<AssessmentNextStep> _buildDeterministicNextSteps(
  AssessmentSafeFacts safeFacts,
) {
  if (safeFacts.screeningMode && safeFacts.currentContext.isNotEmpty) {
    return recommendedAssessmentChecks(
          safeFacts.currentContext,
          entryBlocked: safeFacts.fieldEntryBlocked,
          recordIssues: safeFacts.outstandingIssueCount,
        )
        .map(
          (step) => AssessmentNextStep(
            icon: _resolveStepIcon(step.type, step.title),
            title: step.title,
            description: step.description,
            type: step.type,
            stationRefs: step.references,
          ),
        )
        .toList();
  }
  final list = <AssessmentNextStep>[];

  if (safeFacts.fieldEntryBlocked) {
    return [
      const AssessmentNextStep(
        icon: Icons.warning_amber_rounded,
        type: 'safety_review',
        title: 'Confirm field-entry safety first',
        description:
            'Do not enter the field until the reported re-entry restriction and other entry requirements have been verified.',
      ),
      const AssessmentNextStep(
        icon: Icons.groups_outlined,
        type: 'extension_consultation',
        title: 'Share the saved record for advice',
        description:
            'An agronomist can review the saved findings and photos without a new field visit.',
      ),
    ];
  }

  if (safeFacts.outstandingIssueCount > 0 || safeFacts.notAssessableCount > 0) {
    list.add(
      const AssessmentNextStep(
        icon: Icons.fact_check_outlined,
        type: 'review_evidence',
        title: 'Review incomplete sample evidence',
        description:
            'Check the unscreened observations and saved record issues before treating this sample as complete evidence.',
      ),
    );
  }

  if (safeFacts.hasAnyEvidence &&
      safeFacts.highestEvidenceStations.isNotEmpty) {
    list.add(
      AssessmentNextStep(
        icon: Icons.location_on_outlined,
        type: safeFacts.screeningMode ? 'review_evidence' : 'station_revisit',
        stationRefs: safeFacts.highestEvidenceStations,
        title: safeFacts.screeningMode
            ? 'Review flagged plant evidence'
            : 'Revisit affected stations',
        description: safeFacts.screeningMode
            ? 'Open the saved photos and model damage-screening findings for the flagged plant before deciding what needs field confirmation.'
            : 'Return to the station locations with the highest recorded evidence count and compare them with the surrounding sampled area.',
      ),
    );
  }

  if (safeFacts.hasAnyEvidence) {
    list.add(
      AssessmentNextStep(
        icon: Icons.search_rounded,
        type: 'surrounding_inspection',
        title: 'Inspect surrounding plants',
        description: safeFacts.screeningMode
            ? 'Check neighboring maize plants to confirm whether the model-suggested damage or signs are present.'
            : 'Check neighboring maize plants for fresh feeding signs, frass, larvae, or eggs and record only what is directly observed.',
      ),
    );
  }

  if (safeFacts.hasEggs) {
    list.add(
      const AssessmentNextStep(
        icon: Icons.egg_outlined,
        type: 'egg_followup',
        title: 'Recheck egg-positive locations',
        description:
            'Revisit the locations where eggs were recorded and document any change during the next protocol-guided assessment.',
      ),
    );
  }

  if (safeFacts.hasLarvae) {
    list.add(
      const AssessmentNextStep(
        icon: Icons.pest_control_outlined,
        type: 'larval_followup',
        title: 'Review larval-positive observations',
        description:
            'Pay attention to the recorded larval locations and compare nearby plants for continuing feeding evidence.',
      ),
    );
  }

  list.add(
    const AssessmentNextStep(
      icon: Icons.bar_chart_rounded,
      type: 'field_monitoring',
      title: 'Continue protocol-based monitoring',
      description:
          'Repeat scouting according to the applicable Cropwise field protocol and compare the next completed assessment with this saved record.',
    ),
  );

  if (safeFacts.hasAnyEvidence) {
    list.add(
      const AssessmentNextStep(
        icon: Icons.groups_outlined,
        type: 'extension_consultation',
        title: 'Use local agricultural support when needed',
        description:
            'Share the completed assessment with the appropriate local agriculture office when follow-up support or management decisions are needed.',
      ),
    );
  }

  return list;
}

String _buildDeterministicInterpretation(
  AssessmentSafeFacts safeFacts, {
  bool filipino = false,
}) {
  if (safeFacts.screeningMode && safeFacts.currentContext.isNotEmpty) {
    final expert =
        safeFacts.currentContext['finalized_expert_findings'] as Map?;
    final infestation = safeFacts.currentContext['sampled_infestation'] as Map?;
    final damage = safeFacts.currentContext['damage_screen'] as Map?;
    final mean = expert?['mean_davis_score'];
    final screened = damage?['eligible_count'] as num? ?? 0;
    final buffer = StringBuffer();
    if (mean is num) {
      buffer.write(
        filipino
            ? 'DA severity classification: ${AppWords(AppLanguage.filipino).translate(daSeverityClassification(mean))}. Mean Davis severity: ${mean.toStringAsFixed(1)}/9 sa ${expert!['scored_plants']} na-rate na halaman. '
            : 'DA severity classification: ${daSeverityClassification(mean)}. Finalized mean Davis severity is ${mean.toStringAsFixed(1)}/9 across ${expert!['scored_plants']} scored plants. ',
      );
    }
    if (infestation?['percent'] is num) {
      final rate = (infestation!['percent'] as num).toStringAsFixed(1);
      buffer.write(
        '${expert == null ? 'Sampled infestation' : 'Current sampled infestation'}: $rate% (${infestation['infested_count']} / ${infestation['denominator'] ?? infestation['eligible_count']} plants). ',
      );
    } else {
      buffer.write(
        filipino
            ? 'Hindi available ang sampled infestation. '
            : 'Sampled infestation is unavailable. ',
      );
    }
    buffer.write(
      screened == 0
          ? (filipino
                ? 'Hindi available ang damage screening.'
                : 'Damage screening is unavailable.')
          : '${damage!['damaged_count']} of $screened plants screened for damage (${(damage['percent'] as num).toStringAsFixed(1)}%).',
    );
    return buffer.toString();
  }
  if (safeFacts.screeningMode) {
    if (filipino) {
      return safeFacts.primaryDenominator == 0
          ? 'Hindi available ang damage screening para sa sample na ito.'
          : '${_formatMetricCount(safeFacts.primaryNumerator)} sa ${_formatMetricCount(safeFacts.primaryDenominator)} nasuring halaman ang may pinsalang nakita ng modelo (${safeFacts.primaryMetricValue.toStringAsFixed(1)}%).';
    }
    return safeFacts.primaryDenominator == 0
        ? 'Damage screening is not available for this sample.'
        : '${_formatMetricCount(safeFacts.primaryNumerator)} of ${_formatMetricCount(safeFacts.primaryDenominator)} sampled plants screened positive for damage (${safeFacts.primaryMetricValue.toStringAsFixed(1)}%).';
  }

  final words = AppWords(filipino ? AppLanguage.filipino : AppLanguage.english);
  if (filipino) {
    final metricName = words.translate(safeFacts.primaryMetricTitle);
    final denominator = words.translate(safeFacts.primaryDenominatorLabel);
    final metricText = safeFacts.primaryDenominator <= 0
        ? '$metricName ay hindi available dahil zero ang naka-save na denominator.'
        : '$metricName: ${_formatPrimaryMetricValue(safeFacts.primaryUnit, safeFacts.primaryMetricValue)} '
              '(${_formatMetricCount(safeFacts.primaryNumerator)} sa '
              '${_formatMetricCount(safeFacts.primaryDenominator)} $denominator).';
    if (!safeFacts.hasAnyEvidence) {
      return 'Walang naitalang pinsalang kaugnay ng FAW, dumi ng uod, uod, o itlog sa mga nasampolang obserbasyon para sa pagsusuring ito. '
          '$metricText Inilalarawan lamang nito ang natapos na sample at hindi nito pinatutunayan ang kalagayan ng buong bukid.';
    }
    final categories = <String>[
      if (safeFacts.hasDamage) 'pinsala',
      if (safeFacts.hasFrass) 'dumi ng uod',
      if (safeFacts.hasLarvae) 'uod',
      if (safeFacts.hasEggs) 'itlog',
    ];
    final categoryText = categories.join(', ');
    final buffer = StringBuffer(
      'Kabilang sa naitalang ebidensiyang kaugnay ng FAW ang $categoryText sa '
      '${safeFacts.affectedStationCount} sa ${safeFacts.stationStats.length} nasampolang istasyon. '
      '$metricText',
    );
    if (safeFacts.highestEvidenceStations.length == 1 &&
        safeFacts.affectedStationCount > 1) {
      buffer.write(
        ' Pinakamarami ang naitalang uri ng ebidensiya sa ${safeFacts.highestEvidenceStations.first}.',
      );
    } else if (safeFacts.highestEvidenceStations.length > 1 &&
        safeFacts.highestEvidenceStations.length <
            safeFacts.affectedStationCount) {
      buffer.write(
        ' Magkapantay ang pinakamataas na bilang ng naitalang ebidensiya sa ${safeFacts.highestEvidenceStations.join(', ')}.',
      );
    }
    return buffer.toString();
  }
  final metricText = safeFacts.primaryDenominator <= 0
      ? '${safeFacts.primaryMetricTitle} is unavailable because the saved denominator is zero.'
      : '${safeFacts.primaryMetricTitle}: '
            '${_formatPrimaryMetricValue(safeFacts.primaryUnit, safeFacts.primaryMetricValue)} '
            '(${_formatMetricCount(safeFacts.primaryNumerator)} of '
            '${_formatMetricCount(safeFacts.primaryDenominator)} '
            '${safeFacts.primaryDenominatorLabel}).';

  if (!safeFacts.hasAnyEvidence) {
    return 'No FAW-related damage, frass, larvae, or eggs were recorded in the sampled observations for this assessment. '
        '$metricText This statement describes the completed sample only and does not establish the condition of the entire field.';
  }

  final categories = <String>[
    if (safeFacts.hasDamage) 'damage',
    if (safeFacts.hasFrass) 'frass',
    if (safeFacts.hasLarvae) 'larvae',
    if (safeFacts.hasEggs) 'eggs',
  ];
  final categoryText = categories.length == 1
      ? categories.first
      : '${categories.sublist(0, categories.length - 1).join(', ')} and ${categories.last}';

  final buffer = StringBuffer(
    'Recorded FAW-related evidence included $categoryText across '
    '${safeFacts.affectedStationCount} of ${safeFacts.stationStats.length} sampled stations. '
    '$metricText',
  );

  if (safeFacts.highestEvidenceStations.length == 1 &&
      safeFacts.affectedStationCount > 1) {
    buffer.write(
      ' ${safeFacts.highestEvidenceStations.first} had the highest count of recorded evidence categories in this assessment.',
    );
  } else if (safeFacts.highestEvidenceStations.length > 1 &&
      safeFacts.highestEvidenceStations.length <
          safeFacts.affectedStationCount) {
    buffer.write(
      ' The highest recorded evidence count was shared by ${safeFacts.highestEvidenceStations.join(', ')}.',
    );
  }

  return buffer.toString();
}

bool _containsProhibitedChemicalTerms(String text) {
  final lower = text.toLowerCase();
  const prohibited = [
    'chemical spray',
    'chlorantraniliprole',
    'cypermethrin',
    'lambda-cyhalothrin',
    'emamectin',
    'methomyl',
    'carbaryl',
    'malathion',
    'dosage',
    'spray schedule',
    'application rate',
    'chemical treatment',
    'kemikal na spray',
    'dosis',
    'iskedyul ng pag-spray',
    'i-spray',
  ];
  return prohibited.any(lower.contains);
}

const _allowedRecommendationTypes = <String>{
  'review_evidence',
  'safety_review',
  'station_revisit',
  'monitoring',
  'surrounding_inspection',
  'egg_followup',
  'larval_followup',
  'field_monitoring',
  'protocol_guidance',
  'extension_consultation',
  'report_assessment',
  'expert_review',
};

bool _containsUnsupportedAgronomicClaim(String text) {
  final lower = text.toLowerCase();
  const unsupported = [
    'action threshold',
    'economic threshold',
    'regional threshold',
    'below threshold',
    'above threshold',
    'field is healthy',
    'field is clean',
    'clean and in good health',
    'manageable condition',
    'economic action',
    'hangganan ng aksiyon',
    'malusog ang buong bukid',
    'malinis ang buong bukid',
  ];
  return unsupported.any(lower.contains);
}

bool _containsUnsupportedRecommendationTiming(String text) {
  final lower = text.toLowerCase();
  const timingTerms = [
    'hour',
    'hours',
    'day',
    'days',
    'week',
    'weeks',
    'weekly',
    'monthly',
    '48–72',
    '3–5',
    '7–14',
    'oras',
    'araw',
    'linggo',
    'buwan',
  ];
  return timingTerms.any(
    (term) =>
        RegExp('(^|[^a-z])${RegExp.escape(term)}([^a-z]|\$)').hasMatch(lower),
  );
}

bool _containsUnsupportedInterpretationNumber(
  String text,
  AssessmentSafeFacts facts,
) {
  var comparableText = text.replaceAll(facts.formattedGrowthStage, '');
  for (final stationRef in facts.validStationRefs) {
    comparableText = comparableText.replaceAll(stationRef, '');
  }
  Iterable<double> numbers(Object? value) sync* {
    if (value is num && value.isFinite) {
      yield value.toDouble();
    }
    if (value is List) {
      for (final item in value) {
        yield* numbers(item);
      }
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (!const [
          'created_at',
          'finalized_at',
          'assessed_at',
          'reviewer_name',
          'interpretation',
          'measurement_basis',
        ].contains(entry.key)) {
          yield* numbers(entry.value);
        }
      }
    }
  }

  final allowed = <double>{
    0,
    9,
    ...numbers(facts.currentContext['sampling']),
    ...numbers(facts.currentContext['blocks']),
    ...numbers(facts.currentContext['plants']),
    ...numbers(facts.currentContext['damage_screen']),
    ...numbers(facts.currentContext['sampled_infestation']),
    ...numbers(facts.currentContext['finalized_expert_findings']),
    facts.primaryMetricValue,
    facts.primaryNumerator,
    facts.primaryDenominator,
    facts.damageCount.toDouble(),
    facts.frassCount.toDouble(),
    facts.larvaCount.toDouble(),
    facts.eggCount.toDouble(),
    facts.stationStats.length.toDouble(),
    facts.affectedStationCount.toDouble(),
    ...facts.stationStats.expand<double>(
      (station) => <double>[
        station.stationNumber.toDouble(),
        station.infestationPercent,
        station.damageCount.toDouble(),
        station.frassCount.toDouble(),
        station.larvaCount.toDouble(),
        station.eggCount.toDouble(),
      ],
    ),
  };

  for (final match in RegExp(r'\d+(?:\.\d+)?').allMatches(comparableText)) {
    final parsed = double.tryParse(match.group(0)!);
    if (parsed == null) continue;
    final supported = allowed.any((value) => (value - parsed).abs() < 0.051);
    if (!supported) return true;
  }
  return false;
}

Map<String, dynamic>? _validateAndSanitizeAiJson(
  String responseText,
  AssessmentSafeFacts safeFacts, {
  void Function(String reason)? onRejected,
}) {
  try {
    var raw = responseText.trim();
    if (raw.startsWith('```json')) {
      raw = raw.substring(7);
    } else if (raw.startsWith('```')) {
      raw = raw.substring(3);
    }
    if (raw.endsWith('```')) {
      raw = raw.substring(0, raw.length - 3);
    }
    raw = raw.trim();

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      onRejected?.call('The AI returned an unexpected format.');
      return null;
    }

    String? interpretation = (decoded['interpretation'] ?? '')
        .toString()
        .trim();
    if (interpretation.isEmpty) interpretation = null;

    final invalidInterpretation =
        interpretation != null &&
        (_containsProhibitedChemicalTerms(interpretation) ||
            _containsUnsupportedAgronomicClaim(interpretation) ||
            _containsUnsupportedInterpretationNumber(
              interpretation,
              safeFacts,
            ) ||
            (safeFacts.screeningMode &&
                AdvisorAssessmentContract.finalized(
                      Map<String, dynamic>.from(
                        safeFacts.currentContext['expert_review'] as Map? ??
                            const {},
                      ),
                    ) ==
                    null &&
                RegExp(
                  r'confirmed (?:faw |current )?infestation|current infestation rate',
                  caseSensitive: false,
                ).hasMatch(interpretation)));
    if (invalidInterpretation) interpretation = null;

    final rawRecs = decoded['recommendations'];
    final validSteps = <AssessmentNextStep>[];

    if (rawRecs is List) {
      for (final item in rawRecs) {
        if (item is! Map) continue;
        final recommendation = Map<String, dynamic>.from(item);

        final title = (recommendation['title'] ?? '').toString().trim();
        final desc = (recommendation['description'] ?? '').toString().trim();
        final type = (recommendation['type'] ?? '').toString().trim();
        if (title.isEmpty ||
            desc.isEmpty ||
            !_allowedRecommendationTypes.contains(type)) {
          continue;
        }

        final combined = '$title $desc';
        if (_containsProhibitedChemicalTerms(combined) ||
            _containsUnsupportedAgronomicClaim(combined) ||
            _containsUnsupportedRecommendationTiming(combined) ||
            _containsUnsupportedInterpretationNumber(combined, safeFacts)) {
          continue;
        }

        if (type == 'egg_followup' && !safeFacts.hasEggs) continue;
        if (type == 'larval_followup' && !safeFacts.hasLarvae) continue;
        if (safeFacts.fieldEntryBlocked &&
            (!const {
                  'safety_review',
                  'review_evidence',
                  'expert_review',
                  'extension_consultation',
                  'report_assessment',
                }.contains(type) ||
                const {
                  'station_revisit',
                  'surrounding_inspection',
                  'egg_followup',
                  'larval_followup',
                  'field_monitoring',
                }.contains(type) ||
                (!_allowedRecommendationTypes.contains(type) &&
                    RegExp(
                      r'\b(enter|revisit|visit|inspect|scout)\b',
                      caseSensitive: false,
                    ).hasMatch(combined)))) {
          continue;
        }
        if (!safeFacts.hasAnyEvidence &&
            const {
              'station_revisit',
              'surrounding_inspection',
              'egg_followup',
              'larval_followup',
            }.contains(type)) {
          continue;
        }

        final step = AssessmentNextStep.fromJson({
          ...recommendation,
          'source': 'ai',
        });
        if (step.stationRefs.any(
          (stationRef) => !safeFacts.validStationRefs.contains(stationRef),
        )) {
          continue;
        }
        validSteps.add(step);
      }
    }

    if (validSteps.isNotEmpty && safeFacts.screeningMode) {
      final checks = _buildDeterministicNextSteps(safeFacts);
      final substantive = validSteps
          .where(
            (step) =>
                !const {'monitoring', 'field_monitoring'}.contains(step.type),
          )
          .toList();
      if (substantive.isEmpty) {
        onRejected?.call('The AI returned only generic monitoring advice.');
        return null;
      }
      // Preserve essential follow-ups when the AI omitted them. Added checks
      // carry a visible Saved findings label; they are not presented as AI.
      for (final check in checks) {
        final text = validSteps
            .map((s) => '${s.title} ${s.description}')
            .join(' ')
            .toLowerCase();
        final covered = check.title.contains('potential larvae')
            ? text.contains('larv')
            : check.title.contains('potential eggs')
            ? text.contains('egg')
            : check.title.contains('potential frass')
            ? text.contains('frass')
            : check.title == 'Check missing plant photos'
            ? RegExp(
                r'missing|no (?:available |saved )?photos|kulang',
              ).hasMatch(text)
            : check.title == 'Check the plants rated Davis 7–9'
            ? RegExp(r'7.{0,8}9|high.{0,10}rat|sever').hasMatch(text)
            : check.title == 'Compare screening with the expert review'
            ? RegExp(r'compar|old damage|freshness|pagkakaiba').hasMatch(text)
            : check.title == 'Check unavailable plant evidence' ||
                  check.title == 'Check missing sign detection'
            ? RegExp(
                r'unavailable|unclear|missing|blur|malabo|kulang',
              ).hasMatch(text)
            : check.title == 'Review the damage flagged by the app'
            ? validSteps.any(
                (s) => s.type == 'review_evidence' && s.stationRefs.isNotEmpty,
              )
            : validSteps.any((s) => s.type == check.type);
        if (!covered) {
          if (check.type == 'safety_review') {
            validSteps.insert(0, check);
          } else {
            validSteps.add(check);
          }
        }
      }
    }

    if (validSteps.isEmpty) {
      onRejected?.call(
        rawRecs is List && rawRecs.isNotEmpty
            ? 'The AI next steps did not pass the saved-facts and safety checks.'
            : 'The AI did not return any next steps.',
      );
      return null;
    }

    return {
      'interpretation': interpretation,
      'recommendations': validSteps.map((s) => s.toJson()).toList(),
      'isOffline': false,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  } catch (_) {
    onRejected?.call('The AI returned unreadable JSON.');
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCROLLABLE BODY
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsScrollableBody extends StatelessWidget {
  const _ResultsScrollableBody({
    required this.detail,
    required this.stats,
    required this.isTestMode,
    required this.storage,
    required this.selectedTabIndex,
    required this.onTabChanged,
    required this.scrollController,
    required this.aiInterpretation,
    required this.aiRecommendations,
    required this.isLoadingAi,
    required this.isOfflineAi,
    required this.isCachedAi,
    required this.aiAvailabilityMessage,
    required this.aiGeneratedAt,
    required this.shareAssessmentWithAi,
    required this.onShareAssessmentWithAiChanged,
    required this.reportStatus,
    required this.reportError,
    required this.assistantPreview,
    required this.onOpenAssistant,
    required this.onOpenRecommendedStep,
    required this.onRegenerateAi,
    required this.onSendReport,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final bool isTestMode;
  final EvidenceStorageService storage;
  final int selectedTabIndex;
  final ValueChanged<int> onTabChanged;
  final ScrollController scrollController;
  final String? aiInterpretation;
  final List<AssessmentNextStep>? aiRecommendations;
  final bool isLoadingAi;
  final bool isOfflineAi;
  final bool isCachedAi;
  final String? aiAvailabilityMessage;
  final DateTime? aiGeneratedAt;
  final bool shareAssessmentWithAi;
  final ValueChanged<bool> onShareAssessmentWithAiChanged;
  final int reportStatus;
  final String? reportError;
  final AssessmentAssistantPreview? assistantPreview;
  final VoidCallback onOpenAssistant;
  final ValueChanged<AssessmentNextStep> onOpenRecommendedStep;
  final VoidCallback onRegenerateAi;
  final VoidCallback onSendReport;

  @override
  Widget build(BuildContext context) {
    final assessment = detail.assessment;
    final completed = assessment.status == DatabaseCodes.completed;
    final isDa = ScoutingSamplingProtocol.isDa(assessment.protocolVersion);

    final items = <Widget>[
      // Record context uses the same card width and spacing as Assess.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: isDa
            ? _RecommendationContext(detail: detail)
            : _AerialResultsHeader(
                detail: detail,
                isTestMode: isTestMode,
                completed: completed,
              ),
      ),

      const SizedBox(height: 14),

      if (selectedTabIndex == 0 && isDa) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DaAssessmentResultsSection(
            detail: detail,
            storage: storage,
            reportStatus: reportStatus,
            onSubmit: onSendReport,
            onRecommendations: () => onTabChanged(1),
          ),
        ),
      ] else if (selectedTabIndex == 0) ...[
        // STATIONS TAB CONTENT:
        if (completed && !detail.readiness.isValid)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _VerificationNotice(
              key: Key('results_verification_warning'),
            ),
          ),

        // Overall Infestation Hero Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _OverallInfestationHeroCard(
            detail: detail,
            stats: stats,
            completed: completed,
          ),
        ),

        const SizedBox(height: 14),

        if (!stats.screeningMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SamplingQualityCard(summary: detail.resultSummary),
          ),
          const SizedBox(height: 14),
        ],
        if (!stats.screeningMode || stats.highlightedPlants > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EvidenceBreakdownRow(stats: stats),
          ),
          const SizedBox(height: 14),
        ],
        if (!stats.screeningMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EvidenceTypeBarChart(stats: stats),
          ),
          const SizedBox(height: 14),
        ],

        // Per-Station Results Section with full station cards!
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PerStationResultsSection(
            detail: detail,
            stats: stats,
            storage: storage,
          ),
        ),

        // R3-R6 boundary callout
        if (assessment.growthStage == 'r3_r6')
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _InterpretationBoundary(
              key: Key('results_interpretation_boundary'),
              stage: 'r3_r6',
            ),
          ),

        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ReportAssessmentCard(
            detail: detail,
            reportStatus: reportStatus,
            reportError: reportError,
            onSendReport: onSendReport,
          ),
        ),

        const SizedBox(height: 18),

        const SizedBox(height: 28),
      ] else if (isDa) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _FieldInterpretationCard(
            detail: detail,
            stats: stats,
            aiInterpretation: aiInterpretation,
            isLoadingAi: isLoadingAi,
            isOfflineAi: isOfflineAi,
            isCachedAi: isCachedAi,
            aiAvailabilityMessage: aiAvailabilityMessage,
            aiGeneratedAt: aiGeneratedAt,
            shareAssessmentWithAi: shareAssessmentWithAi,
            onShareAssessmentWithAiChanged: onShareAssessmentWithAiChanged,
            onRegenerate: onRegenerateAi,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _RecommendedNextStepsCard(
            detail: detail,
            stats: stats,
            steps: aiRecommendations,
            isOfflineAi: isOfflineAi,
            isCachedAi: isCachedAi,
            isLoadingAi: isLoadingAi,
            availabilityMessage: aiAvailabilityMessage,
            onRegenerate: onRegenerateAi,
            onOpenStep: onOpenRecommendedStep,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ResultSurface(
            padding: 0,
            child: Column(
              children: [
                const _RecommendationResourceRow(
                  key: Key('assessment_guidelines_link'),
                  icon: Icons.menu_book_outlined,
                  title: 'Guidelines',
                  subtitle: 'Need more information? Browse the guides.',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1),
                ),
                _RecommendationResourceRow(
                  key: const Key('ask_wormwise_assessment_card'),
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Ask Cropwise',
                  subtitle: assistantPreview?.hasConversation == true
                      ? 'Continue your assessment chat'
                      : 'Ask about these results',
                  onTap: onOpenAssistant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 28),
      ] else ...[
        // RECOMMENDATIONS TAB CONTENT:
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PrimaryNextActionCard(
            facts: AssessmentSafeFacts.fromDetailAndStats(detail, stats),
            steps: aiRecommendations,
            isOfflineAi: isOfflineAi,
            onOpenStep: onOpenRecommendedStep,
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _FieldInterpretationCard(
            detail: detail,
            stats: stats,
            aiInterpretation: aiInterpretation,
            isLoadingAi: isLoadingAi,
            isOfflineAi: isOfflineAi,
            isCachedAi: isCachedAi,
            aiAvailabilityMessage: aiAvailabilityMessage,
            aiGeneratedAt: aiGeneratedAt,
            shareAssessmentWithAi: shareAssessmentWithAi,
            onShareAssessmentWithAiChanged: onShareAssessmentWithAiChanged,
            onRegenerate: onRegenerateAi,
          ),
        ),

        const SizedBox(height: 14),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _AskWormWiseLinkCard(
            preview: assistantPreview,
            onTap: onOpenAssistant,
          ),
        ),

        const SizedBox(height: 14),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _RecommendedNextStepsCard(
            detail: detail,
            stats: stats,
            steps: aiRecommendations,
            isOfflineAi: isOfflineAi,
            isCachedAi: isCachedAi,
            isLoadingAi: isLoadingAi,
            availabilityMessage: aiAvailabilityMessage,
            onRegenerate: onRegenerateAi,
            onOpenStep: onOpenRecommendedStep,
          ),
        ),

        const SizedBox(height: 14),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _ResultsGuidelinesLink(),
        ),

        const SizedBox(height: 14),

        const SizedBox(height: 28),
      ],
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.workflowMaxWidth),
        child: CustomScrollView(
          key: const PageStorageKey('assessment-results-scroll'),
          controller: scrollController,
          // ignore: deprecated_member_use
          cacheExtent: 1500,
          slivers: [
            SliverToBoxAdapter(child: items.first),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ResultsTabHeaderDelegate(
                selectedIndex: selectedTabIndex,
                onTabChanged: onTabChanged,
                firstTabLabel: isDa ? 'Results' : 'Stations',
                height: MediaQuery.textScalerOf(context).scale(14) > 20
                    ? 84
                    : 62,
              ),
            ),
            SliverList.builder(
              itemCount: items.length - 1,
              itemBuilder: (context, index) => items[index + 1],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 104)),
          ],
        ),
      ),
    );
  }
}

class _RecommendationContext extends StatelessWidget {
  const _RecommendationContext({required this.detail});
  final AssessmentHistoryDetail detail;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2E5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.agriculture_outlined,
          color: AppColors.primary,
          size: 22,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.workspace.field.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('MMM d, yyyy').format(
                (detail.assessment.completedAt ??
                        detail.assessment.startedAt ??
                        detail.assessment.createdAt)
                    .toLocal(),
              ),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RecommendationResourceRow extends StatelessWidget {
  const _RecommendationResourceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap:
        onTap ??
        () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AdvisorOfflineGuidesScreen()),
        ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                AppText(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ],
      ),
    ),
  );
}

class _ResultsTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ResultsTabHeaderDelegate({
    required this.selectedIndex,
    required this.onTabChanged,
    this.firstTabLabel = 'Stations',
    this.height = 62,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final String firstTabLabel;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: AppColors.background,
      elevation: overlapsContent ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: _SegmentedTabBar(
          selectedIndex: selectedIndex,
          onTabChanged: onTabChanged,
          firstTabLabel: firstTabLabel,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ResultsTabHeaderDelegate oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.firstTabLabel != firstTabLabel ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.onTabChanged != onTabChanged;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. ASSESSMENT CONTEXT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AerialResultsHeader extends StatelessWidget {
  const _AerialResultsHeader({
    required this.detail,
    required this.isTestMode,
    required this.completed,
  });

  final AssessmentHistoryDetail detail;
  final bool isTestMode;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final rawName = detail.workspace.field.name;
    final fieldName = isTestMode
        ? rawName
        : rawName.replaceAll(RegExp(r'\[TEST DATA\]\s*'), '').trim();
    final barangay = detail.workspace.field.barangay;
    final locationText = (barangay != null && barangay.trim().isNotEmpty)
        ? barangay.trim()
        : 'Field assessment';

    final dateStr = DateFormat(
      'MMM d, yyyy · h:mm a',
    ).format(detail.assessment.createdAt.toLocal());
    final stageLabel = _formatGrowthStage(detail.assessment.growthStage);
    if (ScoutingSamplingProtocol.isDa(detail.assessment.protocolVersion)) {
      return Container(
        key: const Key('assessment_results_hero'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4E9DF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/assessment_results_field.png',
                width: 64,
                height: 76,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fieldName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(detail.workspace.boundary?.areaHectares ?? 0).toStringAsFixed(2)} ha · $stageLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (barangay?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      barangay!.trim(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        DateFormat(
                          'MMM d, yyyy',
                        ).format(detail.assessment.createdAt.toLocal()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: AppText(
                          completed
                              ? 'Completed'
                              : assessmentStatusLabel(detail.assessment.status),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final status = detail.assessment.status;
    final String statusLabel;
    if (status == DatabaseCodes.completed || completed) {
      statusLabel = 'Completed';
    } else if (status == DatabaseCodes.inProgress) {
      statusLabel = 'In Progress';
    } else {
      statusLabel = status
          .replaceAll('_', ' ')
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
    }
    return ClipRRect(
      key: const Key('assessment_results_hero'),
      borderRadius: AppRadii.cardBorder,
      child: Stack(
        children: [
          // Match the field imagery used by the Assess tab without loading tiles.
          Positioned.fill(
            child: Image.asset(
              'assets/images/assessment_results_field.png',
              fit: BoxFit.cover,
            ),
          ),

          // Controlled Dark Gradient Scrim for crisp outdoor text readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.48, 1.0],
                  colors: [
                    const Color(0xFF102C22).withValues(alpha: 0.68),
                    const Color(0xFF102C22).withValues(alpha: 0.51),
                    const Color(0xFF102C22).withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),

          // Hero Content Layer
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fieldName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 2),
                  child: Text(
                    locationText,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    _CompactHeroChip(
                      icon: completed
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      label: statusLabel,
                      iconColor: Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.image_search_outlined,
                      color: Colors.white,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stageLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHeroChip extends StatelessWidget {
  const _CompactHeroChip({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D52),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: iconColor ?? Colors.white.withValues(alpha: 0.90),
            size: 12,
          ),
          const SizedBox(width: 4),
          AppText(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.15,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. SEGMENTED TAB BAR (STATIONS & RECOMMENDATIONS)
// ─────────────────────────────────────────────────────────────────────────────

class _SegmentedTabBar extends StatelessWidget {
  const _SegmentedTabBar({
    required this.selectedIndex,
    required this.onTabChanged,
    this.firstTabLabel = 'Stations',
  });

  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final String firstTabLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('results_pinned_tabs'),
      height: MediaQuery.textScalerOf(context).scale(14) > 20 ? 68 : 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF4EF),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              title: firstTabLabel,
              isSelected: selectedIndex == 0,
              onTap: () => onTabChanged(0),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _TabButton(
              title: 'Recommendations',
              isSelected: selectedIndex == 1,
              onTap: () => onTabChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1F563F) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF203A2E),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. TAB 1: OVERALL INFESTATION HERO CARD
// ─────────────────────────────────────────────────────────────────────────────

class AssessmentResultDetailsScreen extends StatelessWidget {
  const AssessmentResultDetailsScreen({
    super.key,
    required this.detail,
    required this.stats,
    required this.storage,
    this.initialTab = 0,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final EvidenceStorageService storage;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return AssessmentResultsScreen(
      assessmentId: detail.assessment.id,
      initialTab: initialTab,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. TAB 1: PER-STATION RESULTS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _PerStationResultsSection extends StatelessWidget {
  const _PerStationResultsSection({
    required this.detail,
    required this.stats,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    final stationCount = stats.stationStats.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFF2E7D32), size: 20),
            const SizedBox(width: 6),
            const Expanded(
              child: AppText(
                'Sampling stations',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AppText(
              '$stationCount',
              style: const TextStyle(
                color: Color(0xFF708077),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final st in stats.stationStats) ...[
          _PerStationDetailedCard(
            detail: detail,
            stationStats: st,
            storage: storage,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PerStationDetailedCard extends StatelessWidget {
  const _PerStationDetailedCard({
    required this.detail,
    required this.stationStats,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final StationEvidenceStats stationStats;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    if (stationStats.screeningMode && stationStats.highlightedPlants == 0) {
      return _ScreeningStationTile(
        station: stationStats,
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => StationDetailsScreen(
              detail: detail,
              station: stationStats.snapshot,
              storage: storage,
            ),
          ),
        ),
      );
    }
    final stNum = stationStats.stationNumber;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => StationDetailsScreen(
                detail: detail,
                station: stationStats.snapshot,
                storage: storage,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD8E7DE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F4EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF1F563F),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Station $stNum',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        AppText(
                          '${stationStats.recordedCount} plant records · ${stationStats.assessableCount} assessable',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppText(
                        '${stationStats.infestationPercent.toStringAsFixed(stationStats.infestationPercent == stationStats.infestationPercent.roundToDouble() ? 0 : 1)}%',
                        style: const TextStyle(
                          color: Color(0xFF1F563F),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const AppText(
                        'sampled',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF1F563F)),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniEvidenceCounter(
                      icon: Icons.image_search_outlined,
                      color: const Color(0xFF2E7D32),
                      label: 'Damage',
                      count: stationStats.damageCount,
                    ),
                  ),
                  Expanded(
                    child: _MiniEvidenceCounter(
                      icon: Icons.blur_on_rounded,
                      color: AppColors.primaryContainer,
                      label: 'Frass',
                      count: stationStats.frassCount,
                      display:
                          stationStats.screeningMode &&
                              stationStats.highlightedPlants == 0
                          ? 'Not assessed'
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _MiniEvidenceCounter(
                      icon: Icons.bug_report_outlined,
                      color: AppColors.moderateSeverityRing,
                      label: 'Larvae',
                      count: stationStats.larvaCount,
                      display:
                          stationStats.screeningMode &&
                              stationStats.highlightedPlants == 0
                          ? 'Not assessed'
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _MiniEvidenceCounter(
                      icon: Icons.bubble_chart_outlined,
                      color: AppColors.highContrastGreen,
                      label: 'Egg masses',
                      count: stationStats.eggCount,
                      display:
                          stationStats.screeningMode &&
                              stationStats.highlightedPlants == 0
                          ? 'Not assessed'
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniEvidenceCounter extends StatelessWidget {
  const _MiniEvidenceCounter({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    this.display,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final String? display;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 2),
        AppText(
          display ?? '$count',
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. TAB 1: BOTTOM ACTION BUTTONS ([ View Map ] and [ Export ])
// ─────────────────────────────────────────────────────────────────────────────

class _PersistentResultsActionBar extends StatelessWidget {
  const _PersistentResultsActionBar({
    required this.detail,
    required this.stats,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('persistent_results_action_bar'),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: const Border(top: BorderSide(color: AppColors.cardBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: _BottomActionButtons(
              detail: detail,
              stats: stats,
              storage: storage,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomActionButtons extends StatelessWidget {
  const _BottomActionButtons({
    required this.detail,
    required this.stats,
    required this.storage,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final EvidenceStorageService storage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ScoutingSamplingProtocol.isDa(
                        detail.assessment.protocolVersion,
                      )
                      ? AssessmentMapScreen(detail: detail, storage: storage)
                      : _AssessmentInteractiveMapScreen(
                          detail: detail,
                          stats: stats,
                        ),
                ),
              );
            },
            icon: const Icon(Icons.map_outlined, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: AppText(
                'View map',
                style: TextStyle(
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.labelLarge?.fontFamily,
                ),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1B4D3E),
              side: const BorderSide(color: Color(0xFF1B4D3E), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _showExportSheet(context),
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: AppText(
                'Export',
                style: TextStyle(
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.labelLarge?.fontFamily,
                ),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1F563F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showExportSheet(BuildContext context) {
    if (ScoutingSamplingProtocol.isDa(detail.assessment.protocolVersion)) {
      showDaReportExportOptions(context, detail);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText(
                'Export assessment report',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              const AppText(
                'Save or share a PDF report for a crop expert.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const Key('export_expert_pdf_option'),
                leading: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Color(0xFF1B4D3E),
                ),
                title: const AppText(
                  'Save or Share Assessment PDF',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: const AppText(
                  'Offline report with sample counts, station findings, treatment safety, and evidence inventory.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  exportExpertPdf(
                    context,
                    detail: detail,
                    stats: stats,
                    storage: storage,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> exportExpertPdf(
    BuildContext context, {
    required AssessmentHistoryDetail detail,
    required AssessmentEvidenceStats stats,
    required EvidenceStorageService storage,
  }) async {
    if (ScoutingSamplingProtocol.isDa(detail.assessment.protocolVersion)) {
      await showDaReportExportOptions(context, detail);
      return;
    }
    var includeCoordinates = false;
    var includeMap = true;
    var includePhotos = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const AppText('Export assessment report'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppText(
                  'The PDF contains saved field findings and reported treatment safety details. Add the field map and available evidence photos for expert review. Expert severity review remains separate.',
                ),
                CheckboxListTile(
                  key: const Key('export_include_map'),
                  value: includeMap,
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Include field map and stations'),
                  subtitle: const AppText(
                    'Shows the saved outline and phone-GPS station markers without aerial imagery.',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => includeMap = value ?? false),
                ),
                CheckboxListTile(
                  key: const Key('export_include_photos'),
                  value: includePhotos,
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Include evidence photos'),
                  subtitle: const AppText(
                    'Adds available saved photos to the PDF; the file may be large.',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => includePhotos = value ?? false),
                ),
                CheckboxListTile(
                  key: const Key('export_include_coordinates'),
                  value: includeCoordinates,
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Include precise station coordinates'),
                  subtitle: const AppText(
                    'Only stations recorded with phone GPS will show coordinates.',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => includeCoordinates = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('Create PDF'),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !context.mounted) return;
    try {
      final data = AssessmentPdfData(
        primaryMetricTitle: _primaryMetricTitle(stats.primaryMetricCode),
        primaryUnit: stats.primaryUnit,
        primaryNumerator: stats.primaryNumerator,
        primaryDenominator: stats.primaryDenominator,
        primaryValue: stats.overallInfestationPercent,
        primaryDenominatorLabel: _primaryMetricDenominatorLabel(
          stats.primaryMetricCode,
          detail.assessment.growthStage,
        ),
        screeningMode: stats.screeningMode,
        stations: [
          for (final station in stats.stationStats)
            AssessmentPdfStation(
              blockNumber: station.blockSequence,
              stationNumber: station.stationNumber,
              recorded: station.recordedCount,
              assessable: station.assessableCount,
              positive: station.positiveCount,
              damage: station.damageCount,
              frass: station.frassCount,
              larvae: station.larvaCount,
              eggs: station.eggCount,
              photoCount: station.photoCount,
              locationSource: station.snapshot.station?.locationSource,
              latitude: station.snapshot.station?.latitude,
              longitude: station.snapshot.station?.longitude,
            ),
        ],
      );
      final bytes = await const AssessmentPdfExportService().build(
        language: AppWords.of(context).language,
        detail: detail,
        data: data,
        includeCoordinates: includeCoordinates,
        includeMap: includeMap,
        includePhotos: includePhotos,
        evidenceStorage: storage,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'wormwise-assessment-${detail.assessment.id.length > 8 ? detail.assessment.id.substring(0, 8) : detail.assessment.id}.pdf',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText(
            'Could not create the PDF report. Please try again.',
          ),
        ),
      );
    }
  }
}

class _FieldInterpretationCard extends StatelessWidget {
  const _FieldInterpretationCard({
    required this.detail,
    required this.stats,
    required this.aiInterpretation,
    required this.isLoadingAi,
    required this.isOfflineAi,
    required this.isCachedAi,
    required this.aiAvailabilityMessage,
    required this.aiGeneratedAt,
    required this.shareAssessmentWithAi,
    required this.onShareAssessmentWithAiChanged,
    required this.onRegenerate,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final String? aiInterpretation;
  final bool isLoadingAi;
  final bool isOfflineAi;
  final bool isCachedAi;
  final String? aiAvailabilityMessage;
  final DateTime? aiGeneratedAt;
  final bool shareAssessmentWithAi;
  final ValueChanged<bool> onShareAssessmentWithAiChanged;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final facts = AssessmentSafeFacts.fromDetailAndStats(
      detail,
      stats,
      expertReview:
          context.watch<ExpertReviewService?>()?.assessmentReviewFacts(
            detail.assessment.id,
          ) ??
          const {},
    );
    final interpretation = readableAssessmentReferences(
      (isOfflineAi && AppWords.of(context).language == AppLanguage.filipino)
          ? _buildDeterministicInterpretation(facts, filipino: true)
          : aiInterpretation ?? _buildDeterministicInterpretation(facts),
    );
    final isGemini = !isOfflineAi && aiInterpretation != null;

    return AssessmentInterpretationPanel(
      facts: facts.currentContext,
      interpretation: interpretation,
      sourceLabel:
          '${AppWords.of(context).translate(isGemini ? (isCachedAi ? 'Saved AI advice' : 'New AI advice') : 'Guidance from saved findings')}${aiGeneratedAt == null ? '' : ' · ${DateFormat('MMM d, h:mm a').format(aiGeneratedAt!.toLocal())}'}',
      loading: isLoadingAi,
      availabilityMessage: aiAvailabilityMessage,
      aiEnabled: shareAssessmentWithAi,
      onAiChanged: onShareAssessmentWithAiChanged,
      onRegenerate: onRegenerate,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. TAB 2: RECOMMENDED NEXT STEPS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PrimaryNextActionCard extends StatelessWidget {
  const _PrimaryNextActionCard({
    required this.facts,
    required this.steps,
    required this.isOfflineAi,
    required this.onOpenStep,
  });

  final AssessmentSafeFacts facts;
  final List<AssessmentNextStep>? steps;
  final bool isOfflineAi;
  final ValueChanged<AssessmentNextStep> onOpenStep;

  @override
  Widget build(BuildContext context) {
    final hasAiSteps = !isOfflineAi && steps != null && steps!.isNotEmpty;
    final step = hasAiSteps
        ? steps!.first
        : _buildDeterministicNextSteps(facts).first;
    return Container(
      key: const Key('assessment_primary_next_action'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: facts.fieldEntryBlocked
            ? const Color(0xFFFFF3E8)
            : const Color(0xFF164D3A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: facts.fieldEntryBlocked
              ? const Color(0xFFDEAA7A)
              : const Color(0xFF164D3A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assistant_navigation,
                size: 20,
                color: facts.fieldEntryBlocked
                    ? const Color(0xFF7C3F0B)
                    : const Color(0xFFBFE5CC),
              ),
              const SizedBox(width: 8),
              AppText(
                'NEXT ACTION',
                style: TextStyle(
                  color: facts.fieldEntryBlocked
                      ? const Color(0xFF7C3F0B)
                      : const Color(0xFFBFE5CC),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                hasAiSteps ? 'AI advice' : 'Saved findings',
                style: TextStyle(
                  color: facts.fieldEntryBlocked
                      ? const Color(0xFF7C3F0B)
                      : Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            AppWords.of(
              context,
            ).translate(readableAssessmentReferences(step.title)),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: facts.fieldEntryBlocked
                  ? const Color(0xFF2A2118)
                  : Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppWords.of(context).translate(step.description),
            style: TextStyle(
              color: facts.fieldEntryBlocked
                  ? const Color(0xFF4D4034)
                  : Colors.white.withValues(alpha: 0.9),
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          if (facts.screeningMode) ...[
            const SizedBox(height: 12),
            AppText(
              'Model damage screening and sign hints need review; they are not confirmed FAW infestation.',
              style: TextStyle(
                fontSize: 11.5,
                color: facts.fieldEntryBlocked
                    ? const Color(0xFF4D4034)
                    : Colors.white70,
                height: 1.3,
              ),
            ),
          ],
          if (facts.notAssessableCount > 0 ||
              facts.outstandingIssueCount > 0) ...[
            const SizedBox(height: 8),
            AppText(
              '${facts.notAssessableCount} not assessable · ${facts.outstandingIssueCount} record issue(s)',
              style: TextStyle(
                fontSize: 12,
                color: facts.fieldEntryBlocked
                    ? const Color(0xFF4D4034)
                    : Colors.white70,
              ),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => onOpenStep(step),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF164D3A),
              side: BorderSide.none,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: AppText(
              step.type == 'safety_review'
                  ? 'Review entry safety'
                  : step.type == 'review_evidence' ||
                        step.type == 'station_revisit'
                  ? 'View saved evidence'
                  : 'View next step',
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedNextStepsCard extends StatelessWidget {
  const _RecommendedNextStepsCard({
    required this.detail,
    required this.stats,
    this.steps,
    required this.isOfflineAi,
    required this.isCachedAi,
    required this.isLoadingAi,
    this.availabilityMessage,
    required this.onRegenerate,
    required this.onOpenStep,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;
  final List<AssessmentNextStep>? steps;
  final bool isOfflineAi;
  final bool isCachedAi;
  final bool isLoadingAi;
  final String? availabilityMessage;
  final VoidCallback onRegenerate;
  final ValueChanged<AssessmentNextStep> onOpenStep;

  @override
  Widget build(BuildContext context) {
    final safeFacts = AssessmentSafeFacts.fromDetailAndStats(
      detail,
      stats,
      expertReview:
          context.watch<ExpertReviewService?>()?.assessmentReviewFacts(
            detail.assessment.id,
          ) ??
          const {},
    );
    final candidateSteps = (steps != null && steps!.isNotEmpty)
        ? steps!
        : _buildDeterministicNextSteps(safeFacts);
    final effectiveSteps = candidateSteps;

    return ResultSurface(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.format_list_bulleted_rounded,
                color: Color(0xFF2E7D32),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: AppText(
                  'Recommended steps',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          AppText(
            isOfflineAi
                ? availabilityMessage != null
                      ? 'AI unavailable · using saved findings'
                      : 'Based on saved findings'
                : isCachedAi
                ? 'Saved AI guidance for this assessment'
                : 'AI guidance with checks from saved findings',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (isLoadingAi)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: AppText(
                'Preparing AI guidance…',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 12),

          if (effectiveSteps.isEmpty)
            const AppText('No additional steps are recorded.'),
          for (var i = 0; i < effectiveSteps.length; i++) ...[
            _NextStepItem(
              index: i + 1,
              step: effectiveSteps[i],
              onTap: () => onOpenStep(effectiveSteps[i]),
            ),
            if (i != effectiveSteps.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _NextStepItem extends StatelessWidget {
  const _NextStepItem({
    required this.index,
    required this.step,
    required this.onTap,
  });
  final int index;
  final AssessmentNextStep step;
  final VoidCallback onTap;

  Future<void> _showDetails(BuildContext context) async {
    final action = step.type == 'expert_review'
        ? 'Open expert review'
        : step.stationRefs.isNotEmpty
        ? 'View plant evidence'
        : step.type == 'safety_review'
        ? 'Check entry requirements'
        : const {
            'field_monitoring',
            'protocol_guidance',
            'monitoring',
          }.contains(step.type)
        ? 'Open scouting guide'
        : 'View details';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AssessmentActionModal(
        title: readableAssessmentReferences(step.title),
        eyebrow:
            '${index == 1 ? 'START HERE · ' : ''}${step.source == 'ai' ? 'AI SUGGESTION' : 'SAVED FINDINGS'}',
        icon: step.icon,
        priority: index == 1,
        locations: readableAssessmentLocations(step.stationRefs),
        actionLabel: action,
        content: AppText(
          readableAssessmentReferences(step.description),
          style: const TextStyle(
            fontSize: 15,
            height: 1.55,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
    if (proceed == true && context.mounted) onTap();
  }

  @override
  Widget build(BuildContext context) {
    final first = index == 1;
    return Material(
      color: first ? const Color(0xFFF6F1E7) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('recommended_step_$index'),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              if (MediaQuery.textScalerOf(context).scale(14) <= 21) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: first
                        ? const Color(0xFFEEE0C5)
                        : const Color(0xFFEDF3EE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    step.icon,
                    size: 20,
                    color: first ? const Color(0xFF805A22) : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      readableAssessmentReferences(step.title),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      '${first ? 'Start here · ' : ''}${step.source == 'ai' ? 'AI suggestion' : 'Saved findings'}${step.stationRefs.isEmpty ? '' : '\n${readableAssessmentLocations(step.stationRefs)}'}',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpertSubmissionDialog extends StatefulWidget {
  const _ExpertSubmissionDialog({required this.detail});

  final AssessmentHistoryDetail detail;

  @override
  State<_ExpertSubmissionDialog> createState() =>
      _ExpertSubmissionDialogState();
}

class _ExpertSubmissionDialogState extends State<_ExpertSubmissionDialog> {
  late final TextEditingController _nameController;
  final _questionController = TextEditingController();
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.detail.evaluator == 'Evaluator unavailable'
          ? ''
          : widget.detail.evaluator,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = 'Enter the name attached to this report.');
      return;
    }
    Navigator.of(context).pop(
      _ExpertSubmissionInput(
        farmerName: name,
        question: _questionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const AppText('Send to an expert'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: AppWords.of(context).translate('Farmer name'),
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              maxLines: 3,
              maxLength: 800,
              decoration: InputDecoration(
                labelText: AppWords.of(context).translate('Message (optional)'),
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const AppText(
              'The report includes assessment results, photos and field location.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const AppText('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const AppText('Send securely')),
      ],
    );
  }
}

class _ExpertSubmissionInput {
  const _ExpertSubmissionInput({
    required this.farmerName,
    required this.question,
  });

  final String farmerName;
  final String question;
}

class _ReportAssessmentCard extends StatelessWidget {
  const _ReportAssessmentCard({
    required this.detail,
    required this.reportStatus,
    required this.reportError,
    required this.onSendReport,
  });

  final AssessmentHistoryDetail detail;
  final int reportStatus; // 0 = Ready, 1 = Sending, 2 = Submitted, 3 = Error
  final String? reportError;
  final VoidCallback onSendReport;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat(
      'MMM d, yyyy',
    ).format(detail.assessment.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: reportStatus == 3
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: reportStatus == 3
              ? const Color(0xFFFECACA)
              : const Color(0xFFBBF7D0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Avatar & Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: reportStatus == 3
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF1B4D3E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  reportStatus == 3
                      ? Icons.error_outline_rounded
                      : Icons.account_balance_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppText(
                  'Send to an Expert',
                  style: TextStyle(
                    color: reportStatus == 3
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF1B4D3E),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildStatusBadge(),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            reportStatus == 3
                ? (reportError ??
                      'The assessment could not be sent. Please retry.')
                : reportStatus == 2
                ? 'This assessment was securely submitted for expert review.'
                : 'Send the completed assessment to an authorized reviewer. You choose separately whether to share the field boundary and evidence photos.',
            style: TextStyle(
              color: reportStatus == 3
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF334155),
              fontSize: 13,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 12),

          // Metadata Chips Row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              const _ReportMetaChip(
                icon: Icons.groups_outlined,
                label: 'Authorized Cropwise expert',
              ),
              const _ReportMetaChip(
                icon: Icons.description_outlined,
                label: 'Assessment results',
              ),
              _ReportMetaChip(
                icon: Icons.calendar_today_outlined,
                label: dateStr,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Primary Send / Retry Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: reportStatus == 3
                  ? const Key('retry_queue_report_button')
                  : const Key('queue_report_button'),
              onPressed: reportStatus == 1 || reportStatus == 2
                  ? null
                  : onSendReport,
              icon: reportStatus == 1
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      reportStatus == 3
                          ? Icons.refresh
                          : (reportStatus == 2
                                ? Icons.check_circle_outline
                                : Icons.support_agent_outlined),
                      size: 18,
                    ),
              label: Text(
                reportStatus == 1
                    ? 'Sending securely...'
                    : reportStatus == 3
                    ? 'Retry Sending'
                    : reportStatus == 2
                    ? 'Sent to Expert'
                    : 'Send to Expert',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: reportStatus == 3
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF1B4D3E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (reportStatus == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFFB45309),
              ),
            ),
            SizedBox(width: 4),
            AppText(
              'Sending...',
              style: TextStyle(
                color: Color(0xFFB45309),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (reportStatus == 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle, size: 12, color: Color(0xFF065F46)),
            SizedBox(width: 4),
            AppText(
              'Submitted',
              style: TextStyle(
                color: Color(0xFF065F46),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (reportStatus == 3) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error, size: 12, color: Color(0xFFDC2626)),
            SizedBox(width: 4),
            AppText(
              'Send failed',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.support_agent_outlined,
            size: 12,
            color: Color(0xFF166534),
          ),
          SizedBox(width: 4),
          AppText(
            'Ready to send',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportMetaChip extends StatelessWidget {
  const _ReportMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF166534)),
          const SizedBox(width: 4),
          AppText(
            label,
            style: const TextStyle(
              color: Color(0xFF166534),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 11. TAB 2: GUIDELINES LINK
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsGuidelinesLink extends StatelessWidget {
  const _ResultsGuidelinesLink();

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      key: const Key('assessment_guidelines_link'),
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const AdvisorOfflineGuidesScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E9E3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'Guidelines',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  AppText(
                    'Need more information? Open the guides.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 12. TAB 2: ASK WORMWISE ABOUT THIS ASSESSMENT
// ─────────────────────────────────────────────────────────────────────────────

class _AskWormWiseLinkCard extends StatelessWidget {
  const _AskWormWiseLinkCard({required this.preview, required this.onTap});

  final AssessmentAssistantPreview? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasConversation = preview?.hasConversation == true;
    return Material(
      color: const Color(0xFFF4F7F2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          key: const Key('ask_wormwise_assessment_card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E9E3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Color(0xFF1F563F),
                    size: 22,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppText(
                          'Ask Cropwise',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasConversation
                              ? 'Continue your assessment chat'
                              : 'Ask about these results',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCBD5E1),
                    size: 22,
                  ),
                ],
              ),
              if (hasConversation) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('continue_assessment_conversation_button'),
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const AppText('Continue conversation'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 13. PROTOCOL DISCLAIMER BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _SamplingQualityCard extends StatelessWidget {
  const _SamplingQualityCard({required this.summary});

  final AssessmentResultSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('assessment_sampling_quality'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E7DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.fact_check_outlined,
                color: Color(0xFF1B4D3E),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: AppText(
                  'Sampling quality',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _qualityRow(
            'Recorded stations',
            '${summary.recordedStationCount} of ${summary.expectedStationCount}',
          ),
          _qualityRow(
            'Reviewed stations',
            '${summary.currentReviewedStationCount} of ${summary.expectedStationCount}',
          ),
          _qualityRow(
            'Assessable plant observations',
            '${summary.assessableObservationCount} of ${summary.recordedObservationCount}',
          ),
          _qualityRow(
            'Stations with coordinates',
            '${summary.stationsWithCoordinates} of ${summary.expectedStationCount}',
          ),
        ],
      ),
    );
  }

  Widget _qualityRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationNotice extends StatelessWidget {
  const _VerificationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB91C1C), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: AppText(
              'Recorded data requires verification before relying on these results.',
              style: TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InterpretationBoundary extends StatelessWidget {
  const _InterpretationBoundary({super.key, required this.stage});

  final String stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Color(0xFF1D4ED8), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: AppText(
              'Ear damage metrics describe the opened subsample only and are not estimated yield loss.',
              style: TextStyle(
                color: Color(0xFF1E40AF),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsMessage extends StatelessWidget {
  const _ResultsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              AppWords.of(context).translate(title),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppWords.of(context).translate(message),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

String _formatGrowthStage(String stage) {
  return switch (stage) {
    've' => 'VE',
    'v1' => 'V1',
    'v2' => 'V2',
    'v3_v6' => 'V3–V6',
    'v7_v12' => 'V7–V12',
    'vt_r2' => 'VT–R2',
    'r3_r6' => 'R3–R6',
    _ => stage.toUpperCase().replaceAll('_', '–'),
  };
}
