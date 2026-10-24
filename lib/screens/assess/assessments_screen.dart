import 'package:flutter/material.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../models/assessment_history_models.dart';
import '../../providers/assessment_history_provider.dart';
import '../../providers/assessment_workspace_provider.dart';
import '../../providers/field_workspace_provider.dart';
import '../../services/cloud/expert_review_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../assessment_setup_screen.dart';
import '../expert_review_screen.dart';
import 'assessment_details_screen.dart';
import 'assessment_results_screen.dart';
import 'assessment_resume_screen.dart';
import 'assessment_status_badge.dart';

class AssessmentsScreen extends StatefulWidget {
  const AssessmentsScreen({super.key, this.onNewAssessment});

  final VoidCallback? onNewAssessment;

  @override
  State<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends State<AssessmentsScreen> {
  AssessmentHistoryProvider? _history;
  AssessmentHistoryRepository? _repository;
  late Stream<List<FieldRecord>> _fields;
  late Stream<Set<String>> _recordedStatuses;
  bool _initialFieldSet = false;
  String? _lastActiveFieldId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_history == null) {
      final repository = AssessmentHistoryRepository(
        context.read<AppDatabase>(),
      );
      _repository = repository;
      _history = AssessmentHistoryProvider(repository);
      _fields = repository.watchFields();
      _recordedStatuses = repository.watchRecordedStatuses();
    }
    final workspace = context.watch<FieldWorkspaceProvider>();
    if (!_initialFieldSet && !workspace.isLoading) {
      _initialFieldSet = true;
      _history!.filter(field: workspace.activeFieldId, state: null);
      _lastActiveFieldId = workspace.activeFieldId;
    } else if (!workspace.isLoading &&
        workspace.activeFieldId != _lastActiveFieldId) {
      final followedPreviousActiveField =
          _history!.fieldId == _lastActiveFieldId;
      _lastActiveFieldId = workspace.activeFieldId;
      if (followedPreviousActiveField) {
        _history!.filter(
          field: workspace.activeFieldId,
          state: _history!.status,
        );
      }
    }
  }

  @override
  void dispose() {
    _history?.dispose();
    super.dispose();
  }

  Future<void> _openRecord(AssessmentHistoryEntry record) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => record.status == DatabaseCodes.completed
              ? AssessmentResultsScreen(assessmentId: record.id)
              : AssessmentDetailsScreen(assessmentId: record.id),
        ),
      );

  Future<void> _resume(String id) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => AssessmentResumeScreen(assessmentId: id)),
  );

  Future<void> _startAssessment() async {
    if (widget.onNewAssessment != null) {
      widget.onNewAssessment!();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AssessmentSetupScreen()),
    );
    if (mounted) _history?.reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: const AppText('Assess'),
      actions: [
        Consumer<ExpertReviewService>(
          builder: (context, reviews, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('assess_expert_messages_button'),
                tooltip: AppWords.of(context).translate('Expert messages'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpertReviewScreen()),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
              if (reviews.unreadCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC62828),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      reviews.unreadCount > 9 ? '9+' : '${reviews.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.workflowMaxWidth,
          ),
          child: ListenableBuilder(
            listenable: _history!,
            builder: (context, _) {
              final history = _history!;
              final assessmentWorkspace = context
                  .watch<AssessmentWorkspaceProvider>();
              final openAssessment = assessmentWorkspace.currentAssessment;
              final active = history.entries
                  .where(
                    (record) =>
                        record.id == openAssessment?.id &&
                        assessmentResumeLabel(record.status) != null,
                  )
                  .firstOrNull;
              final recent = active != null && history.status == null
                  ? history.entries
                        .where((record) => record.id != active.id)
                        .toList(growable: false)
                  : history.entries;

              return CustomScrollView(
                key: const PageStorageKey('assessment_history_scroll'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldSelector(fields: _fields, history: history),
                          const SizedBox(height: 12),
                          if (assessmentWorkspace.isLoading)
                            const _AssessmentStateLoadingCard()
                          else if (openAssessment == null)
                            _AssessmentSetupCard(onStart: _startAssessment)
                          else if (active != null)
                            _ActiveAssessmentCard(
                              repository: _repository!,
                              record: active,
                              onResume: () => _resume(active.id),
                              onOpen: () => _openRecord(active),
                            )
                          else
                            _OngoingAssessmentCard(
                              fieldName:
                                  assessmentWorkspace
                                      .fieldWorkspace
                                      ?.field
                                      .name ??
                                  'Selected field',
                              onResume: () => _resume(openAssessment.id),
                            ),
                          const SizedBox(height: 12),
                          StreamBuilder<Set<String>>(
                            stream: _recordedStatuses,
                            builder: (context, snapshot) => _StatusFilters(
                              history: history,
                              recordedStatuses: snapshot.data ?? const {},
                            ),
                          ),
                          if (!history.loading &&
                              history.error == null &&
                              recent.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    active != null && history.status == null
                                        ? 'Recent assessments'
                                        : 'Assessment records',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                AppText(
                                  '${recent.length} saved',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (history.loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (history.error != null)
                    SliverToBoxAdapter(
                      child: _HistoryMessage(
                        title: 'Could not load assessments',
                        message: 'Your saved records have not been changed.',
                        action: TextButton(
                          onPressed: history.reload,
                          child: const AppText('Try again'),
                        ),
                      ),
                    )
                  else if (history.entries.isEmpty)
                    SliverToBoxAdapter(
                      child: _HistoryMessage(
                        title: history.status != null
                            ? 'No matching assessments'
                            : 'No assessments saved here yet',
                        message: history.status != null
                            ? 'Choose another status or field to see more records.'
                            : 'Set up an assessment above. Saved work and completed results will appear here.',
                        action: TextButton(
                          onPressed: () =>
                              history.filter(field: null, state: null),
                          child: const AppText('Show all fields and statuses'),
                        ),
                      ),
                    )
                  else if (recent.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: recent.length,
                        itemBuilder: (context, index) {
                          final record = recent[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AssessmentCard(
                              record: record,
                              onOpen: () => _openRecord(record),
                              onResume: () => _resume(record.id),
                            ),
                          );
                        },
                      ),
                    ),
                  if (history.canLoadMore && !history.loading)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: history.loadMore,
                          child: const AppText('Load more records'),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _AssessmentSetupCard extends StatelessWidget {
  const _AssessmentSetupCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: AppRadii.prominentBorder,
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_add, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'Start a field assessment',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    'Choose the field, confirm its maize area, and review the sampling workload.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('new_assessment_from_assess'),
            onPressed: onStart,
            icon: const Icon(Icons.tune),
            label: const AppText('Set up assessment'),
          ),
        ),
      ],
    ),
  );
}

class _AssessmentStateLoadingCard extends StatelessWidget {
  const _AssessmentStateLoadingCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 86,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: AppRadii.prominentBorder,
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: const SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    ),
  );
}

class _OngoingAssessmentCard extends StatelessWidget {
  const _OngoingAssessmentCard({
    required this.fieldName,
    required this.onResume,
  });

  final String fieldName;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF9E8),
      borderRadius: AppRadii.prominentBorder,
      border: Border.all(color: const Color(0xFFE9D99B)),
      boxShadow: AppColors.cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFE7A900),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pending_actions_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'Assessment in progress',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fieldName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('continue_assessment_from_assess'),
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const AppText('Continue assessment'),
          ),
        ),
      ],
    ),
  );
}

