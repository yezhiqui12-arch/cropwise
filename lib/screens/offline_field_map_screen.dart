import '../services/map_view_policy.dart';
import '../localization/app_language.dart';
import '../localization/app_text.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/local/app_database.dart';
import '../data/repositories/field_repository.dart';
import '../services/offline_field_map_store.dart';
import '../services/local_piat_map_store.dart';
import '../services/phone_location_service.dart';
import '../services/polygon_calculator.dart';
import '../theme/app_colors.dart';

class OfflineFieldMapScreen extends StatefulWidget {
  const OfflineFieldMapScreen({super.key, required this.workspace, this.store});
  final FieldWorkspaceRecord workspace;
  final OfflineFieldMapStore? store;

  @override
  State<OfflineFieldMapScreen> createState() => _OfflineFieldMapScreenState();
}

class _OfflineFieldMapScreenState extends State<OfflineFieldMapScreen> {
  final _controller = MapController();
  late final _store = widget.store ?? OfflineFieldMapStore.instance;
  late final List<LatLng> _outline = PolygonCalculator.fromGeoJson(
    widget.workspace.boundary?.geometryGeojson ?? '',
  ).toList();
  late final List<LatLng> _points = _outline.isNotEmpty
      ? _outline
      : [
          if (widget.workspace.boundary?.centroidLatitude != null &&
              widget.workspace.boundary?.centroidLongitude != null)
            LatLng(
              widget.workspace.boundary!.centroidLatitude!,
              widget.workspace.boundary!.centroidLongitude!,
            ),
        ];
  OfflineFieldMap? _map;
  bool _packagedMap = false;
  List<({LatLng point, String label})> _stations = [];
  LatLng? _location;
  double? _accuracy;
  bool _busy = true;
  bool _locating = false;
  bool _showImagery = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final boundaryId = widget.workspace.boundary?.id;
      final savedMap = boundaryId == null || _points.isEmpty
          ? null
          : await _store.load(boundaryId, _points);
      OfflineFieldMap? localMap;
      try {
        final packaged = await LocalPiatMapStore.load();
        if (_points.isNotEmpty && _points.every(packaged.area.contains)) {
          localMap = packaged;
        }
      } catch (_) {
        // The existing downloaded map and imagery remain available.
      }
      if (!mounted) return;
      setState(() {
        _map = localMap ?? savedMap;
        _packagedMap = localMap != null;
        _showImagery = _map == null;
      });
      if (localMap != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller.move(_points.first, 14);
        });
      }
      final db = context.read<AppDatabase>();
      final rows = await db
          .customSelect(
            '''
        SELECT s.latitude, s.longitude, s.station_number, r.block_sequence
        FROM stations s JOIN assessment_block_runs r ON r.id = s.assessment_block_run_id
        WHERE r.assessment_id = (
          SELECT a.id FROM assessments a JOIN crop_cycles c ON c.id = a.crop_cycle_id
          WHERE c.field_id = ? AND a.deleted_at IS NULL
          ORDER BY a.created_at DESC LIMIT 1
        ) AND s.deleted_at IS NULL AND s.latitude IS NOT NULL AND s.longitude IS NOT NULL
      ''',
            variables: [Variable<String>(widget.workspace.field.id)],
          )
          .get();
      if (!mounted) return;
      setState(
        () => _stations = [
          for (final row in rows)
            (
              point: LatLng(
                row.read<double>('latitude'),
                row.read<double>('longitude'),
              ),
              label:
                  'B${row.read<int>('block_sequence')} · S${row.read<int>('station_number')}',
            ),
        ],
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Some saved map information could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final map = await _store.save(widget.workspace.boundary!.id, _points);
      if (mounted) setState(() => _map = map);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Download failed. Check your internet and try again. Any previous download is kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _store.remove(widget.workspace.boundary!.id);
      if (mounted) setState(() => _map = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the saved map.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final fix = await const PhoneLocationService().captureAverage(
        targetSamples: 1,
        maximumWait: const Duration(seconds: 15),
      );
      if (!mounted) return;
      final point = LatLng(fix.latitude, fix.longitude);
      setState(() {
        _location = point;
        _accuracy = fix.averageAccuracyMeters;
      });
      _controller.move(point, 17);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'GPS unavailable. Enable location permission and try outside.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _selectMapMode(bool imagery) {
    if (_showImagery == imagery || (!imagery && _map == null)) return;
    setState(() => _showImagery = imagery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final map = _map;
      if (_packagedMap && !imagery) {
        _controller.move(_points.first, 14);
      } else if (imagery || map == null) {
        if (_points.length >= 3) {
          _controller.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(_points),
              padding: const EdgeInsets.all(30),
              maxZoom: 18,
            ),
          );
        } else {
          _controller.move(_points.first, 16);
        }
      } else {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(map.area.south, map.area.west),
              LatLng(map.area.north, map.area.east),
            ),
            padding: const EdgeInsets.all(26),
            maxZoom: 16,
          ),
        );
      }
    });
  }

  void _showMapInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('About this map'),
        content: const AppText(
          'The Piat-area street map is stored in the app and works offline. It contains OpenStreetMap roads and waterways. Your field boundary and station markers appear on top. Imagery needs internet. For fields outside the Piat-area map, you can download a small nearby map.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const AppText('Offline field map'),
        actions: [
          IconButton(
            tooltip: AppWords.of(context).translate('Map information'),
            onPressed: _showMapInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFDDE7E0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.workspace.field.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF293D31),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: map == null
                                  ? const Color(0xFFF3F5F3)
                                  : const Color(0xFFE5F1E7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: AppText(
                              _packagedMap
                                  ? 'On device'
                                  : map == null
                                  ? 'No download'
                                  : 'Saved offline',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2D5940),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        _packagedMap
                            ? 'Piat-area streets · works without internet'
                            : map == null
                            ? 'Save nearby streets for use without internet.'
                            : '${(map.bytes / 1024).toStringAsFixed(0)} KB · Updated ${map.savedAt.toLocal().toString().split(' ').first}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF647B6B),
                        ),
                      ),
                      if (!_packagedMap) ...[
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy || _points.isEmpty
                                    ? null
                                    : _download,
                                icon: Icon(
                                  map == null
                                      ? Icons.download_rounded
                                      : Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: AppText(
                                  map == null ? 'Download map' : 'Update map',
                                ),
                              ),
                            ),
                            if (map != null) ...[
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: AppWords.of(
                                  context,
                                ).translate('Remove download'),
                                onPressed: _busy ? null : _remove,
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (_busy) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        AppText(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _points.isEmpty
                  ? const Center(
                      child: AppText(
                        'Save a field boundary or location first.',
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _controller,
                          options: MapOptions(
                            minZoom: MapViewPolicy.minZoom,
                            maxZoom: MapViewPolicy.maxZoom,
                            initialCenter: MapViewPolicy.initialCenter(
                              _points.first,
                            ),
                            initialZoom: 16,
                            initialCameraFit: _points.length >= 3
                                ? CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(_points),
                                    padding: const EdgeInsets.all(40),
                                    maxZoom: 18,
                                  )
                                : null,

                            backgroundColor: const Color(0xFFEDEFE4),
                          ),
                          children: [
                            if (_showImagery)
                              TileLayer(
                                tileUpdateTransformer:
                                    TileUpdateTransformers.debounce(
                                      const Duration(milliseconds: 160),
                                    ),
                                panBuffer: 0,
                                keepBuffer: 3,
                                urlTemplate:
                                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                                userAgentPackageName:
                                    'com.wormwise.app.wormwise',
                                maxNativeZoom: 18,
                              ),
                            if (!_showImagery && map != null) ...[
                              PolygonLayer(
                                polygons: [
                                  for (final feature in map.features.where(
                                    (f) => f.isArea,
                                  ))
                                    Polygon(
                                      points: feature.points,
                                      color: feature.kind == 'water'
                                          ? const Color(0xFFB9DEED)
                                          : feature.kind == 'building'
                                          ? const Color(0xFFD4C9BE)
                                          : const Color(0xFFDCE5CA),
                                      borderStrokeWidth: .5,
                                      borderColor: Colors.grey,
                                    ),
                                ],
                              ),
                              PolylineLayer(
                                polylines: [
                                  for (final feature in map.features.where(
                                    (f) => !f.isArea && f.kind != 'road',
                                  ))
                                    Polyline(
                                      points: feature.points,
                                      color: const Color(0xFF7CB7D0),
                                      strokeWidth: 2.5,
                                    ),
                                ],
                              ),
                              PolylineLayer(
                                polylines: [
                                  for (final feature in map.features.where(
                                    (f) => f.kind == 'road',
                                  ))
                                    Polyline(
                                      points: feature.points,
                                      color: _roadColor(feature.roadClass),
                                      strokeWidth: _roadWidth(
                                        feature.roadClass,
                                      ),
                                      borderStrokeWidth: 1.5,
                                      borderColor: const Color(0xFFC2C6B7),
                                    ),
                                ],
                              ),
                            ],
                            if (_outline.length >= 3)
                              PolygonLayer(
                                polygons: [
                                  Polygon(
                                    points: _outline,
                                    color: const Color(0x33338844),
                                    borderColor: Colors.green.shade800,
                                    borderStrokeWidth: 3,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (_outline.length < 3)
                                  Marker(
                                    point: _points.first,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.green,
                                    ),
                                  ),
                                if (!_showImagery && _outline.length >= 3)
                                  Marker(
                                    point: PolygonCalculator.calculateCenter(
                                      _outline,
                                    ),
                                    width: 74,
                                    height: 32,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF216B3A),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Center(
                                        child: AppText(
                                          'Field',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final station in _stations)
                                  Marker(
                                    point: station.point,
                                    width: 78,
                                    height: 42,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.green),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(child: Text(station.label)),
                                    ),
                                  ),
                                if (_location != null)
                                  Marker(
                                    point: _location!,
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _MapModeButton(
                                    label: 'Imagery',
                                    selected: _showImagery,
                                    onTap: () => _selectMapMode(true),
                                  ),
                                  _MapModeButton(
                                    label: _packagedMap
                                        ? 'Streets'
                                        : 'Saved map',
                                    selected: !_showImagery,
                                    onTap: map == null
                                        ? null
                                        : () => _selectMapMode(false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                heroTag: 'offline_gps',
                                onPressed: _locating ? null : _locate,
                                tooltip: AppWords.of(
                                  context,
                                ).translate('My GPS position'),
                                child: _locating
                                    ? const CircularProgressIndicator()
                                    : const Icon(Icons.my_location),
                              ),
                              FloatingActionButton.small(
                                heroTag: 'offline_field',
                                onPressed: () {
                                  if (_packagedMap && !_showImagery) {
                                    _controller.move(_points.first, 14);
                                  } else {
                                    _controller.fitCamera(
                                      CameraFit.bounds(
                                        bounds: LatLngBounds.fromPoints(
                                          _points,
                                        ),
                                        padding: const EdgeInsets.all(30),
                                        maxZoom: 18,
                                      ),
                                    );
                                  }
                                },
                                tooltip: AppWords.of(
                                  context,
                                ).translate('Back to field'),
                                child: const Icon(Icons.crop_free),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: ColoredBox(
                            color: Colors.white.withValues(alpha: .9),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Text(
                                _showImagery
                                    ? 'Imagery: Esri · Field boundary overlay'
                                    : 'Map data: © OpenStreetMap contributors · ODbL${_accuracy == null ? '' : ' · GPS ±${_accuracy!.round()} m'}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapModeButton extends StatelessWidget {
  const _MapModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE5F1E7) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppText(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: onTap == null
              ? const Color(0xFFA8B7AC)
              : const Color(0xFF2D5940),
        ),
      ),
    ),
  );
}

Color _roadColor(String? roadClass) => switch (roadClass) {
  'primary' => const Color(0xFFF4B76B),
  'secondary' => const Color(0xFFF7D49B),
  'tertiary' => const Color(0xFFFFE6BD),
  'track' || 'path' || 'footway' => const Color(0xFFDFD8C8),
  _ => Colors.white,
};

double _roadWidth(String? roadClass) => switch (roadClass) {
  'primary' => 8,
  'secondary' => 7,
  'tertiary' => 6,
  'track' || 'path' || 'footway' => 2.5,
  _ => 4.5,
};

