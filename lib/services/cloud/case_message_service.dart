import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/local_id.dart';
import '../evidence_storage_service.dart';
import '../evidence_quality_feedback.dart';
import 'wormwise_identity_service.dart';

class CaseMessagePhoto {
  CaseMessagePhoto({
    required this.id,
    required this.localUri,
    required this.thumbnailUri,
    this.caption = '',
    this.station,
    this.plant,
    this.blockRunId,
    this.captureSource = 'unknown',
    this.capturedAt,
    this.qualityWarnings = const [],
  });
  final String id, localUri, thumbnailUri;
  String caption;
  int? station, plant;
  String? blockRunId;
  final String captureSource;
  final DateTime? capturedAt;
  final List<String> qualityWarnings;
  Map<String, dynamic> toJson() => {
    'id': id,
    'local_uri': localUri,
    'thumbnail_uri': thumbnailUri,
    'caption': caption,
    'station': station,
    'plant': plant,
    'block_run_id': blockRunId,
    'capture_source': captureSource,
    'captured_at': capturedAt?.toUtc().toIso8601String(),
    'quality_warnings': qualityWarnings,
  };
  factory CaseMessagePhoto.fromJson(Map<String, dynamic> value) =>
      CaseMessagePhoto(
        id: value['id'] as String,
        localUri: value['local_uri'] as String,
        thumbnailUri: value['thumbnail_uri'] as String,
        caption: value['caption'] as String? ?? '',
        station: value['station'] as int?,
        plant: value['plant'] as int?,
        blockRunId: value['block_run_id'] as String?,
        captureSource: value['capture_source'] as String? ?? 'unknown',
        capturedAt: DateTime.tryParse(value['captured_at'] as String? ?? ''),
        qualityWarnings: (value['quality_warnings'] as List? ?? [])
            .whereType<String>()
            .toList(),
      );
}

class CaseMessageDraft {
  CaseMessageDraft({
    String? id,
    this.body = '',
    List<CaseMessagePhoto>? photos,
    this.requestId,
    this.attempted = false,
    this.targetBlockId,
    this.targetPlant,
    this.targetBlockSequence,
    this.requestedViews = const [],
    this.samePlantConfirmed = false,
  }) : id = id ?? LocalId.generate(),
       photos = photos ?? [];
  final String id;
  String body;
  final List<CaseMessagePhoto> photos;
  String? requestId;
  bool attempted;
  String? targetBlockId;
  int? targetPlant, targetBlockSequence;
  List<String> requestedViews;
  bool samePlantConfirmed;
  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'photos': photos.map((p) => p.toJson()).toList(),
    'request_id': requestId,
    'attempted': attempted,
    'target_block_id': targetBlockId,
    'target_plant': targetPlant,
    'target_block_sequence': targetBlockSequence,
    'requested_views': requestedViews,
    'same_plant_confirmed': samePlantConfirmed,
  };
  factory CaseMessageDraft.fromJson(Map<String, dynamic> value) =>
      CaseMessageDraft(
        id: value['id'] as String,
        body: value['body'] as String? ?? '',
        requestId: value['request_id'] as String?,
        attempted: value['attempted'] == true,
        targetBlockId: value['target_block_id'] as String?,
        targetPlant: value['target_plant'] as int?,
        targetBlockSequence: value['target_block_sequence'] as int?,
        requestedViews: (value['requested_views'] as List? ?? [])
            .whereType<String>()
            .toList(),
        samePlantConfirmed: value['same_plant_confirmed'] == true,
        photos: (value['photos'] as List? ?? [])
            .map(
              (p) => CaseMessagePhoto.fromJson(
                Map<String, dynamic>.from(p as Map),
              ),
            )
            .toList(),
      );
}

