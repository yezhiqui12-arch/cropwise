import 'package:flutter/material.dart';

import '../../localization/app_text.dart';
import '../../theme/app_colors.dart';

/// Content-sized surfaces used by assessment recommendations.
class ResultSurface extends StatelessWidget {
  const ResultSurface({super.key, required this.child, this.padding = 16});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE2E8E0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

Future<void> showResultInformation(
  BuildContext context, {
  required String title,
  required String body,
  IconData icon = Icons.info_outline_rounded,
  String? actionLabel,
  VoidCallback? onAction,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: const Color(0xFFF8FAF6),
  useSafeArea: true,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppText(
            body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          if (actionLabel != null && onAction != null) ...[
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onAction();
              },
              style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
              icon: const Icon(Icons.menu_book_outlined, size: 20),
              label: AppText(actionLabel),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
            child: const AppText('Close'),
          ),
        ],
      ),
    ),
  ),
);
