import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

typedef EvidenceRootDirectory = Future<Directory> Function();

class StoredEvidenceFile {
  const StoredEvidenceFile({
    required this.localUri,
    required this.thumbnailLocalUri,
    required this.byteSize,
    required this.sha256Checksum,
    required this.widthPx,
    required this.heightPx,
  });

  final String localUri;
  final String thumbnailLocalUri;
  final int byteSize;
  final String sha256Checksum;
  final int widthPx;
  final int heightPx;
}

class EvidenceStorageService {
  EvidenceStorageService({EvidenceRootDirectory? rootDirectory})
    : _rootDirectory = rootDirectory ?? _applicationEvidenceDirectory;

  static const maximumLongEdgePx = 2048;
  static const thumbnailLongEdgePx = 400;
  static const jpegQuality = 82;

  final EvidenceRootDirectory _rootDirectory;

  Future<StoredEvidenceFile> stageCapturedFile({
    required String sourcePath,
    required String assessmentId,
    required String stationId,
    required String scopeKey,
    required String mediaId,
    bool deleteSourceAfterCopy = true,
    bool stripMetadata = false,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('The captured image is unavailable.');
    }

    final sourceBytes = await source.readAsBytes();
    final prepared = await compute(
      stripMetadata ? _preparePrivateEvidenceImage : _prepareEvidenceImage,
      sourceBytes,
    );
    final folder = [
      _safeSegment(assessmentId),
      _safeSegment(stationId),
      _safeSegment(scopeKey),
      'staging',
    ].join('/');
    final localUri = '$folder/${_safeSegment(mediaId)}.jpg';
    final thumbnailLocalUri = '$folder/${_safeSegment(mediaId)}_thumb.jpg';
    final main = await resolve(localUri);
    final thumbnail = await resolve(thumbnailLocalUri);
    await main.parent.create(recursive: true);
    await _writeVerified(main, prepared.imageBytes);
    await _writeVerified(thumbnail, prepared.thumbnailBytes);
    if (deleteSourceAfterCopy) await discardSource(sourcePath);

    return StoredEvidenceFile(
      localUri: localUri,
      thumbnailLocalUri: thumbnailLocalUri,
      byteSize: prepared.imageBytes.length,
      sha256Checksum: sha256.convert(prepared.imageBytes).toString(),
      widthPx: prepared.width,
      heightPx: prepared.height,
    );
  }

  // Publish only complete, verified files. A failed write keeps the capture.
  Future<void> _writeVerified(File destination, Uint8List bytes) async {
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      final stored = await temporary.readAsBytes();
      if (stored.length != bytes.length ||
          sha256.convert(stored) != sha256.convert(bytes)) {
        throw const FileSystemException('Evidence file verification failed.');
      }
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> discardSource(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (await source.exists()) await source.delete();
    } on FileSystemException {
      // Cache cleanup must not turn a committed capture into a failed save.
    }
  }

  Future<({String localUri, String thumbnailLocalUri})> promote({
    required String localUri,
    required String thumbnailLocalUri,
  }) async {
    final readyUri = _readyUri(localUri);
    final readyThumbnailUri = _readyUri(thumbnailLocalUri);
    final stagedFile = await resolve(localUri);
    final stagedThumbnail = await resolve(thumbnailLocalUri);
    final readyFile = await resolve(readyUri);
    final readyThumbnail = await resolve(readyThumbnailUri);
    await readyFile.parent.create(recursive: true);

    if (await stagedFile.exists()) {
      if (await readyFile.exists()) await readyFile.delete();
      await stagedFile.rename(readyFile.path);
    } else if (!await readyFile.exists()) {
      throw const FileSystemException('The staged evidence image is missing.');
    }
    if (await stagedThumbnail.exists()) {
      if (await readyThumbnail.exists()) await readyThumbnail.delete();
      await stagedThumbnail.rename(readyThumbnail.path);
    }
    return (localUri: readyUri, thumbnailLocalUri: readyThumbnailUri);
  }

