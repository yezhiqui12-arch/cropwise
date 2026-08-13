import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import 'evidence_capture_panel.dart';

class StationContextEvidenceStep extends StatelessWidget {
  const StationContextEvidenceStep({
    super.key,
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
  Widget build(BuildContext context) {
    final satisfied = bundle.isViewSatisfied(
      DatabaseCodes.evidenceViewStationContext,
    );
    return ListView(
      key: const Key('station_context_evidence_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const Text(
          'BLOCK 1 · STATION 1 · CONTEXT',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Record the station context',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Photograph the maize row and immediate station surroundings without including people or identifying documents.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 12),
        const Card(
          elevation: 0,
          color: Color(0xFFFFF3CD),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This image documents context only. It does not prove that the sampling procedure or route was followed correctly.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        EvidenceCapturePanel(
          title: 'Station-context image',
          scopeLabel: 'Block 1 · Station 1',
          instruction:
              'Frame enough of the row and surrounding crop to document conditions at Station 1.',
          viewType: DatabaseCodes.evidenceViewStationContext,
          bundle: bundle,
          resolveFile: resolveFile,
          onCapture: onCapture,
          onInspect: onInspect,
          onAccept: onAccept,
          onRetake: onRetake,
          onRemove: onRemove,
          onManualFallback: onManualFallback,
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton(
            key: const Key('continue_after_station_context'),
            onPressed: satisfied && !isSaving ? onContinue : null,
            child: Text(
              bundle.waivedViewTypes.contains(
                    DatabaseCodes.evidenceViewStationContext,
                  )
                  ? 'Continue with documented fallback'
                  : 'Continue to ten plants',
            ),
          ),
        ),
      ],
    );
  }
}
