import 'dart:async';
import '../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum TabSkeletonType { home, assess, map, guide }

/// Builds a tab only after its lightweight skeleton has painted once, then
/// cross-fades to the real content. This keeps expensive tab initialization
/// out of the navigation-tap frame.
class DeferredTabBody extends StatefulWidget {
  const DeferredTabBody({super.key, required this.type, required this.builder});

  final TabSkeletonType type;
  final WidgetBuilder builder;

  @override
  State<DeferredTabBody> createState() => _DeferredTabBodyState();
}

class _DeferredTabBodyState extends State<DeferredTabBody>
    with SingleTickerProviderStateMixin {
  Widget? _child;
  late final AnimationController _transitionController;
  late final Animation<double> _transitionOpacity;
  late final Animation<Offset> _contentPosition;
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _transitionOpacity = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    );
    _contentPosition =
        Tween<Offset>(begin: const Offset(0, .018), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _transitionController,
            curve: Curves.easeOutCubic,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Timer(const Duration(milliseconds: 180), () async {
        if (!mounted) return;
        await _transitionController.forward(from: 0);
        if (!mounted) return;
        _transitionController.value = 0;
        setState(() {
          _child = widget.builder(context);
          _showContent = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await _transitionController.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DeferredTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_child != null) _child = widget.builder(context);
  }

  @override
  Widget build(BuildContext context) {
    final child = _child;
    if (!_showContent || child == null) {
      return FadeTransition(
        opacity: ReverseAnimation(_transitionOpacity),
        child: TabLoadingSkeleton(type: widget.type),
      );
    }
    return FadeTransition(
      opacity: _transitionOpacity,
      child: SlideTransition(position: _contentPosition, child: child),
    );
  }
}

class TabLoadingSkeleton extends StatefulWidget {
  const TabLoadingSkeleton({super.key, required this.type});

  final TabSkeletonType type;

  @override
  State<TabLoadingSkeleton> createState() => _TabLoadingSkeletonState();
}

class _TabLoadingSkeletonState extends State<TabLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAppBar =
        widget.type == TabSkeletonType.assess ||
        widget.type == TabSkeletonType.guide;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: hasAppBar
          ? AppBar(
              title: widget.type == TabSkeletonType.assess
                  ? const AppText('Assess')
                  : const AppText('Guide'),
              actions: widget.type == TabSkeletonType.guide
                  ? const [
                      Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: Icon(
                          Icons.settings_suggest_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ]
                  : null,
            )
          : null,
      body: SafeArea(
        top: !hasAppBar,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final color = Color.lerp(
              const Color(0xFFE2E8E3),
              const Color(0xFFF1F4F1),
              Curves.easeInOut.transform(_controller.value),
            )!;
            return RepaintBoundary(child: _layout(color));
          },
        ),
      ),
    );
  }

  Widget _layout(Color color) => Padding(
    padding: const EdgeInsets.all(16),
    child: switch (widget.type) {
      TabSkeletonType.home => _home(color),
      TabSkeletonType.assess => _assess(color),
      TabSkeletonType.map => _map(color),
      TabSkeletonType.guide => _guide(color),
    },
  );

  Widget _home(Color color) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    children: [
      _card(color, 220),
      const SizedBox(height: 14),
      _card(color, 128),
      const SizedBox(height: 14),
      _card(color, 170),
      const SizedBox(height: 14),
      _card(color, 112),
    ],
  );

  Widget _assess(Color color) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    children: [
      _bone(color, double.infinity, 50),
      const SizedBox(height: 18),
      _bone(color, 150, 20),
      const SizedBox(height: 12),
      for (var i = 0; i < 3; i++) ...[
        _card(color, 104),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget _map(Color color) => Column(
    children: [
      Row(
        children: [
          Expanded(child: _bone(color, double.infinity, 48)),
          const SizedBox(width: 10),
          _bone(color, 48, 48),
        ],
      ),
      const SizedBox(height: 14),
      Expanded(child: _card(color, double.infinity)),
      const SizedBox(height: 14),
      _bone(color, double.infinity, 54),
    ],
  );

  Widget _guide(Color color) => Column(
    children: [
      Expanded(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _bone(color, 190, 20),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _card(color, 112)),
                const SizedBox(width: 12),
                Expanded(child: _card(color, 112)),
              ],
            ),
            const SizedBox(height: 18),
            _card(color, 132),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _bone(color, double.infinity, 54),
    ],
  );

  Widget _card(Color color, double height) => Container(
    height: height,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.surfaceVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bone(color, 32, 32),
        const SizedBox(height: 8),
        _bone(color, 148, 14),
        const SizedBox(height: 6),
        _bone(color, 220, 10),
      ],
    ),
  );

  Widget _bone(Color color, double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height > 30 ? 12 : 7),
    ),
  );
}
