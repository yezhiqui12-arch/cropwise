import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../localization/app_text.dart';
import '../../models/assessment_history_models.dart';
import '../../models/assessment_map_data.dart';
import '../../models/da_assessment_results.dart';
import '../../models/sampled_infestation.dart';
import '../../models/da_severity.dart';
import '../../services/cloud/expert_review_service.dart';
import '../../services/evidence_storage_service.dart';
import '../../services/map_view_policy.dart';
import '../../services/phone_location_service.dart';
import '../../services/polygon_calculator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/available_satellite_layer.dart';
import '../expert_severity_review_screen.dart';
import '../station1/evidence_photo_viewer.dart';
import 'assessment_result_components.dart';
import 'plant_details_screen.dart';

/// Spatial presentation of saved DA samples; it does not run models or write results.
class AssessmentMapScreen extends StatefulWidget {
  const AssessmentMapScreen({
    super.key,
    required this.detail,
    required this.storage,
    this.reviewCase,
    this.loadRatings,
    this.showMapTiles = true,
  });
  final AssessmentHistoryDetail detail;
  final EvidenceStorageService storage;
  // The injection points also let offline widget tests exercise finalized reviews.
  final ExpertReviewCase? reviewCase;
  final Future<List<ExpertPlantRating>> Function()? loadRatings;
  final bool showMapTiles;
  @override
  State<AssessmentMapScreen> createState() => _AssessmentMapScreenState();
}

