import 'advisor_rag_service.dart';

/// In-flow references to curated figures. Neither URLs nor asset paths come
/// from the model. The marker travels with the answer through chat storage.
class AdvisorVisualReference {
  const AdvisorVisualReference(this.article, this.visual);
  final AdvisorKnowledgeChunk article;
  final AdvisorGuideVisual visual;

  static final marker = RegExp(r'\[\[guide:([a-z0-9-]+):(\d+)\]\]');

  static AdvisorVisualReference? resolve(
    Match match,
    Iterable<AdvisorKnowledgeChunk> articles,
  ) {
    for (final article in articles) {
      if (article.id != match.group(1)) continue;
      for (final visual in article.visuals) {
        if (visual.figureNumber == int.tryParse(match.group(2)!)) {
          return AdvisorVisualReference(article, visual);
        }
      }
    }
    return null;
  }

  static String clean(String text, Iterable<AdvisorKnowledgeChunk> articles) {
    final used = <String>{};
    return text.replaceAllMapped(marker, (match) {
      final reference = resolve(match, articles);
      if (reference == null || !used.add(reference.visual.asset)) {
        return '';
      }
      return '\n\n${match.group(0)}\n\n';
    }).trim();
  }

  static String plainText(String text) => text.replaceAll(marker, '').trim();
}
