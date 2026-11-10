import 'package:flutter/material.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import '../../services/advisor/advisor_rag_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';

class AdvisorOfflineGuidesScreen extends StatelessWidget {
  const AdvisorOfflineGuidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('advisor_offline_guides_screen'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: AppWords.of(context).translate('Back'),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('FAW Guide', style: TextStyle(fontWeight: FontWeight.w800)),
            AppText(
              'Offline Cropwise reference',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: AdvisorOfflineGuidesTab(),
            ),
          ),
        ),
      ),
    );
  }
}

class AdvisorOfflineGuidesTab extends StatefulWidget {
  const AdvisorOfflineGuidesTab({super.key});

  @override
  State<AdvisorOfflineGuidesTab> createState() =>
      _AdvisorOfflineGuidesTabState();
}

class _AdvisorOfflineGuidesTabState extends State<AdvisorOfflineGuidesTab> {
  final _searchController = TextEditingController();
  final _rag = const AdvisorRagService();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.trim().isEmpty
        ? const <AdvisorRetrievedChunk>[]
        : _rag.retrieve(_query, maxResults: 8).results;
    return ListView(
      key: const Key('advisor_guides_tab'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        TextField(
          key: const Key('advisor_guide_search'),
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: AppWords.of(
              context,
            ).translate('Search topics, symptoms, or management'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: AppWords.of(context).translate('Clear search'),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: AppColors.surfaceCard,
            border: OutlineInputBorder(
              borderRadius: AppRadii.cardBorder,
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_query.trim().isNotEmpty)
          _buildSearchResults(results)
        else ...[
          _buildQuickStart(),
          const SizedBox(height: AppSpacing.lg),
          AppText(
            'Offline FAW guide',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppText(
            'Reviewed guidance for maize scouting and fall armyworm. Choose a topic to browse.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final category in _rag.categories)
            _CategoryCard(
              category: category,
              articles: _rag.byCategory(category),
              onArticleTap: _openArticle,
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4F8),
              borderRadius: AppRadii.cardBorder,
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off_outlined, color: Color(0xFF336B78)),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppText(
                    'These guides and their source notes remain available without internet.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickStart() {
    const items = [
      ('Inspect a plant', Icons.pest_control_outlined, 'inspect maize plant'),
      ('Recognize FAW', Icons.bug_report_outlined, 'recognize faw larva'),
      ('Understand frass', Icons.grain_outlined, 'frass fresh evidence'),
      ('Get expert help', Icons.support_agent_outlined, 'expert help'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          'Quick start',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 88,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              borderRadius: AppRadii.cardBorder,
              onTap: () {
                final result = _rag.retrieve(item.$3, maxResults: 1);
                if (result.results.isNotEmpty) {
                  _openArticle(result.results.first.chunk);
                }
              },
              child: Ink(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: index.isEven
                      ? AppColors.primaryLight
                      : const Color(0xFFF5F2E9),
                  borderRadius: AppRadii.cardBorder,
                ),
                child: Row(
                  children: [
                    Icon(item.$2, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppWords.of(context).translate(item.$1),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults(List<AdvisorRetrievedChunk> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppWords.of(context).translate(
            results.isEmpty ? 'No reviewed guide found' : 'Guide results',
          ),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (results.isEmpty)
          const AppText(
            'Try a symptom, “inspect a plant,” “frass,” “boundary,” or “expert help.”',
          )
        else
          for (final result in results)
            _ArticleResultTile(
              article: result.chunk,
              onTap: () => _openArticle(result.chunk),
            ),
      ],
    );
  }

  Future<void> _openArticle(AdvisorKnowledgeChunk article) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _GuideArticleSheet(article: article),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.articles,
    required this.onArticleTap,
  });

  final String category;
  final List<AdvisorKnowledgeChunk> articles;
  final ValueChanged<AdvisorKnowledgeChunk> onArticleTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category) {
      'Identification' => Icons.bug_report_outlined,
      'Scouting Protocol' => Icons.assignment_outlined,
      'Symptoms & Evidence' => Icons.manage_search_outlined,
      'Management' => Icons.health_and_safety_outlined,
      'Safety' => Icons.shield_outlined,
      _ => Icons.support_agent_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardBorder,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: AppRadii.controlBorder,
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppWords.of(context).translate(category),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  for (final article in articles)
                    InkWell(
                      onTap: () => onArticleTap(article),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                AppWords.of(context).translate(article.title),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleResultTile extends StatelessWidget {
  const _ArticleResultTile({required this.article, required this.onTap});

  final AdvisorKnowledgeChunk article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      child: ListTile(
        onTap: onTap,
        title: Text(AppWords.of(context).translate(article.title)),
        subtitle: AppText(
          '${AppWords.of(context).translate(article.category)} · ${AppWords.of(context).translate(article.summary)}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _GuideArticleSheet extends StatelessWidget {
  const _GuideArticleSheet({required this.article});

  final AdvisorKnowledgeChunk article;

  @override
  Widget build(BuildContext context) {
    final gradeLabel = switch (article.grade) {
      AdvisorEvidenceGrade.verifiedCore => 'Source-grounded',
      AdvisorEvidenceGrade.operationalRule => 'Cropwise protocol',
      AdvisorEvidenceGrade.expertValidationRequired =>
        'Expert validation required',
    };
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppWords.of(context).translate(article.category),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppWords.of(context).translate('Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            AppWords.of(context).translate(article.title),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(label: Text(AppWords.of(context).translate(gradeLabel))),
              if (!article.isPublishable)
                const Chip(label: AppText('Technical review pending')),
              const Chip(label: AppText('Maize · Philippines')),
              const Chip(label: Text(AdvisorRagService.knowledgeVersion)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppWords.of(context).translate(article.summary),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(AppWords.of(context).translate(article.body)),
          if (article.steps.isNotEmpty)
            _GuideListSection(title: 'Steps', items: article.steps),
          if (article.lookFor.isNotEmpty)
            _GuideListSection(title: 'Look for', items: article.lookFor),
          if (article.doNotAssume.isNotEmpty)
            _GuideListSection(
              title: 'Do not assume',
              items: article.doNotAssume,
            ),
          if (article.safetyWarnings.isNotEmpty)
            _GuideListSection(title: 'Safety', items: article.safetyWarnings),
          if (article.escalateWhen.isNotEmpty)
            _GuideListSection(
              title: 'Ask for expert help when',
              items: article.escalateWhen,
            ),
          if (article.warning != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5DB),
                borderRadius: AppRadii.cardBorder,
                border: Border.all(color: const Color(0xFFE6C76B)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFF805B00),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppWords.of(context).translate(article.warning!),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppText(
            'Sources',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final id in article.sourceIds)
            if (id != 'CROPWISE-PROTOCOL')
              _SourceTile(source: AdvisorRagService.sources[id]!),
          const SizedBox(height: AppSpacing.md),
          const AppText(
            'This guide supports field screening and consistent scouting. It does not replace diagnosis, a current pesticide label, or qualified local advice.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _GuideListSection extends StatelessWidget {
  const _GuideListSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppWords.of(context).translate(title),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(AppWords.of(context).translate(item))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final AdvisorReferenceSource source;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.verified_outlined, color: AppColors.primary),
      title: Text(AppWords.of(context).translate(source.label)),
      subtitle: AppText('${source.jurisdiction}\n${source.reference}'),
      isThreeLine: true,
    );
  }
}
