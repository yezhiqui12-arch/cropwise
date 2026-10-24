part of 'assessment_results_screen.dart';

class _AssessmentInteractiveMapScreen extends StatefulWidget {
  const _AssessmentInteractiveMapScreen({
    required this.detail,
    required this.stats,
  });

  final AssessmentHistoryDetail detail;
  final AssessmentEvidenceStats stats;

  @override
  State<_AssessmentInteractiveMapScreen> createState() =>
      _AssessmentInteractiveMapScreenState();
}

class _AssessmentInteractiveMapScreenState
    extends State<_AssessmentInteractiveMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _userLocation;
  bool _findingUser = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _centerUser() async {
    if (_findingUser) return;
    setState(() => _findingUser = true);
    try {
      final reading = await const PhoneLocationService().captureAverage(
        targetSamples: 1,
        maximumWait: const Duration(seconds: 8),
      );
      if (!mounted) return;
      final point = LatLng(reading.latitude, reading.longitude);
      setState(() => _userLocation = point);
      _mapController.move(point, 17);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('Current location unavailable.')),
        );
      }
    } finally {
      if (mounted) setState(() => _findingUser = false);
    }
  }

  AssessmentHistoryDetail get detail => widget.detail;
  AssessmentEvidenceStats get stats => widget.stats;
  bool get isDa =>
      ScoutingSamplingProtocol.isDa(detail.assessment.protocolVersion);

  @override
  Widget build(BuildContext context) {
    final boundary = detail.workspace.boundary;
    final outline = PolygonCalculator.fromGeoJson(
      boundary?.geometryGeojson ?? '',
    ).toList();
    final center = outline.isNotEmpty
        ? PolygonCalculator.calculateCenter(outline)
        : boundary?.centroidLatitude != null &&
              boundary?.centroidLongitude != null
        ? LatLng(boundary!.centroidLatitude!, boundary.centroidLongitude!)
        : const LatLng(17.7905, 121.4781);

    void centerField() {
      if (outline.length >= 2) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: outline,
            padding: const EdgeInsets.fromLTRB(40, 60, 80, 270),
          ),
        );
      } else {
        _mapController.move(center, 17);
      }
    }

    final plannedTargets = <String, LatLng>{};
    for (final s in stats.stationStats) {
      final key = '${s.snapshot.prepared.run.id}:${s.stationNumber}';
      final target = _savedStationTarget(
        s.snapshot.prepared.run.routeGeojson,
        s.stationNumber,
      );
      if (target != null) plannedTargets[key] = target;
    }
    final markers = <Marker>[];
    for (final s in stats.stationStats) {
      final st = s.snapshot.station;
      final key = '${s.snapshot.prepared.run.id}:${s.stationNumber}';
      final planned = plannedTargets[key];
      final point =
          planned ??
          (st?.latitude != null && st?.longitude != null
              ? LatLng(st!.latitude!, st.longitude!)
              : null);
      if (point != null) {
        final pinColor = isDa
            ? s.assessableCount == 0
                  ? const Color(0xFF68766F)
                  : s.positiveCount > 0
                  ? const Color(0xFF9B5F11)
                  : AppColors.primary
            : _sampleRateColor(
                s.assessableCount == 0 ? null : s.infestationPercent,
              );

        markers.add(
          Marker(
            point: point,
            width: 58,
            height: 48,
            child: Semantics(
              button: true,
              label: isDa
                  ? 'Plant ${s.stationNumber}, ${s.assessableCount == 0
                        ? 'screening unavailable'
                        : s.positiveCount > 0
                        ? 'screened positive'
                        : 'screened negative'}'
                  : s.assessableCount == 0
                  ? 'Station ${s.stationNumber}, no data'
                  : 'Station ${s.stationNumber}, ${s.infestationPercent.toStringAsFixed(0)} percent of assessed plants with positive results',
              child: InkWell(
                onTap: () => _showStationMapDetails(context, s, planned),
                customBorder: const CircleBorder(),
                child: Container(
                  decoration: BoxDecoration(
                    color: pinColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(
                        '${isDa ? 'P' : 'S'}${s.stationNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      AppText(
                        isDa
                            ? s.assessableCount == 0
                                  ? '?'
                                  : s.positiveCount > 0
                                  ? '+'
                                  : '−'
                            : s.assessableCount == 0
                            ? 'No data'
                            : '${s.infestationPercent.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    for (final station in stats.stationStats) {
      for (final item in station.snapshot.plants) {
        final plant = item.plant;
        if (plant.locationSource != 'phone_gps' ||
            plant.latitude == null ||
            plant.longitude == null) {
          continue;
        }
        markers.add(
          Marker(
            point: LatLng(plant.latitude!, plant.longitude!),
            width: 24,
            height: 24,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: AppText(
                    isDa
                        ? 'Plant ${station.stationNumber}'
                        : 'Station ${station.stationNumber} · Plant ${plant.sequenceNumber}',
                  ),
                  content: AppText(
                    '${plant.latitude!.toStringAsFixed(6)}, ${plant.longitude!.toStringAsFixed(6)}\nAccuracy ±${plant.gpsAccuracyM?.toStringAsFixed(1) ?? "?"} m\nGPS recorded: ${plant.locationCapturedAt?.toLocal().toString() ?? "Not recorded"}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const AppText('Close'),
                    ),
                  ],
                ),
              ),
              child: const Icon(
                Icons.circle,
                size: 12,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        );
      }
    }
    final fieldName = detail.workspace.field.name;
    final barangay = detail.workspace.field.barangay;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Field Map & Telemetry',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              barangay != null ? '$barangay · $fieldName' : fieldName,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              minZoom: MapViewPolicy.minZoom,
              maxZoom: MapViewPolicy.maxZoom,
              initialCenter: MapViewPolicy.initialCenter(center),
              initialZoom: 17.0,
              onMapReady: centerField,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                tileUpdateTransformer: TileUpdateTransformers.debounce(
                  const Duration(milliseconds: 160),
                ),
                panBuffer: 0,
                keepBuffer: 3,
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                maxZoom: 19,
              ),
              if (outline.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: outline,
                      color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                      borderColor: const Color(0xFF22C55E),
                      borderStrokeWidth: 3.0,
                    ),
                  ],
                ),
              PolylineLayer(
                polylines: _assessmentRoutePolylines(
                  stats.stationStats,
                  plannedTargets,
                ),
              ),
              MarkerLayer(
                markers: [
                  ...markers,
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.my_location,
                        color: Color(0xFF1565C0),
                        size: 30,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'results_center_field',
                  tooltip: AppWords.of(context).translate('Center field'),
                  onPressed: centerField,
                  child: const Icon(Icons.center_focus_strong),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'results_center_user',
                  tooltip: AppWords.of(
                    context,
                  ).translate('Center on my location'),
                  onPressed: _centerUser,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppText(
                        '${stats.stationStats.length} ${isDa ? 'sampling points' : 'sampled stations'}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Flexible(
                        child: AppText(
                          '${_primaryMetricTitle(stats.primaryMetricCode)}: ${isDa && stats.primaryDenominator == 0 ? 'Unavailable' : _formatPrimaryMetricValue(stats.primaryUnit, stats.overallInfestationPercent)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1B4D3E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppText(
                    '${_formatMetricCount(stats.primaryNumerator)} of ${_formatMetricCount(stats.primaryDenominator)} ${_primaryMetricDenominatorLabel(stats.primaryMetricCode, detail.assessment.growthStage)} · ${isDa ? '20 plants per sampling block' : 'structured ${detail.assessment.scoutingPattern.toUpperCase()} sample'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isDa)
                    const AppText(
                      'Amber +: screened positive · Green −: screened negative · Gray ?: unavailable',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    _SampleRateLegend(onTap: () => _showLegendHelp(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegendHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Station color scale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              AppText(
                stats.screeningMode
                    ? 'Damage-screening bands: green <10%, amber 10–20%, red >20%. Gray: not assessed.'
                    : 'Sampled infestation display bands: green below 10%, amber 10–20%, red above 20%. Gray means no assessable observations. Small blue markers show individual plant GPS, not severity.',
              ),
              SizedBox(height: 8),
              AppText(
                'The colors describe only the sampled stations. They are not severity categories and do not estimate conditions between stations.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStationMapDetails(
    BuildContext context,
    StationEvidenceStats station,
    LatLng? planned,
  ) {
    final currentEvidenceCount = station.assessableCount == 0
        ? 0
        : (station.infestationPercent * station.assessableCount / 100).round();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Block ${station.blockSequence} · ${isDa ? 'Plant' : 'Station'} ${station.stationNumber}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (planned != null)
                AppText(
                  'Scouting-pattern target: ${planned.latitude.toStringAsFixed(6)}, ${planned.longitude.toStringAsFixed(6)} (generated, approximate)',
                ),
              if (planned != null) const SizedBox(height: 8),
              AppText(
                isDa
                    ? station.assessableCount == 0
                          ? 'Screening unavailable for this plant.'
                          : station.positiveCount > 0
                          ? 'This plant screened positive. Expert confirmation is separate.'
                          : 'This plant screened negative. This does not establish a clean field.'
                    : station.assessableCount == 0
                    ? 'No data — no assessable plants recorded.'
                    : '$currentEvidenceCount of ${station.assessableCount} assessed plants had recorded positive results (${station.infestationPercent.toStringAsFixed(1)}%).',
              ),
              const SizedBox(height: 8),
              AppText(
                station.snapshot.station?.locationSource == 'phone_gps'
                    ? 'Phone GPS · accuracy ±${station.snapshot.station?.gpsAccuracyM?.toStringAsFixed(1) ?? "?"} m\nGPS recorded: ${station.snapshot.station?.locationCapturedAt?.toLocal().toString() ?? "Not recorded"}'
                    : 'Station location unverified; measured GPS not recorded.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MapEvidenceChip(label: 'Damage', count: station.damageCount),
                  _MapEvidenceChip(
                    label: station.screeningMode ? 'Frass hints' : 'Frass',
                    count: station.frassCount,
                    display:
                        station.screeningMode && station.highlightedPlants == 0
                        ? 'Not assessed'
                        : null,
                  ),
                  _MapEvidenceChip(
                    label: station.screeningMode ? 'Larvae hints' : 'Larvae',
                    count: station.larvaCount,
                    display:
                        station.screeningMode && station.highlightedPlants == 0
                        ? 'Not assessed'
                        : null,
                  ),
                  _MapEvidenceChip(
                    label: station.screeningMode ? 'Eggs hints' : 'Eggs',
                    count: station.eggCount,
                    display:
                        station.screeningMode && station.highlightedPlants == 0
                        ? 'Not assessed'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppText(
                isDa
                    ? 'This result describes the sampled plant, not the unsampled area around it.'
                    : 'These values describe the sampled station and do not assign a measured value to unsampled locations.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _sampleRateColor(double? percent) {
  if (percent == null || !percent.isFinite) return const Color(0xFF64748B);
  if (percent > 20) return const Color(0xFFEF4444);
  if (percent >= 10) return const Color(0xFFF59E0B);
  return const Color(0xFF22C55E);
}

LatLng? _savedStationTarget(String? routeGeojson, int stationNumber) {
  if (routeGeojson == null || routeGeojson.isEmpty) return null;
  try {
    final route = jsonDecode(routeGeojson) as Map<String, dynamic>;
    final features = route['features'] as List<dynamic>? ?? const [];
    for (final raw in features) {
      final feature = raw as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>?;
      if (properties?['feature_type'] != 'station_target' ||
          properties?['station_number'] != stationNumber) {
        continue;
      }
      final coordinates =
          (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) return null;
      final longitude = (coordinates[0] as num).toDouble();
      final latitude = (coordinates[1] as num).toDouble();
      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude.abs() > 90 ||
          longitude.abs() > 180) {
        return null;
      }
      return LatLng(latitude, longitude);
    }
  } catch (_) {
    return null;
  }
  return null;
}

List<Polyline> _assessmentRoutePolylines(
  List<StationEvidenceStats> stations,
  Map<String, LatLng> plannedTargets,
) {
  if (stations.isNotEmpty && stations.first.snapshot.requiredPlantCount == 1) {
    return const [];
  }
  final byBlock = <int, List<StationEvidenceStats>>{};
  for (final station in stations) {
    final key = '${station.snapshot.prepared.run.id}:${station.stationNumber}';
    final actual = station.snapshot.station;
    if (!plannedTargets.containsKey(key) &&
        (actual?.latitude == null || actual?.longitude == null)) {
      continue;
    }
    byBlock.putIfAbsent(station.blockSequence, () => []).add(station);
  }
  return [
    for (final group in byBlock.values)
      if (group.length >= 2)
        Polyline(
          points: [
            for (final station
                in (group
                  ..sort((a, b) => a.stationNumber.compareTo(b.stationNumber))))
              plannedTargets['${station.snapshot.prepared.run.id}:${station.stationNumber}'] ??
                  LatLng(
                    station.snapshot.station!.latitude!,
                    station.snapshot.station!.longitude!,
                  ),
          ],
          color: const Color(0xFF064D2B),
          strokeWidth: 4,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ),
  ];
}

class _SampleRateLegend extends StatelessWidget {
  const _SampleRateLegend({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('assessment_map_color_legend'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final band in const [
              (Color(0xFF64748B), 'No data'),
              (Color(0xFF22C55E), '<10%'),
              (Color(0xFFF59E0B), '10–20%'),
              (Color(0xFFEF4444), '>20%'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: band.$1),
                  const SizedBox(width: 4),
                  AppText(band.$2, style: const TextStyle(fontSize: 10.5)),
                ],
              ),
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _MapEvidenceChip extends StatelessWidget {
  const _MapEvidenceChip({
    required this.label,
    required this.count,
    this.display,
  });

  final String label;
  final int count;
  final String? display;

  @override
  Widget build(BuildContext context) {
    return Chip(label: AppText('$label: ${display ?? count}'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. TAB 2: FIELD INTERPRETATION CARD
// ─────────────────────────────────────────────────────────────────────────────
