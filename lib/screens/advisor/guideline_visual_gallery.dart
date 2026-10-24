import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/advisor/advisor_rag_service.dart';
import 'clemson_growth_source_screen.dart';

Widget _referenceImage(AdvisorGuideVisual visual) =>
    visual.asset.endsWith('.svg')
    ? SvgPicture.asset(
        visual.asset,
        fit: BoxFit.contain,
        semanticsLabel: visual.caption,
      )
    : Image.asset(
        visual.asset,
        fit: BoxFit.contain,
        semanticLabel: visual.caption,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Reference image unavailable')),
      );

/// Offline educational illustrations, shared by Guidelines and Advisor replies.
class GuidelineVisualGallery extends StatefulWidget {
  const GuidelineVisualGallery({
    super.key,
    required this.article,
    this.onOpenArticle,
    this.compact = false,
    this.figureNumbers,
  });
  final AdvisorKnowledgeChunk article;
  final VoidCallback? onOpenArticle;
  final bool compact;
  final List<int>? figureNumbers;
  @override
  State<GuidelineVisualGallery> createState() => _GuidelineVisualGalleryState();
}

class _GuidelineVisualGalleryState extends State<GuidelineVisualGallery> {
  int _index = 0;
  final _pages = PageController();
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GuidelineVisualGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.id != widget.article.id ||
        oldWidget.figureNumbers?.join(',') != widget.figureNumbers?.join(',')) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(0);
      });
    }
  }

  void _jump(int index) => _pages.animateToPage(
    index,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );

  void _openImage(AdvisorGuideVisual visual) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF152019),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      visual.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close image',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(child: _referenceImage(visual)),
              ),
            ),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: widget.compact ? 120 : 180,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: widget.compact ? const Color(0xFF223329) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual.caption,
                      maxLines: widget.compact ? 2 : null,
                      overflow: widget.compact ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                        color: widget.compact ? Colors.white : null,
                      ),
                    ),
                    if (widget.compact && visual.credit != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          visual.credit!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (!widget.compact) FigureProvenance(visual: visual),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final visuals = widget.article.visuals
        .where(
          (v) =>
              widget.figureNumbers == null ||
              widget.figureNumbers!.contains(v.figureNumber),
        )
        .toList();
    if (visuals.isEmpty) return const SizedBox.shrink();
    if (widget.compact) return _compactGallery(visuals);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.article.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (visuals.length > 3)
              DropdownButton<int>(
                isExpanded: true,
                value: _index,
                items: [
                  for (var i = 0; i < visuals.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        visuals[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (i) {
                  if (i != null) _jump(i);
                },
              ),
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _pages,
                itemCount: visuals.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final visual = visuals[index];
                  return Semantics(
                    button: true,
                    label: 'Enlarge: ${visual.title}',
                    child: InkWell(
                      onTap: () => _openImage(visual),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(
                          color: const Color(0xFFF3F6F1),
                          child: _referenceImage(visual),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous image',
                  onPressed: _index > 0 ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_index + 1}/${visuals.length} · ${visuals[_index].title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Next image',
                  onPressed: _index < visuals.length - 1
                      ? () => _jump(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(visuals[_index].caption),
            FigureProvenance(visual: visuals[_index]),
            if (widget.article.sourceIds.contains('CLEMSON-GROWTH'))
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ClemsonGrowthSourceScreen(),
                  ),
                ),
                child: const Text('Read complete Clemson source'),
              ),
            if (widget.onOpenArticle != null)
              TextButton(
                onPressed: widget.onOpenArticle,
                child: const Text('Open full guide'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _compactGallery(List<AdvisorGuideVisual> visuals) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE6DC)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        SizedBox(
          height: 205,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: visuals.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    final visual = visuals[index];
                    return Semantics(
                      button: true,
                      label: 'Enlarge: ${visual.title}',
                      child: InkWell(
                        onTap: () => _openImage(visual),
                        child: ColoredBox(
                          color: const Color(0xFFF1F5EF),
                          child: _referenceImage(visual),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: const Color(0xDDFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.open_in_full_rounded, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              if (visuals.length > 1) ...[
                IconButton(
                  tooltip: 'Previous image',
                  visualDensity: VisualDensity.compact,
                  onPressed: _index > 0 ? () => _jump(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  visuals[_index].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (visuals.length > 1) ...[
                Text(
                  '${_index + 1}/${visuals.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5D6C60),
                  ),
                ),
                IconButton(
                  tooltip: 'Next image',
                  visualDensity: VisualDensity.compact,
                  onPressed: _index < visuals.length - 1
                      ? () => _jump(_index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                visuals[_index].caption,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (visuals[_index].credit != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Image credit: ${visuals[_index].credit}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              if (widget.onOpenArticle != null)
                TextButton(
                  onPressed: widget.onOpenArticle,
                  child: const Text('Open full guide'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class FigureProvenance extends StatelessWidget {
  const FigureProvenance({super.key, required this.visual});
  final AdvisorGuideVisual visual;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (visual.credit != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Image credit: ${visual.credit}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (visual.sourceUrl != null)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Image source'),
          children: [SelectableText(visual.sourceUrl!)],
        ),
    ],
  );
}
