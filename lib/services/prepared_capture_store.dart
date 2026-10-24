import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../data/local/app_database.dart';
import 'evidence_storage_service.dart';

/// A private filesystem journal bridges verified files and their DB transaction.
/// It contains no account credential and is replayed only against a matching
/// session in the currently prepared account's local database view.
class PreparedCaptureStore {
  PreparedCaptureStore(this.storage);
  final EvidenceStorageService storage;
  String _uri(String imageUri) =>
      '${imageUri.replaceFirst('/staging/', '/intake/')}.pending.json';

  Future<void> prepare({
    required EvidenceCaptureSessionRecord session,
    required String mediaId,
    required String actorId,
    required String viewType,
    required StoredEvidenceFile stored,
    required String? previousId,
    required DateTime capturedAt,
  }) async {
    final file = await storage.resolve(_uri(stored.localUri));
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'media_id': mediaId,
        'session_id': session.id,
        'assessment_id': session.assessmentId,
        'station_id': session.stationId,
        'scope_key': session.scopeKey,
        'actor_id': actorId,
        'view_type': viewType,
        'previous_id': previousId,
        'session_updated_at': session.updatedAt.toUtc().toIso8601String(),
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'local_uri': stored.localUri,
        'thumbnail_uri': stored.thumbnailLocalUri,
        'byte_size': stored.byteSize,
        'sha256': stored.sha256Checksum,
        'width': stored.widthPx,
        'height': stored.heightPx,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<List<File>> pending({String? assessmentId}) =>
      storage.pendingCaptureJournals(assessmentId);
  Future<void> finish(String localUri) async {
    final file = await storage.resolve(_uri(localUri));
    if (await file.exists()) await file.delete();
  }

  Future<bool> hasPending(String assessmentId) async =>
      (await pending(assessmentId: assessmentId)).isNotEmpty;

  Future<Map<String, dynamic>> read(File file) async {
    if (await file.length() > 32768) {
      throw const FormatException('Pending capture descriptor is too large.');
    }
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic> || json['version'] != 1) {
      throw const FormatException('Invalid pending capture.');
    }
    for (final key in [
      'media_id',
      'session_id',
      'assessment_id',
      'station_id',
      'scope_key',
      'actor_id',
      'view_type',
      'session_updated_at',
      'captured_at',
      'local_uri',
      'thumbnail_uri',
      'sha256',
    ]) {
      if (json[key] is! String || (json[key] as String).isEmpty) {
        throw const FormatException('Incomplete pending capture.');
      }
    }
    if (DateTime.tryParse(json['captured_at']) == null ||
        DateTime.tryParse(json['session_updated_at']) == null ||
        json['byte_size'] is! int ||
        json['width'] is! int ||
        json['height'] is! int ||
        (json['width'] as int) <= 0 ||
        (json['height'] as int) <= 0 ||
        (json['byte_size'] as int) <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['sha256'])) {
      throw const FormatException('Invalid pending capture metadata.');
    }
    String segment(String key) =>
        (json[key] as String).replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    final canonical =
        '${segment('assessment_id')}/${segment('station_id')}/${segment('scope_key')}/staging/${segment('media_id')}.jpg';
    if (json['local_uri'] != canonical) {
      throw const FormatException(
        'Pending capture does not match its session path.',
      );
    }
    // Bind descriptors to this exact private journal, never another record's file.
    final image = await storage.resolve(json['local_uri']);
    final thumbnail = await storage.resolve(json['thumbnail_uri']);
    final expected = await storage.resolve(_uri(json['local_uri']));
    if (expected.absolute.path != file.absolute.path ||
        !json['local_uri'].contains('/staging/') ||
        json['thumbnail_uri'] !=
            json['local_uri'].replaceFirst(RegExp(r'\.jpg$'), '_thumb.jpg')) {
      throw const FormatException('Unsafe pending capture descriptor.');
    }
    if (await image.exists()) {
      final bytes = await image.readAsBytes();
      if (bytes.length != json['byte_size'] ||
          sha256.convert(bytes).toString() != json['sha256']) {
        throw const FormatException('Pending capture checksum mismatch.');
      }
      if (!await thumbnail.exists()) {
        await storage.repairThumbnail(json['local_uri'], json['thumbnail_uri']);
      }
    }
    return json;
  }
}
