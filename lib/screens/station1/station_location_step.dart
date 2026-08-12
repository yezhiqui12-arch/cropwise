import 'package:flutter/material.dart';

import '../../data/local/database_codes.dart';
import '../../services/phone_location_service.dart';

class StationLocationStep extends StatefulWidget {
  const StationLocationStep({
    super.key,
    required this.captureLocation,
    required this.isSaving,
    required this.onUseLocation,
    required this.onSaveUnavailable,
  });

  final Future<AveragedPhoneLocation> Function() captureLocation;
  final bool isSaving;
  final Future<void> Function(AveragedPhoneLocation location) onUseLocation;
  final Future<void> Function({required String reason, String? note})
  onSaveUnavailable;

  @override
  State<StationLocationStep> createState() => _StationLocationStepState();
}

class _StationLocationStepState extends State<StationLocationStep> {
  AveragedPhoneLocation? _location;
  PhoneLocationException? _locationError;
  bool _capturing = false;
  bool _showUnavailable = false;
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('station_location_step'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        const Text(
          'STATION LOCATION · 0 OF 10 PLANTS SAVED',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Record Station 1',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Stand at the Station 1 observation point. WormWise will average several phone readings when available.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 16),
        if (_location != null) _LocationResult(location: _location!),
        if (_locationError != null) ...[
          _WarningCard(message: _locationError!.message),
          const SizedBox(height: 12),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: FilledButton.icon(
            key: const Key('capture_station_gps_button'),
            onPressed: _capturing || widget.isSaving ? null : _capture,
            icon: _capturing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(_location == null ? 'Record station GPS' : 'Retry GPS'),
          ),
        ),
        if (_location != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: FilledButton.tonal(
              key: const Key('use_station_gps_button'),
              onPressed: widget.isSaving ? null : _useLocation,
              child: const Text('Use this location'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: OutlinedButton(
            key: const Key('station_gps_unavailable_button'),
            onPressed: widget.isSaving
                ? null
                : () => setState(() => _showUnavailable = true),
            child: const Text('Continue without station GPS'),
          ),
        ),
        if (_showUnavailable) ...[
          const SizedBox(height: 20),
          const Text(
            'Why is station GPS unavailable?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('station_gps_reason_field'),
            initialValue: _reason,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Select a reason',
            ),
            items: _reasonLabels.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _reason = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Location note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: FilledButton(
              key: const Key('save_station_without_gps_button'),
              onPressed: _reason == null || widget.isSaving
                  ? null
                  : _saveUnavailable,
              child: const Text('Save reason and continue'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _locationError = null;
    });
    try {
      final result = await widget.captureLocation();
      if (!mounted) return;
      setState(() => _location = result);
    } on PhoneLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = error;
        _showUnavailable = true;
        _reason ??= _reasonForFailure(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationError = const PhoneLocationException(
          'Could not read the phone location. Retry or save why it is unavailable.',
        );
        _showUnavailable = true;
      });
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _useLocation() => _run(() => widget.onUseLocation(_location!));

  Future<void> _saveUnavailable() =>
      _run(() => widget.onSaveUnavailable(reason: _reason!, note: _note.text));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }
}

class _LocationResult extends StatelessWidget {
  const _LocationResult({required this.location});

  final AveragedPhoneLocation location;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('station_gps_result'),
      elevation: 0,
      color: const Color(0xFFEAF6EE),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Phone location received',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 4),
            Text(
              'Average reported accuracy: ${location.averageAccuracyMeters.toStringAsFixed(1)} m · ${location.sampleCount} reading${location.sampleCount == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 6),
            const Text(
              'Accuracy is the phone’s technical estimate. It is displayed for context and does not block this station.',
              style: TextStyle(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF3CD),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, style: const TextStyle(height: 1.4)),
      ),
    );
  }
}

const _reasonLabels = <String, String>{
  DatabaseCodes.stationLocationServicesOff: 'Phone location is off',
  DatabaseCodes.stationPermissionDenied: 'Location permission denied',
  DatabaseCodes.stationPermissionBlocked: 'Permission blocked in settings',
  DatabaseCodes.stationNoCurrentFix: 'No current GPS reading',
  DatabaseCodes.stationUnsafeToWait: 'Unsafe or impractical to wait here',
  DatabaseCodes.stationLocationDeviceError: 'Phone or location error',
  DatabaseCodes.stationLocationOther: 'Other reason',
};

String _reasonForFailure(PhoneLocationFailureCode code) => switch (code) {
  PhoneLocationFailureCode.servicesDisabled =>
    DatabaseCodes.stationLocationServicesOff,
  PhoneLocationFailureCode.permissionDenied =>
    DatabaseCodes.stationPermissionDenied,
  PhoneLocationFailureCode.permissionBlocked =>
    DatabaseCodes.stationPermissionBlocked,
  PhoneLocationFailureCode.noCurrentFix => DatabaseCodes.stationNoCurrentFix,
  PhoneLocationFailureCode.deviceError =>
    DatabaseCodes.stationLocationDeviceError,
};
