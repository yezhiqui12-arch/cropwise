import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/esri_imagery_coverage.dart';

/// Keeps camera zoom independent of satellite coverage. Missing high-resolution
/// tiles use lower-resolution imagery stretched by flutter_map at the same location.
class AvailableSatelliteLayer extends StatefulWidget {
  const AvailableSatelliteLayer({super.key, this.onError, this.coverage});
  final VoidCallback? onError;
  final EsriImageryCoverage? coverage;
  @override
  State<AvailableSatelliteLayer> createState() =>
      _AvailableSatelliteLayerState();
}

class _AvailableSatelliteLayerState extends State<AvailableSatelliteLayer> {
  Timer? _timer;
  String? _cell;
  int _nativeZoom = 18;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final camera = MapCamera.of(context);
    if (camera.zoom <= 16) return;
    final cell = EsriImageryCoverage.cellKey(camera.center);
    if (cell == _cell) return;
    _cell = cell;
    _timer?.cancel();
    final center = camera.center;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      final zoom = await (widget.coverage ?? EsriImageryCoverage.instance)
          .nativeZoomFor(center);
      if (mounted && _cell == cell && zoom != null && zoom != _nativeZoom) {
        setState(() => _nativeZoom = zoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nativeZoom = _nativeZoom;
    return TileLayer(
      key: ValueKey(nativeZoom),
      urlTemplate: EsriImageryCoverage.tileUrl,
      maxZoom: 20,
      maxNativeZoom: nativeZoom,
      userAgentPackageName: 'com.wormwise.app.wormwise',
      panBuffer: 0,
      keepBuffer: 2,
      tileUpdateTransformer: TileUpdateTransformers.debounce(
        const Duration(milliseconds: 160),
      ),
      errorTileCallback: (tile, error, stack) {
        // blankTile=false makes absent Esri imagery a real 404 rather than an
        // image saying "Map data not yet available". Do not downgrade for outages.
        if (error is NetworkImageLoadException &&
            error.statusCode == 404 &&
            nativeZoom > 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _nativeZoom == nativeZoom) {
              setState(() => _nativeZoom = nativeZoom - 1);
            }
          });
        } else {
          widget.onError?.call();
        }
      },
    );
  }
}
