import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_codes.dart';
import '../../localization/app_text.dart';
import '../../services/field_imagery_provider.dart';
import '../../services/phone_location_service.dart';
import '../../services/scouting_route_generator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/offline_scouting_route_map.dart';
import 'scouting_ui.dart';

/// One active plant rather than a mandatory grid of twenty numbered cards.
class GuidedPlantWalkStep extends StatefulWidget {
  const GuidedPlantWalkStep({
    super.key,
    required this.fieldName,
    required this.areaHectares,
    required this.plantNumber,
    required this.completedPlants,
    required this.boundary,
    required this.plan,
    required this.completedLocations,
    required this.completedNumbers,
    required this.watchLocation,
    required this.arrived,
    required this.isSaving,
    required this.onArrive,
    required this.onCapture,
    required this.onImport,
    required this.onContinue,
    required this.onReview,
    required this.onAdjust,
    required this.resolveFile,
    this.photos = const [],
    this.resultLabel,
    this.resultConfidence,
    this.onScreen,
    this.instruction = 'Inspect the upper 3–4 leaves.',
    this.imageryProvider,
    this.onOpenPlant,
    this.onImportSample,
    this.actionGuidance,
    this.evidenceNumbers,
  });

  final String fieldName;
  final double areaHectares;
  final int plantNumber;
  final int completedPlants;
  final List<LatLng> boundary;
  final ScoutingRoutePlan plan;
  final Map<int, LatLng> completedLocations;
  final Set<int> completedNumbers;
  final Future<Stream<PhoneLocationReading>> Function() watchLocation;
  final bool arrived;
  final bool isSaving;
  final Future<void> Function() onArrive,
      onCapture,
      onImport,
      onReview,
      onAdjust;
  final Future<void> Function() onContinue;
  final Future<File> Function(String uri) resolveFile;
  final List<EvidenceMediaRecord> photos;
  final String? resultLabel;
  final double? resultConfidence;
  final Future<void> Function()? onScreen;
  final String instruction;
  final FieldImageryProvider? imageryProvider;
  final Future<void> Function(int number)? onOpenPlant;
  final Future<void> Function()? onImportSample;
  final Widget? actionGuidance;
  final Set<int>? evidenceNumbers;

  @override
  State<GuidedPlantWalkStep> createState() => _GuidedPlantWalkStepState();
}

