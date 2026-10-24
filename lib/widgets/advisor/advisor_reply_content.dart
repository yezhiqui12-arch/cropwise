import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../localization/app_text.dart';
import '../../theme/app_colors.dart';

/// Render Markdown. The message-level reveal controls progressive typing.
class AdvisorReplyContent extends StatelessWidget {
  const AdvisorReplyContent({
    super.key,
    required this.text,
    this.animate = false,
  });
  final String text;
  final bool animate;

  static String prepare(String input) {
    final text = input.replaceAll('\r\n', '\n').trim();
    // Older persisted replies were often one long paragraph. Reflow only
    // unformatted prose; preserve every sentence and its order.
    if (text.length < 500 ||
        text.contains('\n') ||
        RegExp(r'[#*|]').hasMatch(text)) {
      return text;
    }
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z])'));
    final paragraphs = <String>[];
    var current = '';
    for (final sentence in sentences) {
      if (current.isNotEmpty && current.length + sentence.length > 360) {
        paragraphs.add(current);
        current = '';
      }
      current = current.isEmpty ? sentence : '$current $sentence';
    }
    if (current.isNotEmpty) paragraphs.add(current);
    return paragraphs.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium!.copyWith(
      height: 1.55,
      color: AppColors.textPrimary,
    );
    final heading = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: AppColors.highContrastGreen,
    );
    final data = prepare(text);
    final separator = RegExp(r'^\s*\|?\s*:?-{3,}:?\s*\|');
    final tableColumns = data
        .split('\n')
        .where(separator.hasMatch)
        .fold<int>(
          0,
          (count, line) => math.max(
            count,
            line.split('|').where((cell) => cell.trim().isNotEmpty).length,
          ),
        );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth / 2).clamp(120.0, 180.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tableColumns * cellWidth > constraints.maxWidth + 0.5)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: AppText(
                  'Swipe tables sideways to see more',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            SelectionArea(
              child: MarkdownBody(
                data: data,
                selectable: false,
                fitContent: false,
                // Reply content cannot load model-proposed local or remote images.
                // Actual evidence photos are rendered by the existing gallery.
                imageBuilder: (uri, title, alt) => Text(alt ?? '', style: body),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: body,
                  a: body,
                  strong: const TextStyle(fontWeight: FontWeight.w700),
                  h1: heading.copyWith(fontSize: 20),
                  h2: heading.copyWith(fontSize: 18),
                  h3: heading.copyWith(fontSize: 16),
                  h4: heading,
                  h5: heading,
                  h6: heading,
                  h1Padding: const EdgeInsets.only(top: 12, bottom: 4),
                  h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
                  h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
                  blockSpacing: 12,
                  listIndent: 22,
                  listBullet: body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  listBulletPadding: const EdgeInsets.only(right: 6),
                  tableColumnWidth: FixedColumnWidth(cellWidth),
                  tableScrollbarThumbVisibility: true,
                  tableHead: body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.highContrastGreen,
                  ),
                  tableBody: body.copyWith(fontSize: 13, height: 1.4),
                  tableHeadAlign: TextAlign.left,
                  tableBorder: TableBorder.all(color: AppColors.cardBorder),
                  tableCellsPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  tableHeadCellsDecoration: const BoxDecoration(
                    color: Color(0xFFE7F2E5),
                  ),
                  tableCellsDecoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  tableVerticalAlignment: TableCellVerticalAlignment.top,
                  tablePadding: const EdgeInsets.only(bottom: 8),
                  blockquote: body.copyWith(color: AppColors.highContrastGreen),
                  blockquotePadding: const EdgeInsets.all(12),
                  blockquoteDecoration: const BoxDecoration(
                    color: Color(0xFFE7F2E5),
                    border: Border(
                      left: BorderSide(color: AppColors.primary, width: 3),
                    ),
                  ),
                  horizontalRuleDecoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) return content;
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: content,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
    );
  }
}
