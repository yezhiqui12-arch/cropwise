import 'dart:async';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../data/repositories/evidence_capture_repository.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../../services/station_evidence_policy.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/phone_location_service.dart';
import '../../services/scouting_route_generator.dart';
import '../../widgets/offline_scouting_route_map.dart';
import 'station_batch_upload_screen.dart' show EvidenceSlot;

class PlantCaptureBoardStep extends StatefulWidget {
  const PlantCaptureBoardStep({
    super.key,
    this.blockNumber = 1,
    this.stationNumber = 1,
    this.isVeV2 = false,
    this.evidencePolicy = StationEvidencePolicy.cameraFirstOverviewConditional,
    required this.selectedPosition,
    required this.boundary,
    required this.plan,
    required this.watchLocation,
    this.completedStationLocations = const {},
    this.completedStationNumbers = const {},
    this.imageryProvider,
    required this.capturedPlantCount,
    required this.stationBundles,
    this.veV2Units = const [],
    required this.isSaving,
    required this.resolveFile,
    required this.onSelectPlant,
    required this.onCapture,
    this.onBatchUpload,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onCompleteStationCapture,
    required this.onCannotAssess,
    this.onSaveVeV2UnitException,
    this.onQuickOverride,
    this.cvDiagnoses = const {},
    this.primaryViewType,
  });

  final int blockNumber;
  final int stationNumber;
  final bool isVeV2;
  final StationEvidencePolicy evidencePolicy;
  final int selectedPosition;
  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final FieldImageryProvider? imageryProvider;
  final int capturedPlantCount;
  final List<EvidenceCaptureBundle> stationBundles;
  final List<PlantingUnitObservationRecord> veV2Units;
  final bool isSaving;
  final Future<File> Function(String localUri) resolveFile;
  final ValueChanged<int> onSelectPlant;
  final Future<String?> Function(int position, String viewType) onCapture;
  final VoidCallback? onBatchUpload;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<bool> Function(EvidenceMediaRecord media) onAccept;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<bool> Function(
    int position,
    String viewType,
    String reason,
    String? note,
  )
  onManualFallback;
  final VoidCallback onCompleteStationCapture;
  final Future<void> Function(int position, String reason) onCannotAssess;
  final Future<void> Function(int position, String occupancy, String? reason)?
  onSaveVeV2UnitException;
  final Future<void> Function(int position, String status)? onQuickOverride;
  final Map<int, PlantDiagnosisResult> cvDiagnoses;
  final String? primaryViewType;

  @override
  State<PlantCaptureBoardStep> createState() => _PlantCaptureBoardStepState();
}

class _PlantCaptureBoardStepState extends State<PlantCaptureBoardStep> {
  int? _expandedPosition;
  StreamSubscription<PhoneLocationReading>? _locationSubscription;
  PhoneLocationReading? _location;
  bool _locationPromptShown = false;

  String get _primaryViewType => widget.isVeV2
      ? DatabaseCodes.evidenceViewWholeSeedling
      : widget.primaryViewType ?? DatabaseCodes.evidenceViewWhorlOverview;

  @override
  void initState() {
    super.initState();
    _expandedPosition = widget.selectedPosition;
    _startLocation();
  }

  Future<void> _startLocation() async {
    try {
      final stream = await widget.watchLocation();
      _locationSubscription = stream.listen((reading) {
        if (mounted) setState(() => _location = reading);
      });
    } on PhoneLocationException catch (error) {
      if (mounted) _offerLocationFix(error);
    } catch (_) {
      // Plant capture remains usable when the device cannot provide GPS.
    }
  }

  Future<void> _offerLocationFix(PhoneLocationException error) async {
    if (_locationPromptShown || !mounted) return;
    _locationPromptShown = true;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.location_off_outlined),
        title: const AppText('Location needed'),
        content: AppText(
          '${error.message}\n\nTurn on location so WormWise can show where you are inside the field.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.settings_outlined),
            label: AppText(
              error.code == PhoneLocationFailureCode.servicesDisabled
                  ? 'Turn on location'
                  : 'Open settings',
            ),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      if (error.code == PhoneLocationFailureCode.servicesDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
      _locationPromptShown = false;
      await _startLocation();
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlantCaptureBoardStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPosition != widget.selectedPosition) {
      _expandedPosition = widget.selectedPosition;
    }
  }

