import 'package:flutter/material.dart';
import '../../services/advisor/clemson_growth_reference.dart';
import '../../services/advisor/advisor_rag_service.dart';
import 'guideline_visual_gallery.dart';

/// Complete educational reprint, including original captions and references.
class ClemsonGrowthSourceScreen extends StatelessWidget {
  const ClemsonGrowthSourceScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Clemson source guide')),
    body: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: clemsonGrowthBlocks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: SelectableText(
              'Complete educational reprint • Clemson Extension, LGP 1170\nPublished June 16, 2023 • Source checked September 30, 2026\nhttps://lgpress.clemson.edu/publication/visual-guide-to-corn-growth-stages/\n\nOriginal US field-corn reference. Calendar and moisture estimates are source-specific; they are not a Philippine schedule.',
            ),
          );
        }
        final block = clemsonGrowthBlocks[index - 1];
        if (block['kind'] == 'figure') {
          final figure = clemsonGrowthFigures.firstWhere(
            (f) => f['number'] == block['figure'],
          );
          final visual = AdvisorGuideVisual(
            asset: figure['asset']!,
            title: figure['title']!,
            caption: figure['caption']!,
            credit: figure['credit'],
            sourceUrl: figure['sourceUrl'],
          );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: Semantics(
                    button: true,
                    label: 'Enlarge ${visual.title}',
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => Dialog(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Align(
                                  alignment: Alignment.topRight,
                                  child: IconButton(
                                    tooltip: 'Close',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * .55,
                                  width: double.infinity,
                                  child: InteractiveViewer(
                                    minScale: 1,
                                    maxScale: 5,
                                    child: Image.asset(
                                      visual.asset,
                                      fit: BoxFit.contain,
                                      semanticLabel: visual.title,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(visual.caption),
                                      FigureProvenance(visual: visual),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      child: Image.asset(
                        visual.asset,
                        fit: BoxFit.contain,
                        semanticLabel: visual.title,
                      ),
                    ),
                  ),
                ),
                Text(visual.caption),
                FigureProvenance(visual: visual),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SelectableText(
            block['text']!,
            style: block['kind'] == 'heading'
                ? Theme.of(context).textTheme.titleLarge
                : Theme.of(context).textTheme.bodyLarge,
          ),
        );
      },
    ),
  );
}
