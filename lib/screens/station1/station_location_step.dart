import 'package:flutter/material.dart';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/local/database_codes.dart';
import '../../services/phone_location_service.dart';

class StationLocationStep extends StatefulWidget {
  const StationLocationStep({
    super.key,
    this.stationNumber = 1,
    required this.captureLocation,
    required this.isSaving,
    required this.onUseLocation,
    required this.onSaveUnavailable,
  });

  final int stationNumber;
  final Future<AveragedPhoneLocation> Function() captureLocation;
  final bool isSaving;
  final Future<void> Function(AveragedPhoneLocation location) onUseLocation;
  final Future<void> Function({required String reason, String? note})
  onSaveUnavailable;

  @override
  State<StationLocationStep> createState() => _StationLocationStepState();
}

class _StationLocationStepState extends State<StationLocationStep> {
  PhoneLocationException? _locationError;
  bool _capturing = false;
  bool _showUnavailable = false;
  String? _reason;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

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
        AppText(
          'STATION ${widget.stationNumber}',
          style: TextStyle(
            color: Color(0xFF176B3A),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const AppText(
          'Saving station location…',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const AppText('Keep WormWise open while it records this station.'),
        const SizedBox(height: 20),
        if (_capturing || widget.isSaving)
          const Center(child: CircularProgressIndicator()),
        if (_locationError != null) ...[
          _WarningCard(message: _locationError!.message),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: FilledButton.icon(
              key: const Key('capture_station_gps_button'),
              onPressed: _capturing || widget.isSaving ? null : _capture,
              icon: const Icon(Icons.refresh),
              label: const AppText('Try again'),
            ),
          ),
          if (_locationError!.code ==
              PhoneLocationFailureCode.servicesDisabled) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('open_location_settings_button'),
              onPressed: Geolocator.openLocationSettings,
              child: const AppText('Turn on location'),
            ),
          ],
          if (_locationError!.code ==
              PhoneLocationFailureCode.permissionBlocked) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('open_app_location_settings_button'),
              onPressed: Geolocator.openAppSettings,
              child: const AppText('Open app settings'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            key: const Key('station_gps_unavailable_button'),
            onPressed: widget.isSaving
                ? null
                : () => setState(() => _showUnavailable = true),
            child: const AppText('Record location problem'),
          ),
        ],
        if (_showUnavailable) ...[
          const SizedBox(height: 20),
          const AppText(
            'Why is station GPS unavailable?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('station_gps_reason_field'),
            initialValue: _reason,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: AppWords.of(context).translate('Select a reason'),
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
            decoration: InputDecoration(
              labelText: AppWords.of(
                context,
              ).translate('Location note (optional)'),
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
              child: const AppText('Save problem and continue'),
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
      await widget.onUseLocation(result);
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