  void _togglePlant(int position) {
    if (widget.capturedPlantCount < 10 && position > _firstIncompletePosition) {
      return;
    }
    setState(() {
      if (_expandedPosition == position) {
        _expandedPosition = null; // Close card if already open!
      } else {
        _expandedPosition = position; // Open card!
        widget.onSelectPlant(position);
      }
    });
  }

  EvidenceCaptureBundle? _bundleFor(int position) {
    for (final b in widget.stationBundles) {
      if (b.session.scopeType == DatabaseCodes.evidenceScopePlant &&
          b.session.plantPosition == position) {
        return b;
      }
    }
    return null;
  }

  bool _isPlantSatisfied(int position) {
    if (widget.isVeV2) {
      for (final unit in widget.veV2Units) {
        if (unit.sequenceNumber == position &&
            (unit.occupancyStatus == DatabaseCodes.veOccupancyEmpty ||
                unit.occupancyStatus ==
                    DatabaseCodes.veOccupancyNotAssessable)) {
          return true;
        }
      }
    }
    final bundle = _bundleFor(position);
    if (bundle == null) return false;
    if (bundle.session.completedAt != null) return true;
    final hasPrimary =
        bundle.isViewSatisfied(_primaryViewType) ||
        bundle.media.any(
          (m) =>
              m.viewType == _primaryViewType &&
              m.deletedAt == null &&
              (m.storageState == DatabaseCodes.evidenceStorageReady ||
                  m.storageState == DatabaseCodes.evidenceStorageStaged),
        );
    final hasWaived = bundle.waivedViewTypes.isNotEmpty;
    return hasPrimary || hasWaived;
  }