  Future<void> deleteArtifacts({
    required String localUri,
    String? thumbnailLocalUri,
  }) async {
    final readyThumbnailUri = thumbnailLocalUri == null
        ? null
        : _readyUri(thumbnailLocalUri);
    final paths = <String>{
      localUri,
      _readyUri(localUri),
      ?thumbnailLocalUri,
      ?readyThumbnailUri,
    };
    for (final path in paths) {
      final file = await resolve(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<bool> exists(String localUri) async =>
      (await resolve(localUri)).exists();

  Future<File> resolve(String localUri) async {
    if (localUri.startsWith('/') ||
        localUri.contains('..') ||
        localUri.contains('\\')) {
      throw ArgumentError.value(localUri, 'localUri', 'Unsafe evidence path');
    }
    final root = await _rootDirectory();
    var current = root.path;
    for (final segment in localUri.split('/')) {
      current = '$current${Platform.pathSeparator}$segment';
    }
    return File(current);
  }

  Future<List<String>> listRelativeFiles(String assessmentId) async {
    final root = await _rootDirectory();
    final assessmentDirectory = Directory(
      '${root.path}${Platform.pathSeparator}${_safeSegment(assessmentId)}',
    );
    if (!await assessmentDirectory.exists()) return const [];
    final result = <String>[];
    await for (final entity in assessmentDirectory.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      result.add(relative);
    }
    return result;
  }

  String readyUriFor(String stagedUri) => _readyUri(stagedUri);

  static Future<Directory> _applicationEvidenceDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}wormwise_private'
      '${Platform.pathSeparator}evidence',
    );
    await directory.create(recursive: true);
    return directory;
  }

  static String _safeSegment(String value) {
    final sanitized = value.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    if (sanitized.isEmpty) {
      throw ArgumentError.value(value, 'path segment', 'Cannot be empty');
    }
    return sanitized;
  }

  static String _readyUri(String value) =>
      value.replaceFirst('/staging/', '/ready/');
}

class _PreparedEvidenceImage {
  const _PreparedEvidenceImage({
    required this.imageBytes,
    required this.thumbnailBytes,
    required this.width,
    required this.height,
  });

  final Uint8List imageBytes;
  final Uint8List thumbnailBytes;
  final int width;
  final int height;
}

_PreparedEvidenceImage _preparePrivateEvidenceImage(Uint8List sourceBytes) =>
    _prepareEvidenceImage(sourceBytes, stripMetadata: true);

_PreparedEvidenceImage _prepareEvidenceImage(
  Uint8List sourceBytes, {
  bool stripMetadata = false,
}) {
  final decoded = image_lib.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('The captured file is not a supported image.');
  }
  var evidence = image_lib.bakeOrientation(decoded);
  final longEdge = evidence.width > evidence.height
      ? evidence.width
      : evidence.height;
  if (longEdge > EvidenceStorageService.maximumLongEdgePx) {
    evidence = evidence.width >= evidence.height
        ? image_lib.copyResize(
            evidence,
            width: EvidenceStorageService.maximumLongEdgePx,
            interpolation: image_lib.Interpolation.average,
          )
        : image_lib.copyResize(
            evidence,
            height: EvidenceStorageService.maximumLongEdgePx,
            interpolation: image_lib.Interpolation.average,
          );
  }
  if (stripMetadata) {
    // New raster contains only visible pixels, without camera GPS/EXIF data.
    final clean = image_lib.Image(
      width: evidence.width,
      height: evidence.height,
      numChannels: 3,
    );
    image_lib.fill(clean, color: image_lib.ColorRgb8(255, 255, 255));
    image_lib.compositeImage(clean, evidence);
    evidence = clean;
  }
  final thumbnail = evidence.width >= evidence.height
      ? image_lib.copyResize(
          evidence,
          width: EvidenceStorageService.thumbnailLongEdgePx,
          interpolation: image_lib.Interpolation.average,
        )
      : image_lib.copyResize(
          evidence,
          height: EvidenceStorageService.thumbnailLongEdgePx,
          interpolation: image_lib.Interpolation.average,
        );
  return _PreparedEvidenceImage(
    imageBytes: Uint8List.fromList(
      image_lib.encodeJpg(
        evidence,
        quality: EvidenceStorageService.jpegQuality,
      ),
    ),
    thumbnailBytes: Uint8List.fromList(
      image_lib.encodeJpg(thumbnail, quality: 72),
    ),
    width: evidence.width,
    height: evidence.height,
  );
}
