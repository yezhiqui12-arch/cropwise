import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';

enum EvidencePhotoAction {
  usePhoto,
  retake,
  addCloseUp,
  addDiagnosticDetail,
  remove,
}

class EvidencePhotoViewer extends StatefulWidget {
  const EvidencePhotoViewer({
    super.key,
    required this.media,
    required this.scopeLabel,
    required this.resolveFile,
    this.allowActions = false,
    this.allowAddCloseUp = false,
    this.allowAddDiagnosticDetail = false,
    this.transformationController,
  });

  final EvidenceMediaRecord media;
  final String scopeLabel;
  final Future<File> Function(String localUri) resolveFile;
  final bool allowActions;
  final bool allowAddCloseUp;
  final bool allowAddDiagnosticDetail;
  final TransformationController? transformationController;

  @override
  State<EvidencePhotoViewer> createState() => _EvidencePhotoViewerState();
}

class _EvidencePhotoViewerState extends State<EvidencePhotoViewer> {
  late Future<File> _file;
  late final TransformationController _transformationController;
  late final bool _ownsTransformationController;

  @override
  void initState() {
    super.initState();
    _file = widget.resolveFile(widget.media.localUri);
    _ownsTransformationController = widget.transformationController == null;
    _transformationController =
        widget.transformationController ?? TransformationController();
  }

  @override
  void dispose() {
    if (_ownsTransformationController) _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staged =
        widget.media.storageState == DatabaseCodes.evidenceStorageStaged;
    return Scaffold(
      appBar: AppBar(title: const Text('Inspect canonical evidence')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.scopeLabel,
                    key: const Key('evidence_viewer_scope_label'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    evidenceViewLabel(widget.media.viewType),
                    key: const Key('evidence_viewer_view_label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Pinch to zoom and drag to inspect the stored evidence. The evaluator confirms framing and observations.',
                    style: TextStyle(height: 1.3),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: FutureBuilder<File>(
                  future: _file,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || !snapshot.data!.existsSync()) {
                      return const Center(
                        child: Text(
                          'Canonical evidence is unavailable.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }
                    return InteractiveViewer(
                      key: const Key('evidence_interactive_viewer'),
                      transformationController: _transformationController,
                      minScale: 1,
                      maxScale: 5,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.hardEdge,
                      child: Center(
                        child: Image.file(
                          snapshot.data!,
                          key: const Key('evidence_canonical_image'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, _, _) => const Text(
                            'Canonical evidence could not be decoded.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (widget.allowActions)
              Material(
                elevation: 8,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (staged)
                        _ViewerButton(
                          key: const Key('viewer_use_photo'),
                          filled: true,
                          icon: Icons.check_circle_outline,
                          label: 'Use photo',
                          action: EvidencePhotoAction.usePhoto,
                        ),
                      _ViewerButton(
                        key: const Key('viewer_retake'),
                        icon: Icons.refresh,
                        label: 'Retake',
                        action: EvidencePhotoAction.retake,
                      ),
                      if (widget.allowAddCloseUp)
                        _ViewerButton(
                          key: const Key('viewer_add_close_up'),
                          icon: Icons.add_a_photo_outlined,
                          label: 'Add close-up',
                          action: EvidencePhotoAction.addCloseUp,
                        ),
                      if (widget.allowAddDiagnosticDetail)
                        _ViewerButton(
                          key: const Key('viewer_add_diagnostic_detail'),
                          icon: Icons.add_a_photo_outlined,
                          label: 'Add extra detail',
                          action: EvidencePhotoAction.addDiagnosticDetail,
                        ),
                      _ViewerButton(
                        key: const Key('viewer_remove'),
                        icon: Icons.delete_outline,
                        label: 'Remove',
                        action: EvidencePhotoAction.remove,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.action,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final EvidencePhotoAction action;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56, minWidth: 112),
      child: filled
          ? FilledButton.icon(
              onPressed: () => Navigator.pop(context, action),
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, action),
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

String evidenceViewLabel(String? viewType) => switch (viewType) {
  DatabaseCodes.evidenceViewStationContext => 'Station-context view',
  DatabaseCodes.evidenceViewWhorlOverview => 'Whorl and newest-leaves overview',
  DatabaseCodes.evidenceViewCloseUp => 'Required closer whorl view',
  DatabaseCodes.evidenceViewDiagnosticDetail => 'Conditional evidence detail',
  _ => 'Evidence view',
};
