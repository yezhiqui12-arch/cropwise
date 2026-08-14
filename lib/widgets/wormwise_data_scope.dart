import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/intervention_repository.dart';
import '../data/repositories/people_repository.dart';
import '../data/services/assessment_completion_validator.dart';
import '../data/services/assessment_metrics_service.dart';
import '../providers/app_data_mode.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../providers/wormwise_provider.dart';

class WormWiseDataScope extends StatelessWidget {
  const WormWiseDataScope({
    super.key,
    required this.database,
    required this.dataMode,
    required this.child,
    this.disposeDatabase = true,
  });

  final AppDatabase database;
  final AppDataMode dataMode;
  final Widget child;
  final bool disposeDatabase;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>(
          create: (_) => database,
          dispose: disposeDatabase ? (_, value) => value.close() : null,
        ),
        Provider<AppDataMode>.value(value: dataMode),
        ProxyProvider<AppDatabase, PeopleRepository>(
          update: (_, value, _) => PeopleRepository(value),
        ),
        ProxyProvider<AppDatabase, FieldRepository>(
          update: (_, value, _) => FieldRepository(value),
        ),
        ProxyProvider<AppDatabase, InterventionRepository>(
          update: (_, value, _) => InterventionRepository(value),
        ),
        ProxyProvider<AppDatabase, AssessmentRepository>(
          update: (_, value, _) => AssessmentRepository(value),
        ),
        ProxyProvider<AppDatabase, AssessmentCompletionValidator>(
          update: (_, value, _) => AssessmentCompletionValidator(value),
        ),
        ProxyProvider<AppDatabase, AssessmentMetricsService>(
          update: (_, value, _) => AssessmentMetricsService(value),
        ),
        ChangeNotifierProvider<FieldWorkspaceProvider>(
          create: (context) =>
              FieldWorkspaceProvider(context.read<FieldRepository>()),
        ),
        ChangeNotifierProxyProvider<
          FieldWorkspaceProvider,
          AssessmentWorkspaceProvider
        >(
          create: (context) => AssessmentWorkspaceProvider(
            context.read<AssessmentRepository>(),
            context.read<PeopleRepository>(),
          ),
          update: (_, fields, assessments) {
            assessments!.bindFieldWorkspace(fields.activeWorkspace);
            return assessments;
          },
        ),
        ChangeNotifierProvider(create: (_) => WormWiseProvider()),
      ],
      child: child,
    );
  }
}
