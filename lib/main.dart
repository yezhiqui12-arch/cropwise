import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/local/app_database.dart';
import 'localization/app_language.dart';
import 'providers/app_data_mode.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/animated_app_entry_screen.dart';
import 'services/startup/app_startup.dart';
import 'services/startup/app_startup_gate.dart';
import 'services/cloud/wormwise_cloud_sync_service.dart';
import 'services/cloud/wormwise_identity_service.dart';
import 'theme/app_theme.dart';
import 'widgets/wormwise_data_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AppStartupGate<AppStartupResources>(
      initialize: initializeWormWise,
      release: (resources) => resources.close(),
      builder: (_, resources) => WormWiseApp(
        database: resources.database,
        languageController: resources.language,
        identityService: resources.identity,
        cloudSyncService: resources.cloudSync,
        startupRecoveryWarning: resources.unresolvedCaptures > 0,
        disposeDatabase: false,
        showLaunchExperience: true,
      ),
    ),
  );
}

class WormWiseApp extends StatelessWidget {
  const WormWiseApp({
    super.key,
    this.database,
    this.disposeDatabase = true,
    this.startupRecoveryWarning = false,
    this.languageController,
    this.identityService,
    this.cloudSyncService,
    this.debugFeaturesEnabled = kDebugMode,
    this.showLaunchExperience = false,
  });

  final AppDatabase? database;
  final bool disposeDatabase;
  final bool startupRecoveryWarning;
  final AppLanguageController? languageController;
  final WormWiseIdentityService? identityService;
  final WormWiseCloudSyncService? cloudSyncService;
  final bool debugFeaturesEnabled;
  // Nullable so a hot reload can safely rebuild WormWiseApp instances that
  // were created before this launch flag was added. A cold start always passes
  // an explicit value from main().
  final bool? showLaunchExperience;

  @override
  Widget build(BuildContext context) {
    final appDatabase = database ?? AppDatabase();
    return WormWiseDataScope(
      database: appDatabase,
      disposeDatabase: disposeDatabase,
      languageController:
          languageController ?? AppLanguageController(appDatabase),
      dataMode: AppDataMode.production(
        debugFeaturesEnabled: debugFeaturesEnabled,
      ),
      identityService: identityService,
      cloudSyncService: cloudSyncService,
      child: Consumer<AppLanguageController>(
        builder: (context, language, _) => MaterialApp(
          title: 'Cropwise',
          builder: startupRecoveryWarning
              ? (_, child) => StartupRecoveryNotice(child: child!)
              : null,
          locale: language.locale,
          supportedLocales: const [Locale('en'), Locale('fil')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: showLaunchExperience == true
              ? const AnimatedAppEntryScreen(launchLogoAlreadyShown: true)
              : const MainNavigationScreen(),
        ),
      ),
    );
  }
}
