import 'package:flutter/material.dart';

enum ReviewPositionState {
  confirmed,
  notReviewed,
  missing,
  insufficient,
  fallback,
  notAssessable,
}

class StationReviewHeader extends StatelessWidget {
  const StationReviewHeader({
    super.key,
    required this.stationNumber,
    required this.confirmedCount,
    required this.itemLabel,
    required this.needsAttentionCount,
  });

  final int stationNumber;
  final int confirmedCount;
  final String itemLabel;
  final int needsAttentionCount;

  @override
  Widget build(BuildContext context) {
    final allDone = needsAttentionCount == 0 && confirmedCount == 10;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allDone
            ? const Color(0xFFEAF6EE)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allDone
              ? const Color(0xFF176B3A).withValues(alpha: 0.25)
              : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF176B3A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'STATION $stationNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (allDone)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Color(0xFF176B3A),
                      size: 18,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Ready to Complete',
                      style: TextStyle(
                        color: Color(0xFF176B3A),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '$needsAttentionCount Need Attention',
                  style: const TextStyle(
                    color: Color(0xFFB3261E),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Station Evidence Review',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$confirmedCount of 10 $itemLabel confirmed',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class StationReviewStatusStrip extends StatelessWidget {
  const StationReviewStatusStrip({
    super.key,
    required this.states,
    required this.itemLabel,
    required this.onSelected,
  });

  final Map<int, ReviewPositionState> states;
  final String itemLabel;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$itemLabel review progress',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var position = 1; position <= 10; position++)
          _PositionButton(
            position: position,
            state: states[position] ?? ReviewPositionState.notReviewed,
            itemLabel: itemLabel,
            onTap: () => onSelected(position),
          ),
      ],
    ),
  );
}

class StationReviewBottomBar extends StatelessWidget {
  const StationReviewBottomBar({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.onPressed,
    this.isSaving = false,
  });

  final String message;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback? onPressed;
  final bool isSaving;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: FilledButton.icon(
                key: actionKey,
                onPressed: isSaving ? null : onPressed,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PositionButton extends StatelessWidget {
  const _PositionButton({
    required this.position,
    required this.state,
    required this.itemLabel,
    required this.onTap,
  });

  final int position;
  final ReviewPositionState state;
  final String itemLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon, label) = switch (state) {
      ReviewPositionState.confirmed => (
        const Color(0xFFDDF1E2),
        const Color(0xFF176B3A),
        Icons.check,
        'confirmed',
      ),
      ReviewPositionState.missing => (
        const Color(0xFFFFE3DE),
        const Color(0xFF9F2D20),
        Icons.image_not_supported_outlined,
        'missing evidence',
      ),
      ReviewPositionState.insufficient => (
        const Color(0xFFFFE3DE),
        const Color(0xFF9F2D20),
        Icons.priority_high,
        'insufficient evidence',
      ),
      ReviewPositionState.fallback => (
        const Color(0xFFE3EDF7),
        const Color(0xFF24547A),
        Icons.description_outlined,
        'manual fallback',
      ),
      ReviewPositionState.notAssessable => (
        const Color(0xFFE8EAEB),
        const Color(0xFF4E585C),
        Icons.block_outlined,
        'not assessable',
      ),
      ReviewPositionState.notReviewed => (
        const Color(0xFFFFEBC4),
        const Color(0xFF7A4A00),
        Icons.pending_outlined,
        'not reviewed',
      ),
    };
    return Semantics(
      button: true,
      label: '$itemLabel $position, $label',
      child: InkWell(
        key: Key('review_position_$position'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 58,
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: foreground.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(height: 2),
              Text(
                '$position',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
