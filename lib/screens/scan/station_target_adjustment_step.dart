import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../services/scouting_route_generator.dart';
import '../../services/field_imagery_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';

class StationTargetAdjustmentStep extends StatefulWidget {
  const StationTargetAdjustmentStep({
    super.key,
    required this.boundary,
    required this.plan,
    required this.completedStationLocations,
    required this.completedStationNumbers,
    required this.isSaving,
    required this.onSaveDraft,
    required this.onApply,
    required this.onCancel,
    this.imageryProvider,
  });

  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final bool isSaving;
  final Future<void> Function({
    required LatLng? candidate,
    required String reason,
  })
  onSaveDraft;
  final Future<void> Function() onApply;
  final Future<void> Function() onCancel;
  final FieldImageryProvider? imageryProvider;

  @override
  State<StationTargetAdjustmentStep> createState() =>
      _StationTargetAdjustmentStepState();
}

class _StationTargetAdjustmentStepState
    extends State<StationTargetAdjustmentStep> {
  late final TextEditingController _reasonController;
  Timer? _saveTimer;
  LatLng? _candidate;
  String? _error;

  PendingTargetAdjustment get _pending => widget.plan.pendingAdjustment!;

  @override
  void initState() {
    super.initState();
    _candidate = _pending.candidate;
    _reasonController = TextEditingController(text: _pending.reason);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  void _scheduleReasonSave(String _) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _persistDraft);
  }

  Future<void> _selectCandidate(LatLng value) async {
    setState(() {
      _candidate = value;
      _error = null;
    });
    await _persistDraft();
  }

  Future<void> _persistDraft() async {
    try {
      await widget.onSaveDraft(
        candidate: _candidate,
        reason: _reasonController.text,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    }
  }

  Future<void> _apply() async {
    _saveTimer?.cancel();
    try {
      await _persistDraft();
      await widget.onApply();
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationNumber = _pending.stationNumber;
    return ListView(
      key: const Key('station_target_adjustment_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        const Text(
          'TARGET ADJUSTMENT',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Move Station $stationNumber safely',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap a suitable position inside the assessment block and outside marked obstacles. Completed station locations cannot be changed.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 14),
        OfflineScoutingRouteMap(
          boundary: widget.boundary,
          plan: widget.plan,
          activeStation: stationNumber,
          completedStationLocations: widget.completedStationLocations,
          completedStationNumbers: widget.completedStationNumbers,
          imageryProvider: widget.imageryProvider,
          candidate: _candidate,
          onTap: widget.isSaving ? null : _selectCandidate,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('station_target_adjustment_reason'),
          controller: _reasonController,
          enabled: !widget.isSaving,
          minLines: 2,
          maxLines: 4,
          onChanged: _scheduleReasonSave,
          decoration: const InputDecoration(
            labelText: 'Required reason',
            hintText:
                'For example: deep ditch, dense vegetation, unsafe access',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('target_adjustment_error'),
            style: const TextStyle(color: Color(0xFFB3261E)),
          ),
        ],
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('apply_station_target_adjustment'),
            onPressed: widget.isSaving ? null : _apply,
            icon: const Icon(Icons.check),
            label: const Text('Use adjusted target'),
          ),
        ),
        TextButton(
          key: const Key('cancel_station_target_adjustment'),
          onPressed: widget.isSaving ? null : widget.onCancel,
          child: const Text('Cancel adjustment'),
        ),
      ],
    );
  }
}

String _friendly(Object error) => error
    .toString()
    .replaceFirst('StateError: ', '')
    .replaceFirst('RouteGenerationException: ', '');
