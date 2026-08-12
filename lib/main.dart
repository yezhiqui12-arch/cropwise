import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'data/local/app_database.dart';
import 'data/repositories/assessment_repository.dart';
import 'data/repositories/field_repository.dart';
import 'data/repositories/intervention_repository.dart';
import 'data/repositories/people_repository.dart';
import 'data/services/assessment_completion_validator.dart';
import 'data/services/assessment_metrics_service.dart';
import 'providers/assessment_workspace_provider.dart';
import 'providers/field_workspace_provider.dart';
import 'providers/wormwise_provider.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WormWiseApp());
}

class WormWiseApp extends StatelessWidget {
  const WormWiseApp({super.key, this.database});

  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>(
          create: (_) => database ?? AppDatabase(),
          dispose: (_, database) => database.close(),
        ),
        ProxyProvider<AppDatabase, PeopleRepository>(
          update: (_, database, _) => PeopleRepository(database),
        ),
        ProxyProvider<AppDatabase, FieldRepository>(
          update: (_, database, _) => FieldRepository(database),
        ),
        ProxyProvider<AppDatabase, InterventionRepository>(
          update: (_, database, _) => InterventionRepository(database),
        ),
        ProxyProvider<AppDatabase, AssessmentRepository>(
          update: (_, database, _) => AssessmentRepository(database),
        ),
        ProxyProvider<AppDatabase, AssessmentCompletionValidator>(
          update: (_, database, _) => AssessmentCompletionValidator(database),
        ),
        ProxyProvider<AppDatabase, AssessmentMetricsService>(
          update: (_, database, _) => AssessmentMetricsService(database),
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
      child: MaterialApp(
        title: 'WormWise',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            surface: AppColors.surface,
            background: AppColors.background,
          ),
          textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
          scaffoldBackgroundColor: AppColors.background,
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}