class CaseMessageAttachment {
  const CaseMessageAttachment({
    required this.path,
    required this.caption,
    required this.purpose,
    this.station,
    this.plant,
    this.url,
    this.blockSequence,
    this.provenance = '',
  });
  final String path, caption, purpose;
  final String provenance;
  final int? station, plant, blockSequence;
  final String? url;
  String get label => [
    purpose == 'field_evidence'
        ? 'Additional field evidence'
        : 'Expert reference',
    if (blockSequence != null) 'Block $blockSequence',
    if (station != null)
      blockSequence != null && plant == 1
          ? 'Sampled plant $station'
          : 'Station $station',
    if (plant != null && !(blockSequence != null && plant == 1)) 'Plant $plant',
    if (caption.isNotEmpty) caption,
    if (provenance.isNotEmpty) provenance,
  ].join(' · ');
}

/// Follow-up photos join the expert evidence queue without changing AI observations or scores.
class CaseMessageService {
  CaseMessageService(
    this.identity, {
    FlutterSecureStorage? draftStorage,
    EvidenceStorageService? files,
  }) : _draftStorage = draftStorage ?? const FlutterSecureStorage(),
       files = files ?? EvidenceStorageService();
  static const bucket = 'case-message-images';
  static const maxPhotos = 5;
  static const maxBytes = 10 * 1024 * 1024;
  final WormWiseIdentityService identity;
  final FlutterSecureStorage _draftStorage;
  final EvidenceStorageService files;
  Future<void> _writes = Future.value();
  final _signed = <String, ({String url, DateTime expires})>{};
  String _key(String owner, String caseId) =>
      'case_message_draft_${owner}_$caseId';

