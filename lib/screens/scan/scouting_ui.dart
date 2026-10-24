import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../theme/app_colors.dart';

/// Shared presentation for the guided walk and its detail sheets.
class ScoutingCard extends StatelessWidget {
  const ScoutingCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE1E8DF)),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class ScoutingTag extends StatelessWidget {
  const ScoutingTag(this.label, {super.key, this.color = AppColors.primary});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: AppText(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

Future<void> showScoutingGuide(
  BuildContext context, {
  required String instruction,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: AppColors.background,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: AppText(
                    'Scouting guide',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close guide',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const AppText(
              '20 plants per sampling block',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _GuideRow(
              Icons.route_outlined,
              'Follow the walk',
              'Visit the numbered plants spread across the field.',
            ),
            const SizedBox(height: 18),
            _GuideRow(Icons.search_rounded, 'Inspect the plant', instruction),
            const SizedBox(height: 18),
            const _GuideRow(
              Icons.photo_camera_outlined,
              'Capture and save',
              'Take one overview and up to two closer photos. Save before moving on.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
              child: const AppText('Got it'),
            ),
          ],
        ),
      ),
    ),
  ),
);

class _GuideRow extends StatelessWidget {
  const _GuideRow(this.icon, this.title, this.description);
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            AppText(
              description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
