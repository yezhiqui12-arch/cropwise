import 'package:flutter/material.dart';
import '../../localization/app_text.dart';

import '../../services/station_evidence_policy.dart';

class PlantSelectionStep extends StatelessWidget {
  const PlantSelectionStep({
    super.key,
    required this.onBegin,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.evidencePolicy = StationEvidencePolicy.station1TwoView,
  });

  final VoidCallback onBegin;
  final int blockNumber;
  final int stationNumber;
  final StationEvidencePolicy evidencePolicy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('plant_selection_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        AppText(
          'BLOCK $blockNumber · PLANT $stationNumber',
          style: const TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const AppText(
          'Inspect this plant',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const AppText(
          'Inspect the selected plant at this sampling point.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        const _Instruction(
          number: '1',
          text: 'Keep the selected plant at this point.',
        ),
        const _Instruction(
          number: '2',
          text: 'Check the newest leaves and whorl.',
        ),
        const _Instruction(
          number: '3',
          text: 'Take a close-up only when more detail is needed.',
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('begin_selected_plant_button'),
            onPressed: onBegin,
            icon: const Icon(Icons.pin_drop_outlined),
            label: const AppText('Start this plant'),
          ),
        ),
      ],
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFEAF6EE),
            foregroundColor: const Color(0xFF176B3A),
            child: Text(
              number,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
