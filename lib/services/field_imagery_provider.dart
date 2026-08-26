import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';

const fieldImageryManifestVersion = 'wormwise_field_imagery_v1';

enum FieldImageryKind {
  approvedHighResolutionPackage,
  onlineBasemap,
  sentinel2Package,
}

class FieldImageryRequest {
  const FieldImageryRequest({
    required this.assessmentId,
    required this.boundaryVersionId,
    required this.boundary,
  });

  final String assessmentId;
  final String boundaryVersionId;
  final List<LatLng> boundary;
}

class FieldImageryBounds {
  const FieldImageryBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double west;
  final double south;
  final double east;
  final double north;

  bool get isValid =>
      west.isFinite &&
      east.isFinite &&
      south.isFinite &&
      north.isFinite &&
      west < east &&
      south < north &&
      west >= -180 &&
      east <= 180 &&
      south >= -90 &&
      north <= 90;

  bool contains(LatLng point) =>
      point.longitude >= west &&
      point.longitude <= east &&
      point.latitude >= south &&
      point.latitude <= north;
}

class FieldImagerySource {
  const FieldImagerySource._({
    required this.kind,
    required this.displayName,
    required this.attribution,
    required this.licenseReference,
    this.resolutionLabel,
    this.imageProvider,
    this.imageBounds,
    this.tileUrlTemplate,
    this.tileMaxNativeZoom = 18,
  });

  factory FieldImagerySource.packaged({
    required FieldImageryKind kind,
    required String displayName,
    required String attribution,
    required String licenseReference,
    required ImageProvider imageProvider,
    required FieldImageryBounds imageBounds,
    String? resolutionLabel,
  }) => FieldImagerySource._(
    kind: kind,
    displayName: displayName,
    attribution: attribution,
    licenseReference: licenseReference,
    resolutionLabel: resolutionLabel,
    imageProvider: imageProvider,
    imageBounds: imageBounds,
  );

  factory FieldImagerySource.onlineTiles({
    required String displayName,
    required String attribution,
    required String licenseReference,
    required String tileUrlTemplate,
    int maxNativeZoom = 18,
  }) => FieldImagerySource._(
    kind: FieldImageryKind.onlineBasemap,
    displayName: displayName,
    attribution: attribution,
    licenseReference: licenseReference,
    tileUrlTemplate: tileUrlTemplate,
    tileMaxNativeZoom: maxNativeZoom,
  );

  final FieldImageryKind kind;
  final String displayName;
  final String attribution;
  final String licenseReference;
  final String? resolutionLabel;
  final ImageProvider? imageProvider;
  final FieldImageryBounds? imageBounds;
  final String? tileUrlTemplate;
  final int tileMaxNativeZoom;

  bool get isPackaged => imageProvider != null && imageBounds != null;
  bool get isOnline => tileUrlTemplate != null;
}

abstract interface class FieldImageryProvider {
  Future<FieldImagerySource?> resolve(FieldImageryRequest request);
}

class CompositeFieldImageryProvider implements FieldImageryProvider {
  const CompositeFieldImageryProvider(this.providers);

  final List<FieldImageryProvider> providers;

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async {
    for (final provider in providers) {
      final source = await provider.resolve(request);
      if (source != null) return source;
    }
    return null;
  }
}

typedef ImageryRootDirectory = Future<Directory> Function();

class PackagedFieldImageryProvider implements FieldImageryProvider {
  const PackagedFieldImageryProvider({
    required this.manifestFileName,
    required this.expectedKind,
    this.rootDirectory = _defaultImageryRoot,
  });

  final String manifestFileName;
  final FieldImageryKind expectedKind;
  final ImageryRootDirectory rootDirectory;

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async {
    if (!_safeIdentifier(request.boundaryVersionId)) return null;
    final root = await rootDirectory();
    final separator = Platform.pathSeparator;
    final directory = Directory(
      '${root.path}${separator}wormwise_field_imagery$separator${request.boundaryVersionId}',
    );
    final manifest = File('${directory.path}$separator$manifestFileName');
    if (!await manifest.exists()) return null;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map) return null;
      final value = decoded.cast<String, Object?>();
      if (value['schema_version'] != fieldImageryManifestVersion ||
          value['source_kind'] != expectedKind.name) {
        return null;
      }
      final imageFileName = value['image_file'] as String?;
      final attribution = (value['attribution'] as String?)?.trim();
      final license = (value['license_reference'] as String?)?.trim();
      final displayName = (value['display_name'] as String?)?.trim();
      if (imageFileName == null ||
          !_safeFileName(imageFileName) ||
          attribution == null ||
          attribution.isEmpty ||
          license == null ||
          license.isEmpty ||
          displayName == null ||
          displayName.isEmpty) {
        return null;
      }
      final bounds = FieldImageryBounds(
        west: (value['west'] as num).toDouble(),
        south: (value['south'] as num).toDouble(),
        east: (value['east'] as num).toDouble(),
        north: (value['north'] as num).toDouble(),
      );
      if (!bounds.isValid || !request.boundary.every(bounds.contains)) {
        return null;
      }
      final imageFile = File('${directory.path}$separator$imageFileName');
      if (!await imageFile.exists() || await imageFile.length() == 0) {
        return null;
      }
      return FieldImagerySource.packaged(
        kind: expectedKind,
        displayName: displayName,
        attribution: attribution,
        licenseReference: license,
        resolutionLabel: (value['resolution_label'] as String?)?.trim(),
        imageProvider: FileImage(imageFile),
        imageBounds: bounds,
      );
    } catch (_) {
      return null;
    }
  }
}

class OpenStreetMapBasemapProvider implements FieldImageryProvider {
  const OpenStreetMapBasemapProvider();

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async {
    return FieldImagerySource.onlineTiles(
      displayName: 'OpenStreetMap',
      attribution: '\u00A9 OpenStreetMap contributors \u00B7 ODbL',
      licenseReference: 'https://www.openstreetmap.org/copyright',
      tileUrlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxNativeZoom: 19,
    );
  }
}

class EsriWorldImageryBasemapProvider implements FieldImageryProvider {
  const EsriWorldImageryBasemapProvider();

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async {
    return FieldImagerySource.onlineTiles(
      displayName: 'Esri World Imagery',
      attribution: 'Esri World Imagery',
      licenseReference:
          'https://www.esri.com/en-us/legal/terms/full-master-agreement',
      tileUrlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      maxNativeZoom: 17,
    );
  }
}

class PiatFieldImageryProvider extends CompositeFieldImageryProvider {
  PiatFieldImageryProvider({
    ImageryRootDirectory rootDirectory = _defaultImageryRoot,
  }) : super([
         PackagedFieldImageryProvider(
           manifestFileName: 'approved_imagery.json',
           expectedKind: FieldImageryKind.approvedHighResolutionPackage,
           rootDirectory: rootDirectory,
         ),
         PackagedFieldImageryProvider(
           manifestFileName: 'sentinel2_imagery.json',
           expectedKind: FieldImageryKind.sentinel2Package,
           rootDirectory: rootDirectory,
         ),
         const EsriWorldImageryBasemapProvider(),
       ]);
}

Future<Directory> _defaultImageryRoot() => getApplicationDocumentsDirectory();

bool _safeIdentifier(String value) =>
    value.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

bool _safeFileName(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    !value.contains('/') &&
    !value.contains('\\') &&
    !value.contains(':');

@visibleForTesting
bool isSafeImageryFileName(String value) => _safeFileName(value);
