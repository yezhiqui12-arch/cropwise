import 'dart:async';
import '../localization/app_language.dart';
import '../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_data_mode.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';
import '../widgets/account_recovery_view.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/top_header.dart';
import '../widgets/tab_loading_skeleton.dart';
import 'advisor/advisor_screen.dart';
import 'boundary_map_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'assess/assessments_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.onExitTestMode,
    this.onClearTestMode,
    this.backgroundStartupEnabled = true,
  });

  final int initialIndex;
  final VoidCallback? onExitTestMode;
  final Future<void> Function()? onClearTestMode;
  final bool backgroundStartupEnabled;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  int _guideRefreshToken = 0;
  late final List<Widget?> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _screens = List<Widget?>.filled(5, null);
    _screens[_currentIndex] = _createScreen(_currentIndex);
    if (widget.backgroundStartupEnabled) _scheduleBackgroundStartup();
  }

  @override
  void didUpdateWidget(covariant MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.backgroundStartupEnabled &&
        widget.backgroundStartupEnabled) {
      _screens[0] = _createScreen(0);
      _scheduleBackgroundStartup();
    }
  }

  void _scheduleBackgroundStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<WormWiseCloudSyncService>().start());
    });
  }

  Widget _createScreen(int index) => switch (index) {
    0 => HomeScreen(backgroundStartupEnabled: widget.backgroundStartupEnabled),
    1 => DeferredTabBody(
      type: TabSkeletonType.assess,
      builder: (_) => const AssessmentsScreen(),
    ),
    2 => DeferredTabBody(
      type: TabSkeletonType.map,
      builder: (_) => const BoundaryMapScreen(),
    ),
    3 => DeferredTabBody(
      type: TabSkeletonType.guide,
      builder: (_) => AdvisorScreen(
        refreshToken: _guideRefreshToken,
        onSelectDestination: _selectDestination,
      ),
    ),
    4 => const MoreScreen(),
    _ => const SizedBox.shrink(),
  };

  void _selectDestination(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      if (index == 3) {
        _guideRefreshToken++;
        _screens[index] = _createScreen(index);
      } else {
        _screens[index] ??= _createScreen(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataMode =
        context.watch<AppDataMode?>() ?? const AppDataMode.production();
    final isHome = _currentIndex == 0;
    final sync = context.watch<WormWiseCloudSyncService?>();
    if (!dataMode.isTestMode && sync?.needsAccountRecovery == true) {
      return Scaffold(
        body: AccountRecoveryView(
          state: sync!.recoveryState,
          detail: sync.recoveryDetail,
          onRetry: () => unawaited(sync.synchronizeNow()),
          onContinueWithLocalData: sync.canContinueWithLocalData
              ? sync.continueWithLocalData
              : null,
        ),
      );
    }
    return Scaffold(
      appBar: isHome
          ? TopHeader(
              key: const Key('home_top_header'),
              onOpenAssess: () => _selectDestination(1),
            )
          : null,
      body: Column(
        children: [
          if (dataMode.isTestMode)
            Material(
              key: const Key('permanent_test_data_indicator'),
              color: const Color(0xFF8B1E1E),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: AppText(
                          'TEST DATA · Separate from farmer records',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('clear_test_mode_button'),
                        onPressed: widget.onClearTestMode,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const AppText('Clear'),
                      ),
                      IconButton(
                        key: const Key('exit_test_mode_button'),
                        tooltip: AppWords.of(
                          context,
                        ).translate('Exit test mode'),
                        onPressed: widget.onExitTestMode,
                        color: Colors.white,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: List<Widget>.generate(
                _screens.length,
                (index) => _screens[index] ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: _selectDestination,
      ),
    );
  }
}
