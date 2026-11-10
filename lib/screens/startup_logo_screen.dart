import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The existing launch logo, shown before any account or database preparation.
class StartupLogoScreen extends StatefulWidget {
  const StartupLogoScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<StartupLogoScreen> createState() => _StartupLogoScreenState();
}

class _StartupLogoScreenState extends State<StartupLogoScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _imageReady() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_animate());
    });
  }

  Future<void> _animate() async {
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _controller.forward();
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 360));
      if (!mounted) return;
      await _controller.reverse();
    } else {
      _controller.value = 1;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F7F1),
    body: SafeArea(
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: Image.asset(
            'assets/images/wormwise_brand_logo.png',
            key: const Key('launch_logo'),
            width: 220,
            height: 156,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            frameBuilder: (_, child, frame, _) {
              if (frame != null) _imageReady();
              return child;
            },
            errorBuilder: (_, _, _) {
              _imageReady();
              return const Icon(
                Icons.agriculture_rounded,
                size: 120,
                color: AppColors.primary,
              );
            },
          ),
        ),
      ),
    ),
  );
}
