import 'package:flutter/material.dart';

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
          'Select ten consecutive plants',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'At Station $stationNumber, face along the approved scouting direction. Use the nearest plant directly ahead as Plant 1, then inspect the next nine plant positions consecutively in that same row.',
          style: const TextStyle(height: 1.45),
        ),
        if (evidencePolicy ==
            StationEvidencePolicy.cameraFirstOverviewConditional) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('camera_first_policy_notice'),
            elevation: 0,
            color: const Color(0xFFEAF6EE),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Camera-first pilot · ${evidencePolicy.requirementsVersion}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _Instruction(
          number: '1',
          text: 'Do not choose plants because they look damaged or healthy.',
        ),
        const _Instruction(
          number: '2',
          text:
              'Keep every position in sequence. If a plant cannot be assessed, record that position and its reason.',
        ),
        const _Instruction(
          number: '3',
          text:
              'For every assessable plant, inspect the newest three or four leaves emerging from the whorl.',
        ),
        _Instruction(
          number: '4',
          text: evidencePolicy == StationEvidencePolicy.station1TwoView
              ? 'This older saved evidence record retains its original overview-and-close-up requirement.'
              : 'Gently expose the newest leaves and whorl. Take one guided overview for every assessable plant, then continue directly to the next plant.',
        ),
        _Instruction(
          number: '5',
          text: evidencePolicy == StationEvidencePolicy.station1TwoView
              ? 'Add a third image only when a larva, egg mass, unclear feature, or other evidence needs detail.'
              : 'Add a close-up only when damage, larvae, eggs, possible non-FAW evidence, uncertainty, or inadequate overview detail makes it necessary. Use documented fallback when photography is unavailable.',
        ),
        const _Instruction(
          number: '6',
          text:
              'WormWise has no validated image model. After Plant 10, confirm every plant manually from Station Review.',
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('begin_ten_plants_button'),
            onPressed: onBegin,
            icon: const Icon(Icons.eco_outlined),
            label: const Text('Begin with Plant 1'),
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
