import 'dart:async';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/cloud/expert_review_service.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../services/advisor/advisor_assessment_contract.dart';
import '../../services/advisor/assessment_result_ai_context.dart';
import '../../services/advisor/advisor_gemini_settings.dart';
import '../../services/advisor/advisor_open_chat_service.dart';
import '../../services/advisor/gemini_advisor_open_chat_service.dart';
import '../advisor/advisor_screen.dart';

class AssessmentAssistantPreview {
  const AssessmentAssistantPreview({
    required this.latestQuestion,
    required this.latestResponse,
  });

  final String latestQuestion;
  final String latestResponse;

  bool get hasConversation => latestQuestion.trim().isNotEmpty;
}

String _assessmentAssistantPreferenceKey(String assessmentId) =>
    'assessment_assistant_thread_$assessmentId';

Future<AssessmentAssistantPreview?> loadAssessmentAssistantPreview(
  AppDatabase database,
  String assessmentId,
) async {
  try {
    final row =
        await (database.select(database.appPreferences)..where(
              (tbl) => tbl.preferenceKey.equals(
                _assessmentAssistantPreferenceKey(assessmentId),
              ),
            ))
            .getSingleOrNull();
    if (row == null || row.preferenceValue.trim().isEmpty) return null;

    final messages = _decodeConversation(row.preferenceValue);
    String? latestQuestion;
    String latestResponse = '';
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (latestResponse.isEmpty &&
          message.role == _AssessmentChatRole.assistant) {
        latestResponse = message.text;
      }
      if (message.role == _AssessmentChatRole.user) {
        latestQuestion = message.text;
        break;
      }
    }
    if (latestQuestion == null || latestQuestion.trim().isEmpty) return null;
    return AssessmentAssistantPreview(
      latestQuestion: latestQuestion,
      latestResponse: latestResponse,
    );
  } catch (_) {
    return null;
  }
}

class AssessmentAssistantScreen extends StatefulWidget {
  const AssessmentAssistantScreen({
    super.key,
    required this.database,
    required this.assessmentId,
    required this.fieldName,
    required this.assessmentContext,
    this.initialQuestion,
    this.geminiSettingsStore,
    this.openChatService,
    this.advisorBuilder,
  });

  final AppDatabase database;
  final String assessmentId;
  final String fieldName;
  final String assessmentContext;
  final String? initialQuestion;
  final AdvisorGeminiSettingsStore? geminiSettingsStore;
  final AdvisorOpenChatService? openChatService;
  final Widget Function(String question)? advisorBuilder;

  @override
  State<AssessmentAssistantScreen> createState() =>
      _AssessmentAssistantScreenState();
}

