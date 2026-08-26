import 'package:flutter/material.dart';

import '../../services/station_evidence_policy.dart';

class PlantSelectionStep extends StatelessWidget {
  const PlantSelectionStep({
    super.key,
    required this.onBegin,
    this.onMarkAllHealthy,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.evidencePolicy = StationEvidencePolicy.station1TwoView,
  });

  final VoidCallback onBegin;
  final VoidCallback? onMarkAllHealthy;
  final int blockNumber;
  final int stationNumber;
  final StationEvidencePolicy evidencePolicy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('plant_selection_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Text(
          'BLOCK $blockNumber · STATION $stationNumber · 0 OF 10 PLANTS SAVED',
          style: const TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Inspect 10 plants',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Start with the nearest plant ahead. Check the next nine plants in the same row.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        const _Instruction(number: '1', text: 'Keep every plant in order.'),
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
            key: const Key('begin_ten_plants_button'),
            onPressed: onBegin,
            icon: const Icon(Icons.eco_outlined),
            label: const Text('Start Plant 1'),
          ),
        ),
        if (onMarkAllHealthy != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: OutlinedButton.icon(
              key: const Key('mark_all_healthy_button'),
              onPressed: onMarkAllHealthy,
              icon: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF176B3A),
              ),
              label: const Text('All 10 Plants Clean (1-Tap Shortcut)'),
            ),
          ),
        ],
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
