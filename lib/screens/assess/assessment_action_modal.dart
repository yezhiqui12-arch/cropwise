import 'package:flutter/material.dart';
import '../../localization/app_text.dart';
import '../../theme/app_colors.dart';

/// A focused, scrollable detail dialog with an optional direct next action.
class AssessmentActionModal extends StatelessWidget {
  const AssessmentActionModal({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.icon,
    required this.content,
    this.locations,
    this.actionLabel,
    this.priority = false,
  });
  final String title, eyebrow;
  final IconData icon;
  final Widget content;
  final String? locations, actionLabel;
  final bool priority;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('assessment_action_modal'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: const Color(0xFF193F35),
                    padding: const EdgeInsets.fromLTRB(22, 14, 14, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF335C4D),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                icon,
                                color: priority
                                    ? const Color(0xFFF4D69C)
                                    : const Color(0xFFD7EADF),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppText(
                                eyebrow,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.4,
                                  color: Color(0xFFCAE0D4),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(context, false),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        AppText(
                          title,
                          style: const TextStyle(
                            fontSize: 23,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (locations != null && locations!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F1E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: Color(0xFF86612C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppText(
                                    locations!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.45,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF685435),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        content,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (actionLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              child: FilledButton(
                key: const Key('assessment_modal_action'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  minimumSize: const Size(48, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        actionLabel!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
