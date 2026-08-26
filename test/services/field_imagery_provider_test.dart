import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wormwise/services/field_imagery_provider.dart';

void main() {
  const boundary = [
    LatLng(17.6500, 121.7500),
    LatLng(17.6500, 121.7510),
    LatLng(17.6510, 121.7510),
    LatLng(17.6510, 121.7500),
  ];
  const request = FieldImageryRequest(
    assessmentId: 'assessment-1',
    boundaryVersionId: 'boundary-1',
    boundary: boundary,
  );

  test('composite provider uses the first legally described source', () async {
    final approved = _FakeProvider(
      FieldImagerySource.onlineTiles(
        displayName: 'Approved package test double',
        attribution: 'Licensed source',
        licenseReference: 'licence-1',
        tileUrlTemplate: 'https://example.test/{z}/{x}/{y}',
      ),
    );
    final later = _FakeProvider(
      FieldImagerySource.onlineTiles(
        displayName: 'Later source',
        attribution: 'Later attribution',
        licenseReference: 'licence-2',
        tileUrlTemplate: 'https://later.test/{z}/{x}/{y}',
      ),
    );

    final result = await CompositeFieldImageryProvider([
      approved,
      later,
    ]).resolve(request);

    expect(result?.displayName, 'Approved package test double');
    expect(approved.calls, 1);
    expect(later.calls, 0);
  });

  test(
    'approved package requires attribution, licence, and field coverage',
    () async {
      final root = await Directory.systemTemp.createTemp('wormwise-imagery-');
      addTearDown(() => root.delete(recursive: true));
      final package = Directory(
        '${root.path}${Platform.pathSeparator}wormwise_field_imagery'
        '${Platform.pathSeparator}boundary-1',
      );
      await package.create(recursive: true);
      await File(
        '${package.path}${Platform.pathSeparator}field.webp',
      ).writeAsBytes([1, 2, 3]);
      await File(
        '${package.path}${Platform.pathSeparator}approved_imagery.json',
      ).writeAsString('''
{
  "schema_version": "$fieldImageryManifestVersion",
  "source_kind": "approvedHighResolutionPackage",
  "image_file": "field.webp",
  "display_name": "DA licensed Piat imagery",
  "attribution": "Department of Agriculture",
  "license_reference": "DA-Piat-2026-001",
  "resolution_label": "0.5 m supplied imagery",
  "west": 121.749,
  "south": 17.649,
  "east": 121.752,
  "north": 17.652
}
''');
      final provider = PackagedFieldImageryProvider(
        manifestFileName: 'approved_imagery.json',
        expectedKind: FieldImageryKind.approvedHighResolutionPackage,
        rootDirectory: () async => root,
      );

      final result = await provider.resolve(request);

      expect(result?.displayName, 'DA licensed Piat imagery');
      expect(result?.attribution, 'Department of Agriculture');
      expect(result?.isPackaged, isTrue);
    },
  );

  test('package outside field coverage is rejected', () async {
    final root = await Directory.systemTemp.createTemp('wormwise-imagery-');
    addTearDown(() => root.delete(recursive: true));
    final package = Directory(
      '${root.path}${Platform.pathSeparator}wormwise_field_imagery'
      '${Platform.pathSeparator}boundary-1',
    );
    await package.create(recursive: true);
    await File(
      '${package.path}${Platform.pathSeparator}field.webp',
    ).writeAsBytes([1]);
    await File(
      '${package.path}${Platform.pathSeparator}approved_imagery.json',
    ).writeAsString('''
{
  "schema_version": "$fieldImageryManifestVersion",
  "source_kind": "approvedHighResolutionPackage",
  "image_file": "field.webp",
  "display_name": "Wrong extent",
  "attribution": "Licensed source",
  "license_reference": "licence",
  "west": 121.749,
  "south": 17.649,
  "east": 121.7505,
  "north": 17.6505
}
''');

    final result = await PackagedFieldImageryProvider(
      manifestFileName: 'approved_imagery.json',
      expectedKind: FieldImageryKind.approvedHighResolutionPackage,
      rootDirectory: () async => root,
    ).resolve(request);

    expect(result, isNull);
  });

  test(
    'OpenStreetMap provider remains available as an explicit source',
    () async {
      final source = await const OpenStreetMapBasemapProvider().resolve(
        request,
      );

      expect(
        source?.tileUrlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      expect(source?.kind, FieldImageryKind.onlineBasemap);
      expect(source?.displayName, 'OpenStreetMap');
      expect(source?.attribution, contains('OpenStreetMap contributors'));
      expect(
        source?.licenseReference,
        'https://www.openstreetmap.org/copyright',
      );
    },
  );

  test('Esri World Imagery matches the Map tab default', () async {
    final source = await const EsriWorldImageryBasemapProvider().resolve(
      request,
    );

    expect(
      source?.tileUrlTemplate,
      contains('ArcGIS/rest/services/World_Imagery'),
    );
    expect(source?.kind, FieldImageryKind.onlineBasemap);
    expect(source?.displayName, 'Esri World Imagery');
    expect(source?.attribution, contains('Esri World Imagery'));
  });

  test(
    'Piat provider falls through absent packages to Esri World Imagery',
    () async {
      final root = await Directory.systemTemp.createTemp('wormwise-imagery-');
      addTearDown(() => root.delete(recursive: true));

      final source = await PiatFieldImageryProvider(
        rootDirectory: () async => root,
      ).resolve(request);

      expect(source?.kind, FieldImageryKind.onlineBasemap);
      expect(source?.displayName, 'Esri World Imagery');
    },
  );

  test('imagery package file names cannot escape their directory', () {
    expect(isSafeImageryFileName('field.webp'), isTrue);
    expect(isSafeImageryFileName('../field.webp'), isFalse);
    expect(isSafeImageryFileName(r'C:\field.webp'), isFalse);
  });
}

class _FakeProvider implements FieldImageryProvider {
  _FakeProvider(this.source);

  final FieldImagerySource? source;
  int calls = 0;

  @override
  Future<FieldImagerySource?> resolve(FieldImageryRequest request) async {
    calls++;
    return source;
  }
}
