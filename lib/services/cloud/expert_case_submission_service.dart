import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/field_repository.dart';
import '../../data/repositories/assessment_history_repository.dart';
import '../../models/assessment_history_models.dart';
import '../evidence_storage_service.dart';
import '../scouting_sampling_protocol.dart';

class ExpertCaseSubmissionResult {
  const ExpertCaseSubmissionResult({
    required this.caseId,
    required this.existed,
  });
  final String caseId;
  final bool existed;
}

class ExpertSubmissionStageException implements Exception {
  const ExpertSubmissionStageException(this.stage, this.cause);
  final String stage;
  final Object cause;
  @override
  String toString() => '$stage failed: $cause';
}

Future<T> _submissionStage<T>(
  String stage,
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } catch (error) {
    throw ExpertSubmissionStageException(stage, error);
  }
}

class ExpertCaseSubmissionService {
  const ExpertCaseSubmissionService({
    required AppDatabase database,
    required SupabaseClient client,
    required EvidenceStorageService storage,
  }) : _database = database,
       _client = client,
       _storage = storage;

  final AppDatabase _database;
  final SupabaseClient _client;
  final EvidenceStorageService _storage;

  /// Repairs only shared, unpublished photo metadata using the original local
  /// media/station IDs. It never uploads new photos or changes consent/grades.
  Future<void> synchronizeSubmittedBlockIdentities() async {
    final ownerId = _client.auth.currentUser?.id;
    if (ownerId == null) return;
    final cases = await _client
        .from('expert_cases')
        .select('id,assessment_id')
        .eq('owner_id', ownerId)
        .eq('evidence_photo_consent', true);
    if (cases.isEmpty) return;
    final finalized = await _client
        .from('expert_severity_summaries')
        .select('case_id')
        .inFilter('case_id', [for (final c in cases) c['id']]);
    final finalizedIds = {for (final row in finalized) row['case_id']};
    for (final c in cases) {
      if (finalizedIds.contains(c['id'])) continue;
      if (_client.auth.currentUser?.id != ownerId) {
        throw StateError(
          'The signed-in account changed during synchronization.',
        );
      }
      final detail = await AssessmentHistoryRepository(
        _database,
      ).loadDetail(c['assessment_id'] as String);
      if (detail != null) await _syncEvidenceBlockIdentities(detail, ownerId);
    }
  }