class _GuidedPlantWalkStepState extends State<GuidedPlantWalkStep> {
  StreamSubscription<PhoneLocationReading>? _subscription;
  PhoneLocationReading? _location;
  Object? _locationError;
  bool _busy = false;
  int _fieldRevision = 0;
  int _locationRevision = 0;
  final _sheetController = DraggableScrollableController();
  ScrollController? _panelScrollController;
  double _sheetExtent = .48;
  double _minimumExtent = .16;
  Timer? _freshnessTimer;
  int? _transitionFromPlant;
  int _transitionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _watch();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant GuidedPlantWalkStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plantNumber == widget.plantNumber) return;
    final generation = ++_transitionGeneration;
    final from = oldWidget.plantNumber;
    // Expose the walking area before moving the camera. A block or direct
    // navigation change must not replay a completed-plant animation.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _transitionGeneration) return;
      if (_panelScrollController?.hasClients == true) {
        _panelScrollController!.jumpTo(0);
      }
      if (_sheetController.isAttached) {
        await _sheetController.animateTo(
          _minimumExtent,
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 260,
          ),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted || generation != _transitionGeneration) return;
      setState(
        () => _transitionFromPlant =
            widget.plantNumber == from + 1 &&
                widget.completedNumbers.contains(from)
            ? from
            : null,
      );
    });
  }

  Future<void> _watch() async {
    await _subscription?.cancel();
    try {
      final stream = await widget.watchLocation();
      if (!mounted) return;
      _subscription = stream.listen(
        (reading) {
          if (mounted)
            setState(() {
              _location = reading;
              _locationError = null;
            });
        },
        onError: (Object error) {
          if (mounted) setState(() => _locationError = error);
        },
      );
    } catch (error) {
      if (mounted) setState(() => _locationError = error);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _freshnessTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || widget.isSaving) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _disabled => _busy || widget.isSaving;
  Duration get _panelDuration =>
      Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 260);
  List<EvidenceMediaRecord> get _photos => widget.photos
      .where(
        (p) =>
            p.deletedAt == null &&
            p.storageState == DatabaseCodes.evidenceStorageReady,
      )
      .toList();

  void _toggleMap() {
    if (!_sheetController.isAttached) return;
    if (_panelScrollController?.hasClients == true) {
      _panelScrollController!.jumpTo(0);
    }
    _sheetController.animateTo(
      _sheetExtent > .3 ? _minimumExtent : .48,
      duration: _panelDuration,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _showWholeField({bool location = false}) async {
    if (_panelScrollController?.hasClients == true) {
      _panelScrollController!.jumpTo(0);
    }
    if (_sheetController.isAttached) {
      await _sheetController.animateTo(
        _minimumExtent,
        duration: _panelDuration,
        curve: Curves.easeInOut,
      );
    }
    if (mounted)
      setState(() {
        if (location) {
          _locationRevision++;
        } else {
          _fieldRevision++;
        }
      });
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('guided_plant_walk_step'),
    children: [
      _header(context),
      Expanded(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            _minimumExtent = ((74 + 20 * scale) / viewport.maxHeight).clamp(
              .14,
              .30,
            );
            final expanded = _sheetExtent > _minimumExtent + .06;
            return Stack(
              fit: StackFit.expand,
              children: [
                OfflineScoutingRouteMap(
                  boundary: widget.boundary,
                  plan: widget.plan,
                  activeStation: widget.plantNumber,
                  completedStationLocations: widget.completedLocations,
                  completedStationNumbers: widget.completedNumbers,
                  evidenceStationNumbers: {
                    ...?widget.evidenceNumbers,
                    if (widget.evidenceNumbers == null)
                      ...widget.completedNumbers,
                    if (_photos.isNotEmpty) widget.plantNumber,
                  },
                  currentLocation: _usableLocation,
                  animateFromCompletedStation: _transitionFromPlant,
                  imageryProvider: widget.imageryProvider,
                  height: double.infinity,
                  minimalChrome: true,
                  recenterFieldRevision: _fieldRevision,
                  recenterLocationRevision: _locationRevision,
                  viewportBottomInset: viewport.maxHeight * _sheetExtent,
                  onTargetTap: widget.onOpenPlant == null
                      ? null
                      : (number) => _run(() => widget.onOpenPlant!(number)),
                ),
                // Map controls share a fixed corner and never overlap attribution.
                if (_sheetExtent < .86)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.white,
                      elevation: 3,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const Key('guided_walk_expand_map'),
                            tooltip: expanded
                                ? 'Expand map'
                                : 'Show plant details',
                            onPressed: _toggleMap,
                            icon: Icon(
                              expanded
                                  ? Icons.fullscreen_rounded
                                  : Icons.fullscreen_exit_rounded,
                            ),
                          ),
                          IconButton(
                            key: const Key('guided_walk_fit_field'),
                            tooltip: 'Fit field',
                            onPressed: _showWholeField,
                            icon: const Icon(Icons.center_focus_strong_rounded),
                          ),
                          IconButton(
                            tooltip: 'My location',
                            onPressed: _usableLocation == null
                                ? null
                                : () => _showWholeField(location: true),
                            icon: const Icon(Icons.my_location_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (notification) {
                    if ((_sheetExtent - notification.extent).abs() > .001) {
                      setState(() => _sheetExtent = notification.extent);
                    }
                    return false;
                  },
                  child: DraggableScrollableSheet(
                    key: const Key('guided_walk_draggable_sheet'),
                    controller: _sheetController,
                    initialChildSize: .48,
                    minChildSize: _minimumExtent,
                    maxChildSize: 1,
                    snap: true,
                    snapSizes: [_minimumExtent, .48, 1],
                    builder: (context, controller) {
                      _panelScrollController = controller;
                      return Material(
                        color: AppColors.background,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                controller: controller,
                                child: _panel(context, expanded: expanded),
                              ),
                            ),
                            if (expanded) _primaryAction(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  PhoneLocationReading? get _usableLocation {
    final reading = _location;
    if (reading == null || reading.isCached || _locationError != null)
      return null;
    final age = DateTime.now().toUtc().difference(reading.capturedAt.toUtc());
    if (age.isNegative || age > const Duration(seconds: 30)) return null;
    return reading;
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 22;
        final field = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              widget.fieldName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 3),
            AppText(
              '${widget.areaHectares.toStringAsFixed(2)} ha · Sampling block',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        );
        final progress = Semantics(
          label:
              'Current plant ${widget.plantNumber} of 20. ${widget.completedPlants} saved.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  '${widget.plantNumber} of 20',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  '${widget.completedPlants} saved',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
        return largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [field, const SizedBox(height: 8), progress],
              )
            : Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 12),
                  progress,
                ],
              );
      },
    ),
  );

  String get _distanceLabel {
    if (widget.arrived) return 'At the plant';
    final location = _usableLocation;
    if (location == null) return 'GPS unavailable';
    final distance = ScoutingRouteGenerator.distanceMeters(
      LatLng(location.latitude, location.longitude),
      widget.plan.targetFor(widget.plantNumber).location,
    );
    return distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km away'
        : '${distance.round()} m away';
  }

  void _expandDetails() {
    if (_panelScrollController?.hasClients == true)
      _panelScrollController!.jumpTo(0);
    _sheetController.animateTo(
      _sheetExtent < .35
          ? .48
          : _sheetExtent < .85
          ? 1
          : .48,
      duration: _panelDuration,
      curve: Curves.easeInOut,
    );
  }

  void _beginSheetDrag(DragStartDetails details) {
    if (!_sheetController.isAttached) return;
    // Stop a tap animation immediately so the handle stays under the finger.
    _sheetController.jumpTo(_sheetController.size);
    if (_panelScrollController?.hasClients == true) {
      _panelScrollController!.jumpTo(0);
    }
  }

  void _dragSheet(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final extent =
        _sheetController.size - _sheetController.pixelsToSize(details.delta.dy);
    _sheetController.jumpTo(extent.clamp(_minimumExtent, 1));
  }

  void _settleSheet() {
    if (!_sheetController.isAttached) return;
    final current = _sheetController.size;
    final stops = [_minimumExtent, .48, 1.0];
    stops.sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
    _sheetController.animateTo(
      stops.first,
      duration: _panelDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _panel(BuildContext context, {required bool expanded}) {
    final photos = _photos;
    final location = _usableLocation;
    return Padding(
      key: const Key('guided_walk_action_sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: expanded ? 'Expand plant details' : 'Pull up plant details',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _beginSheetDrag,
              onVerticalDragUpdate: _dragSheet,
              onVerticalDragEnd: (_) => _settleSheet(),
              onVerticalDragCancel: _settleSheet,
              child: InkWell(
                key: const Key('guided_walk_sheet_handle'),
                onTap: _expandDetails,
                child: SizedBox(
                  height: 28,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD4C9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Plant ${widget.plantNumber}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AppText(
                      _distanceLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _sheetExtent > .85
                    ? 'Show map'
                    : 'Expand plant details',
                onPressed: _expandDetails,
                icon: Icon(
                  _sheetExtent > .85
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            ScoutingCard(
              color: const Color(0xFFF0F5ED),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.pin_drop_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      widget.instruction,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.arrived && location != null) ...[
              const SizedBox(height: 10),
              AppText(
                'GPS accuracy ±${location.accuracyMeters.round()} m',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (_locationError != null)
              TextButton(onPressed: _watch, child: const AppText('Retry GPS')),
            if (widget.arrived) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: AppText(
                      'Photos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ScoutingTag('${photos.length} / 3'),
                ],
              ),
              const SizedBox(height: 10),
              if (photos.isEmpty)
                const ScoutingCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: AppText(
                          'Take an overview of this plant.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: 88,
                  child: Row(
                    children: [
                      for (final photo in photos)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: _disabled
                                ? null
                                : () => _run(_openCurrentPlant),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 88,
                                height: 88,
                                child: FutureBuilder<File>(
                                  future: widget.resolveFile(photo.localUri),
                                  builder: (context, snapshot) =>
                                      snapshot.hasData
                                      ? Image.file(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const ColoredBox(
                                                color: AppColors.primaryLight,
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                        )
                                      : const ColoredBox(
                                          color: AppColors.primaryLight,
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (photos.length < 3)
                        SizedBox(
                          width: 64,
                          height: 88,
                          child: Material(
                            color: const Color(0xFFF0F5ED),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: const Key('guided_walk_add_photo'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: _disabled
                                  ? null
                                  : () => _run(widget.onCapture),
                              child: const Tooltip(
                                message: 'Add photo (optional)',
                                child: Icon(
                                  Icons.add_a_photo_outlined,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScoutingCard(
                  key: const Key('guided_walk_screening_status'),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.analytics_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          widget.resultLabel != null
                              ? '${widget.resultLabel}${widget.resultConfidence == null ? '' : ' · ${(widget.resultConfidence! * 100).round()}% confidence'}'
                              : _disabled
                              ? 'Screening…'
                              : 'Not screened',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.resultLabel == null &&
                          !_disabled &&
                          widget.onScreen != null)
                        IconButton(
                          tooltip: 'Screen photos',
                          onPressed: () => _run(widget.onScreen!),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('guided_walk_model_results'),
                  onPressed: _disabled ? null : () => _run(_openCurrentPlant),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const AppText('Model results'),
                ),
                if (widget.actionGuidance != null) widget.actionGuidance!,
              ],
            ],
            if (widget.arrived && photos.isEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('guided_walk_import'),
                onPressed: _disabled ? null : _chooseImport,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const AppText('Use saved photos'),
              ),
            ],
            if (!widget.arrived)
              TextButton(
                onPressed: _disabled ? null : () => _run(widget.onAdjust),
                child: const AppText('Cannot reach this point?'),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseImport() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppText(
              'Use saved photos',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            ScoutingCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    key: const Key('guided_import_this_plant'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.photo_outlined,
                      color: AppColors.primary,
                    ),
                    title: AppText(
                      'Plant ${widget.plantNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const AppText('1–3 views of the same plant'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, 'plant'),
                  ),
                  if (widget.onImportSample != null) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      key: const Key('guided_import_batch'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        Icons.collections_outlined,
                        color: AppColors.primary,
                      ),
                      title: const AppText(
                        'Batch import',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const AppText(
                        'Photos for several plants in this sample',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, 'sample'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'plant') await _run(widget.onImport);
    if (choice == 'sample' && widget.onImportSample != null) {
      await _run(widget.onImportSample!);
    }
  }

  Future<void> _openCurrentPlant() => widget.onOpenPlant == null
      ? widget.onReview()
      : widget.onOpenPlant!(widget.plantNumber);

  Widget _primaryAction() => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE1E8DF))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_disabled) const LinearProgressIndicator(minHeight: 2),
        FilledButton.icon(
          key: Key(
            widget.arrived
                ? 'guided_walk_primary_action'
                : 'guided_walk_arrive',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          onPressed: _disabled
              ? null
              : () => _run(
                  !widget.arrived
                      ? widget.onArrive
                      : _photos.isEmpty
                      ? widget.onCapture
                      : widget.onContinue,
                ),
          icon: Icon(
            !widget.arrived
                ? Icons.location_on_outlined
                : _photos.isEmpty
                ? Icons.photo_camera_outlined
                : Icons.arrow_forward_rounded,
            size: 20,
          ),
          label: AppText(
            !widget.arrived
                ? "I'm at the plant"
                : _photos.isEmpty
                ? 'Capture plant'
                : widget.plantNumber == 20
                ? 'Save and review sample'
                : 'Save and next plant',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}