  int get _firstIncompletePosition {
    for (var pos = 1; pos <= 10; pos++) {
      if (!_isPlantSatisfied(pos)) return pos;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final allComplete = widget.capturedPlantCount >= 10;
    final activeTarget = _expandedPosition ?? _firstIncompletePosition;

    return Column(
      children: [
        _BoardHeader(
          blockNumber: widget.blockNumber,
          stationNumber: widget.stationNumber,
          isVeV2: widget.isVeV2,
          capturedCount: widget.capturedPlantCount,
          isSaving: widget.isSaving,
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('continuous_plant_capture_step'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            itemCount: 10,
            itemBuilder: (context, index) {
              final position = index + 1;
              final bundle = _bundleFor(position);
              final isSelected = position == _expandedPosition;
              final isSatisfied = _isPlantSatisfied(position);
              final diagnosis = widget.cvDiagnoses[position];
              final unit = widget.veV2Units
                  .where((u) => u.sequenceNumber == position)
                  .firstOrNull;

              return _PlantTile(
                key: ValueKey('plant_tile_$position'),
                position: position,
                isVeV2: widget.isVeV2,
                unit: unit,
                isSelected: isSelected,
                isSatisfied: isSatisfied,
                bundle: bundle,
                diagnosis: diagnosis,
                isSaving: widget.isSaving,
                evidencePolicy: widget.evidencePolicy,
                primaryViewType: _primaryViewType,
                resolveFile: widget.resolveFile,
                onTap: () => _togglePlant(position),
                onCapture: widget.onCapture,
                onInspect: widget.onInspect,
                onAccept: widget.onAccept,
                onRetake: widget.onRetake,
                onRemove: widget.onRemove,
                onManualFallback: widget.onManualFallback,
                onCannotAssess: () => _showCannotAssessDialog(position),
                onChoosePositionException:
                    widget.onSaveVeV2UnitException == null
                    ? null
                    : () => _showVeV2PositionExceptionDialog(position),
                onQuickOverride: widget.onQuickOverride == null
                    ? null
                    : (status) => widget.onQuickOverride!(position, status),
                onNextPlant: () {
                  final nextPos = position < 10 ? position + 1 : 1;
                  _togglePlant(nextPos);
                },
              );
            },
          ),
        ),
        if (!widget.isVeV2 && !allComplete && widget.onBatchUpload != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('open_station_batch_upload'),
                onPressed: widget.isSaving ? null : widget.onBatchUpload,
                icon: const Icon(Icons.photo_library_outlined),
                label: const AppText('Import station photos together'),
              ),
            ),
          ),
        _BoardBottomBar(
          allComplete: allComplete,
          isVeV2: widget.isVeV2,
          selectedPosition: activeTarget,
          isSaving: widget.isSaving,
          mapAction: _PlantPositionMiniMap(
            boundary: widget.boundary,
            plan: widget.plan,
            stationNumber: widget.stationNumber,
            completedStationLocations: widget.completedStationLocations,
            completedStationNumbers: widget.completedStationNumbers,
            currentLocation: _location,
            watchLocation: widget.watchLocation,
            imageryProvider: widget.imageryProvider,
          ),
          onAction: () {
            if (allComplete) {
              widget.onCompleteStationCapture();
            } else {
              final target = activeTarget;
              final bundle = _bundleFor(target);
              final hasPrimary =
                  bundle?.isViewSatisfied(_primaryViewType) ?? false;
              final viewType = hasPrimary
                  ? DatabaseCodes.evidenceViewCloseUp
                  : _primaryViewType;
              widget.onCapture(target, viewType);
            }
          },
        ),
      ],
    );
  }

  Future<void> _showVeV2PositionExceptionDialog(int position) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppText(
                  'What is at Seedling Position $position?',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.grass_outlined),
                  title: const AppText('Empty spot'),
                  subtitle: const AppText('No emerged seedling at this spot.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancyEmpty,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.content_cut_outlined),
                  title: const AppText('Seedling remnant'),
                  subtitle: const AppText('Dead or cut seedling stem remnant.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancyRemnant,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const AppText('Living seedling'),
                  subtitle: const AppText('Living maize seedling present.'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    DatabaseCodes.veOccupancySeedling,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted && widget.onSaveVeV2UnitException != null) {
      await widget.onSaveVeV2UnitException!(position, result, null);
    }
  }

  Future<void> _showCannotAssessDialog(int position) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText('Cannot assess Plant $position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Document why this plant cannot be assessed (e.g. missing plant, animal damage, flooded spot).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: AppWords.of(context).translate('Reason'),
                hintText: AppWords.of(
                  context,
                ).translate('e.g. Broken stem / Missing seedling'),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(
                dialogContext,
                text.isEmpty ? 'Cannot assess plant' : text,
              );
            },
            child: const AppText('Confirm'),
          ),
        ],
      ),
    );
    if (reason != null && mounted) {
      await widget.onCannotAssess(position, reason);
    }
  }
}

class _PlantPositionMiniMap extends StatefulWidget {
  const _PlantPositionMiniMap({
    required this.boundary,
    required this.plan,
    required this.stationNumber,
    required this.completedStationLocations,
    required this.completedStationNumbers,
    required this.currentLocation,
    required this.watchLocation,
    required this.imageryProvider,
  });

  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final int stationNumber;
  final Map<int, LatLng> completedStationLocations;
  final Set<int> completedStationNumbers;
  final PhoneLocationReading? currentLocation;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final FieldImageryProvider? imageryProvider;

  @override
  State<_PlantPositionMiniMap> createState() => _PlantPositionMiniMapState();
}

