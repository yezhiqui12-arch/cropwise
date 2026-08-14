import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppDataMode {
  const AppDataMode({
    required this.isTestMode,
    this.debugFeaturesEnabled = kDebugMode,
  });

  const AppDataMode.production({this.debugFeaturesEnabled = kDebugMode})
    : isTestMode = false;

  final bool isTestMode;
  final bool debugFeaturesEnabled;

  bool testShortcutsAvailableForBuild({required bool debugBuild}) =>
      debugBuild && debugFeaturesEnabled && isTestMode;

  bool get testShortcutsAvailable =>
      testShortcutsAvailableForBuild(debugBuild: kDebugMode);

  bool canEnterTestModeForBuild({required bool debugBuild}) =>
      debugBuild && debugFeaturesEnabled && !isTestMode;

  bool get canEnterTestMode => canEnterTestModeForBuild(debugBuild: kDebugMode);

  Future<Directory> evidenceRootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    if (!isTestMode) return documents;
    return Directory(
      '${documents.path}${Platform.pathSeparator}wormwise_test_data',
    );
  }
}
