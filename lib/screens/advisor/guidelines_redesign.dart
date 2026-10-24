import 'package:flutter/material.dart';
import 'guideline_visual_gallery.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import '../../services/advisor/advisor_rag_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';

class AdvisorOfflineGuidesScreen extends StatefulWidget {
  const AdvisorOfflineGuidesScreen({super.key, this.initialArticleId});

  final String? initialArticleId;

  @override
  State<AdvisorOfflineGuidesScreen> createState() =>
      _AdvisorOfflineGuidesScreenState();
}

class _AdvisorOfflineGuidesScreenState
    extends State<AdvisorOfflineGuidesScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  final _rag = const AdvisorRagService();
  final List<String> _recentSearches = [];
  String _query = '';
  String? _submittedQuery;
  String? _selectedCategory;
  bool _useOriginalQuery = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    final articleId = widget.initialArticleId;
    if (articleId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final article = AdvisorRagService.chunks
            .where((chunk) => chunk.id == articleId)
            .firstOrNull;
        if (article != null) _openArticle(article);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _changeQuery(String value) {
    setState(() {
      _query = value;
      _submittedQuery = null;
      _selectedCategory = null;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _submittedQuery = null;
      _selectedCategory = null;
    });
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _submittedQuery = null;
      _selectedCategory = null;
      _useOriginalQuery = false;
    });
  }

  void _submitSearch([String? value]) {
    final query = (value ?? _searchController.text).trim();
    if (query.isEmpty) return;
    _searchController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _searchFocus.unfocus();
    setState(() {
      _query = query;
      _submittedQuery = query;
      _selectedCategory = null;
      _useOriginalQuery = false;
      _recentSearches
        ..remove(query)
        ..insert(0, query);
      if (_recentSearches.length > 4) _recentSearches.removeLast();
    });
  }

  List<AdvisorRetrievedChunk> _results(String query) {
    if (_rag.categories.contains(query)) {
      return _rag
          .byCategory(query)
          .map((chunk) => AdvisorRetrievedChunk(chunk: chunk, score: 1))
          .toList();
    }
    return _rag
        .retrieve(query, maxResults: AdvisorRagService.chunks.length)
        .results;
  }

  List<AdvisorKnowledgeChunk> get _suggestions {
    if (_query.trim().length < 2) return const [];
    return _results(_query).map((item) => item.chunk).take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _searchFocus.hasFocus && _submittedQuery == null;
    return Scaffold(
      key: const Key('advisor_offline_guides_screen'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: AppWords.of(
            context,
          ).translate(focused ? 'Close search' : 'Back'),
          onPressed: focused ? _closeSearch : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const AppText('Guidelines'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: CustomScrollView(
              key: const Key('advisor_guides_tab'),
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: _searchField()),
                ),
                if (focused)
                  _focusedSearch()
                else if (_submittedQuery != null)
                  _searchResults(_submittedQuery!)
                else
                  _home(),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxl),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Semantics(
      textField: true,
      label: 'Search guidelines',
      child: TextField(
        key: const Key('advisor_guide_search'),
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        onChanged: _changeQuery,
        onSubmitted: _submitSearch,
        decoration: InputDecoration(
          hintText: AppWords.of(context).translate('Search guidelines...'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: AppWords.of(context).translate('Clear search'),
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
    );
  }

  SliverPadding _home() {
    const recommendedIds = [
      'scouting-systematic',
      'identify-larva',
      'safety-pesticide',
    ];
    final recommended = recommendedIds
        .map(
          (id) => AdvisorRagService.chunks
              .where((item) => item.id == id)
              .firstOrNull,
        )
        .whereType<AdvisorKnowledgeChunk>();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        0,
      ),
      sliver: SliverList.list(
        children: [
          _SectionTitle(
            title: 'Browse by category',
            subtitle: '${AdvisorRagService.chunks.length} field references',
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent:
                  100 + MediaQuery.textScalerOf(context).scale(14) * 3.5,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
            ),
            itemCount: _rag.categories.length,
            itemBuilder: (context, index) {
              final category = _rag.categories[index];
              return _CategoryTile(
                category: category,
                count: _rag.byCategory(category).length,
                onTap: () {
                  _submitSearch(category);
                  setState(() => _selectedCategory = category);
                },
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle(title: 'Start here'),
          const SizedBox(height: AppSpacing.xs),
          for (final article in recommended)
            _GuidelineRow(
              article: article,
              query: '',
              onTap: () => _openArticle(article),
            ),
        ],
      ),
    );
  }

  SliverPadding _focusedSearch() {
    final suggestions = _suggestions;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        0,
      ),
      sliver: SliverList.list(
        children: [
          if (_query.trim().length >= 2) ...[
            const _SectionTitle(title: 'Suggestions'),
            const SizedBox(height: AppSpacing.xs),
            if (suggestions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: AppText(
                  'Keep typing or press Search to check every guideline.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final article in suggestions)
                ListTile(
                  minTileHeight: 52,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search, size: 21),
                  title: _HighlightedText(text: article.title, query: _query),
                  trailing: const Icon(Icons.north_west, size: 18),
                  onTap: () => _submitSearch(article.title),
                ),
          ] else ...[
            if (_recentSearches.isNotEmpty) ...[
              const _SectionTitle(title: 'Recent searches'),
              const SizedBox(height: AppSpacing.xs),
              for (final query in _recentSearches)
                ListTile(
                  minTileHeight: AppSizes.minimumTouchTarget,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, size: 21),
                  title: Text(query),
                  trailing: IconButton(
                    tooltip: 'Remove $query',
                    onPressed: () =>
                        setState(() => _recentSearches.remove(query)),
                    icon: const Icon(Icons.close, size: 19),
                  ),
                  onTap: () => _submitSearch(query),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const _SectionTitle(title: 'Related topics'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final category in _rag.categories)
                  ActionChip(
                    avatar: Icon(_categoryIcon(category), size: 18),
                    label: Text(AppWords.of(context).translate(category)),
                    onPressed: () => _submitSearch(category),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  SliverPadding _searchResults(String query) {
    final correction = _useOriginalQuery ? null : _correctedQuery(query);
    final effectiveQuery = correction ?? query;
    final allResults = _results(effectiveQuery);
    final filtered = _selectedCategory == null
        ? allResults
        : allResults
              .where((result) => result.chunk.category == _selectedCategory)
              .toList();
    final categories = allResults.map((item) => item.chunk.category).toSet();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      sliver: SliverList.list(
        children: [
          if (correction != null) ...[
            Text.rich(
              TextSpan(
                text: 'Showing results for ',
                style: const TextStyle(color: AppColors.textSecondary),
                children: [
                  TextSpan(
                    text: '“$correction”',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _useOriginalQuery = true),
                child: AppText('Search instead for “$query”'),
              ),
            ),
          ],
          AppText(
            '${allResults.length} ${allResults.length == 1 ? 'result' : 'results'} for “$effectiveQuery”',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (allResults.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const AppText('All'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                  for (final category in categories) ...[
                    const SizedBox(width: AppSpacing.xs),
                    ChoiceChip(
                      label: Text(AppWords.of(context).translate(category)),
                      selected: _selectedCategory == category,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (allResults.isEmpty)
            _NoResults(
              query: query,
              suggestion: _fallbackSuggestion(query),
              onSuggestion: _submitSearch,
              onClear: _clearSearch,
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Column(
                children: [
                  const Icon(Icons.filter_alt_off_outlined, size: 36),
                  const SizedBox(height: AppSpacing.md),
                  AppText(
                    'No results match this filter.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => setState(() => _selectedCategory = null),
                    child: const AppText('Clear filter'),
                  ),
                ],
              ),
            )
          else
            for (final result in filtered)
              _GuidelineRow(
                article: result.chunk,
                query: effectiveQuery,
                onTap: () => _openArticle(result.chunk),
              ),
        ],
      ),
    );
  }

  String? _correctedQuery(String query) => const {
    'protectve equipmnt': 'protective equipment',
    'protectve equipment': 'protective equipment',
    'fied inspection': 'field inspection',
    'catapillar': 'caterpillar',
  }[query.toLowerCase().trim()];

  String _fallbackSuggestion(String query) {
    final value = query.toLowerCase();
    if (value.contains('protect') || value.contains('ppe')) {
      return 'pesticide safety';
    }
    if (value.contains('field') || value.contains('inspect')) {
      return 'inspect maize plant';
    }
    return 'scouting protocol';
  }

  Future<void> _openArticle(AdvisorKnowledgeChunk article) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _GuidelineDetailScreen(article: article, rag: _rag),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppWords.of(context).translate(title),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            AppWords.of(context).translate(subtitle!),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });
  final String category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F8F2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFFDCE8DA)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_outward,
                    size: 17,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                AppWords.of(context).translate(category),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppWords.of(context).language == AppLanguage.filipino
                    ? '$count gabay'
                    : '$count ${count == 1 ? 'guideline' : 'guidelines'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidelineRow extends StatelessWidget {
  const _GuidelineRow({
    required this.article,
    required this.query,
    required this.onTap,
  });
  final AdvisorKnowledgeChunk article;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppWords.of(
                          context,
                        ).translate(_contentType(article)).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _HighlightedText(
                        text: article.title,
                        query: query,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      _HighlightedText(
                        text: _matchingExcerpt(article, query),
                        query: query,
                        maxLines: 3,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        AppWords.of(context).language == AppLanguage.filipino
                            ? '${_readMinutes(article)} minutong basahin · ${AppWords.of(context).translate(article.category)}'
                            : '${_readMinutes(article)} min read · ${article.category}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 22),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    this.style,
    this.maxLines,
  });
  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final displayText = AppWords.of(context).translate(text);
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.length > 2)
        .toList();
    if (terms.isEmpty) {
      return Text(
        displayText,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    final matcher = RegExp(
      '(${terms.map(RegExp.escape).join('|')})',
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    var start = 0;
    for (final match in matcher.allMatches(displayText)) {
      if (match.start > start) {
        spans.add(TextSpan(text: displayText.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: displayText.substring(match.start, match.end),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            backgroundColor: AppColors.primaryLight,
          ),
        ),
      );
      start = match.end;
    }
    if (start < displayText.length) {
      spans.add(TextSpan(text: displayText.substring(start)));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.query,
    required this.suggestion,
    required this.onSuggestion,
    required this.onClear,
  });
  final String query;
  final String suggestion;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 36, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          AppText(
            'No results for',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppText('“$query”', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          const AppText(
            'Check the spelling, try fewer words, or use a related topic.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppText('Did you mean “$suggestion”?'),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: () => onSuggestion(suggestion),
            child: AppText('Search “$suggestion”'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onClear,
            child: const AppText('Try another search'),
          ),
        ],
      ),
    );
  }
}

class _GuidelineDetailScreen extends StatefulWidget {
  const _GuidelineDetailScreen({required this.article, required this.rag});
  final AdvisorKnowledgeChunk article;
  final AdvisorRagService rag;

  @override
  State<_GuidelineDetailScreen> createState() => _GuidelineDetailScreenState();
}

class _GuidelineDetailScreenState extends State<_GuidelineDetailScreen> {
  final _overviewKey = GlobalKey();
  final _guidanceKey = GlobalKey();
  final _safetyKey = GlobalKey();
  final _sourcesKey = GlobalKey();

  Future<void> _goTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: AppMotion.standard,
        curve: Curves.easeOut,
        alignment: .08,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final related = article.relatedArticleIds
        .map(
          (id) => AdvisorRagService.chunks
              .where((item) => item.id == id)
              .firstOrNull,
        )
        .whereType<AdvisorKnowledgeChunk>()
        .take(4);
    final reviewed = article.reviewedOn == null
        ? 'Technical review pending'
        : 'Reviewed ${_monthYear(article.reviewedOn!)}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const BackButton(),
        title: const AppText('Guideline'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: SizedBox(
              width: double.infinity,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Column(
                        key: _overviewKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppWords.of(
                              context,
                            ).translate(_contentType(article)).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            AppWords.of(context).translate(article.title),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            AppWords.of(context).language ==
                                    AppLanguage.filipino
                                ? '${AppWords.of(context).translate(reviewed)} · ${_readMinutes(article)} minutong basahin'
                                : '$reviewed · ${_readMinutes(article)} min read',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ArticleSectionNavigation(
                      onOverview: () => _goTo(_overviewKey),
                      onGuidance: () => _goTo(_guidanceKey),
                      onSafety: () => _goTo(_safetyKey),
                      onSources: () => _goTo(_sourcesKey),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xxl,
                    ),
                    sliver: SliverList.list(
                      children: [
                        const _ArticleHeading('Overview'),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          AppWords.of(context).translate(article.readerSummary),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AppWords.of(context).translate(article.readerBody),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        SizedBox(key: _guidanceKey, height: AppSpacing.lg),
                        if (article.visuals.isNotEmpty)
                          GuidelineVisualGallery(article: article),
                        if (article.steps.isNotEmpty)
                          _NumberedSection(
                            title: 'Procedure',
                            items: article.steps,
                          ),
                        if (article.lookFor.isNotEmpty)
                          _BulletSection(
                            title: 'Look for',
                            items: article.lookFor,
                          ),
                        if (article.doNotAssume.isNotEmpty)
                          _BulletSection(
                            title: 'Do not assume',
                            items: article.doNotAssume,
                          ),
                        SizedBox(key: _safetyKey, height: AppSpacing.lg),
                        if (article.safetyWarnings.isNotEmpty)
                          _BulletSection(
                            title: 'Safety',
                            items: article.safetyWarnings,
                          ),
                        if (article.escalateWhen.isNotEmpty)
                          _BulletSection(
                            title: 'Ask for expert help when',
                            items: article.escalateWhen,
                          ),
                        if (article.warning != null)
                          _ImportantNote(text: article.warning!),
                        if (related.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const _ArticleHeading('Related guidelines'),
                          const SizedBox(height: AppSpacing.xs),
                          for (final item in related)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                AppWords.of(context).translate(item.title),
                              ),
                              subtitle: Text(
                                AppWords.of(context).translate(item.category),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => _GuidelineDetailScreen(
                                        article: item,
                                        rag: widget.rag,
                                      ),
                                    ),
                                  ),
                            ),
                        ],
                        SizedBox(key: _sourcesKey, height: AppSpacing.xl),
                        const _ArticleHeading('Sources / References'),
                        const SizedBox(height: AppSpacing.xs),
                        for (final id in article.sourceIds)
                          if (id != 'WORMWISE-PROTOCOL')
                            if (AdvisorRagService.sources[id]
                                case final source?)
                              _SourceRow(source: source),
                        const SizedBox(height: AppSpacing.lg),
                        AppText(
                          'Content version ${article.contentVersion} · ${article.jurisdiction}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const AppText(
                          'This guideline supports field screening and consistent scouting. It does not replace diagnosis, a current pesticide label, or qualified local advice.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleSectionNavigation extends StatelessWidget {
  const _ArticleSectionNavigation({
    required this.onOverview,
    required this.onGuidance,
    required this.onSafety,
    required this.onSources,
  });
  final VoidCallback onOverview;
  final VoidCallback onGuidance;
  final VoidCallback onSafety;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: AppColors.background,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              ActionChip(
                label: const AppText('Overview'),
                onPressed: onOverview,
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(
                label: const AppText('Guidance'),
                onPressed: onGuidance,
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(label: const AppText('Safety'), onPressed: onSafety),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(label: const AppText('Sources'), onPressed: onSources),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleHeading extends StatelessWidget {
  const _ArticleHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    AppWords.of(context).translate(text),
    style: Theme.of(context).textTheme.titleLarge,
  );
}

class _BulletSection extends StatelessWidget {
  const _BulletSection({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArticleHeading(title),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppWords.of(context).translate(item),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberedSection extends StatelessWidget {
  const _NumberedSection({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArticleHeading(title),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.highContrastGreen,
                    child: AppText(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppWords.of(context).translate(items[index]),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportantNote extends StatelessWidget {
  const _ImportantNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5DB),
        borderRadius: AppRadii.controlBorder,
        border: Border.all(color: const Color(0xFFE6C76B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF805B00)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText(
                  'Important',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(AppWords.of(context).translate(text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final AdvisorReferenceSource source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            source.hasVerifiedReference
                ? Icons.verified_outlined
                : Icons.library_books_outlined,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppWords.of(context).translate(source.label),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xxs),
                AppText(
                  '${source.jurisdiction}\n${source.locator ?? source.reference}\n${source.publicUrl ?? ''}\n${source.hasVerifiedReference ? 'Reference checked ${source.verifiedOn}' : 'Reference details awaiting verification'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(String category) => switch (category) {
  'Identification' => Icons.bug_report_outlined,
  'Scouting Protocol' => Icons.route_outlined,
  'Symptoms & Evidence' => Icons.manage_search_outlined,
  'Management' => Icons.handyman_outlined,
  'Safety' => Icons.shield_outlined,
  _ => Icons.support_agent_outlined,
};

String _contentType(AdvisorKnowledgeChunk article) =>
    switch (article.category) {
      'Scouting Protocol' => 'Procedure',
      'Safety' => 'Safety',
      'Management' => 'Management reference',
      'Expert Help' => 'Reporting',
      _ => 'Reference',
    };

int _readMinutes(AdvisorKnowledgeChunk article) {
  final words = [
    article.readerSummary,
    article.readerBody,
    ...article.steps,
    ...article.lookFor,
    ...article.safetyWarnings,
  ].join(' ').split(RegExp(r'\s+')).length;
  return (words / 180).ceil().clamp(2, 8).toInt();
}

String _matchingExcerpt(AdvisorKnowledgeChunk article, String query) {
  if (query.trim().isEmpty) return article.readerSummary;
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.length > 2);
  for (final sentence in article.readerBody.split(RegExp(r'(?<=[.!?])\s+'))) {
    final lower = sentence.toLowerCase();
    if (terms.any(lower.contains)) return sentence;
  }
  return article.readerSummary;
}

String _monthYear(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