class _PlantPositionMiniMapState extends State<_PlantPositionMiniMap> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        key: const Key('open_plant_position_map'),
        onPressed: _openExpandedMap,
        icon: const Icon(Icons.map_outlined, size: 20),
        label: const AppText(
          'View map',
          maxLines: 1,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          side: const BorderSide(color: Color(0xFFB8CDBE)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Future<void> _openExpandedMap() async {
    var fieldRevision = 0;
    var locationRevision = 0;
    Stream<PhoneLocationReading>? locationStream;
    try {
      locationStream = await widget.watchLocation();
    } catch (_) {
      // The parent screen already offers the relevant location settings.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) =>
            StreamBuilder<PhoneLocationReading>(
              stream: locationStream,
              initialData: widget.currentLocation,
              builder: (context, locationSnapshot) => Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 34,
                ),
                elevation: 16,
                shadowColor: Colors.black.withValues(alpha: .28),
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 560,
                    maxHeight: 650,
                  ),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * .70,
                    child: Material(
                      color: const Color(0xFFF7F9F5),
                      borderRadius: BorderRadius.circular(26),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: AppText(
                                    'Field position',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  key: const Key('close_expanded_plant_map'),
                                  tooltip: AppWords.of(
                                    context,
                                  ).translate('Close map'),
                                  onPressed: () => Navigator.pop(dialogContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                  key: const Key(
                                    'center_expanded_plant_map_on_field',
                                  ),
                                  onPressed: () =>
                                      setDialogState(() => fieldRevision++),
                                  icon: const Icon(Icons.center_focus_strong),
                                  label: const AppText('Field'),
                                ),
                                TextButton.icon(
                                  key: const Key(
                                    'center_expanded_plant_map_on_user',
                                  ),
                                  onPressed: locationSnapshot.data == null
                                      ? null
                                      : () => setDialogState(
                                          () => locationRevision++,
                                        ),
                                  icon: const Icon(Icons.my_location),
                                  label: const AppText('My location'),
                                ),
                                if (locationSnapshot.data == null)
                                  const AppText('Waiting for GPS'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: Material(
                                borderRadius: BorderRadius.circular(20),
                                clipBehavior: Clip.antiAlias,
                                child: OfflineScoutingRouteMap(
                                  boundary: widget.boundary,
                                  plan: widget.plan,
                                  activeStation: widget.stationNumber,
                                  completedStationLocations:
                                      widget.completedStationLocations,
                                  completedStationNumbers:
                                      widget.completedStationNumbers,
                                  currentLocation: locationSnapshot.data,
                                  animateAssessmentStation:
                                      widget.stationNumber,
                                  imageryProvider: widget.imageryProvider,
                                  recenterFieldRevision: fieldRevision,
                                  recenterLocationRevision: locationRevision,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.blockNumber,
    required this.stationNumber,
    this.isVeV2 = false,
    required this.capturedCount,
    required this.isSaving,
  });

  final int blockNumber;
  final int stationNumber;
  final bool isVeV2;
  final int capturedCount;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF176B3A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppText(
                  'BLOCK $blockNumber Â· STATION $stationNumber',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              AppText(
                '$capturedCount/10 Captured',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: capturedCount >= 10
                      ? const Color(0xFF176B3A)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              AppText(
                isVeV2 ? 'Capture Seedlings 1â€“10' : 'Capture Plants 1â€“10',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlantTile extends StatelessWidget {
  const _PlantTile({
    super.key,
    required this.position,
    this.isVeV2 = false,
    this.unit,
    required this.isSelected,
    required this.isSatisfied,
    required this.bundle,
    this.diagnosis,
    required this.isSaving,
    required this.evidencePolicy,
    required this.primaryViewType,
    required this.resolveFile,
    required this.onTap,
    required this.onCapture,
    required this.onInspect,
    required this.onAccept,
    required this.onRetake,
    required this.onRemove,
    required this.onManualFallback,
    required this.onCannotAssess,
    this.onChoosePositionException,
    this.onQuickOverride,
    required this.onNextPlant,
  });

  final int position;
  final bool isVeV2;
  final PlantingUnitObservationRecord? unit;
  final bool isSelected;
  final bool isSatisfied;
  final EvidenceCaptureBundle? bundle;
  final PlantDiagnosisResult? diagnosis;
  final bool isSaving;
  final StationEvidencePolicy evidencePolicy;
  final String primaryViewType;
  final Future<File> Function(String localUri) resolveFile;
  final VoidCallback onTap;
  final Future<String?> Function(int position, String viewType) onCapture;
  final Future<String?> Function(EvidenceMediaRecord media) onInspect;
  final Future<bool> Function(EvidenceMediaRecord media) onAccept;
  final Future<String?> Function(EvidenceMediaRecord media) onRetake;
  final Future<void> Function(EvidenceMediaRecord media) onRemove;
  final Future<bool> Function(
    int position,
    String viewType,
    String reason,
    String? note,
  )
  onManualFallback;
  final VoidCallback onCannotAssess;
  final VoidCallback? onChoosePositionException;
  final Future<void> Function(String status)? onQuickOverride;
  final VoidCallback onNextPlant;

  String get _primaryViewType =>
      isVeV2 ? DatabaseCodes.evidenceViewWholeSeedling : primaryViewType;

  String get _primaryViewLabel => isVeV2 ? 'Seedling' : 'Overview';

  EvidenceMediaRecord? _mediaFor(String viewType) {
    if (bundle == null) return null;
    for (final m in bundle!.media.reversed) {
      if (m.viewType == viewType &&
          m.deletedAt == null &&
          (m.storageState == DatabaseCodes.evidenceStorageReady ||
              m.storageState == DatabaseCodes.evidenceStorageStaged)) {
        return m;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final primaryMedia = _mediaFor(_primaryViewType);
    final closeUpMedia = _mediaFor(DatabaseCodes.evidenceViewCloseUp);
    final detailMedia = _mediaFor(DatabaseCodes.evidenceViewDiagnosticDetail);
    final hasPrimary =
        primaryMedia != null ||
        (bundle?.isViewSatisfied(_primaryViewType) ?? false);
    final hasCloseUp =
        closeUpMedia != null ||
        (bundle?.isViewSatisfied(DatabaseCodes.evidenceViewCloseUp) ?? false);
    final hasDetail =
        detailMedia != null ||
        (bundle?.isViewSatisfied(DatabaseCodes.evidenceViewDiagnosticDetail) ??
            false);
    final isWaived = (bundle?.waivedViewTypes.isNotEmpty) ?? false;
    final isEmptySpot = unit?.occupancyStatus == DatabaseCodes.veOccupancyEmpty;
    final isRemnant = unit?.occupancyStatus == DatabaseCodes.veOccupancyRemnant;

    final String statusSubtitle;
    if (isEmptySpot) {
      statusSubtitle = 'Empty spot documented';
    } else if (isRemnant) {
      statusSubtitle = 'Remnant documented';
    } else if (isWaived) {
      statusSubtitle = 'Manual fallback documented';
    } else if (hasPrimary && hasCloseUp && hasDetail) {
      statusSubtitle = '$_primaryViewLabel âœ“ Â· Close-up âœ“ Â· Detail âœ“';
    } else if (hasPrimary && hasCloseUp) {
      statusSubtitle = '$_primaryViewLabel âœ“ Â· Close-up âœ“';
    } else if (hasPrimary) {
      statusSubtitle = '$_primaryViewLabel âœ“ Â· Close-up optional';
    } else {
      statusSubtitle = '$_primaryViewLabel needed';
    }

    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : isSatisfied
        ? const Color(0xFF176B3A).withValues(alpha: 0.3)
        : Colors.black12;

    final bgColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2)
        : isSatisfied
        ? const Color(0xFFF6FBF7)
        : Colors.white;

    final titleLabel = isVeV2 ? 'Seedling $position' : 'Plant $position';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
      ),
      color: bgColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PlantNumberBadge(
                    position: position,
                    done: isSatisfied,
                    active: isSelected,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          titleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isEmptySpot || isRemnant || isWaived)
                              _StatusChip(
                                label: statusSubtitle,
                                icon: Icons.info_outline,
                                filled: true,
                              )
                            else ...[
                              _StatusChip(
                                label: _primaryViewLabel,
                                icon: Icons.local_florist_outlined,
                                filled: hasPrimary,
                              ),
                              _StatusChip(
                                label: 'Close-up',
                                icon: Icons.zoom_in,
                                filled: hasCloseUp,
                              ),
                              _StatusChip(
                                label: 'Detail',
                                icon: Icons.biotech_outlined,
                                filled: hasDetail,
                              ),
                            ],
                            if (diagnosis != null)
                              _DiagnosisPill(diagnosis: diagnosis!),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isSelected)
                    _ThumbStack(
                      media: [
                        ?primaryMedia,
                        ?closeUpMedia,
                        ?detailMedia,
                      ],
                      resolveFile: resolveFile,
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    isSelected
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.black45,
                    size: 20,
                  ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (index, slot) in [
                      (
                        _primaryViewType,
                        _primaryViewLabel,
                        Icons.local_florist_outlined,
                        primaryMedia,
                        true,
                      ),
                      (
                        DatabaseCodes.evidenceViewCloseUp,
                        'Close-up',
                        Icons.zoom_in,
                        closeUpMedia,
                        false,
                      ),
                      (
                        DatabaseCodes.evidenceViewDiagnosticDetail,
                        'Detail',
                        Icons.biotech_outlined,
                        detailMedia,
                        false,
                      ),
                    ].indexed) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: slot.$4 == null
                            ? EvidenceSlot(
                                label: slot.$2,
                                icon: slot.$3,
                                required: slot.$5,
                                onTap: () => onCapture(position, slot.$1),
                              )
                            : EvidenceSlot(
                                key: ValueKey(slot.$4!.id),
                                label: slot.$2,
                                icon: slot.$3,
                                image: _MediaImage(
                                  media: slot.$4!,
                                  resolveFile: resolveFile,
                                ),
                                trailing: Column(
                                  children: [
                                    _MicroActionButton(
                                      icon: Icons.refresh,
                                      tooltip: AppWords.of(
                                        context,
                                      ).translate('Retake'),
                                      onTap: () => onRetake(slot.$4!),
                                    ),
                                    const SizedBox(height: 4),
                                    _MicroActionButton(
                                      icon: Icons.delete_outline,
                                      tooltip: AppWords.of(
                                        context,
                                      ).translate('Remove'),
                                      onTap: () => onRemove(slot.$4!),
                                    ),
                                  ],
                                ),
                                onTap: () => onInspect(slot.$4!),
                              ),
                      ),
                    ],
                  ],
                ),
                if (diagnosis != null || hasPrimary) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (diagnosis?.classificationLabel == 'FAW damage' ||
                              diagnosis?.isInfested == true)
                          ? const Color(0xFFFDE8E8)
                          : const Color(0xFFEAF6EE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            (diagnosis?.classificationLabel == 'FAW damage' ||
                                diagnosis?.isInfested == true)
                            ? const Color(0xFFB3261E).withValues(alpha: 0.3)
                            : const Color(0xFF176B3A).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              (diagnosis?.classificationLabel == 'FAW damage' ||
                                      diagnosis?.isInfested == true)
                                  ? Icons.bug_report
                                  : Icons.check_circle,
                              size: 16,
                              color:
                                  (diagnosis?.classificationLabel ==
                                          'FAW damage' ||
                                      diagnosis?.isInfested == true)
                                  ? const Color(0xFFB3261E)
                                  : const Color(0xFF176B3A),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: AppText(
                                diagnosis != null
                                    ? '${diagnosis!.pestLabel} Â· ${(diagnosis!.confidenceScore * 100).toInt()}% confidence'
                                    : 'Photo ready for review',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      (diagnosis?.classificationLabel ==
                                              'FAW damage' ||
                                          diagnosis?.isInfested == true)
                                      ? const Color(0xFFB3261E)
                                      : const Color(0xFF176B3A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (diagnosis?.detectedSigns.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          AppText(
                            'Signs detected: ${diagnosis!.detectedSigns.map((s) => s.replaceAll('_', ' ')).join(', ')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      key: const Key('capture_cannot_assess'),
                      onPressed: isSaving ? null : onCannotAssess,
                      icon: const Icon(Icons.report_outlined, size: 14),
                      label: const AppText(
                        'Cannot assess',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    if (isVeV2 && onChoosePositionException != null)
                      TextButton.icon(
                        key: ValueKey('ve_spot_exception_$position'),
                        onPressed: isSaving ? null : onChoosePositionException,
                        icon: const Icon(Icons.more_horiz, size: 14),
                        label: AppText(
                          isEmptySpot
                              ? 'Empty'
                              : isRemnant
                              ? 'Remnant'
                              : 'Spot status',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (isSatisfied && position < 10)
                      FilledButton.tonalIcon(
                        onPressed: onNextPlant,
                        icon: const Icon(Icons.arrow_forward, size: 13),
                        label: AppText(
                          'Next (${isVeV2 ? "Seedling" : "Plant"} ${position + 1})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardBottomBar extends StatelessWidget {
  const _BoardBottomBar({
    required this.allComplete,
    this.isVeV2 = false,
    required this.selectedPosition,
    required this.isSaving,
    required this.mapAction,
    required this.onAction,
  });

  final bool allComplete;
  final bool isVeV2;
  final int selectedPosition;
  final bool isSaving;
  final Widget mapAction;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final noun = isVeV2 ? 'Seedling' : 'Plant';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      color: Colors.transparent,
      child: Row(
        children: [
          mapAction,
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('finish_plant_capture'),
                onPressed: isSaving ? null : onAction,
                icon: Icon(
                  allComplete
                      ? Icons.fact_check_outlined
                      : Icons.camera_alt_outlined,
                ),
                label: AppText(
                  allComplete
                      ? 'Review station'
                      : 'Capture $noun $selectedPosition',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroActionButton extends StatelessWidget {
  const _MicroActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 13,
        color: Colors.white,
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
      ),
    );
  }
}


class _PlantNumberBadge extends StatelessWidget {
  const _PlantNumberBadge({
    required this.position,
    required this.done,
    required this.active,
  });

  final int position;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B3A);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? green
            : active
            ? green.withValues(alpha: .12)
            : const Color(0xFFEFF1EE),
        border: active && !done ? Border.all(color: green, width: 1.5) : null,
      ),
      child: done
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : Text(
              '$position',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: active ? green : Colors.black54,
              ),
            ),
    );
  }
}

/// Small per-view indicator: filled green when that view has a photo.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.filled,
  });

  final String label;
  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B3A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFE3F1E7) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: filled ? Colors.transparent : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            filled ? Icons.check_circle : icon,
            size: 12,
            color: filled ? green : Colors.black38,
          ),
          const SizedBox(width: 4),
          AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: filled ? green : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisPill extends StatelessWidget {
  const _DiagnosisPill({required this.diagnosis});

  final PlantDiagnosisResult diagnosis;

  @override
  Widget build(BuildContext context) {
    final notAssessed =
        diagnosis.modelName.startsWith('WormWise-AutoScreen-v1:') &&
        diagnosis.classificationLabel == null;
    final damage =
        diagnosis.classificationLabel == 'FAW damage' || diagnosis.isInfested;
    final color = notAssessed
        ? Colors.black54
        : damage
        ? const Color(0xFFB3261E)
        : const Color(0xFF176B3A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            damage ? Icons.bug_report_outlined : Icons.check_circle_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          AppText(
            notAssessed
                ? 'Not assessed'
                : damage
                ? 'Damage'
                : 'No damage',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlapping thumbnails: 1 photo = single square, 2â€“3 = fanned stack.
class _ThumbStack extends StatelessWidget {
  const _ThumbStack({required this.media, required this.resolveFile});

  final List<EvidenceMediaRecord> media;
  final Future<File> Function(String localUri) resolveFile;

  static const _size = 40.0;
  static const _step = 20.0;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: _size + _step * (media.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < media.length; i++)
            Positioned(
              left: _step * i,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _MediaImage(
                    media: media[i],
                    resolveFile: resolveFile,
                    cacheWidth: 120,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaImage extends StatefulWidget {
  const _MediaImage({
    required this.media,
    required this.resolveFile,
    this.cacheWidth = 320,
  });

  final EvidenceMediaRecord media;
  final Future<File> Function(String localUri) resolveFile;
  final int cacheWidth;

  @override
  State<_MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<_MediaImage> {
  late Future<File> _file = _resolve();

  Future<File> _resolve() => widget.resolveFile(
    widget.media.thumbnailLocalUri ?? widget.media.localUri,
  );

  @override
  void didUpdateWidget(covariant _MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.localUri != widget.media.localUri ||
        oldWidget.media.thumbnailLocalUri != widget.media.thumbnailLocalUri) {
      _file = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.file(
            snapshot.data!,
            fit: BoxFit.cover,
            cacheWidth: widget.cacheWidth,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFF2C2C2C),
              child: Icon(Icons.broken_image, color: Colors.white54),
            ),
          );
        }
        return const ColoredBox(color: Color(0xFFE6E8E5));
      },
    );
  }
}