  Future<ExpertCaseSubmissionResult> submit({
    required AssessmentHistoryDetail detail,
    required String farmerDisplayName,
    required bool shareLocation,
    required bool shareEvidence,
    String? farmerQuestion,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Connect to the internet and try again.');
    }
    if (detail.assessment.status != 'completed') {
      throw StateError(
        'Only completed assessments can be sent for expert review.',
      );
    }
    if (ScoutingSamplingProtocol.isRetired(
      detail.assessment.protocolVersion,
      pattern: detail.assessment.scoutingPattern,
    )) {
      throw StateError(
        'This assessment uses an outdated scouting method. '
        'Create a new DA assessment with 20 plants per block.',
      );
    }
    final field = detail.workspace.field;
    final barangay = field.barangay?.trim() ?? '';
    if (barangay.isEmpty) {
      throw StateError(
        'Add the field barangay before sending this assessment.',
      );
    }
    final name = farmerDisplayName.trim();
    if (name.length < 2 || name.length > 120) {
      throw ArgumentError('Enter the farmer or field representative name.');
    }

    final existing = await _submissionStage(
      'Checking existing expert submission',
      () => _client
          .from('expert_cases')
          .select('id,evidence_photo_consent')
          .eq('assessment_id', detail.assessment.id)
          .maybeSingle(),
    );
    if (existing != null) {
      if (existing['evidence_photo_consent'] == true) {
        await _syncEvidenceBlockIdentities(detail, user.id);
      }
      await _recordSubmission(detail.assessment.id, existing['id'] as String);
      return ExpertCaseSubmissionResult(
        caseId: existing['id'] as String,
        existed: true,
      );
    }

    // Local sync flags and a successful account backup do not prove the
    // relational assessment exists and is visible to the active account.
    final remote = await _submissionStage(
      'Checking cloud assessment',
      () => _client
          .from('assessments')
          .select('id,owner_id,status,completed_at,result_snapshot')
          .eq('id', detail.assessment.id)
          .maybeSingle(),
    );
    if (remote == null) {
      throw StateError(
        'The cloud assessment is not visible to this session. It may not have synchronized, or a server access policy may be blocking it. Being signed in does not confirm cloud synchronization.',
      );
    }
    if (remote['owner_id'] != user.id) {
      throw StateError(
        'The cloud assessment belongs to a different account. Sign in with its owning account.',
      );
    }
    if (remote['status'] != 'completed' ||
        remote['completed_at'] == null ||
        remote['result_snapshot'] == null) {
      throw StateError(
        'The cloud assessment is not ready for submission. Its completed results must synchronize first.',
      );
    }
    if (_client.auth.currentUser?.id != user.id) {
      throw StateError(
        'The signed-in account changed during submission. Reopen the assessment and retry.',
      );
    }

    if (shareEvidence) await _uploadEvidence(detail, user.id);

    if (_client.auth.currentUser?.id != user.id) {
      throw StateError(
        'The signed-in account changed during submission. Reopen the assessment and retry.',
      );
    }

    final response = await _submissionStage(
      'Submitting expert review case',
      () => _client.rpc(
        'submit_assessment_for_expert_review',
        params: {
          'p_assessment_id': detail.assessment.id,
          'p_farmer_display_name': name,
          'p_field_name': field.name,
          'p_barangay': barangay,
          'p_municipality': field.municipalityCity?.trim().isNotEmpty == true
              ? field.municipalityCity!.trim()
              : 'Piat',
          'p_province': field.province?.trim().isNotEmpty == true
              ? field.province!.trim()
              : 'Cagayan',
          'p_location_consent': shareLocation,
          'p_evidence_consent': shareEvidence,
          'p_farmer_question': farmerQuestion?.trim(),
        },
      ),
    );
    final caseId = response?.toString();
    if (caseId == null || caseId.isEmpty) {
      throw StateError('Supabase did not return the created case.');
    }
    await _recordSubmission(detail.assessment.id, caseId);
    return ExpertCaseSubmissionResult(caseId: caseId, existed: false);
  }