class _AssessmentAssistantScreenState extends State<AssessmentAssistantScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AssessmentChatMessage> _messages = [];

  bool _loadingThread = true;
  bool _sending = false;
  int? _animatedReplyIndex;
  String? _error;

  AdvisorGeminiSettingsStore get _settingsStore =>
      widget.geminiSettingsStore ?? const SecureAdvisorGeminiSettingsStore();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreThread());
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreThread() async {
    try {
      final row =
          await (widget.database.select(widget.database.appPreferences)..where(
                (tbl) => tbl.preferenceKey.equals(
                  _assessmentAssistantPreferenceKey(widget.assessmentId),
                ),
              ))
              .getSingleOrNull();
      if (row != null && row.preferenceValue.trim().isNotEmpty) {
        _messages.addAll(_decodeConversation(row.preferenceValue));
      }
    } catch (_) {
      // A conversation failure must not make the assessment results unusable.
    }
    if (!mounted) return;
    setState(() => _loadingThread = false);
    _scrollToBottom(immediate: true);
    final initialQuestion = widget.initialQuestion?.trim();
    if (initialQuestion != null && initialQuestion.isNotEmpty) {
      _composer.text = initialQuestion;
      unawaited(_send());
    }
  }

  Future<void> _persistThread() async {
    final capped = _messages.length <= 24
        ? _messages
        : _messages.sublist(_messages.length - 24);
    final payload = jsonEncode({
      'assessmentId': widget.assessmentId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'messages': capped.map((message) => message.toJson()).toList(),
    });
    await widget.database
        .into(widget.database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            preferenceKey: _assessmentAssistantPreferenceKey(
              widget.assessmentId,
            ),
            preferenceValue: payload,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _send() async {
    final question = _composer.text.trim();
    if (question.isEmpty || _sending) return;

    _composer.clear();
    setState(() {
      _messages.add(
        _AssessmentChatMessage(
          role: _AssessmentChatRole.user,
          text: question,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _sending = true;
      _animatedReplyIndex = null;
      _error = null;
    });
    _scrollToBottom();

    try {
      await _persistThread();
    } catch (_) {
      // Continue the live conversation even if local persistence is unavailable.
    }

    try {
      final preferences = await _settingsStore.loadPreferences();
      final serviceConfigured = await _settingsStore.isServiceConfigured();
      if (!preferences.enabled || !serviceConfigured) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _error =
              'Gemini is not configured for this device. Your question is saved with this assessment, but no AI answer was generated.';
        });
        return;
      }
      if (!preferences.shareFieldContext) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _error =
              'Turn on “Use saved assessment with AI” on the Results screen to ask assessment-specific questions. Your question remains saved locally.';
        });
        return;
      }

      final recentHistory = _messages
          .take(_messages.length - 1)
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .map(
            (message) => AdvisorOpenChatTurn(
              role: message.role == _AssessmentChatRole.user
                  ? AdvisorOpenChatRole.farmer
                  : AdvisorOpenChatRole.advisor,
              text: message.text,
              requiresFieldContextSharing: true,
            ),
          )
          .toList(growable: false);

      if (!mounted) return;
      final reviews = Provider.of<ExpertReviewService?>(
        this.context,
        listen: false,
      );
      final expertFacts =
          reviews?.assessmentReviewFacts(widget.assessmentId) ??
          {
            'availability': 'unavailable',
            'note': 'Expert review data was not loaded.',
          };
      // Reload results on every question, including recovered model outputs.
      // The text passed when opening this screen can predate expert finalization.
      final detail = await AssessmentHistoryRepository(
        widget.database,
      ).loadDetail(widget.assessmentId);
      if (!mounted) return;
      final savedFacts = detail == null
          ? <String, dynamic>{
              'assessment_id': widget.assessmentId,
              'availability': 'unavailable',
            }
          : assessmentResultAiContext(detail, expertReview: expertFacts);
      final context = StringBuffer(AdvisorAssessmentContract.instruction)
        ..writeln('\nSAVED ASSESSMENT RESULTS: ${jsonEncode(savedFacts)}')
        ..writeln(
          '\nFINALIZED EXPERT REVIEW RECORDS: ${jsonEncode(expertFacts)}',
        )
        ..writeln('\n\nASSESSMENT-CONVERSATION RULES:')
        ..writeln(
          'Answer questions in relation to this completed assessment, the supplied field observations, and implemented app workflows such as PDF export, sharing a report, and expert review. App capabilities are known independently of the assessment observations; missing field data does not make export unavailable.',
        )
        ..writeln(
          'Do not invent counts, percentages, stations, thresholds, timing intervals, or unrecorded detections.',
        )
        ..writeln(
          'Do not prescribe or name chemical pesticides, active ingredients, doses, application rates, or spray schedules.',
        )
        ..writeln(
          'If the records do not support an answer, say that the assessment does not provide enough information.',
        )
        ..writeln(
          'For a recommended next step, give a fuller explanation in short paragraphs: how it relates to the saved observations, practical non-chemical actions, and what remains uncertain. Keep the answer readable and avoid unsupported claims.',
        )
        ..writeln(
          'For follow-up questions, answer the newest question directly. The assessment facts and earlier replies are already available as context. Do not start each reply with the field name, growth stage, sample percentage, station list, or the same sample limitation. Mention a saved fact only when it changes the answer. Avoid repeating earlier recommendations; add the specific new detail requested.',
        );

      final service =
          widget.openChatService ??
          GeminiAdvisorOpenChatService(settingsStore: _settingsStore);
      if (!mounted) return;
      final response = await service.answer(
        AdvisorOpenChatRequest(
          question: question,
          assessmentScopeId: widget.assessmentId,
          history: recentHistory,
          languageCode:
              AppWords.of(this.context).language == AppLanguage.filipino
              ? 'fil'
              : 'en',
          fieldContext: AdvisorOpenChatFieldContext(
            fieldAndAssessmentSummary: context.toString(),
            records: {
              'assessment_id': widget.assessmentId,
              'expert_review': expertFacts,
              'assessment_results': savedFacts,
            },
          ),
        ),
      );
      final answer = response.summary.trim();
      if (answer.isEmpty) {
        throw StateError('Gemini returned an empty assessment answer.');
      }

      if (!mounted) return;
      setState(() {
        _messages.add(
          _AssessmentChatMessage(
            role: _AssessmentChatRole.assistant,
            text: answer,
            advisorQuestion: response.topicId == 'assessment_scope_handoff'
                ? question
                : null,
            createdAt: DateTime.now().toUtc(),
          ),
        );
        _animatedReplyIndex = _messages.length - 1;
        _sending = false;
      });
      try {
        await _persistThread();
      } catch (_) {
        // The response remains visible in this session if persistence fails.
      }
      _scrollToBottom();
      if (response.topicId == 'assessment_scope_handoff' && mounted) {
        await _openAdvisor(question);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'WormWise could not answer right now. Your question remains saved with this assessment.';
      });
    }
  }

  Future<void> _openAdvisor(String question) async {
    if (!mounted) return;
    final detail = await AssessmentHistoryRepository(
      widget.database,
    ).loadDetail(widget.assessmentId);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            widget.advisorBuilder?.call(question) ??
            AdvisorScreen(
              initialQuestion: question,
              assessmentId: widget.assessmentId,
              fieldId: detail?.workspace.field.id,
              cropCycleId: detail?.assessment.cropCycleId,
              geminiSettingsStore: _settingsStore,
            ),
      ),
    );
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (immediate) {
        _scrollController.jumpTo(0);
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F3),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Ask WormWise',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.fieldName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5EE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCDE4D4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 18,
                    color: Color(0xFF1B4D3E),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: AppText(
                      'This conversation is scoped to the current saved assessment. WormWise uses its recorded results as context and does not change the official assessment.',
                      style: TextStyle(
                        color: Color(0xFF365247),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadingThread
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty && !_sending
                  ? const _AssessmentAssistantEmptyState()
                  : ListView.separated(
                      key: const Key('assessment_assistant_conversation'),
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (_sending && index == 0) {
                          return const _AssessmentThinkingIndicator();
                        }
                        final messageIndex =
                            _messages.length -
                            1 -
                            (_sending ? index - 1 : index);
                        return _AssessmentAssistantBubble(
                          message: _messages[messageIndex],
                          animateReply: messageIndex == _animatedReplyIndex,
                          onOpenAdvisor:
                              _messages[messageIndex].advisorQuestion == null
                              ? null
                              : () => _openAdvisor(
                                  _messages[messageIndex].advisorQuestion!,
                                ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            _AssessmentAssistantComposer(
              controller: _composer,
              enabled: !_sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentAssistantEmptyState extends StatelessWidget {
  const _AssessmentAssistantEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.forum_outlined, color: Color(0xFF2E7D32), size: 38),
            SizedBox(height: 12),
            AppText(
              'Ask about this assessment',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            AppText(
              'Ask about station differences, recorded evidence, or what the saved results mean. Nothing appears back on the Results card until you send a question.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentAssistantBubble extends StatelessWidget {
  const _AssessmentAssistantBubble({
    required this.message,
    required this.animateReply,
    this.onOpenAdvisor,
  });

  final _AssessmentChatMessage message;
  final bool animateReply;
  final VoidCallback? onOpenAdvisor;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _AssessmentChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (isUser ? 0.80 : 0.90),
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const _AssessmentAssistantIdentity(),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF1B4D3E)
                    : const Color(0xFFF3F7F2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFF1B4D3E)
                      : const Color(0xFFD8E7DE),
                ),
              ),
              child: !isUser && animateReply
                  ? _AssessmentAnimatedReply(
                      text: message.text,
                      createdAt: message.createdAt,
                    )
                  : Text(
                      message.text,
                      style: TextStyle(
                        color: isUser ? Colors.white : const Color(0xFF26372F),
                        fontSize: 13,
                        height: 1.48,
                      ),
                    ),
            ),
            if (onOpenAdvisor != null)
              TextButton.icon(
                key: const Key('assessment_open_advisor'),
                onPressed: onOpenAdvisor,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const AppText('Open Advisor'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentAssistantIdentity extends StatelessWidget {
  const _AssessmentAssistantIdentity();

  @override
  Widget build(BuildContext context) => const AppText(
    'WormWise',
    style: TextStyle(
      color: Color(0xFF1B4D3E),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _AssessmentAnimatedReply extends StatelessWidget {
  const _AssessmentAnimatedReply({required this.text, required this.createdAt});

  final String text;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
    key: ValueKey('assessment_reply_${createdAt.microsecondsSinceEpoch}'),
    tween: IntTween(begin: 0, end: text.length),
    duration: Duration(milliseconds: (text.length * 4).clamp(320, 2200)),
    curve: Curves.linear,
    builder: (context, count, _) => Text(
      text.substring(0, count),
      style: const TextStyle(
        color: Color(0xFF26372F),
        fontSize: 13,
        height: 1.48,
      ),
    ),
  );
}

class _AssessmentThinkingIndicator extends StatefulWidget {
  const _AssessmentThinkingIndicator();

  @override
  State<_AssessmentThinkingIndicator> createState() =>
      _AssessmentThinkingIndicatorState();
}

class _AssessmentThinkingIndicatorState
    extends State<_AssessmentThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Preparing a reply',
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AssessmentAssistantIdentity(),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD8E7DE)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Row(
                    children: [
                      for (var index = 0; index < 3; index++) ...[
                        if (index > 0) const SizedBox(width: 4),
                        Opacity(
                          opacity:
                              .3 +
                              .7 *
                                  (1 -
                                      (((_pulse.value + index / 3) % 1) - .5)
                                              .abs() *
                                          2),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1B4D3E),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const AppText(
                  'Preparing a reply',
                  style: TextStyle(
                    color: Color(0xFF1B4D3E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _AssessmentAssistantComposer extends StatelessWidget {
  const _AssessmentAssistantComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('assessment_assistant_input'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: AppWords.of(
                    context,
                  ).translate('Ask about this assessment…'),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('assessment_assistant_send'),
              onPressed: enabled ? onSend : null,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1B4D3E),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AssessmentChatRole { user, assistant }

class _AssessmentChatMessage {
  const _AssessmentChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.advisorQuestion,
  });

  final _AssessmentChatRole role;
  final String text;
  final DateTime createdAt;
  final String? advisorQuestion;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    if (advisorQuestion != null) 'advisorQuestion': advisorQuestion,
  };

  static _AssessmentChatMessage? fromJson(Map<String, dynamic> json) {
    final text = (json['text'] ?? '').toString().trim();
    final roleText = (json['role'] ?? '').toString();
    if (text.isEmpty || (roleText != 'user' && roleText != 'assistant')) {
      return null;
    }
    return _AssessmentChatMessage(
      role: roleText == 'user'
          ? _AssessmentChatRole.user
          : _AssessmentChatRole.assistant,
      text: text,
      advisorQuestion: json['advisorQuestion'] is String
          ? json['advisorQuestion'] as String
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

List<_AssessmentChatMessage> _decodeConversation(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
      return const [];
    }
    final result = <_AssessmentChatMessage>[];
    for (final item in decoded['messages'] as List) {
      if (item is Map<String, dynamic>) {
        final message = _AssessmentChatMessage.fromJson(item);
        if (message != null) result.add(message);
      }
    }
    return result;
  } catch (_) {
    return const [];
  }
}
