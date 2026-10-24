import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../localization/app_language.dart';
import '../data/repositories/assessment_repository.dart';
import '../data/repositories/field_repository.dart';
import '../data/repositories/intervention_repository.dart';
import '../data/repositories/people_repository.dart';
import '../data/services/assessment_completion_validator.dart';
import '../data/services/assessment_metrics_service.dart';
import '../providers/app_data_mode.dart';
import '../providers/assessment_workspace_provider.dart';
import '../providers/field_workspace_provider.dart';
import '../services/cloud/wormwise_identity_service.dart';
import '../services/cloud/expert_review_service.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';
import '../services/wormwise_notification_service.dart';

class WormWiseDataScope extends StatelessWidget {
  const WormWiseDataScope({
    super.key,
    required this.database,
    required this.dataMode,
    this.languageController,
    required this.child,
    this.disposeDatabase = true,
    this.identityService,
    this.cloudSyncService,
  });

  final AppDatabase database;
  final AppDataMode dataMode;
  final AppLanguageController? languageController;
  final Widget child;
  final bool disposeDatabase;
  final WormWiseIdentityService? identityService;
  final WormWiseCloudSyncService? cloudSyncService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>(
          create: (_) => database,
          dispose: disposeDatabase ? (_, value) => value.close() : null,
        ),
        Provider<AppDataMode>.value(value: dataMode),
        if (languageController != null)
          ChangeNotifierProvider<AppLanguageController>.value(
            value: languageController!,
          )
        else
          ChangeNotifierProvider<AppLanguageController>(
            create: (_) => AppLanguageController(database),
          ),
        if (identityService != null)
          ChangeNotifierProvider<WormWiseIdentityService>.value(
            value: identityService!,
          )
        else
          ChangeNotifierProvider<WormWiseIdentityService>(
            create: (_) => WormWiseIdentityService.localOnly(),
          ),
        ChangeNotifierProvider<ExpertReviewService>(
          create: (context) =>
              ExpertReviewService(context.read<WormWiseIdentityService>()),
        ),
        ChangeNotifierProvider<WormWiseNotificationService>(
          create: (context) => WormWiseNotificationService(
            database,
            context.read<ExpertReviewService>(),
          ),
        ),
        if (cloudSyncService != null)
          ChangeNotifierProvider<WormWiseCloudSyncService>.value(
            value: cloudSyncService!,
          )
        else
          ChangeNotifierProvider<WormWiseCloudSyncService>(
            create: (_) => WormWiseCloudSyncService(database, null),
          ),
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
      ],
      child: child,
    );
  }
}
