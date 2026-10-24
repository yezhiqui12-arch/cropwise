import 'package:flutter/material.dart';
import '../../data/repositories/plant_action_repository.dart';
import '../../theme/app_colors.dart';

class PlantActionSummary extends StatefulWidget {
  const PlantActionSummary({
    super.key,
    required this.repository,
    required this.assessmentId,
  });
  final PlantActionRepository repository;
  final String assessmentId;
  @override
  State<PlantActionSummary> createState() => _PlantActionSummaryState();
}

class _PlantActionSummaryState extends State<PlantActionSummary> {
  late Stream<Map<String, int>> _summary;
  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() =>
      _summary = widget.repository.watchSummary(widget.assessmentId);
  @override
  void didUpdateWidget(covariant PlantActionSummary old) {
    super.didUpdateWidget(old);
    if (old.assessmentId != widget.assessmentId ||
        old.repository.ownerId != widget.repository.ownerId) {
      _watch();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, int>>(
    stream: _summary,
    builder: (_, state) {
      final counts = state.data ?? {};
      if (counts.isEmpty) return const SizedBox.shrink();
      final inspected =
          (counts['inspectWhorl'] ?? 0) + (counts['inspectDamage'] ?? 0);
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F7F0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions recorded',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            if ((counts['larva'] ?? 0) > 0)
              Text('Larva removal · ${counts['larva']} plants'),
            if ((counts['eggs'] ?? 0) > 0)
              Text('Egg destruction · ${counts['eggs']} plants'),
            if (inspected > 0) Text('Inspection · $inspected records'),
          ],
        ),
      );
    },
  );
}
