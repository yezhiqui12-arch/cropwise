import 'package:flutter/material.dart';

import '../data/help/help_content.dart';
import '../localization/app_language.dart';
import '../theme/app_colors.dart';
import 'advisor/advisor_screen.dart';
import 'advisor/guidelines_redesign.dart';
import 'artificial_intelligence_screen.dart';
import 'assess/assessments_screen.dart';
import 'boundary_map_screen.dart';
import 'field_trends_screen.dart';
import 'fields_screen.dart';
import 'language_screen.dart';
import 'models_screen.dart';
import 'my_profile_screen.dart';
import 'notifications_screen.dart';

const _ink = Color(0xFF233D2E);
const _muted = Color(0xFF607368);
const _green = Color(0xFF2D6447);
const _line = Color(0xFFDDE7E0);

bool _filipino(BuildContext context) =>
    AppWords.of(context).language == AppLanguage.filipino;
String _label(BuildContext context, String en, String fil) =>
    _filipino(context) ? fil : en;
String _copy(BuildContext context, HelpCopy value) =>
    value.inLanguage(_filipino(context));

IconData _topicIcon(String topic) => switch (topic) {
  'start' => Icons.explore_outlined,
  'fields' => Icons.landscape_outlined,
  'assess' => Icons.checklist_rounded,
  'photos' => Icons.camera_alt_outlined,
  'results' => Icons.assignment_outlined,
  'maps' => Icons.map_outlined,
  'expert' => Icons.forum_outlined,
  'advisor' => Icons.menu_book_outlined,
  'account' => Icons.cloud_done_outlined,
  'preferences' => Icons.tune_rounded,
  'trouble' => Icons.build_outlined,
  _ => Icons.verified_user_outlined,
};

