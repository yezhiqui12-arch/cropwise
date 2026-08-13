import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import 'evidence_photo_viewer.dart';

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
      elevation: 0,
      color: const Color(0xFFF3F8F4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(
              '$scopeLabel · ${evidenceViewLabel(viewType)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(instruction, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 12),
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
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: Key('retake_$viewType'),
                      onPressed: () => _retake(context, media),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake'),
                    ),
                    TextButton.icon(
                      key: Key('remove_$viewType'),
                      onPressed: () => _remove(context, media),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
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
                label: 'Open guided camera',
                onPressed: onCapture,
              ),
            ],
            if (!waived &&
                media?.storageState != DatabaseCodes.evidenceStorageReady) ...[
              const SizedBox(height: 6),
              TextButton(
                key: Key('manual_fallback_$viewType'),
                onPressed: () => _manualFallback(context),
                child: const Text('Document manual fallback'),
              ),
            ],
          ],
        ),
      ),
    );
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
            content: const Text(
              'The image file will be deleted. WormWise keeps only an audited metadata tombstone and checksum.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
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
      return const SizedBox.shrink();
    }
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Semantics(
          button: true,
          label: 'Open original evidence photo',
          child: InkWell(
            key: Key('inspect_evidence_${widget.media.viewType}'),
            onTap: widget.onInspect,
            borderRadius: BorderRadius.circular(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 144,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFE6E6E6),
                          child: Center(child: Text('Preview unavailable')),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 170,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, size: 18),
                      SizedBox(width: 4),
                      Flexible(child: Text('Tap to inspect original')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
          child: Text(
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
          title: const Text('Document manual fallback'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Photography failure does not invalidate a careful physical assessment. Record why the required image cannot be collected.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('evidence_fallback_reason'),
                  initialValue: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPermissionDenied,
                      child: Text('Camera permission denied'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPermissionBlocked,
                      child: Text('Camera blocked in settings'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackNoCamera,
                      child: Text('No usable camera'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackStorage,
                      child: Text('Phone storage unavailable'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackCaptureFailure,
                      child: Text('Camera or capture failure'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackUnsafe,
                      child: Text('Unsafe to photograph'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackPrivacy,
                      child: Text('Privacy or consent concern'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackFraming,
                      child: Text('Unable to frame useful evidence'),
                    ),
                    DropdownMenuItem(
                      value: DatabaseCodes.evidenceFallbackOther,
                      child: Text('Other recorded reason'),
                    ),
                  ],
                  onChanged: (value) => setState(() => reason = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('evidence_fallback_note'),
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Short note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
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
              child: const Text('Save fallback'),
            ),
          ],
        ),
      ),
    );
  } finally {
    note.dispose();
  }
}