class _ActiveAssessmentCard extends StatefulWidget {
  const _ActiveAssessmentCard({
    required this.repository,
    required this.record,
    required this.onResume,
    required this.onOpen,
  });

  final AssessmentHistoryRepository repository;
  final AssessmentHistoryEntry record;
  final VoidCallback onResume;
  final VoidCallback onOpen;

  @override
  State<_ActiveAssessmentCard> createState() => _ActiveAssessmentCardState();
}

class _ActiveAssessmentCardState extends State<_ActiveAssessmentCard> {
  late Stream<AssessmentHistoryDetail?> _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.repository.watchDetail(widget.record.id);
  }

  @override
  void didUpdateWidget(covariant _ActiveAssessmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.id != widget.record.id ||
        oldWidget.repository != widget.repository) {
      _detail = widget.repository.watchDetail(widget.record.id);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AssessmentHistoryDetail?>(
    stream: _detail,
    builder: (context, snapshot) => _ResumeAssessmentCard(
      record: widget.record,
      detail: snapshot.data,
      onResume: widget.onResume,
      onOpen: widget.onOpen,
    ),
  );
}

class _FieldSelector extends StatelessWidget {
  const _FieldSelector({required this.fields, required this.history});

  final Stream<List<FieldRecord>> fields;
  final AssessmentHistoryProvider history;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<FieldRecord>>(
    stream: fields,
    builder: (context, snapshot) {
      final records = snapshot.data ?? const [];
      final options = {for (final field in records) field.id: field.name};
      if (history.fieldId != null && !options.containsKey(history.fieldId)) {
        options[history.fieldId!] = 'Selected field unavailable';
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('history-field-${history.fieldId}'),
        initialValue: history.fieldId ?? '',
        isExpanded: true,
        menuMaxHeight: 340,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.agriculture_outlined),
          helperText: snapshot.hasError
              ? AppWords.of(context).translate(
                  'Could not load field options. Reopen Assess to retry.',
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: AppColors.cardBorder),
          ),
        ),
        items: [
          const DropdownMenuItem(value: '', child: AppText('All fields')),
          for (final entry in options.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => history.filter(
          field: value == '' ? null : value,
          state: history.status,
        ),
      );
    },
  );
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.history, required this.recordedStatuses});

  final AssessmentHistoryProvider history;
  final Set<String> recordedStatuses;

  static const filters = <String, String>{
    '': 'All',
    'in_progress': 'In progress',
    'completed': 'Completed',
    'draft': 'Drafts',
    'safety_blocked': 'Safety review',
    'incomplete': 'Incomplete',
    'cancelled': 'Cancelled',
    'invalid': 'Invalid',
  };

  @override
  Widget build(BuildContext context) {
    // Keep active workflow filters. Legacy-only statuses remain accessible if
    // stored history uses them, even beyond the current page or selected field.
    final visibleFilters = filters.entries
        .where(
          (filter) =>
              !const {'cancelled', 'invalid'}.contains(filter.key) ||
              recordedStatuses.contains(filter.key) ||
              history.status == filter.key,
        )
        .toList(growable: false);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visibleFilters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = visibleFilters[index];
          final selected = (history.status ?? '') == filter.key;
          return ChoiceChip(
            label: AppText(filter.value),
            selected: selected,
            showCheckmark: false,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.cardBorder,
            ),
            selectedColor: AppColors.primary,
            labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => history.filter(
              field: history.fieldId,
              state: filter.key.isEmpty ? null : filter.key,
            ),
          );
        },
      ),
    );
  }
}