void _openArticle(BuildContext context, HelpArticle article) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HelpArticleScreen(article: article),
      ),
    );

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, this.initialTopic});
  final String? initialTopic;
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _search = TextEditingController();
  String? _topic;
  bool _questions = false;

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final articles = searchHelp(query, topic: _topic);
    final browsing = query.isEmpty && _topic == null;
    final questions = helpQuestionLinks.where((q) {
      final article = helpArticleById(q.articleId);
      if (_topic != null && article.topic != _topic) return false;
      return articles.contains(article);
    }).toList();
    return Scaffold(
      key: const Key('help_support_screen'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_label(context, 'Help & Support', 'Tulong at Suporta')),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _intro(context),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('help_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _label(
                      context,
                      'Search help',
                      'Maghanap ng tulong',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _label(
                              context,
                              'Clear search',
                              'Burahin ang hinahanap',
                            ),
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _line),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(_label(context, 'Guides', 'Mga gabay')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.question_answer_outlined),
                      label: Text(_label(context, 'Questions', 'Mga tanong')),
                    ),
                  ],
                  selected: {_questions},
                  onSelectionChanged: (selected) =>
                      setState(() => _questions = selected.single),
                ),
                if (browsing && !_questions) ...[
                  const SizedBox(height: 18),
                  _featured(context),
                  _heading(
                    _label(context, 'Browse by topic', 'Pumili ng paksa'),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const columns = 2;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 12) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final topic in helpTopics)
                            SizedBox(
                              width: width,
                              child: _topicCard(context, topic),
                            ),
                        ],
                      );
                    },
                  ),
                  _heading(
                    _label(context, 'Common questions', 'Karaniwang tanong'),
                  ),
                  for (final id in [
                    'cannot-start',
                    'resume',
                    'measurements',
                    'backup',
                  ])
                    _articleTile(context, helpArticleById(id)),
                ] else ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: Text(
                            _label(context, 'All topics', 'Lahat ng paksa'),
                          ),
                          selected: _topic == null,
                          onSelected: (_) => setState(() => _topic = null),
                        ),
                        for (final topic in helpTopics) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(_copy(context, topic.title)),
                            selected: _topic == topic.id,
                            onSelected: (value) => setState(
                              () => _topic = value ? topic.id : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _heading(
                    _questions
                        ? _label(
                            context,
                            '${questions.length} questions',
                            '${questions.length} tanong',
                          )
                        : _label(
                            context,
                            '${articles.length} guides',
                            '${articles.length} gabay',
                          ),
                  ),
                  if ((_questions ? questions.isEmpty : articles.isEmpty))
                    _empty(context)
                  else if (_questions)
                    for (final question in questions)
                      _articleTile(
                        context,
                        helpArticleById(question.articleId),
                        title: _copy(context, question.question),
                      )
                  else
                    for (final article in articles)
                      _articleTile(context, article),
                ],
                const SizedBox(height: 24),
                _panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(
                            context,
                            'Still need help?',
                            'Kailangan pa ng tulong?',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _label(
                            context,
                            'Get the details you need to report an app problem.',
                            'Ihanda ang mga detalye para iulat ang problema sa app.',
                          ),
                          style: const TextStyle(height: 1.5, color: _muted),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openArticle(
                            context,
                            helpArticleById('report-problem'),
                          ),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: Text(
                            _label(
                              context,
                              'Prepare a problem report',
                              'Ihanda ang ulat ng problema',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.offline_pin_outlined, size: 16, color: _green),
          const SizedBox(width: 6),
          Text(
            _label(context, 'AVAILABLE OFFLINE', 'MABABASA KAHIT OFFLINE'),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: _green,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _label(context, 'How can we help?', 'Paano kami makakatulong?'),
        style: const TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
    ],
  );

  Widget _featured(BuildContext context) => Material(
    color: const Color(0xFFEAF3EC),
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const Key('help_first_assessment'),
      onTap: () => _openArticle(context, helpArticleById('first-assessment')),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _icon(Icons.route_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(
                      context,
                      'YOUR FIRST ASSESSMENT',
                      'ANG UNANG ASSESSMENT',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _label(
                      context,
                      'From field setup to saved results',
                      'Mula paghahanda hanggang sa resulta',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: _green, size: 20),
          ],
        ),
      ),
    ),
  );

  Widget _topicCard(BuildContext context, HelpTopic topic) => _panel(
    child: InkWell(
      onTap: () => setState(() => _topic = topic.id),
      child: SizedBox(
        height: 114,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _icon(_topicIcon(topic.id)),
                  const Icon(
                    Icons.arrow_outward_rounded,
                    color: _green,
                    size: 18,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                _copy(context, topic.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _empty(BuildContext context) => _panel(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, color: _muted, size: 32),
          const SizedBox(height: 12),
          Text(
            _label(context, 'No matching help yet', 'Walang tumugmang gabay'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _label(
              context,
              'Try a shorter phrase, English or Filipino, or browse all topics.',
              'Subukan ang mas maikling salita, English o Filipino, o tingnan ang lahat ng paksa.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5, color: _muted),
          ),
          TextButton(
            onPressed: () => setState(() {
              _search.clear();
              _topic = null;
            }),
            child: Text(
              _label(
                context,
                'Reset search and filters',
                'I-reset ang paghahanap at filter',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _panel({required Widget child}) => Material(
  color: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: _line),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget _icon(IconData icon) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: const Color(0xFFEDF4EF),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Icon(icon, size: 22, color: _green),
);

Widget _heading(String title) => Padding(
  padding: const EdgeInsets.only(top: 24, bottom: 12),
  child: Text(
    title,
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
  ),
);

Widget _articleTile(
  BuildContext context,
  HelpArticle article, {
  String? title,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: _panel(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(
        title ?? _copy(context, article.title),
        style: const TextStyle(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _copy(context, article.summary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, height: 1.45, color: _muted),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
      onTap: () => _openArticle(context, article),
    ),
  ),
);

class _HelpArticleScreen extends StatelessWidget {
  const _HelpArticleScreen({required this.article});
  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final topic = helpTopics.firstWhere((t) => t.id == article.topic);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_copy(context, topic.title))),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                children: [
                  Text(
                    _copy(context, article.title),
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _copy(context, article.summary),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _panel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(
                              context,
                              'WHERE TO FIND IT',
                              'SAAN ITO MAKIKITA',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w700,
                              color: _green,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            _copy(context, article.location),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: _ink,
                            ),
                          ),
                          if (article.destination != null) ...[
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () => _openDestination(
                                context,
                                article.destination!,
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _destinationLabel(
                                  context,
                                  article.destination!,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _heading(
                    _label(
                      context,
                      'Follow these steps',
                      'Sundin ang mga hakbang',
                    ),
                  ),
                  _panel(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          for (var i = 0; i < article.steps.length; i++) ...[
                            if (i > 0) const Divider(height: 1, color: _line),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    label: _label(
                                      context,
                                      'Step ${i + 1}',
                                      'Hakbang ${i + 1}',
                                    ),
                                    child: ExcludeSemantics(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE5EFE8),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: _green,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _copy(context, article.steps[i]),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3EC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(context, 'What to expect', 'Ano ang aasahan'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: _green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _copy(context, article.outcome),
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (article.questions.isNotEmpty) ...[
                    _heading(
                      _label(
                        context,
                        'You might also ask',
                        'Maaari mo ring itanong',
                      ),
                    ),
                    for (final question in article.questions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _panel(
                          child: ExpansionTile(
                            title: Text(
                              _copy(context, question.question),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              18,
                            ),
                            expandedAlignment: Alignment.centerLeft,
                            children: [
                              Text(
                                _copy(context, question.answer),
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (article.related.isNotEmpty) ...[
                    _heading(
                      _label(
                        context,
                        'Continue reading',
                        'Iba pang kaugnay na gabay',
                      ),
                    ),
                    for (final id in article.related)
                      _articleTile(context, helpArticleById(id)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _destinationLabel(BuildContext context, HelpDestination destination) {
  final title = switch (destination) {
    HelpDestination.fields => 'My Fields|My Fields',
    HelpDestination.assessments => 'Assessments|Mga assessment',
    HelpDestination.map => 'Map|Mapa',
    HelpDestination.advisor => 'Advisor|Advisor',
    HelpDestination.profile => 'My Profile|My Profile',
    HelpDestination.language => 'Language|Wika',
    HelpDestination.models => 'Models|Mga modelo',
    HelpDestination.ai => 'Artificial Intelligence|Artificial Intelligence',
    HelpDestination.guidelines => 'Guidelines|Guidelines',
    HelpDestination.trends => 'Field trends|Field trends',
    HelpDestination.notifications => 'Notifications|Mga abiso',
  };
  return _label(
    context,
    'Open ${HelpCopy(title).english}',
    'Buksan ang ${HelpCopy(title).filipino}',
  );
}

void _openDestination(BuildContext context, HelpDestination destination) {
  final Widget screen = switch (destination) {
    HelpDestination.fields => const FieldsScreen(),
    HelpDestination.assessments => const AssessmentsScreen(),
    HelpDestination.map => const BoundaryMapScreen(),
    HelpDestination.advisor => const AdvisorScreen(),
    HelpDestination.profile => const MyProfileScreen(),
    HelpDestination.language => const LanguageScreen(),
    HelpDestination.models => const ModelsScreen(),
    HelpDestination.ai => const ArtificialIntelligenceScreen(),
    HelpDestination.guidelines => const AdvisorOfflineGuidesScreen(),
    HelpDestination.trends => const FieldTrendsScreen(),
    HelpDestination.notifications => NotificationsScreen(
      onOpenAssess: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AssessmentsScreen()),
      ),
    ),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
