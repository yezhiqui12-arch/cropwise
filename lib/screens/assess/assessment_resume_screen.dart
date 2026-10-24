import 'dart:async';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../data/repositories/assessment_repository.dart';
import '../../data/repositories/field_repository.dart';
import '../../data/repositories/people_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../providers/assessment_workspace_provider.dart';
import '../../providers/field_workspace_provider.dart';
import '../../services/scouting_sampling_protocol.dart';
import 'retired_assessment_notice.dart';
import '../assessment_session_screen.dart';
import '../assessment_setup_screen.dart';

/// Isolates resumed records from the globally selected field and crop cycle.
class AssessmentResumeScreen extends StatefulWidget {
  const AssessmentResumeScreen({
    super.key,
    required this.assessmentId,
    this.blockRunId,
    this.stationNumber,
    this.openForReview = false,
  });
  final String assessmentId;
  final String? blockRunId;
  final int? stationNumber;
  final bool openForReview;
  @override
  State<AssessmentResumeScreen> createState() => _AssessmentResumeScreenState();
}

class _AssessmentResumeScreenState extends State<AssessmentResumeScreen> {
  late final Future<AssessmentHistoryDetail?> _record;
  final _navigator = GlobalKey<NavigatorState>();
  late final NavigatorObserver _observer;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _record = AssessmentHistoryRepository(
      context.read<AppDatabase>(),
    ).loadDetail(widget.assessmentId);
    _observer = _ResumeExitObserver(() {
      unawaited(_exitResumeFlow());
    });
  }

  Future<void> _exitResumeFlow() async {
    if (_isExiting || !mounted) return;
    setState(() => _isExiting = true);
    // Let NavigatorPopHandler rebuild disabled before popping the containing
    // route. Resumed scouting calls this before any inner route is popped, so
    // there is no delayed second pop that can close the app.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AssessmentHistoryDetail?>(
    future: _record,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(title: const AppText('Opening assessment')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final record = snapshot.data;
      if (record != null &&
          ScoutingSamplingProtocol.isRetired(
            record.assessment.protocolVersion,
            pattern: record.assessment.scoutingPattern,
          )) {
        return Scaffold(
          appBar: AppBar(title: const AppText('Outdated assessment')),
          body: RetiredAssessmentNotice(fieldId: record.workspace.field.id),
        );
      }
      if (snapshot.hasError || record == null || !record.canResume) {
        return Scaffold(
          appBar: AppBar(title: const AppText('Assessment unavailable')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: AppText(
              'This record cannot be resumed. It may have changed, its field may have been deleted, or its outline needs confirmation. Return to Assess to review the record.',
            ),
          ),
        );
      }
      final database = context.read<AppDatabase>();
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<FieldWorkspaceProvider>(
            create: (_) => FieldWorkspaceProvider.forAssessment(
              FieldRepository(database),
              record.workspace,
            ),
          ),
          ChangeNotifierProvider<AssessmentWorkspaceProvider>(
            create: (_) => AssessmentWorkspaceProvider.forAssessment(
              AssessmentRepository(database),
              PeopleRepository(database),
              record.workspace,
              record.assessment,
            ),
          ),
        ],
        child: NavigatorPopHandler<Object?>(
          enabled: !_isExiting,
          onPopWithResult: (_) => _navigator.currentState?.maybePop(),
          child: Navigator(
            key: _navigator,
            observers: [_observer],
            // A base route lets existing workflow pop/maybePop calls exit cleanly.
            // Every pushed setup, correction, and camera route retains this scope.
            onGenerateInitialRoutes: (_, _) => [
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/assess-exit'),
                builder: (_) => const SizedBox.shrink(),
              ),
              MaterialPageRoute<void>(
                builder: (_) => record.assessment.status == 'in_progress'
                    ? AssessmentSessionScreen(
                        initialBlockRunId: widget.blockRunId,
                        initialStationNumber: widget.stationNumber,
                        openForReview: widget.openForReview,
                        onExitRequested: _exitResumeFlow,
                        onStationRepairCompleted: widget.openForReview
                            ? _exitResumeFlow
                            : null,
                      )
                    : const AssessmentSetupScreen(),
              ),
            ],
            onGenerateRoute: (_) => null,
          ),
        ),
      );
    },
  );
}

class _ResumeExitObserver extends NavigatorObserver {
  _ResumeExitObserver(this.onExit);
  final VoidCallback onExit;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.settings.name == '/assess-exit') onExit();
  }
}
