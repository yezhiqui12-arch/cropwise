import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/local/app_database.dart';
import 'localization/app_language.dart';
import 'providers/app_data_mode.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/animated_app_entry_screen.dart';
import 'services/cloud/supabase_bootstrap.dart';
import 'services/cloud/wormwise_cloud_sync_service.dart';
import 'services/cloud/wormwise_identity_service.dart';
import 'theme/app_theme.dart';
import 'widgets/wormwise_data_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloud = await SupabaseBootstrap.initialize();
  final identity = WormWiseIdentityService(cloud.client);
  await identity.restoreAccessState();
  final database = AppDatabase();
  final languageController = AppLanguageController(database);
  await languageController.load();
  final cloudSync = WormWiseCloudSyncService(database, cloud.client);
  final restoredUser = identity.user;
  if (restoredUser != null && !restoredUser.isAnonymous) {
    await cloudSync.prepareAccountView(
      restoredUser.id,
      assumeCurrentWhenUntracked: true,
      restoreRecords: false,
    );
  } else if (identity.hasAppAccess) {
    await cloudSync.prepareGuestView();
  }
  runApp(
    WormWiseApp(
      database: database,
      languageController: languageController,
      identityService: identity,
      cloudSyncService: cloudSync,
      showLaunchExperience: true,
    ),
  );
  unawaited(() async {
    await identity.initialize();
  }());
}

class WormWiseApp extends StatelessWidget {
  const WormWiseApp({
    super.key,
    this.database,
    this.languageController,
    this.identityService,
    this.cloudSyncService,
    this.debugFeaturesEnabled = kDebugMode,
    this.showLaunchExperience = false,
  });

  final AppDatabase? database;
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
      languageController:
          languageController ?? AppLanguageController(appDatabase),
      dataMode: AppDataMode.production(
        debugFeaturesEnabled: debugFeaturesEnabled,
      ),
      identityService: identityService,
      cloudSyncService: cloudSyncService,
      child: Consumer<AppLanguageController>(
        builder: (context, language, _) => MaterialApp(
          title: 'WormWise',
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
              ? const AnimatedAppEntryScreen()
              : const MainNavigationScreen(),
        ),
      ),
    );
  }
}