  Future<void> _recordSubmission(String assessmentId, String caseId) async {
    await _database
        .into(_database.syncOutbox)
        .insertOnConflictUpdate(
          SyncOutboxCompanion.insert(
            id: 'report_assessment_$assessmentId',
            entityType: 'assessment_report',
            entityId: assessmentId,
            operation: 'expert_case_submission',
            payloadJson: Value('{"caseId":"$caseId"}'),
            status: const Value('submitted'),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> _uploadEvidence(
    AssessmentHistoryDetail detail,
    String ownerId,
  ) async {
    for (final entry in detail.evidence) {
      if (_client.auth.currentUser?.id != ownerId) {
        throw StateError(
          'The signed-in account changed during photo upload. Reopen the assessment and retry.',
        );
      }
      final media = entry.media;
      if (media.storageState != 'ready' || media.mediaType != 'image') continue;
      final file = await _storage.resolve(media.localUri);
      if (!await file.exists()) {
        throw FileSystemException(
          'A selected evidence photograph is unavailable. Reopen the assessment and review its evidence.',
          file.path,
        );
      }
      final mimeType = _supportedMimeType(media.mimeType);
      final extension = mimeType == 'image/png'
          ? 'png'
          : mimeType == 'image/webp'
          ? 'webp'
          : 'jpg';
      final storagePath =
          '$ownerId/${detail.assessment.id}/${media.id}.$extension';
      // Evidence is immutable: retries must not require UPDATE policies.
      // A previous attempt may have uploaded the object before losing its
      // connection while saving metadata or submitting the case.
      if (await file.length() > 10485760) {
        throw StateError('An evidence photo exceeds the 10 MB upload limit.');
      }
      try {
        await _submissionStage(
          'Uploading evidence photo',
          () async => _client.storage
              .from('assessment-evidence')
              .uploadBinary(
                storagePath,
                await file.readAsBytes(),
                fileOptions: FileOptions(contentType: mimeType, upsert: false),
              ),
        );
      } on ExpertSubmissionStageException catch (failure) {
        final error = failure.cause;
        if (error is! StorageException) rethrow;
        final duplicate =
            error.statusCode == '409' ||
            error.error?.toLowerCase() == 'duplicate' ||
            error.message.toLowerCase().contains('already exists');
        if (!duplicate) rethrow;
        // Confirm the existing private object is readable by this account.
        await _submissionStage(
          'Checking previously uploaded photo',
          () => _client.storage
              .from('assessment-evidence')
              .createSignedUrl(storagePath, 60),
        );
      }
      final stationNumber = _stationNumber(detail, entry.stationId);
      final block = _blockIdentity(detail, entry.stationId);
      await _submissionStage(
        'Saving evidence metadata',
        () async => _client
            .from('evidence_files')
            .upsert(
              {
                'id': media.id,
                'owner_id': ownerId,
                'assessment_id': detail.assessment.id,
                'storage_path': storagePath,
                'station_number': stationNumber,
                'plant_number': entry.plantPosition,
                if (block != null) ...block,
                'mime_type': mimeType,
                'sha256': media.sha256Checksum,
                'captured_at': media.captureSource == 'gallery'
                    ? null
                    : media.capturedAt?.toUtc().toIso8601String(),
                'capture_source': media.captureSource,
                'quality_warnings': jsonDecode(media.qualityIssuesJson ?? '[]'),
                'cv_analysis': await _photoAnalysis(media),
              },
              onConflict: 'id',
              ignoreDuplicates: true,
            ),
      );
      if (block != null) await _syncEvidenceBlockIdentity(media.id, block);
      await (_database.update(
        _database.evidenceMedia,
      )..where((row) => row.id.equals(media.id))).write(
        EvidenceMediaCompanion(
          remoteUri: Value(storagePath),
          uploadState: const Value('synced'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  }

  int? _stationNumber(AssessmentHistoryDetail detail, String? stationId) {
    if (stationId == null) return null;
    for (final snapshot in detail.stations) {
      if (snapshot.station?.id == stationId) return snapshot.stationNumber;
    }
    return null;
  }

  Map<String, dynamic>? _blockIdentity(
    AssessmentHistoryDetail detail,
    String? stationId,
  ) {
    if (stationId == null) return null;
    for (final snapshot in detail.stations) {
      if (snapshot.station?.id == stationId) {
        return {
          'block_run_id': snapshot.prepared.run.id,
          'block_sequence': snapshot.prepared.run.blockSequence,
        };
      }
    }
    return null;
  }

  Future<void> _syncEvidenceBlockIdentities(
    AssessmentHistoryDetail detail,
    String ownerId,
  ) async {
    final remote = await _client
        .from('evidence_files')
        .select('id,block_run_id,block_sequence')
        .eq('assessment_id', detail.assessment.id)
        .eq('owner_id', ownerId);
    final byId = {for (final row in remote) row['id']: row};
    for (final entry in detail.evidence) {
      if (_client.auth.currentUser?.id != ownerId) {
        throw StateError('The signed-in account changed during submission.');
      }
      final block = _blockIdentity(detail, entry.stationId);
      final photo = byId[entry.media.id];
      if (block != null &&
          photo != null &&
          entry.media.deletedAt == null &&
          entry.media.mediaType == 'image' &&
          (photo['block_run_id'] == null || photo['block_sequence'] == null)) {
        await _syncEvidenceBlockIdentity(entry.media.id, block);
      }
    }
  }

  Future<void> _syncEvidenceBlockIdentity(
    String evidenceId,
    Map<String, dynamic> block,
  ) async {
    await _submissionStage(
      'Synchronizing sampling block identity',
      () => _client.rpc(
        'sync_evidence_block_identity',
        params: {
          'p_evidence_id': evidenceId,
          'p_block_run_id': block['block_run_id'],
          'p_block_sequence': block['block_sequence'],
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _photoAnalysis(
    EvidenceMediaRecord media,
  ) async {
    final saved = await FieldRepository(
      _database,
    ).readPreferenceValue('evidence_model_${media.id}');
    if (saved == null) return null;
    try {
      final data = jsonDecode(saved);
      if (data is! Map<String, dynamic> ||
          data['evidence_id'] != media.id ||
          data['sha256'] != media.sha256Checksum ||
          media.sha256Checksum.isEmpty) {
        return null;
      }
      return data;
    } on FormatException {
      return null;
    }
  }

  String _supportedMimeType(String? value) {
    return switch (value?.toLowerCase()) {
      'image/png' => 'image/png',
      'image/webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
