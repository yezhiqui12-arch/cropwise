import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'data/local/app_database.dart';
import 'providers/app_data_mode.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/wormwise_data_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WormWiseApp());
}

class WormWiseApp extends StatelessWidget {
  const WormWiseApp({
    super.key,
    this.database,
    this.debugFeaturesEnabled = kDebugMode,
  });

  final AppDatabase? database;
  final bool debugFeaturesEnabled;

  @override
  Widget build(BuildContext context) {
    return WormWiseDataScope(
      database: database ?? AppDatabase(),
      dataMode: AppDataMode.production(
        debugFeaturesEnabled: debugFeaturesEnabled,
      ),
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
