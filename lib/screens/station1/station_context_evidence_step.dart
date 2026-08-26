import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import 'evidence_capture_panel.dart';

class StationContextEvidenceStep extends StatefulWidget {
  const StationContextEvidenceStep({
    super.key,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.isVeV2 = false,
    required this.bundle,
    required this.isSaving,
    required this.resolveFile,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onContinue,
  });

  final int blockNumber;
  final int stationNumber;
  final bool isVeV2;
  final EvidenceCaptureBundle bundle;
  final bool isSaving;
  final Future<File> Function(String localUri) resolveFile;
  final Future<void> Function() onCapture;
  final Future<void> Function(EvidenceMediaRecord media) onInspect;
  final Future<void> Function(EvidenceMediaRecord media) onAccept;
  final Future<void> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<void> Function(String reasonCode, String? note) onManualFallback;
  final Future<void> Function() onContinue;

  @override
  State<StationContextEvidenceStep> createState() =>
      _StationContextEvidenceStepState();
}

class _StationContextEvidenceStepState
    extends State<StationContextEvidenceStep> {
  bool _cameraOpened = false;

  @override
  void initState() {
    super.initState();
    if (widget.bundle.media.isEmpty && widget.bundle.waivedViewTypes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    }
  }

  Future<void> _openCamera() async {
    if (!mounted || _cameraOpened) return;
    _cameraOpened = true;
    await widget.onCapture();
  }

  @override
  Widget build(BuildContext context) {
    final satisfied = widget.bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewStationContext,
    );
    return ListView(
      key: const Key('station_context_evidence_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        Text(
          'BLOCK ${widget.blockNumber} · STATION ${widget.stationNumber}',
          style: const TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Take station photo',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          widget.isVeV2
              ? 'Photograph the row and planting spots ahead.'
              : 'Photograph the maize row and nearby crop.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 12),
        EvidenceCapturePanel(
          title: 'Station photo',
          scopeLabel:
              'Block ${widget.blockNumber} · Station ${widget.stationNumber}',
          instruction: widget.isVeV2
              ? 'Keep the row and planting spots clearly in the frame.'
              : 'Keep the row and nearby crop clearly in the frame.',
          viewType: DatabaseCodes.evidenceViewStationContext,
          bundle: widget.bundle,
          resolveFile: widget.resolveFile,
          onCapture: widget.onCapture,
          onInspect: widget.onInspect,
          onAccept: widget.onAccept,
          onRetake: widget.onRetake,
          onRemove: widget.onRemove,
          onManualFallback: widget.onManualFallback,
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton(
            key: const Key('continue_after_station_context'),
            onPressed: satisfied && !widget.isSaving ? widget.onContinue : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}