  Future<CaseMessageDraft> loadDraft(String owner, String caseId) async {
    await _writes;
    final raw = await _draftStorage.read(key: _key(owner, caseId));
    return raw == null
        ? CaseMessageDraft()
        : CaseMessageDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDraft(String owner, String caseId, CaseMessageDraft draft) {
    final payload = jsonEncode(draft.toJson());
    final write = _writes.then(
      (_) => _draftStorage.write(key: _key(owner, caseId), value: payload),
    );
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<({bool da, Map<String, int> blocks})> photoPlan(
    String assessmentId,
  ) async {
    final client = identity.client;
    if (client == null) throw StateError('Reconnect to load sampling blocks.');
    final row = await client
        .from('assessments')
        .select('protocol_version,result_snapshot')
        .eq('id', assessmentId)
        .single();
    final snapshot = row['result_snapshot'];
    final routes = snapshot is Map ? snapshot['sampling_routes'] : null;
    return (
      da: row['protocol_version'] == 'wormwise-da-scattered-20-v1',
      blocks: {
        if (routes is List)
          for (final r in routes)
            if (r is Map && r['block_run_id'] is String)
              r['block_run_id'] as String:
                  (r['block_sequence'] as num?)?.toInt() ?? 1,
      },
    );
  }

  Future<CaseMessagePhoto> stagePhoto(
    String caseId,
    CaseMessageDraft draft,
    String sourcePath, {
    int? station,
    int? plant,
    String? blockRunId,
    String captureSource = 'unknown',
    DateTime? capturedAt,
  }) async {
    if (draft.photos.length >= maxPhotos) {
      throw StateError('Attach up to five photos per message.');
    }
    if (await File(sourcePath).length() > maxBytes) {
      throw StateError('Choose a photo up to 10 MB.');
    }
    final id = LocalId.generate();
    final prepared = await files.stageCapturedFile(
      sourcePath: sourcePath,
      assessmentId: caseId,
      stationId: 'case_messages',
      scopeKey: draft.id,
      mediaId: id,
      deleteSourceAfterCopy: false,
      stripMetadata: true,
    );
    return CaseMessagePhoto(
      id: id,
      localUri: prepared.localUri,
      thumbnailUri: prepared.thumbnailLocalUri,
      station: draft.targetPlant ?? station,
      plant: draft.targetPlant != null ? 1 : plant,
      blockRunId: draft.targetPlant != null ? draft.targetBlockId : blockRunId,
      captureSource: captureSource,
      capturedAt: capturedAt,
    );
  }

  Future<void> send({
    required String owner,
    required String caseId,
    required CaseMessageDraft draft,
    required void Function(String) progress,
  }) async {
    final client = identity.client;
    if (client == null || identity.userId != owner) {
      throw StateError('Sign in and reconnect to send.');
    }
    if (draft.body.trim().isEmpty && draft.photos.isEmpty) {
      throw StateError('Write a reply or attach a photo.');
    }
    if (draft.body.length > 8000 || draft.photos.length > maxPhotos) {
      throw StateError('Message exceeds the allowed size.');
    }
    for (final p in draft.photos) {
      if (p.caption.length > 500 ||
          (p.station != null && p.station! <= 0) ||
          (p.plant != null && (p.plant! <= 0 || p.station == null))) {
        throw StateError(
          'Use positive station and plant numbers; a plant needs a station.',
        );
      }
    }
    if (draft.targetPlant != null &&
        draft.photos.isNotEmpty &&
        !draft.samePlantConfirmed) {
      throw StateError(
        'Confirm that these photos show the requested sampled plant.',
      );
    }
    for (final p in draft.photos) {
      if (draft.targetPlant != null &&
          (p.station != draft.targetPlant ||
              p.plant != 1 ||
              p.blockRunId != draft.targetBlockId)) {
        throw StateError(
          'A selected photo belongs to a different requested plant.',
        );
      }
    }
    draft.attempted = true;
    await saveDraft(owner, caseId, draft); // Preserve retry ID before upload.
    try {
      final existing = await client
          .from('case_messages')
          .select('id')
          .eq('id', draft.id)
          .maybeSingle();
      if (existing == null) {
        final attachments = <Map<String, dynamic>>[];
        for (var i = 0; i < draft.photos.length; i++) {
          if (identity.userId != owner) {
            throw StateError('Your account changed. Sign back in to retry.');
          }
          final p = draft.photos[i];
          final file = await files.resolve(p.localUri);
          if (!await file.exists()) {
            throw StateError(
              'A selected photo is no longer available on this phone.',
            );
          }
          progress('Uploading photo ${i + 1} of ${draft.photos.length}…');
          final path = '$caseId/$owner/${draft.id}/${p.id}.jpg';
          try {
            await client.storage
                .from(bucket)
                .uploadBinary(
                  path,
                  await file.readAsBytes(),
                  fileOptions: const FileOptions(
                    contentType: 'image/jpeg',
                    upsert: false,
                  ),
                );
          } on StorageException catch (error) {
            if (error.statusCode != '409' &&
                !RegExp(
                  'already exists|duplicate',
                  caseSensitive: false,
                ).hasMatch(error.message)) {
              rethrow;
            }
          }
          attachments.add({
            'storage_path': path,
            'caption': p.caption,
            'station_number': p.station,
            'plant_number': p.plant,
            'block_run_id': p.blockRunId,
            'capture_source': p.captureSource,
            'captured_at': p.capturedAt?.toUtc().toIso8601String(),
            'quality_warnings': p.qualityWarnings,
            'same_plant_confirmed': draft.samePlantConfirmed,
          });
        }
        if (identity.userId != owner) {
          throw StateError('Your account changed. Sign back in to retry.');
        }
        progress('Sending reply…');
        try {
          await client.rpc(
            'send_case_message',
            params: {
              'p_message_id': draft.id,
              'p_case_id': caseId,
              'p_body': draft.body.trim(),
              'p_attachments': attachments,
              'p_request_message_id': draft.requestId,
            },
          );
        } on PostgrestException catch (error) {
          if (error.code == 'PGRST202' &&
              draft.photos.isEmpty &&
              draft.requestId == null) {
            // Existing text messaging remains usable during the schema rollout.
            await client.from('case_messages').insert({
              'id': draft.id,
              'case_id': caseId,
              'sender_id': owner,
              'body': draft.body.trim(),
              'is_farmer_visible': true,
            });
          } else if (error.code == 'PGRST202') {
            throw StateError(
              'Photo replies need the server update before they can be sent.',
            );
          } else {
            rethrow;
          }
        }
      }
    } on PostgrestException catch (error) {
      // An explicit server rejection is safe to edit. Keep the same ID and
      // staged uploads; a network failure still stays locked for safe retry.
      if (RegExp(
        r'^(P0001|22\w{3}|23\w{3}|42501|PGRST20[0-4])$',
      ).hasMatch(error.code ?? '')) {
        draft.attempted = false;
        await saveDraft(owner, caseId, draft);
      }
      rethrow;
    } on StorageException {
      draft.attempted = false;
      await saveDraft(owner, caseId, draft);
      rethrow;
    }
    await _clear(owner, caseId, draft);
  }

  Future<void> discard(
    String owner,
    String caseId,
    CaseMessageDraft draft,
  ) async {
    if (draft.attempted) {
      final client = identity.client;
      if (client == null || identity.userId != owner) {
        throw StateError(
          'Reconnect to check whether this reply was delivered.',
        );
      }
      final existing = await client
          .from('case_messages')
          .select('id')
          .eq('id', draft.id)
          .maybeSingle();
      if (existing == null && draft.photos.isNotEmpty) {
        await client.storage
            .from(bucket)
            .remove(
              draft.photos
                  .map((p) => '$caseId/$owner/${draft.id}/${p.id}.jpg')
                  .toList(),
            );
      }
    }
    await _clear(owner, caseId, draft);
  }

  Future<void> _clear(
    String owner,
    String caseId,
    CaseMessageDraft draft,
  ) async {
    await _writes;
    await _draftStorage.delete(key: _key(owner, caseId));
    for (final p in draft.photos) {
      for (final uri in [p.localUri, p.thumbnailUri]) {
        // Only files created in this case's draft folder can be removed.
        if (!uri.startsWith('$caseId/case_messages/${draft.id}/staging/')) {
          continue;
        }
        try {
          final file = await files.resolve(uri);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          /* Best effort after publication. */
        }
      }
    }
  }

  Future<void> removeLocalPhoto(
    String caseId,
    CaseMessageDraft draft,
    CaseMessagePhoto photo,
  ) async {
    for (final uri in [photo.localUri, photo.thumbnailUri]) {
      if (!uri.startsWith('$caseId/case_messages/${draft.id}/staging/')) {
        continue;
      }
      final file = await files.resolve(uri);
      if (await file.exists()) await file.delete();
    }
  }

  Future<String?> photoUrl(String path, {bool refresh = false}) async {
    final key = '${identity.userId}:$path';
    final cached = _signed[key];
    if (!refresh && cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final url = await identity.client?.storage
          .from(bucket)
          .createSignedUrl(path, 1800);
      if (url != null) {
        _signed[key] = (
          url: url,
          expires: DateTime.now().add(const Duration(minutes: 25)),
        );
      }
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<List<CaseMessageAttachment>> loadAttachments(Object? json) async {
    if (json is! List) return const [];
    return Future.wait(
      json.whereType<Map>().take(maxPhotos).map((raw) async {
        final path = raw['storage_path'] as String;
        return CaseMessageAttachment(
          path: path,
          caption: raw['caption'] as String? ?? '',
          purpose: raw['purpose'] as String? ?? 'field_evidence',
          station: raw['station_number'] as int?,
          plant: raw['plant_number'] as int?,
          blockSequence: raw['block_sequence'] as int?,
          provenance: [
            'Source: ${raw['capture_source'] ?? 'unknown'}',
            raw['captured_at'] == null
                ? 'Capture time unknown'
                : 'Captured (reported): ${raw['captured_at']}',
            if (raw['received_at'] != null) 'Received: ${raw['received_at']}',
            if (raw['same_plant_confirmed'] == true)
              'Same sampled plant confirmed by farmer',
            for (final warning in (raw['quality_warnings'] as List? ?? []))
              evidenceQualityMessages[warning] ?? warning.toString(),
          ].join(' · '),
          url: await photoUrl(path),
        );
      }),
    );
  }
}
