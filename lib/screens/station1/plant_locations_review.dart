import '../../localization/app_text.dart';
import 'package:flutter/material.dart';
import '../../data/repositories/scouting_workflow_repository.dart';

/// Display only: plant fixes belong to photo capture, never review-time GPS.
class PlantLocationsReview extends StatelessWidget {
  const PlantLocationsReview({
    super.key,
    required this.snapshot,
    required this.onRetryStation,
  });
  final StationSnapshot snapshot;
  final VoidCallback onRetryStation;
  @override
  Widget build(BuildContext context) {
    final station = snapshot.station;
    final located = snapshot.plants
        .where(
          (p) =>
              p.plant.locationSource == 'phone_gps' && p.plant.latitude != null,
        )
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.location_on_outlined),
              label: AppText(
                'Plant locations: $located/${snapshot.plants.length}',
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * .65,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        AppText(
                          'Locations recorded during capture',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const AppText(
                          'Approximate phone GPS. Nearby plants may overlap. To record missing plant GPS, return to that plant and retake its photo.',
                        ),
                        for (final item in snapshot.plants)
                          ListTile(
                            title: AppText(
                              'Plant ${item.plant.sequenceNumber}',
                            ),
                            subtitle: Text(
                              item.plant.locationSource == 'phone_gps' &&
                                      item.plant.latitude != null &&
                                      item.plant.longitude != null
                                  ? '${item.plant.latitude!.toStringAsFixed(6)}, ${item.plant.longitude!.toStringAsFixed(6)}\nAccuracy ±${item.plant.gpsAccuracyM?.toStringAsFixed(1) ?? "?"} m · ${item.plant.locationCapturedAt?.toLocal().toString() ?? "Time unavailable"}'
                                  : 'Location not recorded or unverified',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (station?.locationSource != 'phone_gps')
            TextButton(
              onPressed: onRetryStation,
              child: const AppText('Retry station GPS'),
            ),
        ],
      ),
    );
  }
}
