import 'dart:io';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import 'evidence_photo_viewer.dart';
import 'field_workflow_components.dart';

class EvidenceCapturePanel extends StatelessWidget {
  const EvidenceCapturePanel({
    super.key,
    required this.title,
    required this.instruction,
    required this.scopeLabel,
    required this.viewType,
    required this.bundle,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
  });

  final String title;
  final String instruction;
  final String scopeLabel;
  final String viewType;
  final EvidenceCaptureBundle bundle;
  final Future<File> Function(String localUri) resolveFile;
  final Future<void> Function() onCapture;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(EvidenceMediaRecord media) onAccept;
  final Future<void> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<void> Function(String reasonCode, String? note) onManualFallback;

  @override
  Widget build(BuildContext context) {
    final media = bundle.mediaForView(viewType);
    final waived = bundle.waivedViewTypes.contains(viewType);
    return Card(
      key: Key('evidence_panel_$viewType'),
      elevation: AppElevation.card,
      color: AppColors.surfaceCard,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                WorkflowBadge(
                  label: _stateLabel(media, waived),
                  icon: _stateIcon(media, waived),
                  foreground: _stateColor(media, waived),
                  background: _stateBackground(media, waived),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            AppText('$scopeLabel · ${evidenceViewLabel(viewType)}'),
            const SizedBox(height: AppSpacing.xs),
            Text(instruction, style: const TextStyle(height: 1.4)),
            const SizedBox(height: AppSpacing.sm),
            if (media != null) ...[
              _EvidencePreview(
                media: media,
                resolveFile: resolveFile,
                onInspect: () => onInspect(media),
              ),
              const SizedBox(height: 10),
              _EvidenceStatus(media: media),
              if (waived) ...[
                const SizedBox(height: 10),
                const _FallbackNotice(),
              ],
              const SizedBox(height: 10),
              if (media.storageState == DatabaseCodes.evidenceStorageStaged)
                _ActionButton(
                  key: Key('accept_$viewType'),
                  icon: Icons.check_circle_outline,
                  label: 'Use photo',
                  onPressed: () => onAccept(media),
                ),
              if (media.storageState == DatabaseCodes.evidenceStorageReady ||
                  media.storageState == DatabaseCodes.evidenceStorageStaged ||
                  media.storageState == DatabaseCodes.evidenceStorageMissing)
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    OutlinedButton.icon(
                      key: Key('retake_$viewType'),
                      onPressed: () => _retake(context, media),
                      icon: const Icon(Icons.refresh),
                      label: const AppText('Retake'),
                    ),
                    OutlinedButton.icon(
                      key: Key('remove_$viewType'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.severeSeverityRing,
                      ),
                      onPressed: () => _remove(context, media),
                      icon: const Icon(Icons.delete_outline),
                      label: const AppText('Remove'),
                    ),
                  ],
                ),
            ] else if (waived) ...[
              const _FallbackNotice(),
              const SizedBox(height: 10),
              _ActionButton(
                key: Key('retry_photo_$viewType'),
                icon: Icons.camera_alt_outlined,
                label: 'Try camera again',
                onPressed: onCapture,
              ),
            ] else ...[
              _ActionButton(
                key: Key('capture_$viewType'),
                icon: Icons.camera_alt_outlined,
                label: 'Take photo',
                onPressed: onCapture,
              ),
            ],
            if (!waived &&
                media?.storageState != DatabaseCodes.evidenceStorageReady) ...[
              const SizedBox(height: 6),
              TextButton(
                key: Key('manual_fallback_$viewType'),
                onPressed: () => _manualFallback(context),
                child: const AppText('Camera unavailable'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stateLabel(EvidenceMediaRecord? media, bool waived) {
    if (waived) return 'Fallback recorded';
    return switch (media?.storageState) {
      DatabaseCodes.evidenceStorageReady => 'Photo ready',
      DatabaseCodes.evidenceStorageStaged => 'Review photo',
      DatabaseCodes.evidenceStorageMissing => 'Photo missing',
      _ => 'Photo required',
    };
  }

  IconData _stateIcon(EvidenceMediaRecord? media, bool waived) {
    if (waived) return Icons.assignment_turned_in_outlined;
    return switch (media?.storageState) {
      DatabaseCodes.evidenceStorageReady => Icons.check_circle_outline,
      DatabaseCodes.evidenceStorageMissing => Icons.warning_amber_rounded,
      DatabaseCodes.evidenceStorageStaged => Icons.preview_outlined,
      _ => Icons.camera_alt_outlined,
    };
  }

  Color _stateColor(EvidenceMediaRecord? media, bool waived) {
    if (waived || media?.storageState == DatabaseCodes.evidenceStorageReady) {
      return AppColors.highContrastGreen;
    }
    if (media?.storageState == DatabaseCodes.evidenceStorageMissing) {
      return AppColors.severeSeverityRing;
    }
    return AppColors.textSecondary;
  }

  Color _stateBackground(EvidenceMediaRecord? media, bool waived) {
    if (waived || media?.storageState == DatabaseCodes.evidenceStorageReady) {
      return AppColors.lowSeverityBg;
    }
    if (media?.storageState == DatabaseCodes.evidenceStorageMissing) {
      return AppColors.severeSeverityBg;
    }
    return AppColors.surfaceContainer;
  }

  Future<void> _retake(BuildContext context, EvidenceMediaRecord media) async {
    await onRetake(media);
  }

  Future<void> _remove(BuildContext context, EvidenceMediaRecord media) async {
    if (!await _confirmRemoval(context, retake: false)) return;
    await onRemove(media);
  }

  Future<bool> _confirmRemoval(
    BuildContext context, {
    required bool retake,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(retake ? 'Retake this photo?' : 'Remove this photo?'),
            content: const AppText(
              'The image file will be deleted. WormWise keeps only an audited metadata tombstone and checksum.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const AppText('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm_evidence_removal'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(retake ? 'Delete and retake' : 'Delete photo'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _manualFallback(BuildContext context) async {
    final fallback = await showEvidenceFallbackDialog(context);
    if (fallback == null) return;
    await onManualFallback(fallback.reasonCode, fallback.note);
  }
}

class _EvidencePreview extends StatefulWidget {
  const _EvidencePreview({
    required this.media,
    required this.resolveFile,
    required this.onInspect,
  });

  final EvidenceMediaRecord media;
  final Future<File> Function(String localUri) resolveFile;
  final VoidCallback onInspect;

  @override
  State<_EvidencePreview> createState() => _EvidencePreviewState();
}

class _EvidencePreviewState extends State<_EvidencePreview> {
  late Future<File> _file;

  @override
  void initState() {
    super.initState();
    _file = _resolve();
  }

  @override
  void didUpdateWidget(covariant _EvidencePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.localUri != widget.media.localUri ||
        oldWidget.media.thumbnailLocalUri != widget.media.thumbnailLocalUri) {
      _file = _resolve();
    }
  }

  Future<File> _resolve() => widget.resolveFile(
    widget.media.thumbnailLocalUri ?? widget.media.localUri,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.media.storageState == DatabaseCodes.evidenceStorageMissing) {
      return const _MissingEvidencePreview();
    }
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: AppSizes.evidencePreviewHeight,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Semantics(
          button: true,
          label: 'Open canonical evidence photo',
          child: InkWell(
            key: Key('inspect_evidence_${widget.media.viewType}'),
            onTap: widget.onInspect,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: AppSizes.evidencePreviewHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      snapshot.data!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFE6E6E6),
                        child: Center(child: AppText('Preview unavailable')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Row(
                  children: [
                    Icon(Icons.zoom_in, size: 18),
                    SizedBox(width: 4),
                    Expanded(
                      child: AppText('Tap to inspect full-resolution evidence'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MissingEvidencePreview extends StatelessWidget {
  const _MissingEvidencePreview();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 128),
    decoration: BoxDecoration(
      color: AppColors.severeSeverityBg,
      borderRadius: AppRadii.cardBorder,
      border: Border.all(color: AppColors.severeSeverityRing),
    ),
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 36),
            SizedBox(height: AppSpacing.xs),
            AppText('Photo file missing', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _EvidenceStatus extends StatelessWidget {
  const _EvidenceStatus({required this.media});

  final EvidenceMediaRecord media;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (media.storageState) {
      DatabaseCodes.evidenceStorageStaged => (
        Icons.preview_outlined,
        'Preview recovered. Confirm the framing before accepting.',
        const Color(0xFF8A5A00),
      ),
      DatabaseCodes.evidenceStorageReady => (
        Icons.check_circle_outline,
        'Accepted and saved privately on this phone.',
        const Color(0xFF176B3A),
      ),
      DatabaseCodes.evidenceStorageMissing => (
        Icons.warning_amber_rounded,
        'The image file is missing. Retake it or document manual fallback.',
        const Color(0xFF9D241F),
      ),
      _ => (
        Icons.info_outline,
        'Evidence state: ${media.storageState}',
        const Color(0xFF4D4D4D),
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, height: 1.35)),
        ),
      ],
    );
  }
}

class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.assignment_turned_in_outlined, color: Color(0xFF176B3A)),
        SizedBox(width: 8),
        Expanded(
          child: AppText(
            'Manual fallback documented. Continue the physical assessment and structured observations.',
            style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class EvidenceFallbackChoice {
  const EvidenceFallbackChoice({required this.reasonCode, this.note});

  final String reasonCode;
  final String? note;
}

Future<EvidenceFallbackChoice?> showEvidenceFallbackDialog(
  BuildContext context, {
  String? suggestedReasonCode,
}) async {
  var reason =
      DatabaseCodes.evidenceFallbackReasons.contains(suggestedReasonCode)
      ? suggestedReasonCode
      : null;
  final note = TextEditingController();
  try {
    return await showDialog<EvidenceFallbackChoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const AppText('Camera unavailable'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppText(
                  'Photography failure does not invalidate a careful physical assessment. Record why the required image cannot be collected.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('evidence_fallback_reason'),
                  initialValue: reason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: AppWords.of(context).translate('Reason'),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPermissionDenied,
                      child: AppText('Camera permission denied'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPermissionBlocked,
                      child: AppText('Camera blocked in settings'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackNoCamera,
                      child: AppText('No usable camera'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackStorage,
                      child: AppText('Phone storage unavailable'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackCaptureFailure,
                      child: AppText('Camera or capture failure'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackUnsafe,
                      child: AppText('Unsafe to photograph'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPrivacy,
                      child: AppText('Privacy or consent concern'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackFraming,
                      child: AppText('Unable to frame useful evidence'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackOther,
                      child: AppText('Other recorded reason'),
                    ),
                  ],
                  onChanged: (value) => setState(() => reason = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('evidence_fallback_note'),
                  controller: note,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppWords.of(
                      context,
                    ).translate('Short note (optional)'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('Cancel'),
            ),
            FilledButton(
              key: const Key('save_evidence_fallback'),
              onPressed: reason == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      EvidenceFallbackChoice(
                        reasonCode: reason!,
                        note: note.text.trim().isEmpty
                            ? null
                            : note.text.trim(),
                      ),
                    ),
              child: const AppText('Save fallback'),
            ),
          ],
        ),
      ),
    );
  } finally {
    note.dispose();
  }
}
