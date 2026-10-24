import 'package:flutter/material.dart';

/// One reveal clock for all text in a reply, including details and next steps.
/// Images are atomic markers and tables reveal complete rows to retain layout.
class AdvisorReplyReveal extends StatefulWidget {
  const AdvisorReplyReveal({
    super.key,
    required this.texts,
    required this.animate,
    required this.builder,
    this.onComplete,
  });
  final List<String> texts;
  final bool animate;
  final VoidCallback? onComplete;
  final Widget Function(BuildContext, List<String>, bool complete) builder;

  @override
  State<AdvisorReplyReveal> createState() => _AdvisorReplyRevealState();
}

class _AdvisorReplyRevealState extends State<AdvisorReplyReveal>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener(_statusChanged);
  List<List<String>> _characters = const [];
  int _length = 0;
  bool _initialized = false;
  bool _notified = false;
  int _generation = 0;

  @override
  bool get wantKeepAlive => widget.animate && !_clock.isCompleted;

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _notifyComplete();
      if (mounted) updateKeepAlive();
    }
  }

  void _notifyComplete() {
    if (_notified || !widget.animate) return;
    _notified = true;
    final generation = _generation;
    final callback = widget.onComplete;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Completion still belongs to the message if its off-screen widget is
      // released in this frame. The parent checks the current message ID.
      if (generation == _generation) callback?.call();
    });
  }

  void _configure() {
    _generation++;
    _characters = widget.texts.map((text) => text.characters.toList()).toList();
    _length = _characters.fold(0, (total, part) => total + part.length);
    _notified = false;
    _clock.duration = Duration(milliseconds: (_length * 5).clamp(250, 9000));
    if (!widget.animate ||
        MediaQuery.disableAnimationsOf(context) ||
        _length == 0) {
      _clock.value = 1;
      _notifyComplete();
    } else {
      _clock.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _configure();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
      _notifyComplete();
    }
  }

  @override
  void didUpdateWidget(covariant AdvisorReplyReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.texts.join('\u0000') != widget.texts.join('\u0000') ||
        (!oldWidget.animate && widget.animate)) {
      _configure();
    } else if (!widget.animate && _clock.value != 1) {
      _clock.value = 1;
    }
    updateKeepAlive();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final complete = _clock.value == 1;
        var remaining = (_length * _clock.value).floor();
        final visible = <String>[];
        for (var i = 0; i < _characters.length; i++) {
          final part = _characters[i];
          final count = remaining.clamp(0, part.length);
          remaining -= count;
          visible.add(
            count == part.length
                ? widget.texts[i]
                : safeMarkdownPrefix(part.take(count).join()),
          );
        }
        return widget.builder(context, visible, complete);
      },
    );
  }

  /// Keep incomplete figure markers and table syntax out of the visible text.
  static String safeMarkdownPrefix(String prefix) {
    final markerStart = prefix.lastIndexOf('[[guide:');
    if (markerStart >= 0 && !prefix.substring(markerStart).contains(']]')) {
      prefix = prefix.substring(0, markerStart);
    }
    // The first few characters of a marker are also invisible.
    prefix = prefix.replaceFirst(
      RegExp(r'\[{1,2}(?:g(?:u(?:i(?:d(?:e)?)?)?)?)?$'),
      '',
    );
    final lines = prefix.split('\n');
    final last = lines.last.trimLeft();
    if (last.startsWith('|')) lines.removeLast();
    // Until a table has its complete separator, hide its header as well.
    if (lines.isNotEmpty &&
        lines.last.trimLeft().startsWith('|') &&
        !lines.last.contains(RegExp(r'\|\s*:?-{3,}'))) {
      final tableStart =
          lines.lastIndexWhere((line) => !line.trimLeft().startsWith('|')) + 1;
      final table = lines.sublist(tableStart);
      if (!table.any((line) => RegExp(r'^\s*\|\s*:?-{3,}').hasMatch(line))) {
        lines.removeRange(tableStart, lines.length);
      }
    }
    prefix = lines
        .join('\n')
        .replaceFirst(RegExp(r'(^|\n)\s*(?:#{1,6}|[-*]|\d+\.)\s*$'), '');
    if (prefix.endsWith('*') && !prefix.endsWith('**')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    if ('**'.allMatches(prefix).length.isOdd) prefix += '**';
    return prefix;
  }
}

/// Mount only after reveal completion; a hidden card cannot receive a tap.
class AdvisorCompletionFade extends StatelessWidget {
  const AdvisorCompletionFade({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) => IgnorePointer(
        ignoring: value < 1,
        child: Opacity(opacity: value, child: child),
      ),
    );
  }
}