class _AssessmentMapScreenState extends State<AssessmentMapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  late AssessmentMapData _data;
  late List<LatLng> _outline;
  String? _selectedId, _reviewKey;
  Future<List<ExpertPlantRating>>? _ratings;
  AssessmentMapLayer _chosenLayer = AssessmentMapLayer.damage;
  bool _layerChosen = false, _showBoundary = true, _showBlocks = false;
  bool _ready = false, _findingLocation = false, _tileFailed = false;
  int _tileRevision = 0;
  LatLng? _userLocation;
  double _mapHeight = 600, _extent = .24, _minimum = .24, _middle = .52;
  double? _overviewZoom;
  bool _clusteringAllowed = false;
  List<(Offset, Offset)> _pinLinks = const [];

  @override
  void initState() {
    super.initState();
    _readDetail();
  }

  void _readDetail() {
    _data = AssessmentMapData(widget.detail);
    _outline = PolygonCalculator.fromGeoJson(
      widget.detail.workspace.boundary?.geometryGeojson ?? '',
    ).where(PolygonCalculator.isValidCoordinate).toList();
  }

  @override
  void didUpdateWidget(AssessmentMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail != widget.detail) {
      _readDetail();
      if (oldWidget.detail.assessment.id != widget.detail.assessment.id) {
        _selectedId = null;
        _layerChosen = false;
        _reviewKey = null;
      }
    }
  }

  @override
  void dispose() {
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  LatLng get _center => _outline.isNotEmpty
      ? PolygonCalculator.calculateCenter(_outline)
      : _data.points.where((p) => p.location != null).firstOrNull?.location ??
            MapViewPolicy.initialCenter(
              LatLng(
                widget.detail.workspace.boundary?.centroidLatitude ?? 17.7905,
                widget.detail.workspace.boundary?.centroidLongitude ?? 121.4781,
              ),
            );
  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 320);
  AssessmentMapPoint? get _selected =>
      _data.points.where((p) => p.id == _selectedId).firstOrNull;

  Future<void> _fitField() async {
    if (!_ready) return;
    setState(() {
      _selectedId = null;
      _clusteringAllowed = false;
    });
    if (_sheet.isAttached && _sheet.size > _minimum + .01) {
      await _sheet.animateTo(
        _minimum,
        duration: _duration,
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || !_ready) return;
    final coordinates = <LatLng>[
      ..._outline,
      for (final point in _data.points) ...[
        if (point.location != null) point.location!,
      ],
    ];
    if (coordinates.isNotEmpty) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: coordinates,
          padding: EdgeInsets.fromLTRB(28, 112, 60, _mapHeight * _minimum + 28),
          maxZoom: 19,
        ),
      );
    } else {
      _map.move(_center, 17);
    }
    setState(() => _overviewZoom = _map.camera.zoom);
  }

  void _openPoint(AssessmentMapPoint point) {
    setState(() => _selectedId = point.id);
    if (_sheet.isAttached) {
      _sheet.animateTo(
        _middle,
        duration: _duration,
        curve: Curves.easeOutCubic,
      );
    }
    if (_ready && point.location != null) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [point.location!],
          maxZoom: math.max(17, _map.camera.zoom).clamp(17, 19).toDouble(),
          padding: EdgeInsets.fromLTRB(48, 92, 72, _mapHeight * _middle + 24),
        ),
      );
    }
  }

  Future<void> _locate() async {
    if (_findingLocation) return;
    setState(() => _findingLocation = true);
    try {
      final result = await const PhoneLocationService().captureAverage(
        targetSamples: 1,
        maximumWait: const Duration(seconds: 8),
      );
      if (!mounted) return;
      final point = LatLng(result.latitude, result.longitude);
      if (!PolygonCalculator.isValidCoordinate(point)) {
        throw StateError('Invalid GPS');
      }
      setState(() => _userLocation = point);
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [point],
          maxZoom: 18,
          padding: EdgeInsets.fromLTRB(40, 88, 72, _mapHeight * _extent + 24),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('Current location unavailable.')),
        );
      }
    } finally {
      if (mounted) setState(() => _findingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExpertReviewService?>();
    final cases =
        service?.cases
            .where(
              (c) =>
                  c.assessmentId == widget.detail.assessment.id &&
                  c.severitySummary != null,
            )
            .toList() ??
        <ExpertReviewCase>[];
    cases.sort(
      (a, b) => b.severitySummary!.finalizedAt.compareTo(
        a.severitySummary!.finalizedAt,
      ),
    );
    final review = widget.reviewCase?.severitySummary != null
        ? widget.reviewCase
        : cases.firstOrNull;
    final loader =
        widget.loadRatings ??
        (review != null && service != null
            ? () => service.loadSeverityRatings(review.id)
            : null);
    final key = review == null
        ? null
        : '${widget.detail.assessment.id}:${review.id}:${review.severitySummary!.finalizedAt.toIso8601String()}';
    if (_reviewKey != key) {
      _reviewKey = key;
      _ratings = loader?.call();
    }
    return FutureBuilder<List<ExpertPlantRating>>(
      future: _ratings,
      builder: (context, snapshot) {
        final expert =
            review != null &&
                snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                !snapshot.hasError
            ? DaExpertResults.fromRatings(
                sample: _data.sample,
                summary: review.severitySummary!,
                ratings: snapshot.data!,
              )
            : null;
        final layer = !_layerChosen && expert?.available == true
            ? AssessmentMapLayer.expert
            : _chosenLayer;
        final infestation = DaSampledInfestation(
          _data.sample,
          finalized: review != null,
          expert: expert,
        );
        final loading =
            review != null &&
            snapshot.connectionState == ConnectionState.waiting;
        final failed =
            snapshot.hasError ||
            (review != null && !loading && expert?.available != true);
        return Scaffold(
          appBar: AppBar(
            title: const AppText('Assessment map'),
            actions: [
              IconButton(
                tooltip: 'About this layer',
                onPressed: () => _meaning(layer, review != null),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.detail.workspace.field.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${(widget.detail.workspace.boundary?.areaHectares ?? 0).toStringAsFixed(2)} ha · ${DateFormat('MMM d, yyyy').format(widget.detail.assessment.createdAt.toLocal())}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _Tag(
                          '${_data.sample.recordedPlants}/${_data.sample.expectedPlants} recorded',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _mapHeight = constraints.maxHeight;
                    final scaler = MediaQuery.textScalerOf(context);
                    _minimum =
                        ((154 +
                                    math.max(0, scaler.scale(12) - 12) * 5 +
                                    MediaQuery.paddingOf(context).bottom) /
                                _mapHeight)
                            .clamp(.18, .65)
                            .toDouble();
                    _middle = math.max(_minimum, .52);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: const Color(0xFFE7EDDF),
                            child: FlutterMap(
                              mapController: _map,
                              options: MapOptions(
                                backgroundColor: const Color(0xFFE7EDDF),
                                initialCenter: _center,
                                initialZoom: 17,
                                minZoom: MapViewPolicy.minZoom,
                                maxZoom: MapViewPolicy.maxZoom,
                                onPositionChanged: (camera, hasGesture) {
                                  if (_ready && mounted) {
                                    setState(() {
                                      if (hasGesture && _overviewZoom != null) {
                                        _clusteringAllowed =
                                            camera.zoom < _overviewZoom! - .15;
                                      }
                                    });
                                  }
                                },
                                onMapReady: () {
                                  _ready = true;
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(() {});
                                      _fitField();
                                    }
                                  });
                                },
                                onTap: (_, _) {
                                  if (_selectedId != null) {
                                    setState(() => _selectedId = null);
                                  }
                                },
                              ),
                              children: [
                                if (widget.showMapTiles)
                                  AvailableSatelliteLayer(
                                    key: ValueKey(_tileRevision),
                                    onError: () {
                                      if (mounted && !_tileFailed) {
                                        setState(() => _tileFailed = true);
                                      }
                                    },
                                  ),
                                if (_showBoundary && _outline.length >= 3)
                                  PolygonLayer(
                                    polygons: [
                                      Polygon(
                                        points: _outline,
                                        color: AppColors.primary.withValues(
                                          alpha: .06,
                                        ),
                                        borderColor: const Color(0xFF92D69E),
                                        borderStrokeWidth: 2.5,
                                      ),
                                    ],
                                  ),
                                if (_showBlocks)
                                  PolygonLayer(polygons: _blockPolygons()),
                                Builder(
                                  builder: (context) {
                                    final markers = _markers(
                                      layer,
                                      infestation,
                                      expert,
                                    );
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        IgnorePointer(
                                          child: CustomPaint(
                                            painter: _SamplePinAnchorPainter(
                                              links: _pinLinks,
                                            ),
                                          ),
                                        ),
                                        MarkerLayer(
                                          rotate: true,
                                          markers: markers,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 14,
                          left: 14,
                          right: 76,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Material(
                                color: Colors.white,
                                elevation: 2,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: const Key('assessment_map_layers'),
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _layers(
                                    layer,
                                    review,
                                    expert,
                                    loading,
                                    failed,
                                    loader,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.layers_outlined,
                                          size: 21,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 9),
                                        Flexible(
                                          child: AppText(
                                            layer.label,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.expand_more_rounded,
                                          size: 20,
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.showMapTiles)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .85,
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      '© Esri World Imagery',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_tileFailed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        _tileFailed = false;
                                        _tileRevision++;
                                      }),
                                      child: const Padding(
                                        padding: EdgeInsets.all(9),
                                        child: AppText(
                                          'Imagery unavailable · Retry',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 14,
                          right: 12,
                          child: Column(
                            children: [
                              _MapControl(
                                label: 'Fit field',
                                icon: Icons.center_focus_strong_rounded,
                                onTap: _fitField,
                              ),
                              const SizedBox(height: 8),
                              _MapControl(
                                label: 'My location',
                                icon: Icons.my_location_rounded,
                                loading: _findingLocation,
                                onTap: _locate,
                              ),
                            ],
                          ),
                        ),
                        NotificationListener<DraggableScrollableNotification>(
                          onNotification: (notification) {
                            _extent = notification.extent;
                            return false;
                          },
                          child: DraggableScrollableSheet(
                            key: const Key('assessment_map_panel'),
                            controller: _sheet,
                            initialChildSize: _minimum,
                            minChildSize: _minimum,
                            maxChildSize: 1,
                            snap: true,
                            snapSizes: _middle > _minimum && _middle < 1
                                ? [_middle]
                                : null,
                            builder: (context, controller) => Material(
                              color: const Color(0xFFFAFCF7),
                              elevation: 8,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListView(
                                controller: controller,
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  24 + MediaQuery.paddingOf(context).bottom,
                                ),
                                children: [
                                  InkWell(
                                    key: const Key('assessment_map_expand'),
                                    onTap: () {
                                      if (_sheet.isAttached) {
                                        _sheet.animateTo(
                                          _sheet.size < _middle - .03
                                              ? _middle
                                              : _minimum,
                                          duration: _duration,
                                          curve: Curves.easeOutCubic,
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        width: 38,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCCD5C7),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _summary(
                                    layer,
                                    expert,
                                    infestation,
                                    review,
                                    loading,
                                    failed,
                                    loader,
                                  ),
                                  const SizedBox(height: 12),
                                  _legend(layer),
                                  const Divider(height: 28),
                                  if (_selected case final selected?) ...[
                                    _pointDetails(
                                      selected,
                                      layer,
                                      infestation,
                                      expert,
                                      review,
                                    ),
                                    const SizedBox(height: 22),
                                  ],
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: AppText(
                                          'Sample locations',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${_data.mappedCount} mapped',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_data.unlocatedCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: AppText(
                                        '${_data.unlocatedCount} samples have no saved location.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  if (_data.points.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: AppText(
                                        'No sampling locations saved.',
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  for (final point in _data.points)
                                    _sampleRow(
                                      point,
                                      layer,
                                      infestation,
                                      expert,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Polygon> _blockPolygons() {
    final blocks = {
      for (final p in _data.points)
        p.station.prepared.block.id: p.station.prepared.block,
    };
    final polygons = <Polygon>[];
    for (final block in blocks.values) {
      final points = PolygonCalculator.fromGeoJson(
        block.geometryGeojson,
      ).where(PolygonCalculator.isValidCoordinate).toList();
      if (points.length < 3) continue;
      polygons.add(
        Polygon(
          points: points,
          color: Colors.transparent,
          borderColor: const Color(0xFFEAF5D8),
          borderStrokeWidth: 1.5,
        ),
      );
    }
    return polygons;
  }

  Color _color(
    AssessmentMapLayer layer,
    AssessmentMapPoint point,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
  ) {
    const unknown = Color(0xFF68766F),
        amber = Color(0xFFAD651E),
        green = Color(0xFF237148);
    if (layer == AssessmentMapLayer.expert) {
      final rating = expert?.available == true
          ? expert!.ratingFor(point.station)
          : null;
      final score = rating?.outcome == 'scored' ? rating?.davisScore : null;
      if (score == null) return unknown;
      return Color(daSeverityBand(score)!.color);
    }
    final value = layer == AssessmentMapLayer.damage
        ? point.damage
        : infestation.forPlant(point.station);
    return value == null
        ? unknown
        : value
        ? amber
        : green;
  }

  String _result(
    AssessmentMapLayer layer,
    AssessmentMapPoint point,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
  ) {
    if (layer == AssessmentMapLayer.expert) {
      final rating = expert?.available == true
          ? expert!.ratingFor(point.station)
          : null;
      return rating?.outcome == 'scored'
          ? 'Davis ${rating!.davisScore}/9 · ${daSeverityClassification(rating.davisScore)}'
          : rating?.outcome == 'insufficient_evidence'
          ? 'Insufficient evidence'
          : 'Unavailable';
    }
    if (layer == AssessmentMapLayer.damage) {
      return point.record == null
          ? 'Not recorded'
          : point.damage == null
          ? 'Unavailable'
          : point.damage!
          ? 'Damage detected'
          : 'No damage detected';
    }
    final value = infestation.forPlant(point.station);
    return value == null
        ? 'Unavailable'
        : value
        ? 'Infested'
        : 'Not infested';
  }

  List<Marker> _markers(
    AssessmentMapLayer layer,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
  ) {
    final groups =
        _ready &&
            _clusteringAllowed &&
            _overviewZoom != null &&
            _map.camera.zoom < _overviewZoom! - .15
        ? groupAssessmentMapPoints(
            _data.points.where((p) => p.id != _selectedId).toList(),
            _map.camera.latLngToScreenOffset,
          )
        : [
            for (final p in _data.points.where(
              (p) => p.location != null && p.id != _selectedId,
            ))
              [p],
          ];
    final selected = _selected;
    if (selected?.location != null) groups.add([selected!]);
    final overview =
        _ready &&
        _overviewZoom != null &&
        _map.camera.zoom <= _overviewZoom! + .15 &&
        !_clusteringAllowed;
    final singles = groups
        .where((g) => g.length == 1)
        .map((g) => g.single)
        .toList();
    final offsets = overview
        ? layoutAssessmentMapPins(
            singles
                .map((p) => _map.camera.latLngToScreenOffset(p.location!))
                .toList(),
            Rect.fromLTRB(
              20,
              112,
              _map.camera.nonRotatedSize.width - 20,
              math.max(150, _mapHeight * (1 - _minimum) - 24),
            ),
          )
        : const <Offset>[];
    final displayOffsets = <String, Offset>{
      for (var i = 0; i < offsets.length; i++) singles[i].id: offsets[i],
    };
    _pinLinks = [
      for (var i = 0; i < offsets.length; i++)
        (_map.camera.latLngToScreenOffset(singles[i].location!), offsets[i]),
    ];
    return [
      if (_userLocation != null)
        Marker(
          point: _userLocation!,
          width: 26,
          height: 26,
          child: Semantics(
            label: 'Your current location',
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2478D4),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      for (final group in groups)
        if (group.length == 1)
          _pin(
            group.single,
            layer,
            infestation,
            expert,
            displayOffset: displayOffsets[group.single.id],
          )
        else
          Marker(
            point: PolygonCalculator.calculateCenter(
              group.map((p) => p.location!).toList(),
            ),
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              label: '${group.length} overlapping sample locations',
              child: Material(
                color: const Color(0xFF365267),
                shape: const CircleBorder(
                  side: BorderSide(color: Colors.white, width: 3),
                ),
                elevation: 2,
                child: InkWell(
                  key: ValueKey('map_cluster_${group.first.id}'),
                  customBorder: const CircleBorder(),
                  onTap: () => _openCluster(group, layer, infestation, expert),
                  child: Center(
                    child: Text(
                      '${group.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Marker _pin(
    AssessmentMapPoint point,
    AssessmentMapLayer layer,
    DaSampledInfestation infestation,
    DaExpertResults? expert, {
    Offset? displayOffset,
  }) {
    final compact =
        _ready &&
        _overviewZoom != null &&
        _map.camera.zoom <= _overviewZoom! + .15;
    final rating = expert?.available == true
        ? expert!.ratingFor(point.station)
        : null;
    final value = layer == AssessmentMapLayer.damage
        ? point.damage
        : infestation.forPlant(point.station);
    final symbol = layer == AssessmentMapLayer.expert
        ? rating?.outcome == 'scored'
              ? '${rating!.davisScore}/9'
              : '?'
        : value == null
        ? '?'
        : value
        ? '!'
        : '−';
    return Marker(
      point: displayOffset == null
          ? point.location!
          : _map.camera.screenOffsetToLatLng(displayOffset),
      width: compact ? 30 : 44,
      height: compact ? 34 : 48,
      child: Semantics(
        button: true,
        selected: point.id == _selectedId,
        label: '${point.label}, ${_result(layer, point, infestation, expert)}',
        child: Material(
          color: _color(layer, point, infestation, expert),
          elevation: point.id == _selectedId ? 5 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 15),
            side: BorderSide(
              color: point.id == _selectedId
                  ? const Color(0xFFFAD68C)
                  : Colors.white,
              width: point.id == _selectedId ? 3 : 2,
            ),
          ),
          child: InkWell(
            key: ValueKey('map_pin_${point.id}'),
            borderRadius: BorderRadius.circular(compact ? 10 : 15),
            onTap: () => _openPoint(point),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${point.station.stationNumber}',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 12 : 16,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  symbol,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCluster(
    List<AssessmentMapPoint> group,
    AssessmentMapLayer layer,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
  ) async {
    if (_ready) {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: group.map((p) => p.location!).toList(),
          maxZoom: 20,
          padding: EdgeInsets.fromLTRB(48, 88, 72, _mapHeight * _extent + 24),
        ),
      );
    }
    // Coincident GPS fixes cannot separate at any zoom: preserve their coordinates and offer selection.
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: AppText(
                'Choose a sample',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            for (final point in group)
              ListTile(
                title: AppText(point.label),
                subtitle: AppText(_result(layer, point, infestation, expert)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  _openPoint(point);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
    AssessmentMapLayer layer,
    DaExpertResults? expert,
    DaSampledInfestation infestation,
    ExpertReviewCase? review,
    bool loading,
    bool failed,
    Future<List<ExpertPlantRating>> Function()? loader,
  ) {
    final sample = _data.sample;
    final selected = _selected;
    final value = selected != null
        ? (layer == AssessmentMapLayer.damage
              ? selected.damage == null
                    ? 'Unavailable'
                    : selected.damage!
                    ? 'Damage detected'
                    : 'No damage'
              : _result(layer, selected, infestation, expert))
        : switch (layer) {
            AssessmentMapLayer.damage =>
              sample.screeningPercent == null
                  ? 'Unavailable'
                  : '${sample.screeningPercent!.toStringAsFixed(1)}%',
            AssessmentMapLayer.infestation =>
              infestation.percent == null
                  ? 'Unavailable'
                  : '${infestation.percent!.toStringAsFixed(1)}%',
            AssessmentMapLayer.expert =>
              expert?.available == true && expert?.mean != null
                  ? '${expert!.mean!.toStringAsFixed(2)} / 9'
                  : loading
                  ? 'Loading…'
                  : 'Unavailable',
          };
    final caption = selected != null
        ? layer.label
        : switch (layer) {
            AssessmentMapLayer.damage =>
              '${sample.positivePlants} of ${sample.assessablePlants} assessable plants with damage',
            AssessmentMapLayer.infestation =>
              '${infestation.infested} of ${infestation.denominator} ${infestation.finalized ? 'assessable' : 'sampled'} plants infested · ${infestation.assessable} assessable · ${infestation.source}',
            AssessmentMapLayer.expert =>
              expert?.available == true
                  ? '${daSeverityClassification(expert!.mean)} · ${expert.scoredPlants} scored · ${expert.insufficientPlants} insufficient evidence'
                  : review == null
                  ? 'No finalized findings'
                  : loading
                  ? 'Loading saved expert ratings'
                  : 'Ratings could not be loaded',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText(
                _selected?.label ?? 'Sample summary',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_selected != null)
              IconButton(
                tooltip: 'Clear selected sample',
                onPressed: () => setState(() => _selectedId = null),
                icon: const Icon(Icons.close_rounded, size: 20),
              )
            else
              IconButton(
                tooltip: 'Expand summary',
                onPressed: () {
                  if (_sheet.isAttached) {
                    _sheet.animateTo(
                      _middle,
                      duration: _duration,
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                icon: const Icon(Icons.expand_less_rounded, size: 22),
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: AppText(
                value,
                key: const Key('assessment_map_metric'),
                style: TextStyle(
                  fontSize: selected != null ? 22 : 27,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -.6,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AppText(
                caption,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (layer == AssessmentMapLayer.expert && failed && loader != null)
          TextButton.icon(
            key: const Key('assessment_map_retry_expert'),
            onPressed: () {
              final ratings = loader();
              setState(() {
                _ratings = ratings;
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const AppText('Retry expert findings'),
          ),
        if (layer == AssessmentMapLayer.expert &&
            expert?.available == true &&
            review != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Finalized ${DateFormat('MMM d, yyyy').format(review.severitySummary!.finalizedAt.toLocal())}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _legend(AssessmentMapLayer layer) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        AppText(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
    return Wrap(
      key: const Key('assessment_map_legend'),
      spacing: 12,
      runSpacing: 8,
      children: layer == AssessmentMapLayer.expert
          ? [
              for (final band in daSeverityBands)
                item(Color(band.color), '${band.range} · ${band.label}'),
              item(const Color(0xFF68766F), 'Unavailable'),
            ]
          : [
              item(
                const Color(0xFFAD651E),
                layer == AssessmentMapLayer.damage
                    ? 'Damage detected'
                    : 'Infested',
              ),
              item(
                const Color(0xFF237148),
                layer == AssessmentMapLayer.damage
                    ? 'No damage'
                    : 'Not infested',
              ),
              item(const Color(0xFF68766F), 'Unavailable'),
            ],
    );
  }

  Widget _sampleRow(
    AssessmentMapPoint point,
    AssessmentMapLayer layer,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _selectedId == point.id ? const Color(0xFFEAF2E5) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8DF)),
      ),
      child: ListTile(
        key: ValueKey('map_sample_${point.id}'),
        onTap: () => _openPoint(point),
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _color(layer, point, infestation, expert),
            shape: BoxShape.circle,
          ),
        ),
        title: AppText(
          point.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: AppText(
          _result(layer, point, infestation, expert),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        trailing: Icon(
          point.location == null
              ? Icons.location_off_outlined
              : Icons.chevron_right_rounded,
          size: 20,
          color: AppColors.textMuted,
        ),
      ),
    ),
  );

  Widget _pointDetails(
    AssessmentMapPoint point,
    AssessmentMapLayer layer,
    DaSampledInfestation infestation,
    DaExpertResults? expert,
    ExpertReviewCase? review,
  ) {
    final photos = _data.sample.photos(point.station);
    final rating = expert?.available == true
        ? expert!.ratingFor(point.station)
        : null;
    Widget row(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppText(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: AppText(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('assessment_map_sample_details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppText(
          'Observations',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 10),
        ResultSurface(
          child: Column(
            children: [
              row(
                'Damage screening',
                _result(AssessmentMapLayer.damage, point, infestation, expert),
              ),
              row(
                'Current sampled infestation',
                _result(
                  AssessmentMapLayer.infestation,
                  point,
                  infestation,
                  expert,
                ),
              ),
              if (review != null) ...[
                row(
                  'Expert rating',
                  _result(
                    AssessmentMapLayer.expert,
                    point,
                    infestation,
                    expert,
                  ),
                ),
                if (rating?.outcome == 'scored' && rating?.davisScore != 0)
                  row('Damage observed', switch (rating?.damageFreshness) {
                    'fresh' => 'Fresh damage',
                    'old_only' => 'Old damage only',
                    _ => 'Undetermined',
                  }),
                if (rating?.note.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppText(
                      rating!.note,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in photos)
                SizedBox(
                  width: 82,
                  height: 82,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: const Color(0xFFE8EEE3),
                      child: InkWell(
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EvidencePhotoViewer(
                              media: photo.media,
                              scopeLabel: point.label,
                              resolveFile: widget.storage.resolve,
                              cvDiagnosis: _data.sample
                                  .screening(point.station)
                                  ?.result,
                              fieldName: widget.detail.workspace.field.name,
                              stationLabel: point.label,
                              scoutingStyle: true,
                            ),
                          ),
                        ),
                        child: FutureBuilder<File>(
                          future: widget.storage.resolve(
                            photo.media.thumbnailLocalUri ??
                                photo.media.localUri,
                          ),
                          builder: (_, image) => image.hasData
                              ? Image.file(
                                  image.data!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.image_not_supported_outlined,
                                    color: AppColors.textMuted,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_outlined,
                                  color: AppColors.textMuted,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('assessment_map_open_sample'),
          onPressed: point.record == null
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlantAssessmentDetailsScreen(
                      detail: widget.detail,
                      station: point.station,
                      record: point.record!,
                      storage: widget.storage,
                    ),
                  ),
                ),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const AppText('View sample details'),
        ),
        if (review != null)
          TextButton.icon(
            key: const Key('assessment_map_open_review'),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ExpertSeverityReviewScreen(caseId: review.id),
              ),
            ),
            icon: const Icon(Icons.assignment_outlined, size: 18),
            label: const AppText('Open expert review'),
          ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ExpansionTile(
            title: const AppText(
              'Location details',
              style: TextStyle(fontSize: 13),
            ),
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppText(
                  point.location == null
                      ? 'No saved location'
                      : '${point.locationLabel}\n${point.location!.latitude.toStringAsFixed(6)}, ${point.location!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _layers(
    AssessmentMapLayer active,
    ExpertReviewCase? review,
    DaExpertResults? expert,
    bool loading,
    bool failed,
    Future<List<ExpertPlantRating>> Function()? loader,
  ) async {
    var selected = active;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFAFCF7),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: AppText(
                  'Map layers',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
              ),
              const AppText(
                'Results',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              for (final layer in AssessmentMapLayer.values)
                Semantics(
                  selected: selected == layer,
                  enabled: layer != AssessmentMapLayer.expert || review != null,
                  child: ListTile(
                    key: ValueKey('map_layer_${layer.name}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      selected == layer
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color:
                          layer == AssessmentMapLayer.expert && review == null
                          ? AppColors.textMuted
                          : AppColors.primary,
                    ),
                    title: AppText(
                      layer.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: AppText(switch (layer) {
                      AssessmentMapLayer.damage => 'Saved damage screening',
                      AssessmentMapLayer.infestation =>
                        review == null
                            ? 'Frass / larvae screening'
                            : 'Finalized expert findings',
                      AssessmentMapLayer.expert =>
                        review == null
                            ? 'Not available'
                            : loading
                            ? 'Loading ratings'
                            : failed
                            ? 'Ratings unavailable · retry from summary'
                            : 'Davis scores · 0–9',
                    }, style: const TextStyle(fontSize: 12)),
                    onTap: layer == AssessmentMapLayer.expert && review == null
                        ? null
                        : () {
                            update(() => selected = layer);
                            setState(() {
                              _chosenLayer = layer;
                              _layerChosen = true;
                            });
                          },
                  ),
                ),
              const Divider(height: 28),
              const AppText(
                'Map',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('map_overlay_boundary'),
                contentPadding: EdgeInsets.zero,
                title: const AppText(
                  'Field & boundary',
                  style: TextStyle(fontSize: 14),
                ),
                value: _showBoundary,
                onChanged: (value) {
                  setState(() => _showBoundary = value);
                  update(() {});
                },
              ),
              if (_data.points
                      .map((p) => p.station.prepared.block.id)
                      .toSet()
                      .length >
                  1)
                SwitchListTile.adaptive(
                  key: const Key('map_overlay_blocks'),
                  contentPadding: EdgeInsets.zero,
                  title: const AppText(
                    'Sampling blocks',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _showBlocks,
                  onChanged: (value) {
                    setState(() => _showBlocks = value);
                    update(() {});
                  },
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
                child: const AppText('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _meaning(
    AssessmentMapLayer layer,
    bool finalized,
  ) => showResultInformation(
    context,
    title: layer.label,
    icon: Icons.layers_outlined,
    body: switch (layer) {
      AssessmentMapLayer.damage =>
        'Amber means visible damage was detected in the saved screening. Green means no damage was detected. Gray means a result is unavailable or the plant has not been recorded.\n\nThe percentage uses plants with a screening result. Each sampled plant counts once, regardless of the number of photos. Damage screening does not establish current infestation.',
      AssessmentMapLayer.infestation =>
        '${finalized ? 'This layer uses finalized expert findings. Fresh damage is classified as Infested; old-only damage or a Davis score of zero is Not infested. Unclear or insufficient findings are Unavailable.' : 'This layer uses eggs, larvae or frass detected in the saved model results. Infested means those signs were detected. Not infested means detection completed without those signs. Skipped or failed detection is Unavailable.'}\n\n${finalized ? 'The percentage excludes unavailable results.' : 'The percentage uses the planned sample: 20 plants per block. Unavailable detection remains unknown, not Not infested.'} Pins describe sampled plants, not the unsampled area around them.',
      AssessmentMapLayer.expert =>
        'Each pin shows a finalized Davis rating from 0 to 9. Zero means no visible damage. Higher ratings describe greater visible damage; they are not percentages. The colors match the DA severity classification legend. Gray means no usable rating.\n\nFresh damage and old-only damage appear separately in sample details. The field summary is the mean of valid scored plants, including zeros. No damage surface is inferred between pins. $daSeverityBandExplanation $daSeverityExplanation',
    },
  );
}

class _SamplePinAnchorPainter extends CustomPainter {
  const _SamplePinAnchorPainter({required this.links});
  final List<(Offset, Offset)> links;
  @override
  void paint(Canvas canvas, Size size) {
    for (final (anchor, label) in links) {
      if ((anchor - label).distance < 2) continue;
      canvas.drawLine(
        label,
        anchor,
        Paint()
          ..color = Colors.black26
          ..strokeWidth = 2.5,
      );
      canvas.drawLine(
        label,
        anchor,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1,
      );
      canvas.drawCircle(anchor, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_SamplePinAnchorPainter oldDelegate) =>
      oldDelegate.links != links;
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    borderRadius: BorderRadius.circular(14),
    child: IconButton(
      tooltip: label,
      onPressed: loading ? null : onTap,
      icon: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 23),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2E5),
      borderRadius: BorderRadius.circular(10),
    ),
    child: AppText(
      label,
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
