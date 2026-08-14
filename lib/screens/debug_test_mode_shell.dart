import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local/app_database.dart';
import '../providers/app_data_mode.dart';
import '../services/debug_test_data_service.dart';
import '../widgets/wormwise_data_scope.dart';
import 'main_navigation_screen.dart';

class DebugTestModeShell extends StatefulWidget {
  const DebugTestModeShell({super.key, this.database});

  /// Test injection only. Production debug entry uses its named isolated DB.
  final AppDatabase? database;

  @override
  State<DebugTestModeShell> createState() => _DebugTestModeShellState();
}

class _DebugTestModeShellState extends State<DebugTestModeShell> {
  late final AppDatabase _database;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      throw StateError('Test mode cannot run in a release build.');
    }
    _database = widget.database ?? AppDatabase.debugTest();
    _ready = DebugTestDataService(_database).ensureTestAssessment();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('TEST DATA')),
            body: Center(
              child: Text('Could not open test data: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return WormWiseDataScope(
          database: _database,
          dataMode: const AppDataMode(isTestMode: true),
          // Test mode needs its own Navigator. Without it, routes pushed from
          // Scan attach to the outer production Navigator and lose the
          // isolated database and AppDataMode providers.
          child: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => MainNavigationScreen(
                initialIndex: 2,
                onExitTestMode: () => Navigator.pop(context),
                onClearTestMode: () async {
                  final mode = const AppDataMode(isTestMode: true);
                  await DebugTestDataService(
                    _database,
                  ).clear(evidenceRoot: await mode.evidenceRootDirectory());
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