class _ResumeAssessmentCard extends StatelessWidget {
  const _ResumeAssessmentCard({
    required this.record,
    required this.detail,
    required this.onResume,
    required this.onOpen,
  });

  final AssessmentHistoryEntry record;
  final AssessmentHistoryDetail? detail;
  final VoidCallback onResume;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final totalStations =
        detail?.expectedStationCount ??
        (record.blocks == 0 ? 5 : record.blocks * 5);
    final recordedStations = detail?.currentReviewedStationCount ?? 0;
    final progress = totalStations == 0
        ? 0.0
        : recordedStations / totalStations;
    final percent = (progress * 100).round();
    final pending = <({IconData icon, String text})>[
      if (recordedStations < totalStations)
        (
          icon: Icons.fact_check_outlined,
          text: '${totalStations - recordedStations} station reviews remaining',
        ),
      if (detail != null && detail!.requiredWorkAreaCount > 0)
        (
          icon: Icons.checklist_rounded,
          text:
              '${detail!.requiredWorkAreaCount} ${detail!.requiredWorkAreaCount == 1 ? 'area needs' : 'areas need'} attention',
        ),
      if (record.photos == 0)
        (
          icon: Icons.photo_camera_outlined,
          text: 'Photo evidence not yet saved',
        ),
      if (record.plants == 0 && record.positions == 0)
        (icon: Icons.assignment_outlined, text: 'Field observations not yet saved'),
    ];

