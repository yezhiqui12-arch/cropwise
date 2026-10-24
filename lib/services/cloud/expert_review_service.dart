import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'wormwise_identity_service.dart';
import 'case_message_service.dart';
import 'expert_damage_monitoring.dart';
import '../scouting_sampling_protocol.dart';

class ExpertMessage {
  const ExpertMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.severityCaseId,
    this.attachments = const [],
    this.kind = 'message',
    this.requestedStation,
    this.requestedPlant,
    this.requestId,
    this.requestedBlockId,
    this.requestedBlockSequence,
    this.evidenceStatus,
    this.requestedViews = const [],
  });
  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final String? severityCaseId;
  final List<CaseMessageAttachment> attachments;
  final String kind;
  final int? requestedStation, requestedPlant;
  final String? requestId;
  final String? requestedBlockId, evidenceStatus;
  final int? requestedBlockSequence;
  final List<String> requestedViews;
}

class ExpertPlantPhoto {
  const ExpertPlantPhoto({required this.id, required this.url});
  final String id;
  final String? url;
}

class ExpertPlantRating {
  const ExpertPlantRating({
    required this.stationNumber,
    required this.plantNumber,
    required this.outcome,
    required this.davisScore,
    required this.note,
    required this.photos,
    this.damageFreshness,
    this.blockRunId,
    this.blockSequence,
    this.protocolVersion,
    this.associationAmbiguous = false,
  });
  final int stationNumber;
  final int plantNumber;
  final String outcome;
  final int? davisScore;
  final String note;
  final List<ExpertPlantPhoto> photos;
  final String? damageFreshness;
  final String? blockRunId;
  final int? blockSequence;
  final String? protocolVersion;
  final bool associationAmbiguous;
  String get identityKey =>
      '${blockRunId ?? 'legacy'}:$stationNumber:$plantNumber';
  String get plantLabel =>
      ScoutingSamplingProtocol.isDa(protocolVersion ?? '') && plantNumber == 1
      ? 'Plant $stationNumber'
      : 'Station $stationNumber · Plant $plantNumber';
  String get freshnessLabel => outcome != 'scored'
      ? 'Insufficient evidence'
      : davisScore == 0
      ? 'No visible damage'
      : switch (damageFreshness) {
          'fresh' => 'Fresh damage',
          'old_only' => 'Old damage only',
          'uncertain' => 'Cannot determine',
          _ => 'Freshness not recorded',
        };
}

class ExpertSeveritySummary {
  const ExpertSeveritySummary({
    required this.reviewedPlants,
    required this.scoredPlants,
    required this.insufficientPlants,
    required this.medianDavisScore,
    required this.finalizedAt,
    this.monitoring = const {},
  });

  final int reviewedPlants;
  final int scoredPlants;
  final int insufficientPlants;
  final double? medianDavisScore;
  final DateTime finalizedAt;
  final Map<String, dynamic> monitoring;
}

class ExpertReviewCase {
  const ExpertReviewCase({
    required this.id,
    required this.assessmentId,
    required this.fieldName,
    required this.location,
    required this.status,
    required this.createdAt,
    required this.messages,
    required this.severitySummary,
    this.expertId,
    this.expertName,
    this.expertPhone,
  });
  final String id;
  final String assessmentId;
  final String fieldName;
  final String location;
  final String status;
  final DateTime createdAt;
  final List<ExpertMessage> messages;
  final ExpertSeveritySummary? severitySummary;
  final String? expertId;
  final String? expertName;
  final String? expertPhone;
}

class ExpertReviewService extends ChangeNotifier {
  late final CaseMessageService media = CaseMessageService(_identity);
  ExpertReviewService(this._identity, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _identity.addListener(_identityChanged);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    unawaited(refresh());
  }

  final WormWiseIdentityService _identity;
  final FlutterSecureStorage _storage;
  Timer? _timer;
  Timer? _realtimeDebounce;
  RealtimeChannel? _realtimeChannel;
  String? _subscribedUserId;
  List<ExpertReviewCase> _cases = const [];
  bool _loading = false;
  String? _error;
  DateTime? _lastReadAt;
  String? _loadedUserId;
  int _refreshGeneration = 0;

