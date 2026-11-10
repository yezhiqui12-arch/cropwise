import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/cloud/expert_review_service.dart';
import '../theme/app_colors.dart';
import '../widgets/expert_case_message_media.dart';
import '../widgets/expert_review_presentation.dart';
import 'expert_severity_review_screen.dart';

class ExpertReviewScreen extends StatefulWidget {
  const ExpertReviewScreen({super.key});
  @override
  State<ExpertReviewScreen> createState() => _ExpertReviewScreenState();
}

class _ExpertReviewScreenState extends State<ExpertReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final service = context.read<ExpertReviewService>();
      await service.refresh();
      await service.markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExpertReviewService>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Expert review',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: service.loading ? null : service.refresh,
            tooltip: 'Refresh reviews',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: service.refresh,
        child: service.cases.isNotEmpty
            ? ExpertReviewInbox(
                cases: service.cases,
                userId: service.currentUserId,
                onOpen: (item) => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpertCaseScreen(caseId: item.id),
                  ),
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(30),
                children: [
                  const SizedBox(height: 100),
                  if (service.loading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Icon(
                      service.error == null
                          ? Icons.forum_outlined
                          : Icons.cloud_off_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      service.error == null
                          ? 'Expert support starts here'
                          : 'Could not load your reviews',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      service.error == null
                          ? 'Submit a field assessment for expert review. Messages, photo requests and findings will appear here.'
                          : 'Check your connection and refresh to try again.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    if (service.error != null)
                      TextButton(
                        onPressed: service.refresh,
                        child: const Text('Try again'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class ExpertCaseScreen extends StatefulWidget {
  const ExpertCaseScreen({super.key, required this.caseId});
  final String caseId;
  @override
  State<ExpertCaseScreen> createState() => _ExpertCaseScreenState();
}

class _ExpertCaseScreenState extends State<ExpertCaseScreen> {
  final _composer = GlobalKey<ExpertCaseMessageComposerState>();
  final _messages = ScrollController();
  int _messageCount = -1;
  @override
  void dispose() {
    _messages.dispose();
    super.dispose();
  }

  void _results(ExpertReviewCase item) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ExpertSeverityReviewScreen(caseId: item.id),
    ),
  );
  void _contact(ExpertReviewCase item) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your assigned expert',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              item.expertName?.trim().isNotEmpty == true
                  ? item.expertName!
                  : 'Cropwise expert',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (item.expertPhone?.trim().isNotEmpty == true)
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      item.expertPhone!,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy phone number',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: item.expertPhone!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone number copied.')),
                        );
                      }
                    },
                  ),
                ],
              )
            else
              const Text(
                'Phone number not provided. You can message your expert in this case.',
              ),
            if (item.location.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                item.location,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExpertReviewService>();
    final cases = service.cases.where((c) => c.id == widget.caseId);
    if (cases.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expert review')),
        body: const Center(
          child: Text('This review is unavailable. Refresh your cases.'),
        ),
      );
    }
    final item = cases.first;
    final userId = service.currentUserId;
    if (_messageCount != item.messages.length) {
      final firstLoad = _messageCount == -1;
      _messageCount = item.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Start at the photo requests. Scroll to a newly received reply later.
        if (!firstLoad && _messages.hasClients) {
          _messages.animateTo(
            _messages.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
    final requests = openPhotoRequests(item);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Case conversation',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: service.loading ? null : service.refresh,
            tooltip: 'Refresh conversation',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: service.refresh,
              child: ListView(
                controller: _messages,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ExpertCaseHeader(
                    item: item,
                    onContact: () => _contact(item),
                    onResults: () => _results(item),
                  ),
                  if (service.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (service.error != null)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Could not refresh. Previously loaded messages are shown.',
                        style: TextStyle(color: Color(0xFF855019)),
                      ),
                    ),
                  if (requests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                      child: Text(
                        '${requests.length} ${requests.length == 1 ? 'photo request needs' : 'photo requests need'} your reply',
                        style: const TextStyle(
                          color: Color(0xFF855019),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                    child: Text(
                      'CONVERSATION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  if (item.messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Your expert is reviewing this assessment. You can send a message below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  for (final message in item.messages)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child:
                          message.severityCaseId == item.id &&
                              item.severitySummary != null
                          ? ExpertReviewResultMessage(
                              item: item,
                              onOpen: () => _results(item),
                            )
                          : ExpertConversationMessage(
                              key: ValueKey(message.id),
                              message: message,
                              mine: message.senderId == userId,
                              media: service.media,
                              canReply:
                                  message.kind == 'evidence_request' &&
                                  message.evidenceStatus != 'resolved' &&
                                  item.severitySummary == null &&
                                  item.status != 'closed',
                              onReply: () => _composer.currentState
                                  ?.replyToRequest(message, choosePhotos: true),
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (item.status != 'closed' && userId != null)
            ExpertCaseMessageComposer(
              key: _composer,
              reviewCase: item,
              owner: userId,
              service: service.media,
              refresh: service.refresh,
            )
          else
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This case is closed.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
