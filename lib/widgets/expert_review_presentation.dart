import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/cloud/case_message_service.dart';
import '../services/cloud/expert_review_service.dart';
import '../theme/app_colors.dart';
import 'expert_case_message_media.dart';

const _ink = Color(0xFF183D32);
const _amber = Color(0xFF855019);

String evidencePlantLabel(ExpertMessage message) =>
    message.requestedStation == null
    ? 'Field photos'
    : message.evidenceStatus != null
    ? 'Block ${message.requestedBlockSequence ?? 1} · Plant ${message.requestedStation}'
    : 'Station ${message.requestedStation}${message.requestedPlant == null ? '' : ' · Plant ${message.requestedPlant}'}';

String reviewStatusLabel(String status) => switch (status) {
  'pending' => 'Waiting for expert',
  'claimed' => 'Under review',
  'needs_information' => 'Photos needed',
  'advice_sent' => 'Advice received',
  'closed' => 'Closed',
  _ => 'Review update',
};

List<ExpertMessage> openPhotoRequests(ExpertReviewCase item) => item.messages
    .where(
      (m) =>
          m.kind == 'evidence_request' &&
          m.evidenceStatus != 'resolved' &&
          m.evidenceStatus != 'photos_received' &&
          item.status != 'closed' &&
          item.severitySummary == null,
    )
    .toList();