    return Container(
      key: const Key('active_assessment_option_b_card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5E8),
        borderRadius: AppRadii.prominentBorder,
        border: Border.all(color: const Color(0xFFEAE4CA)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Stack(
        children: [
          // Aerial corn field background photo
          Positioned.fill(
            child: Image.asset(
              'assets/images/resume_field_aerial.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          // Gradient scrim for optimal text contrast and readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF8F5E8).withValues(alpha: 0.90),
                    const Color(0xFFF8F5E8).withValues(alpha: 0.82),
                    const Color(0xFFF2ECE0).withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          // Card content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'PICK UP WHERE YOU LEFT OFF',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.highContrastGreen,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.fieldName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          AssessmentStatusBadge(status: record.status),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ProgressRing(progress: progress, percent: percent),
                  ],
                ),
                const SizedBox(height: 8),
                AppText(
                  '$recordedStations of $totalStations station reviews current',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final item in pending.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFE9A8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.icon,
                              size: 16,
                              color: const Color(0xFF9A6500),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text(item.text)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _GradientAction(
                        label: assessmentResumeLabel(record.status)!,
                        onPressed: onResume,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('active_assessment_details_button'),
                      tooltip: AppWords.of(
                        context,
                      ).translate('View assessment details'),
                      onPressed: onOpen,
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.percent});

  final double progress;
  final int percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    height: 70,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 7,
            backgroundColor: const Color(0xFFDDE2D8),
            color: AppColors.primary,
            strokeCap: StrokeCap.round,
          ),
        ),
        AppText(
          '$percent%',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _GradientAction extends StatelessWidget {
  const _GradientAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0F5F2C), Color(0xFF277540)],
      ),
      borderRadius: AppRadii.controlBorder,
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(AppSizes.primaryActionHeight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 19),
        ],
      ),
    ),
  );
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.record,
    required this.onOpen,
    required this.onResume,
  });

  final AssessmentHistoryEntry record;
  final VoidCallback onOpen;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final action = assessmentResumeLabel(record.status);
    final totalStations = record.blocks == 0 ? 5 : record.blocks * 5;
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: AppRadii.cardBorder,
      child: InkWell(
        key: ValueKey('assessment-card-${record.id}'),
        onTap: onOpen,
        borderRadius: AppRadii.cardBorder,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardBorder,
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  _stageImage(record.growthStage),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fieldName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          DateFormat.yMMMd().format(record.date.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        AssessmentStatusBadge(
                          status: record.status,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      record.blocks == 0
                          ? 'Sampling not started'
                          : '{stations} of {total} station records · {photos} photos',
                      arguments: {
                        'stations': record.stations,
                        'total': totalStations,
                        'photos': record.photos,
                      },
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (action != null)
                      TextButton(
                        onPressed: onResume,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.only(right: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: AppText(action),
                      )
                    else
                      TextButton(
                        onPressed: onOpen,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.only(right: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          record.status == DatabaseCodes.completed
                              ? 'View results'
                              : 'View details',
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.assignment_outlined,
            size: 30,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AppText(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        action,
      ],
    ),
  );
}

String _stageImage(String growthStage) => switch (growthStage) {
  've' || 'v1' || 'v2' => 'assets/images/growth_stages/maize_emergence.jpg',
  'v3_v6' => 'assets/images/growth_stages/maize_young_vegetative.jpg',
  'v7_v12' => 'assets/images/growth_stages/maize_tall_vegetative.jpg',
  'vt_r2' => 'assets/images/growth_stages/maize_silks.jpg',
  'r3_r6' => 'assets/images/growth_stages/maize_mature_kernels.jpg',
  _ => 'assets/images/growth_stages/maize_young_vegetative.jpg',
};
