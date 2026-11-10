import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../screens/startup_logo_screen.dart';

/// Keeps startup failures visible without mounting an unprepared account view.
class AppStartupGate<T extends Object> extends StatefulWidget {
  const AppStartupGate({
    super.key,
    required this.initialize,
    required this.builder,
    required this.release,
  });
  final Future<T> Function(void Function(String) reportStage) initialize;
  final Widget Function(BuildContext, T) builder;
  final Future<void> Function(T) release;
  @override
  State<AppStartupGate<T>> createState() => _AppStartupGateState<T>();
}

class _AppStartupGateState<T extends Object> extends State<AppStartupGate<T>> {
  T? _resources;
  bool _busy = true;
  bool _failed = false;
  String _stage = 'Preparing saved data';
  bool _showLogo = true;

  void _finishLogo() {
    setState(() => _showLogo = false);
    // Paint loading before beginning work that could occupy the UI isolate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final resources = await widget.initialize((stage) {
        if (mounted) setState(() => _stage = stage);
      });
      if (!mounted) {
        await widget.release(resources);
        return;
      }
      setState(() {
        _resources = resources;
        _busy = false;
      });
    } catch (error, stack) {
      debugPrint('Cropwise startup failed during $_stage: $error\n$stack');
      if (mounted) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final resources = _resources;
    if (resources != null) unawaited(widget.release(resources));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resources = _resources;
    if (resources != null && !_showLogo) {
      return widget.builder(context, resources);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _showLogo
          ? StartupLogoScreen(onFinished: _finishLogo)
          : Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_stage),
                        ],
                        if (_failed) ...[
                          const Text(
                            "Cropwise couldn't finish opening your saved data. Check available storage and try again.",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const Key('startup_retry'),
                            onPressed: _busy ? null : _start,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class StartupRecoveryNotice extends StatefulWidget {
  const StartupRecoveryNotice({super.key, required this.child});
  final Widget child;
  @override
  State<StartupRecoveryNotice> createState() => _StartupRecoveryNoticeState();
}

class _StartupRecoveryNoticeState extends State<StartupRecoveryNotice> {
  bool _dismissed = false;
  @override
  Widget build(BuildContext context) => _dismissed
      ? widget.child
      : Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Some unfinished photo saves need review. Your saved assessments are available. Reopen the affected assessment to review its evidence.',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => setState(() => _dismissed = true),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
}
