import '../localization/app_text.dart';
import '../localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/wormwise_notification_service.dart';
import '../theme/app_colors.dart';
import 'assess/assessment_results_screen.dart';
import 'expert_review_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.onOpenAssess});
  final VoidCallback onOpenAssess;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WormWiseNotificationService>();
    final unread = service.items
        .where((item) => !service.isRead(item.id))
        .toList();
    final earlier = service.items
        .where((item) => service.isRead(item.id))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const AppText('Notifications')),
      body: RefreshIndicator(
        onRefresh: service.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            if (service.items.isEmpty)
              const _EmptyNotifications()
            else ...[
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F3E9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          unread.isEmpty
                              ? 'All caught up'
                              : AppWords.of(context).newUpdates(unread.length),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const AppText(
                          'Field reminders and expert replies',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              if (unread.isNotEmpty) ...[
                const _SectionLabel('New'),
                const SizedBox(height: 10),
                for (final item in unread) ...[
                  _NotificationCard(
                    item: item,
                    isRead: false,
                    onTap: () => _openItem(context, service, item),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (earlier.isNotEmpty) ...[
                const SizedBox(height: 14),
                const _SectionLabel('Earlier'),
                const SizedBox(height: 10),
                for (final item in earlier) ...[
                  _NotificationCard(
                    item: item,
                    isRead: true,
                    onTap: () => _openItem(context, service, item),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openItem(
    BuildContext context,
    WormWiseNotificationService service,
    WormWiseNotification item,
  ) async {
    await service.markRead(item.id);
    if (!context.mounted) return;
    if (item.caseId != null) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ExpertCaseScreen(caseId: item.caseId!),
        ),
      );
    } else if (item.assessmentId != null) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AssessmentResultsScreen(assessmentId: item.assessmentId!),
        ),
      );
    } else {
      Navigator.pop(context);
      onOpenAssess();
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => AppText(
    label,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    ),
  );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.isRead,
    required this.onTap,
  });
  final WormWiseNotification item;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expert =
        item.kind == WormWiseNotificationKind.needsInformation ||
        item.kind == WormWiseNotificationKind.adviceReady ||
        item.kind == WormWiseNotificationKind.severityReady;
    final accent = expert ? const Color(0xFF215D75) : AppColors.primary;
    final label = switch (item.kind) {
      WormWiseNotificationKind.followUp => 'FOLLOW UP',
      WormWiseNotificationKind.inactiveField => 'FIELD REMINDER',
      WormWiseNotificationKind.needsInformation => 'EXPERT REVIEW',
      WormWiseNotificationKind.adviceReady => 'EXPERT ADVICE',
      WormWiseNotificationKind.severityReady => 'SEVERITY REVIEW',
    };
    final icon = switch (item.kind) {
      WormWiseNotificationKind.followUp => Icons.event_repeat_rounded,
      WormWiseNotificationKind.inactiveField => Icons.grass_outlined,
      WormWiseNotificationKind.needsInformation =>
        Icons.question_answer_outlined,
      WormWiseNotificationKind.adviceReady => Icons.fact_check_outlined,
      WormWiseNotificationKind.severityReady => Icons.assessment_outlined,
    };
    final action = expert
        ? 'Open review'
        : item.assessmentId != null
        ? 'View assessment'
        : 'Open Assess';
    return Material(
      color: isRead ? Colors.white : const Color(0xFFF5FAF5),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isRead ? const Color(0xFFE3EAE5) : const Color(0xFFC7DCCB),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppText(
                            label,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      item.bodyTemplate ?? item.body,
                      arguments: item.bodyArguments,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 4,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppText(
                          action,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(item.createdAt.toLocal()),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 130),
    child: Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: const BoxDecoration(
            color: Color(0xFFE7F3E9),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 34,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 18),
        const AppText(
          'All caught up',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 7),
        const AppText(
          'Field reminders and expert replies will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}
