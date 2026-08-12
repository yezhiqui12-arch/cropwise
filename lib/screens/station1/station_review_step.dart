import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../data/repositories/station1_workflow_repository.dart';

class StationReviewStep extends StatelessWidget {
  const StationReviewStep({
    super.key,
    required this.snapshot,
    required this.isSaving,
    required this.onEdit,
    required this.onConfirm,
  });

  final Station1Snapshot snapshot;
  final bool isSaving;
  final ValueChanged<int> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final station = snapshot.station!;
    return ListView(
      key: const Key('station_review_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const Text(
          'BLOCK 1 · STATION 1 · 10 OF 10 PLANTS SAVED',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Review Station 1',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          station.latitude == null
              ? 'Station GPS unavailable: ${_reasonLabel(station.notLocatedReason)}'
              : 'Station GPS saved · reported accuracy ${station.gpsAccuracyM!.toStringAsFixed(1)} m',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        for (final item in snapshot.plants)
          _PlantReviewCard(item: item, onEdit: onEdit),
        const SizedBox(height: 18),
        const Card(
          elevation: 0,
          color: Color(0xFFEAF6EE),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Confirm only after checking all ten saved positions. Editing any plant later will require a new review confirmation.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('confirm_station_review_button'),
            onPressed: isSaving ? null : onConfirm,
            icon: const Icon(Icons.check_circle_outline),
            label: isSaving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm Station 1 review'),
          ),
        ),
      ],
    );
  }
}

class _PlantReviewCard extends StatelessWidget {
  const _PlantReviewCard({required this.item, required this.onEdit});

  final Station1PlantRecord item;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final plant = item.plant;
    final raw = <String>[
      if (item.vegetative.smallFreshWindowpanes) 'windowpanes',
      if (item.vegetative.scraping) 'scraping',
      if (item.vegetative.cuttingOrTearing) 'cutting/tearing',
      if (item.vegetative.freshFrass) 'frass',
      if (item.vegetative.whorlFeedingSign) 'whorl signs',
      if (item.vegetative.larvaVisible) 'visible larva',
      if (item.vegetative.eggMassVisible == true) 'egg mass',
      if (plant.oldDamagePresent) 'old damage',
      if (plant.possibleNonFawEvidence == true) 'possible non-FAW',
      if (plant.uncertainEvidence == true) 'uncertain evidence',
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plant ${plant.sequenceNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_statusLabel(plant.plantStatus)),
                  const SizedBox(height: 4),
                  Text(
                    plant.assessable
                        ? (raw.isEmpty
                              ? 'No listed raw signs selected'
                              : raw.join(' · '))
                        : 'Not assessable: ${plant.notAssessableReason}',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('edit_plant_${plant.sequenceNumber}_button'),
              tooltip: 'Edit Plant ${plant.sequenceNumber}',
              onPressed: () => onEdit(plant.sequenceNumber),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  DatabaseCodes.plantNegative => 'No current FAW-consistent evidence',
  DatabaseCodes.plantCurrentPositive => 'Current FAW-consistent evidence',
  DatabaseCodes.plantOldDamageOnly => 'Old damage only',
  DatabaseCodes.plantPossibleNonFaw => 'Possible non-FAW evidence',
  DatabaseCodes.plantUncertain => 'Uncertain interpretation',
  DatabaseCodes.plantNotAssessable => 'Not assessable',
  _ => status,
};

String _reasonLabel(String? reason) => switch (reason) {
  DatabaseCodes.stationLocationServicesOff => 'phone location was off',
  DatabaseCodes.stationPermissionDenied => 'permission was denied',
  DatabaseCodes.stationPermissionBlocked => 'permission was blocked',
  DatabaseCodes.stationNoCurrentFix => 'no current GPS reading',
  DatabaseCodes.stationUnsafeToWait => 'unsafe or impractical to wait',
  DatabaseCodes.stationLocationDeviceError => 'phone or location error',
  DatabaseCodes.stationLocationOther => 'other recorded reason',
  _ => 'recorded reason',
};
