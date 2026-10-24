import 'dart:io';
import 'package:wormwise/services/advisor/advisor_rag_service.dart';
import 'package:wormwise/services/advisor/clemson_growth_reference.dart';
import 'package:wormwise/services/advisor/advisor_visual_reference.dart';

// Small offline content/integration check; no model calls or Flutter tests.
void main() {
  const rag = AdvisorRagService();
  for (final query in [
    'How should I identify my corn crop growth stage?',
    'How can I determine maize development from leaf collars?',
    'Paano malalaman ang growth stage ng mais?',
    'What is the difference between tasseling and silking?',
  ]) {
    final found = rag.retrieve(query, forAi: true).bounded().results;
    if (!found.any((r) => r.chunk.id == 'identify-corn-growth-stage')) {
      throw StateError('Missing stage identification guide: $query');
    }
  }
  final article = AdvisorRagService.chunks.firstWhere(
    (a) => a.id == 'identify-corn-growth-stage',
  );
  for (final query in [
    'How do I determine my corn crop growth stage?',
    'How can I identify the growth stages of maize?',
    'Paano malalaman ang growth stage ng mais?',
    'Explain vegetative and reproductive corn growth stages',
  ]) {
    final context = rag
        .retrieve(query, forAi: true, growthStage: 'V3')
        .bounded();
    if (context.results.first.chunk.id != article.id ||
        !context.toPromptText().contains('[[guide:${article.id}:13]]')) {
      throw StateError('Broad guide lost to active stage or budget: $query');
    }
  }
  if (AdvisorRagService.growthStageGuideArticle('Explain app development') !=
      null) {
    throw StateError('Unrelated development question misclassified');
  }
  for (final (query, id) in [
    ('How do I recognize R3 growth stage?', 'clemson-growth-milk-dough'),
    ('How do I identify V15 growth stage?', 'clemson-growth-leaf-collars'),
  ]) {
    if (rag
            .retrieve(query, forAi: true, growthStage: 'V3')
            .bounded()
            .results
            .first
            .chunk
            .id !=
        id) {
      throw StateError('Specific stage lost to field stage: $query');
    }
  }
  final illustrated =
      'VE explanation\n\n[[guide:${article.id}:1]]\n\n'
      'R6 explanation\n\n[[guide:${article.id}:13]]';
  final restored = AdvisorVisualReference.clean(illustrated, [article]);
  if (AdvisorVisualReference.marker.allMatches(restored).length != 2 ||
      AdvisorVisualReference.plainText(restored).contains('[[guide:') ||
      AdvisorVisualReference.clean('[[guide:unknown:1]]', [
        article,
      ]).isNotEmpty ||
      AdvisorVisualReference.clean('[[guide:${article.id}:999]]', [
        article,
      ]).isNotEmpty) {
    throw StateError('Invalid inline reference or copy-text handling');
  }
  for (final visual in article.visuals) {
    if (!File(visual.asset).existsSync()) {
      throw StateError('Missing ${visual.asset}');
    }
    if (visual.credit?.isNotEmpty != true ||
        visual.sourceUrl?.startsWith('https://lgpress.clemson.edu/') != true) {
      throw StateError('Missing original credit/source for ${visual.title}');
    }
  }
  if (article.visuals.length != 13 ||
      clemsonGrowthFigures.length != 13 ||
      clemsonGrowthBlocks.where((b) => b['kind'] == 'figure').length != 13) {
    throw StateError('Complete source must contain all 13 figures');
  }
  for (final (query, id) in [
    ('corn emergence seedling coleoptile', 'clemson-growth-emergence'),
    ('corn vegetative visible leaf collars', 'clemson-growth-leaf-collars'),
    ('corn tasseling pollen VT', 'clemson-growth-tasseling'),
    ('corn R1 silking R2 blister', 'clemson-growth-silking-blister'),
    ('corn R3 milk R4 dough', 'clemson-growth-milk-dough'),
    ('corn R5 dent R6 black layer', 'clemson-growth-dent-maturity'),
  ]) {
    if (!rag
        .retrieve(query, forAi: true)
        .bounded()
        .results
        .any((r) => r.chunk.id == id)) {
      throw StateError('Missing whole-source stage section: $query');
    }
  }
  final prompt = rag
      .retrieve('leaf collars corn growth stage', forAi: true)
      .toPromptText();
  if (!prompt.contains('Available visual article ID: ${article.id}')) {
    throw StateError('Visuals not advertised to Advisor');
  }
  stdout.writeln(
    'Passed: broad guides with active-stage context, focused stages, trusted inline figures, copy text, 4 paraphrases, 6 source sections and all 13 assets. No AI calls.',
  );
}
