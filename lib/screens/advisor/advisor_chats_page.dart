import '../../localization/app_text.dart';
import '../../localization/app_language.dart';
import 'package:flutter/material.dart';

import '../../services/advisor/advisor_chat_session_store.dart';
import '../../theme/app_colors.dart';

enum AdvisorChatNavigation { newChat }

class AdvisorChatsPage extends StatelessWidget {
  const AdvisorChatsPage({
    super.key,
    this.sessions = const [],
    this.currentTitle = 'New chat',
    this.currentPreview,
    this.hasCurrentChat = false,
  });

  final List<AdvisorChatSession> sessions;
  final String currentTitle;
  final String? currentPreview;
  final bool hasCurrentChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F6),
        title: const AppText('Chats'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              key: const Key('advisor_new_chat'),
              onPressed: () =>
                  Navigator.pop(context, AdvisorChatNavigation.newChat),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.highContrastGreen,
                backgroundColor: const Color(0xFFE8F2E7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const AppText(
                'New',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            const _SectionLabel('Current conversation'),
            const SizedBox(height: 11),
            Material(
              color: const Color(0xFFEAF3E9),
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                key: const Key('advisor_current_chat'),
                borderRadius: BorderRadius.circular(17),
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(17, 16, 14, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.highContrastGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasCurrentChat
                                  ? currentTitle
                                  : AppWords.of(context).translate('New chat'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColors.highContrastGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (hasCurrentChat &&
                                currentPreview?.trim().isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(
                                _preview(currentPreview!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: AppColors.highContrastGreen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                const Expanded(child: _SectionLabel('Recent chats')),
                if (sessions.isNotEmpty)
                  AppText(
                    '${sessions.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 11),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                child: AppText(
                  'No past chats yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                child: Column(
                  children: [
                    for (var index = 0; index < sessions.length; index++) ...[
                      if (index > 0)
                        const Divider(height: 1, indent: 18, endIndent: 18),
                      _RecentChatRow(session: sessions[index]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => AppText(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _RecentChatRow extends StatelessWidget {
  const _RecentChatRow({required this.session});
  final AdvisorChatSession session;

  @override
  Widget build(BuildContext context) {
    final updated = session.updatedAt.toLocal();
    final today = DateTime.now();
    final date = DateUtils.isSameDay(updated, today)
        ? 'Today'
        : DateUtils.isSameDay(updated, today.subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : MaterialLocalizations.of(context).formatShortDate(updated);
    final preview = session.messages.last.text;
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('advisor_saved_chat_${session.id}'),
      onTap: () => Navigator.pop(context, session),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 14, 13, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sessionTitle(session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _preview(preview),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppText(
              date,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _preview(String text) => text
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'\*\*|#{1,6}\s*'), '')
    .trim();

String _sessionTitle(AdvisorChatSession session) {
  final questions = session.messages
      .where((message) => message.role == 'farmer')
      .map((message) => message.text.trim());
  final meaningful = questions.where((text) => text.length >= 12).firstOrNull;
  return meaningful ?? session.title;
}