class ReviewStatusBadge extends StatelessWidget {
  const ReviewStatusBadge(this.status, {super.key, this.finalized = false});
  final String status;
  final bool finalized;
  @override
  Widget build(BuildContext context) {
    final color = finalized
        ? _ink
        : status == 'needs_information'
        ? _amber
        : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        finalized ? 'Review finalized' : reviewStatusLabel(status),
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The live inbox uses this same presentation; it can also render without cloud access.
class ExpertReviewInbox extends StatefulWidget {
  const ExpertReviewInbox({
    super.key,
    required this.cases,
    required this.userId,
    required this.onOpen,
  });
  final List<ExpertReviewCase> cases;
  final String? userId;
  final ValueChanged<ExpertReviewCase> onOpen;
  @override
  State<ExpertReviewInbox> createState() => _ExpertReviewInboxState();
}

class _ExpertReviewInboxState extends State<ExpertReviewInbox> {
  int _filter = 0;
  @override
  Widget build(BuildContext context) {
    final items =
        widget.cases
            .where(
              (c) => switch (_filter) {
                1 => openPhotoRequests(c).isNotEmpty,
                2 => c.severitySummary != null,
                _ => true,
              },
            )
            .toList()
          ..sort((a, b) {
            final priority = (openPhotoRequests(b).isNotEmpty ? 1 : 0)
                .compareTo(openPhotoRequests(a).isNotEmpty ? 1 : 0);
            return priority != 0
                ? priority
                : b.createdAt.compareTo(a.createdAt);
          });
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${switch (_filter) {
                  1 => 'Photos needed',
                  2 => 'Finalized',
                  _ => 'All cases',
                }} · ${items.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            PopupMenuButton<int>(
              key: const ValueKey('expert_case_filter'),
              tooltip: 'Filter cases',
              initialValue: _filter,
              icon: Icon(
                Icons.filter_list_rounded,
                color: _filter == 0 ? AppColors.textSecondary : _ink,
                size: 22,
              ),
              onSelected: (value) => setState(() => _filter = value),
              itemBuilder: (_) => [
                for (final entry in [
                  (0, 'All cases'),
                  (1, 'Photos needed'),
                  (2, 'Finalized'),
                ])
                  CheckedPopupMenuItem<int>(
                    value: entry.$1,
                    checked: _filter == entry.$1,
                    child: Text(entry.$2),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No cases in this view.', textAlign: TextAlign.center),
          ),
        for (final item in items) ...[
          _ReviewCaseTile(
            item: item,
            userId: widget.userId,
            onTap: () => widget.onOpen(item),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ReviewCaseTile extends StatelessWidget {
  const _ReviewCaseTile({
    required this.item,
    required this.userId,
    required this.onTap,
  });
  final ExpertReviewCase item;
  final String? userId;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final requests = openPhotoRequests(item);
    final messages = item.messages.where((m) => m.senderId != userId).toList();
    final last = messages.isEmpty ? null : messages.last;
    final finalized = item.severitySummary != null;
    final statusColor = finalized
        ? _ink
        : item.status == 'needs_information'
        ? _amber
        : AppColors.textSecondary;
    return Material(
      key: ValueKey('expert_case_${item.id}'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.fieldName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat.MMMd().format(
                      (last?.createdAt ?? item.createdAt).toLocal(),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      finalized
                          ? 'Review finalized'
                          : reviewStatusLabel(item.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                requests.isNotEmpty
                    ? '${requests.length} ${requests.length == 1 ? 'photo request' : 'photo requests'} · ${evidencePlantLabel(requests.first)}'
                    : finalized
                    ? 'View expert findings and plant photos.'
                    : last?.body ?? 'Your expert will update this case here.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpertCaseHeader extends StatelessWidget {
  const ExpertCaseHeader({
    super.key,
    required this.item,
    required this.onContact,
    required this.onResults,
  });
  final ExpertReviewCase item;
  final VoidCallback onContact, onResults;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.fieldName,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Submitted ${DateFormat.yMMMd().format(item.createdAt.toLocal())}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ReviewStatusBadge(
              item.status,
              finalized: item.severitySummary != null,
            ),
            if (item.expertId != null)
              TextButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.support_agent_rounded, size: 18),
                label: const Text('Your expert'),
              ),
          ],
        ),
        if (item.severitySummary != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onResults,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('View expert findings'),
            ),
          ),
        ],
      ],
    ),
  );
}

class ExpertConversationMessage extends StatefulWidget {
  const ExpertConversationMessage({
    super.key,
    required this.message,
    required this.mine,
    required this.media,
    required this.canReply,
    required this.onReply,
  });
  final ExpertMessage message;
  final bool mine, canReply;
  final CaseMessageService media;
  final VoidCallback onReply;
  @override
  State<ExpertConversationMessage> createState() =>
      _ExpertConversationMessageState();
}

class _ExpertConversationMessageState extends State<ExpertConversationMessage> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final longInstructions =
        m.body.length > 180 || '\n'.allMatches(m.body).length > 2;
    final request = m.kind == 'evidence_request';
    final received = m.evidenceStatus == 'photos_received';
    final resolved = m.evidenceStatus == 'resolved';
    final foreground = widget.mine ? Colors.white : AppColors.textPrimary;
    final muted = widget.mine ? Colors.white70 : AppColors.textMuted;
    final color = request
        ? const Color(0xFFFFF5E7)
        : widget.mine
        ? _ink
        : Colors.white;
    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: request ? 1 : .92,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: request ? Border.all(color: const Color(0xFFECD7B8)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (request) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      resolved
                          ? Icons.task_alt_rounded
                          : received
                          ? Icons.hourglass_top_rounded
                          : Icons.add_a_photo_outlined,
                      color: _amber,
                      size: 21,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        resolved
                            ? 'Photos reviewed'
                            : received
                            ? 'Photos received'
                            : 'New photos needed',
                        style: const TextStyle(
                          color: _amber,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (m.requestedStation != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    evidencePlantLabel(m),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
                if (m.requestedViews.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final view in m.requestedViews)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            switch (view) {
                              'whole_plant' => 'Whole plant',
                              'whorl' => 'Whorl & newest leaves',
                              'damage_close_up' => 'Damage close-up',
                              _ => view,
                            },
                            style: const TextStyle(
                              fontSize: 12,
                              color: _amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
              ] else ...[
                Text(
                  widget.mine ? 'YOU' : 'YOUR EXPERT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
              ],
              if (m.body.trim().isNotEmpty)
                Text(
                  m.body,
                  maxLines: request && longInstructions && !_expanded
                      ? 3
                      : null,
                  overflow: request && longInstructions && !_expanded
                      ? TextOverflow.ellipsis
                      : null,
                  style: TextStyle(
                    color: request ? AppColors.textPrimary : foreground,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
              if (request && longInstructions)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: _amber,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Less detail' : 'Read instructions'),
                ),
              if (m.attachments.isNotEmpty)
                ExpertMessagePhotos(
                  photos: m.attachments,
                  service: widget.media,
                ),
              if (m.requestId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Linked to the expert’s photo request',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              if (request && received)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Your expert will check the replacement photos.',
                    style: TextStyle(fontSize: 12, color: _amber),
                  ),
                ),
              if (request && widget.canReply) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _ink),
                    onPressed: widget.onReply,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 19,
                    ),
                    label: Text(
                      received ? 'Send more photos' : 'Add requested photos',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                DateFormat.MMMd().add_jm().format(m.createdAt.toLocal()),
                style: TextStyle(fontSize: 11, color: request ? _amber : muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpertReviewResultMessage extends StatelessWidget {
  const ExpertReviewResultMessage({
    super.key,
    required this.item,
    required this.onOpen,
  });
  final ExpertReviewCase item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final summary = item.severitySummary!;
    final mean = summary.monitoring['mean_davis_score'];
    final hasMean =
        mean is num &&
        mean.isFinite &&
        summary.monitoring['association_status'] != 'ambiguous';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFE8F0E9),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_outlined, color: _ink, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Expert findings ready',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (hasMean)
                        Text(
                          'Davis ${mean.toStringAsFixed(2)} / 9 · ${summary.monitoring['da_severity_classification'] ?? 'Classification unavailable'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _ink,
                            height: 1.4,
                          ),
                        )
                      else
                        const Text(
                          'Plant ratings available in the review.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 5),
                      Text(
                        '${summary.scoredPlants} scored · ${summary.insufficientPlants} could not be assessed',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'View findings & photos',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 20, color: _ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