  List<ExpertReviewCase> get cases => _cases;
  String? get currentUserId => _identity.userId;
  bool get loading => _loading;
  String? get error => _error;
  int get unreadCount {
    final userId = _identity.userId;
    if (userId == null) return 0;
    return _cases
        .expand((item) => item.messages)
        .where(
          (message) =>
              message.senderId != userId &&
              (_lastReadAt == null || message.createdAt.isAfter(_lastReadAt!)),
        )
        .length;
  }

  String get _readKey =>
      'expert_review_last_read_${_identity.userId ?? 'local'}';

  Future<void> _identityChanged() async {
    final userId = _identity.userId;
    if (userId != _loadedUserId) {
      _refreshGeneration++;
      _loadedUserId = userId;
      _cases = const [];
      _lastReadAt = null;
      _error = null;
      _loading = false;
      notifyListeners();
    }
    if (userId == null && _realtimeChannel != null) {
      final channel = _realtimeChannel!;
      _realtimeChannel = null;
      _subscribedUserId = null;
      final client = _identity.client;
      if (client != null) unawaited(client.removeChannel(channel));
    }
    await refresh();
  }

  Future<void> refresh() async {
    final client = _identity.client;
    final user = _identity.user;
    if (client == null || user == null || _loading) return;
    if (_loadedUserId != user.id) {
      _refreshGeneration++;
      _loadedUserId = user.id;
      _cases = const [];
      _lastReadAt = null;
      notifyListeners();
    }
    final generation = ++_refreshGeneration;
    _ensureRealtimeSubscription(client, user.id);
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _storage.read(key: _readKey);
      _lastReadAt ??= saved == null ? null : DateTime.tryParse(saved)?.toUtc();
      final rows = await client
          .from('expert_cases')
          .select(
            'id,assessment_id,field_name_snapshot,barangay_snapshot,municipality_snapshot,province_snapshot,status,created_at',
          )
          .eq('owner_id', user.id)
          .order('created_at', ascending: false);
      final rawCases = (rows as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final severityByCase = <String, ExpertSeveritySummary>{};
      final contactsByCase = <String, Map<String, dynamic>>{};
      if (rawCases.isNotEmpty) {
        try {
          final contacts = await client.rpc('get_my_expert_contacts');
          for (final raw in (contacts as List)) {
            final contact = Map<String, dynamic>.from(raw as Map);
            contactsByCase[contact['case_id'] as String] = contact;
          }
        } on PostgrestException {
          // Messaging remains available until the contact migration is applied.
        }
      }
      if (rawCases.isNotEmpty) {
        try {
          final summaryRows = await client
              .from('expert_severity_summaries')
              .select('*')
              .inFilter(
                'case_id',
                rawCases.map((row) => row['id'] as String).toList(),
              );
          for (final rawSummary in (summaryRows as List)) {
            final summary = Map<String, dynamic>.from(rawSummary as Map);
            final medianRaw = summary['median_davis_score'];
            severityByCase[summary['case_id']
                as String] = ExpertSeveritySummary(
              monitoring: expertDamageMonitoringFacts(summary),
              reviewedPlants: summary['reviewed_plants'] as int,
              scoredPlants: summary['scored_plants'] as int,
              insufficientPlants: summary['insufficient_plants'] as int,
              medianDavisScore: medianRaw == null
                  ? null
                  : double.tryParse(medianRaw.toString()),
              finalizedAt: DateTime.parse(
                summary['finalized_at'] as String,
              ).toUtc(),
            );
          }
        } on PostgrestException {
          // Older servers may not have the optional severity migration yet.
        }
      }
      final loaded = <ExpertReviewCase>[];
      for (final row in rawCases) {
        if (generation != _refreshGeneration || _identity.userId != user.id) {
          return;
        }
        final messageRows = <Map<String, dynamic>>[];
        for (var offset = 0; ; offset += 500) {
          final page = await client
              .from('case_messages')
              .select()
              .eq('case_id', row['id'])
              .eq('is_farmer_visible', true)
              .order('created_at', ascending: true)
              .order('id')
              .range(offset, offset + 499);
          if (generation != _refreshGeneration || _identity.userId != user.id)
            return;
          messageRows.addAll(page);
          if (page.length < 500) break;
        }
        final messages = await Future.wait(
          messageRows.map(
            (rawMessage) async => ExpertMessage(
              id: rawMessage['id'] as String,
              senderId: rawMessage['sender_id'] as String,
              body: rawMessage['body'] as String,
              createdAt: DateTime.parse(
                rawMessage['created_at'] as String,
              ).toUtc(),
              severityCaseId: rawMessage['expert_severity_case_id'] as String?,
              attachments: await media.loadAttachments(
                rawMessage['attachments'],
              ),
              kind: rawMessage['message_kind'] as String? ?? 'message',
              requestedStation: rawMessage['requested_station'] as int?,
              requestedPlant: rawMessage['requested_plant'] as int?,
              requestId: rawMessage['request_message_id'] as String?,
              requestedBlockId: rawMessage['requested_block_run_id'] as String?,
              requestedBlockSequence:
                  rawMessage['requested_block_sequence'] as int?,
              evidenceStatus: rawMessage['evidence_request_status'] as String?,
              requestedViews: (rawMessage['requested_views'] as List? ?? [])
                  .whereType<String>()
                  .toList(),
            ),
          ),
        );
        final severity = severityByCase[row['id'] as String];
        // Keep older finalized reviews accessible until the chat migration is
        // installed. The persisted message replaces this fallback automatically.
        if (severity != null &&
            !messages.any((message) => message.severityCaseId == row['id'])) {
          messages.add(
            ExpertMessage(
              id: 'severity-${row['id']}',
              senderId: 'expert-severity-review',
              body: 'Your expert-reviewed leaf-damage severity is ready.',
              createdAt: severity.finalizedAt,
              severityCaseId: row['id'] as String,
            ),
          );
        }
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        loaded.add(
          ExpertReviewCase(
            id: row['id'] as String,
            assessmentId: row['assessment_id'] as String,
            fieldName: (row['field_name_snapshot'] as String?) ?? 'Maize field',
            location:
                [
                      row['barangay_snapshot'],
                      row['municipality_snapshot'],
                      row['province_snapshot'],
                    ]
                    .whereType<String>()
                    .where((value) => value.trim().isNotEmpty)
                    .join(', '),
            status: row['status'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
            messages: messages,
            severitySummary: severityByCase[row['id'] as String],
            expertId: contactsByCase[row['id']]?['expert_id'] as String?,
            expertName: contactsByCase[row['id']]?['display_name'] as String?,
            expertPhone: contactsByCase[row['id']]?['phone'] as String?,
          ),
        );
      }
      if (generation == _refreshGeneration && _identity.userId == user.id) {
        _cases = loaded;
      }
    } on PostgrestException catch (error) {
      if (generation == _refreshGeneration) _error = error.message;
    } catch (_) {
      if (generation == _refreshGeneration) {
        _error = 'Expert reviews could not be loaded. Check your connection.';
      }
    } finally {
      if (generation == _refreshGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _ensureRealtimeSubscription(SupabaseClient client, String userId) {
    if (_subscribedUserId == userId && _realtimeChannel != null) return;
    final previous = _realtimeChannel;
    if (previous != null) unawaited(client.removeChannel(previous));
    _subscribedUserId = userId;
    _realtimeChannel = client
        .channel('mobile-expert-review-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'case_messages',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'expert_cases',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'expert_severity_summaries',
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> markAllRead() async {
    final latest = _cases
        .expand((item) => item.messages)
        .where((message) => message.senderId != _identity.userId)
        .fold<DateTime?>(
          null,
          (value, message) => value == null || message.createdAt.isAfter(value)
              ? message.createdAt
              : value,
        );
    if (latest == null) return;
    _lastReadAt = latest;
    await _storage.write(
      key: _readKey,
      value: latest.toUtc().toIso8601String(),
    );
    notifyListeners();
  }

  Future<void> sendReply(ExpertReviewCase reviewCase, String body) async {
    final client = _identity.client;
    final userId = _identity.userId;
    if (client == null || userId == null) {
      throw StateError('Connect to the internet and try again.');
    }
    if (!_cases.any((item) => item.id == reviewCase.id)) {
      throw StateError('This review is no longer available for your account.');
    }
    await client.from('case_messages').insert({
      'case_id': reviewCase.id,
      'sender_id': userId,
      'body': body.trim(),
      'is_farmer_visible': true,
    });
    await refresh();
  }

  /// Load all farmer-visible text for a report; never truncate at the server row limit.
  Future<List<ExpertMessage>> loadReportGuidance(String caseId) async {
    final client = _identity.client;
    final userId = _identity.userId;
    final review = _cases.where((c) => c.id == caseId).firstOrNull;
    if (client == null || userId == null || review?.severitySummary == null) {
      throw StateError('A finalized review is required.');
    }
    final messages = <ExpertMessage>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('case_messages')
          .select()
          .eq('case_id', caseId)
          .eq('is_farmer_visible', true)
          .order('id')
          .range(offset, offset + 499);
      if (_identity.userId != userId)
        throw StateError('Account changed while loading guidance.');
      for (final row in rows) {
        messages.add(
          ExpertMessage(
            id: row['id'] as String,
            senderId: row['sender_id'] as String,
            body: row['body'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            severityCaseId: row['expert_severity_case_id'] as String?,
          ),
        );
      }
      if (rows.length < 500) break;
    }
    return messages;
  }

  Future<List<ExpertPlantRating>> loadSeverityRatings(String caseId) async {
    final client = _identity.client;
    final userId = _identity.userId;
    final matches = _cases.where((item) => item.id == caseId);
    if (client == null ||
        userId == null ||
        matches.isEmpty ||
        matches.first.severitySummary == null) {
      throw StateError('A finalized review is required.');
    }
    final reviewCase = matches.first;
    final assessment = await client
        .from('assessments')
        .select('protocol_version,result_snapshot')
        .eq('id', reviewCase.assessmentId)
        .maybeSingle();
    final snapshot = assessment?['result_snapshot'];
    final blockSequences = <String, int>{};
    if (snapshot is Map) {
      final routes = snapshot['sampling_routes'];
      final screen = snapshot['automatic_damage_screen'];
      final points = screen is Map ? screen['stations'] : null;
      for (final rows in [routes, points]) {
        if (rows is List) {
          for (final row in rows) {
            if (row is Map &&
                row['block_run_id'] is String &&
                row['block_sequence'] is int) {
              blockSequences[row['block_run_id'] as String] =
                  row['block_sequence'] as int;
            }
          }
        }
      }
    }
    final ratings = <Map<String, dynamic>>[];
    final evidence = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('expert_plant_severity')
          .select()
          .eq('case_id', caseId)
          .order('block_run_id', nullsFirst: true)
          .order('station_number')
          .order('plant_number')
          .range(offset, offset + 499);
      if (_identity.userId != userId)
        throw StateError('Account changed while loading findings.');
      ratings.addAll(page);
      if (page.length < 500) break;
    }
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('evidence_files')
          .select()
          .eq('assessment_id', reviewCase.assessmentId)
          .order('id')
          .range(offset, offset + 499);
      if (_identity.userId != userId)
        throw StateError('Account changed while loading evidence.');
      evidence.addAll(page);
      if (page.length < 500) break;
    }
    final photosByPlant = <String, List<ExpertPlantPhoto>>{};
    for (final photo in evidence) {
      if (photo['block_run_id'] is String && photo['block_sequence'] is int) {
        blockSequences[photo['block_run_id'] as String] =
            photo['block_sequence'] as int;
      }
    }
    final plan = snapshot is Map ? snapshot['sampling_summary'] : null;
    final planned = plan is Map
        ? (plan['planned_sample_count'] as num?)?.toInt() ?? 0
        : 0;
    final isDa = ScoutingSamplingProtocol.isDa(
      assessment?['protocol_version'] as String? ?? '',
    );
    final multipleBlocks =
        blockSequences.length > 1 ||
        evidence
                .map((p) => p['block_run_id'])
                .whereType<String>()
                .toSet()
                .length >
            1 ||
        isDa && planned >= 40 && planned % 20 == 0;
    final associationAmbiguous =
        multipleBlocks &&
        evidence.any(
          (p) => p['plant_number'] != null && p['block_run_id'] == null,
        );
    String key(Map<String, dynamic> row) =>
        '${row['block_run_id'] ?? 'legacy'}:${row['station_number']}:${row['plant_number']}';
    final photoKeys = {for (final photo in evidence) key(photo)};
    final linkedRatings = ratings
        .where((rating) => photoKeys.contains(key(rating)))
        .toList();
    final ratedKeys = {for (final rating in linkedRatings) key(rating)};
    final plantPhotos = evidence
        .where((photo) => ratedKeys.contains(key(photo)))
        .toList();
    final urlsByPath = <String, String>{};
    for (final bucket in {'assessment-evidence', 'case-message-images'}) {
      final bucketPhotos = plantPhotos
          .where(
            (p) => (p['storage_bucket'] ?? 'assessment-evidence') == bucket,
          )
          .toList();
      if (bucketPhotos.isEmpty) continue;
      try {
        final signed = await client.storage.from(bucket).createSignedUrlsResult(
          [for (final photo in bucketPhotos) photo['storage_path'] as String],
          1800,
        );
        for (final result in signed) {
          if (result is SignedUrlSuccess)
            urlsByPath['$bucket:${result.path}'] = result.signedUrl;
        }
      } catch (_) {
        // Preserve ratings when an evidence image cannot be loaded.
      }
    }
    for (final photo in plantPhotos) {
      (photosByPlant[key(photo)] ??= []).add(
        ExpertPlantPhoto(
          id: photo['id'] as String,
          url:
              urlsByPath['${photo['storage_bucket'] ?? 'assessment-evidence'}:${photo['storage_path']}'],
        ),
      );
    }
    if (_identity.userId != userId ||
        !_cases.any((item) => item.id == caseId)) {
      throw StateError('This review is no longer available for your account.');
    }
    final orderedRatings = <ExpertPlantRating>[
      for (final rating in linkedRatings)
        ExpertPlantRating(
          blockRunId: rating['block_run_id'] as String?,
          blockSequence:
              rating['block_sequence'] as int? ??
              blockSequences[rating['block_run_id']],
          protocolVersion: assessment?['protocol_version'] as String?,
          associationAmbiguous: associationAmbiguous,
          stationNumber: rating['station_number'] as int,
          plantNumber: rating['plant_number'] as int,
          outcome: rating['outcome'] as String,
          damageFreshness: rating['damage_freshness'] as String?,
          davisScore: rating['davis_score'] as int?,
          note: rating['note'] as String? ?? '',
          photos: (photosByPlant[key(rating)] ?? [])
            ..sort((a, b) => a.id.compareTo(b.id)),
        ),
    ];
    orderedRatings.sort((a, b) {
      final blockOrder = (a.blockSequence ?? 0).compareTo(b.blockSequence ?? 0);
      if (blockOrder != 0) return blockOrder;
      final blockIdOrder = (a.blockRunId ?? '').compareTo(b.blockRunId ?? '');
      if (blockIdOrder != 0) return blockIdOrder;
      final stationOrder = a.stationNumber.compareTo(b.stationNumber);
      return stationOrder != 0
          ? stationOrder
          : a.plantNumber.compareTo(b.plantNumber);
    });
    return orderedRatings;
  }

  Map<String, dynamic> assessmentReviewFacts(String assessmentId) => {
    'availability': loading
        ? 'loading'
        : error != null
        ? 'error'
        : 'cached',
    'note':
        'Cached cloud review records; absence does not prove no review exists. Finalized results describe the assessment date, not current live field conditions.',
    'cases': [
      for (final c in cases.where((c) => c.assessmentId == assessmentId))
        {
          'status': c.status,
          'created_at': c.createdAt.toIso8601String(),
          'reviewer_guidance': [
            for (final message in c.messages.where(
              (m) => m.senderId != currentUserId && m.body.trim().isNotEmpty,
            ))
              {
                'text': message.body,
                'recorded_at': message.createdAt.toIso8601String(),
                'kind': message.kind,
                if (message.requestedBlockSequence != null)
                  'block_sequence': message.requestedBlockSequence,
                if (message.requestedStation != null)
                  'plant_number': message.requestedStation,
                if (message.evidenceStatus != null)
                  'evidence_request_status': message.evidenceStatus,
              },
          ],
          if (c.severitySummary != null)
            'severity': {
              'reviewed_plants': c.severitySummary!.reviewedPlants,
              'scored_plants': c.severitySummary!.scoredPlants,
              'insufficient_plants': c.severitySummary!.insufficientPlants,
              'median_davis_score': c.severitySummary!.medianDavisScore,
              'finalized_at': c.severitySummary!.finalizedAt.toIso8601String(),
              ...c.severitySummary!.monitoring,
            },
        },
    ],
  };

  @override
  void dispose() {
    _timer?.cancel();
    _realtimeDebounce?.cancel();
    final channel = _realtimeChannel;
    final client = _identity.client;
    if (channel != null && client != null) {
      unawaited(client.removeChannel(channel));
    }
    _identity.removeListener(_identityChanged);
    super.dispose();
  }
}
