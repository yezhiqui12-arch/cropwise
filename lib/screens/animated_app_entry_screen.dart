import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cloud/wormwise_identity_service.dart';
import '../theme/app_colors.dart';
import 'account_access_screen.dart';
import 'main_navigation_screen.dart';

/// Routes to the appropriate first screen after identity restoration.
///
/// Returning users receive one short brand acknowledgement before Home.
/// Signed-out users continue into the complete account-entry sequence.
class AnimatedAppEntryScreen extends StatefulWidget {
  const AnimatedAppEntryScreen({
    super.key,
    this.launchLogoAlreadyShown = false,
  });

  final bool launchLogoAlreadyShown;

  @override
  State<AnimatedAppEntryScreen> createState() => _AnimatedAppEntryScreenState();
}

class _AnimatedAppEntryScreenState extends State<AnimatedAppEntryScreen>
    with SingleTickerProviderStateMixin {
  late final bool _hasAccessAtLaunch;
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  ImageProvider<Object>? _logoProvider;
  bool _started = false;
  bool _showHome = false;
  bool _showLogo = true;

  @override
  void initState() {
    super.initState();
    _hasAccessAtLaunch = context.read<WormWiseIdentityService>().hasAppAccess;
    if (widget.launchLogoAlreadyShown && _hasAccessAtLaunch) {
      _showHome = true;
      _showLogo = false;
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasAccessAtLaunch || widget.launchLogoAlreadyShown || _started) {
      return;
    }
    _started = true;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    _logoProvider = ResizeImage(
      const AssetImage('assets/images/wormwise_brand_logo.png'),
      width: (220 * pixelRatio).round(),
    );
    unawaited(_runReturningUserEntry());
  }

  Future<void> _runReturningUserEntry() async {
    try {
      await precacheImage(_logoProvider!, context);
    } catch (_) {
      // The visible image has its own fallback, so launch cannot be blocked by
      // a damaged or unavailable asset.
    }
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _showHome = true;
        _showLogo = false;
      });
      return;
    }
    await _controller.forward();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;

    // Mount Home behind the still-opaque launch surface. Waiting for the end
    // of the frame guarantees that Home's skeleton (or ready state) has
    // painted before the logo begins to disappear.
    setState(() => _showHome = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) setState(() => _showLogo = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccessAtLaunch) {
      return const AccountAccessScreen(
        allowContinueAsGuest: true,
        replaceWithHomeOnSuccess: true,
        brandedLanding: true,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showHome) const MainNavigationScreen(),
        if (_showLogo)
          FadeTransition(
            opacity: _logoOpacity,
            child: Scaffold(
              backgroundColor: const Color(0xFFF8F7F1),
              body: SafeArea(
                child: Center(
                  child: Image(
                    key: const Key('launch_logo'),
                    image:
                        _logoProvider ??
                        const AssetImage(
                          'assets/images/wormwise_brand_logo.png',
                        ),
                    width: 220,
                    height: 156,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.agriculture_rounded,
                      size: 120,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
