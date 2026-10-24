import 'package:flutter/material.dart';

import '../../screens/advisor/guideline_visual_gallery.dart';
import '../../services/advisor/advisor_rag_service.dart';
import '../../services/advisor/advisor_visual_reference.dart';
import 'advisor_reply_content.dart';
import 'advisor_reply_reveal.dart';

/// Places each trusted reference at its explanation, in reading order.
class AdvisorIllustratedReply extends StatelessWidget {
  const AdvisorIllustratedReply({
    super.key,
    required this.text,
    required this.articleIds,
    this.animate = false,
    this.onOpenArticle,
    this.showTrailingContent = true,
  });
  final String text;
  final List<String> articleIds;
  final bool animate;
  final ValueChanged<String>? onOpenArticle;
  final bool showTrailingContent;

  @override
  Widget build(BuildContext context) {
    final articles = AdvisorRagService.chunks
        .where((a) => articleIds.contains(a.id) && a.visuals.isNotEmpty)
        .toList();
    final content = AdvisorVisualReference.clean(text, articles);
    final children = <Widget>[];
    final inFlow = <String>{};
    var offset = 0;
    void prose(String value) {
      if (value.trim().isEmpty) return;
      children.add(AdvisorReplyContent(text: value.trim(), animate: animate));
    }

    for (final match in AdvisorVisualReference.marker.allMatches(content)) {
      prose(content.substring(offset, match.start));
      final reference = AdvisorVisualReference.resolve(match, articles)!;
      inFlow.add(reference.article.id);
      children.add(
        AdvisorCompletionFade(
          key: ValueKey(match.group(0)),
          child: GuidelineVisualGallery(
            key: ValueKey(match.group(0)),
            article: reference.article,
            figureNumbers: [reference.visual.figureNumber!],
            compact: true,
          ),
        ),
      );
      offset = match.end;
    }
    prose(content.substring(offset));
    if (showTrailingContent && onOpenArticle != null) {
      for (final id in inFlow) {
        children.add(
          AdvisorCompletionFade(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onOpenArticle!(id),
                child: const Text('Open full illustrated guide'),
              ),
            ),
          ),
        );
      }
    }
    // Backward compatibility for replies saved before in-flow references.
    for (final article in articles.where(
      (a) => showTrailingContent && !inFlow.contains(a.id),
    )) {
      children.add(
        AdvisorCompletionFade(
          child: GuidelineVisualGallery(
            article: article,
            compact: true,
            onOpenArticle: onOpenArticle == null
                ? null
                : () => onOpenArticle!(article.id),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
