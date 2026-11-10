import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/local/app_database.dart';
import '../data/local/database_codes.dart';
import 'cloud/expert_review_service.dart';
import 'cloud/account_app_data_service.dart';

enum WormWiseNotificationKind {
  followUp,
  inactiveField,
  needsInformation,
  adviceReady,
  severityReady,
}

class WormWiseNotification {
  const WormWiseNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.assessmentId,
    this.caseId,
    this.bodyTemplate,
    this.bodyArguments = const {},
  });
  final String id;
  final WormWiseNotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? assessmentId;
  final String? caseId;
  // Keep the English body for existing consumers; the UI formats this template
  // in the selected language without translating the field name.
  final String? bodyTemplate;
  final Map<String, Object> bodyArguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'created_at': createdAt.toUtc().toIso8601String(),
    'assessment_id': assessmentId,
    'case_id': caseId,
    'body_template': bodyTemplate,
    'body_arguments': bodyArguments,
  };

  static WormWiseNotification? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['title'] is! String ||
        value['body'] is! String) {
      return null;
    }
    final date = DateTime.tryParse(value['created_at']?.toString() ?? '');
    final kind = WormWiseNotificationKind.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    if (date == null || kind == null) {
      return null;
    }
    return WormWiseNotification(
      id: value['id'] as String,
      kind: kind,
      title: value['title'] as String,
      body: value['body'] as String,
      createdAt: date,
      assessmentId: value['assessment_id'] as String?,
      caseId: value['case_id'] as String?,
      bodyTemplate: value['body_template'] as String?,
      bodyArguments: value['body_arguments'] is Map
          ? Map<String, Object>.from(value['body_arguments'] as Map)
          : const {},
    );
  }
}

/// In-app reminders derived from local records and the current expert cases.
/// History and read IDs join account backups; delivery remains in-app.
class WormWiseNotificationService extends ChangeNotifier {
  WormWiseNotificationService(
    this._database,
    this._reviews, {
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    _reviews.addListener(_reviewsChanged);
    _restoreSubscription = AccountAppDataEvents.restores.stream.listen(
      (_) => unawaited(_initialize()),
    );
    _databaseSubscription = _database
        .customSelect(
          'SELECT 1 FROM assessments LIMIT 1',
          readsFrom: {
            _database.fields,
            _database.cropCycles,
            _database.assessments,
          },
        )
        .watch()
        .listen((_) {
          if (_ready) {
            unawaited(refresh());
          }
        });
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    unawaited(_initialize());
  }

  final AppDatabase _database;
  final ExpertReviewService _reviews;
  final FlutterSecureStorage _storage;
  Timer? _timer;
  StreamSubscription<void>? _restoreSubscription;
  StreamSubscription<dynamic>? _databaseSubscription;
  List<WormWiseNotification> _items = const [];
  Set<String> _readIds = {};
  int _followUpDays = 7;
  bool _ready = false;
  bool _refreshing = false;
  int _initializationGeneration = 0;

  List<WormWiseNotification> get items => _items;
  int get unreadCount =>
      _items.where((item) => !_readIds.contains(item.id)).length;
  int get followUpDays => _followUpDays;
  bool isRead(String id) => _readIds.contains(id);

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    _ready = false;
    var readIds = <String>{};
    var items = <WormWiseNotification>[];
    var followUpDays = 7;
    try {
      final days = int.tryParse(
        await _storage.read(key: 'notification_follow_up_days') ?? '7',
      );
      if ({7, 14, 30}.contains(days)) followUpDays = days!;
      final saved = await _storage.read(key: 'notification_read_ids');
      if (saved != null) {
        readIds = (jsonDecode(saved) as List).cast<String>().toSet();
      }
      final history = await _storage.read(key: 'notification_history_v1');
      if (history != null) {
        items = (jsonDecode(history) as List)
            .map(WormWiseNotification.fromJson)
            .whereType<WormWiseNotification>()
            .toList();
      }
    } catch (_) {
      // Reminders remain usable when secure storage is unavailable.
    }
    if (generation != _initializationGeneration) {
      return;
    }
    _readIds = readIds;
    _items = items;
    _followUpDays = followUpDays;
    _ready = true;
    notifyListeners();
    await refresh();
  }

  Future<void> setFollowUpDays(int days) async {
    if (!{7, 14, 30}.contains(days)) return;
    _followUpDays = days;
    notifyListeners();
    try {
      await _storage.write(key: 'notification_follow_up_days', value: '$days');
      AccountAppDataEvents.changed();
    } catch (_) {
      /* Local preference only. */
    }
    await refresh();
  }

  Future<void> markRead(String id) async {
    if (!_readIds.add(id)) return;
    notifyListeners();
    try {
      await _storage.write(
        key: 'notification_read_ids',
        value: jsonEncode(_readIds.toList()),
      );
      AccountAppDataEvents.changed();
    } catch (_) {
      /* In-memory read state remains. */
    }
  }

  void _reviewsChanged() {
    if (_ready) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!_ready || _refreshing) return;
    _refreshing = true;
    final generation = AccountAppDataEvents.viewGeneration;
    final initializationGeneration = _initializationGeneration;
    try {
      final now = DateTime.now();
      final fields = await _database.select(_database.fields).get();
      final cycles = await _database.select(_database.cropCycles).get();
      final assessments = await _database.select(_database.assessments).get();
      final fieldByCycle = {
        for (final cycle in cycles)
          if (cycle.deletedAt == null) cycle.id: cycle.fieldId,
      };
      final latest = <String, AssessmentRecord>{};
      for (final assessment in assessments) {
        if (assessment.deletedAt != null ||
            assessment.status != DatabaseCodes.completed ||
            assessment.completedAt == null) {
          continue;
        }
        final fieldId = fieldByCycle[assessment.cropCycleId];
        if (fieldId == null) continue;
        final previous = latest[fieldId];
        if (previous == null ||
            assessment.completedAt!.isAfter(previous.completedAt!)) {
          latest[fieldId] = assessment;
        }
      }
      final next = <WormWiseNotification>[];
      for (final field in fields) {
        if (field.deletedAt != null || field.isArchived) continue;
        final last = latest[field.id];
        final basis = last?.completedAt ?? field.createdAt;
        final days = now.difference(basis).inDays;
        final source = last?.id ?? 'none';
        if (days >= 14) {
          // One reminder at 14 days, then one per further 14-day interval.
          final interval = days ~/ 14;
          next.add(
            WormWiseNotification(
              id: 'inactive:${field.id}:$source:$interval',
              kind: WormWiseNotificationKind.inactiveField,
              title: 'No recent assessment',
              bodyTemplate: last == null
                  ? "It's been {days} days since you added {field}. Consider assessing it."
                  : "It's been {days} days since you assessed {field}. Consider checking it again.",
              bodyArguments: {'days': interval * 14, 'field': field.name},
              body: last == null
                  ? "It's been ${interval * 14} days since you added ${field.name}. Consider assessing it."
                  : "It's been ${interval * 14} days since you assessed ${field.name}. Consider checking it again.",
              createdAt: basis.add(Duration(days: interval * 14)),
            ),
          );
        }
        if (last != null &&
            days >= _followUpDays &&
            days < _followUpDays + 14) {
          next.add(
            WormWiseNotification(
              id: 'followup:${field.id}:${last.id}:$_followUpDays',
              kind: WormWiseNotificationKind.followUp,
              title: 'Follow up on your assessment',
              bodyTemplate:
                  'Consider revisiting {field} after your recent assessment.',
              bodyArguments: {'field': field.name},
              body:
                  'Consider revisiting ${field.name} after your recent assessment.',
              createdAt: basis.add(Duration(days: _followUpDays)),
              assessmentId: last.id,
            ),
          );
        }
      }
      for (final review in _reviews.cases) {
        final severity = review.severitySummary;
        if (severity != null) {
          next.add(
            WormWiseNotification(
              id: 'severity:${review.id}:${severity.finalizedAt.toUtc().toIso8601String()}',
              kind: WormWiseNotificationKind.severityReady,
              title: 'Severity overview is ready',
              bodyTemplate:
                  'An expert finalized the severity overview for {field}.',
              bodyArguments: {'field': review.fieldName},
              body:
                  'An expert finalized the severity overview for ${review.fieldName}.',
              createdAt: severity.finalizedAt,
              caseId: review.id,
            ),
          );
        }
        if (review.status != 'needs_information' &&
            review.status != 'advice_sent') {
          continue;
        }
        final kind = review.status == 'needs_information'
            ? WormWiseNotificationKind.needsInformation
            : WormWiseNotificationKind.adviceReady;
        final latestExpertMessage = review.messages
            .where(
              (message) =>
                  message.senderId != _reviews.currentUserId &&
                  message.severityCaseId == null,
            )
            .lastOrNull;
        final timestamp = latestExpertMessage?.createdAt ?? review.createdAt;
        next.add(
          WormWiseNotification(
            id: 'expert:${review.id}:${review.status}:${timestamp.toUtc().toIso8601String()}',
            kind: kind,
            title: kind == WormWiseNotificationKind.needsInformation
                ? 'Expert needs more information'
                : 'Expert advice is ready',
            bodyTemplate: kind == WormWiseNotificationKind.needsInformation
                ? 'An expert needs more information about {field}.'
                : 'Advice is ready for {field}.',
            bodyArguments: {'field': review.fieldName},
            body: kind == WormWiseNotificationKind.needsInformation
                ? 'An expert needs more information about ${review.fieldName}.'
                : 'Advice is ready for ${review.fieldName}.',
            createdAt: timestamp,
            caseId: review.id,
          ),
        );
      }
      if (generation != AccountAppDataEvents.viewGeneration ||
          initializationGeneration != _initializationGeneration) {
        return;
      }
      final history = {
        for (final item in _items) item.id: item,
        for (final item in next) item.id: item,
      }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _items = List.unmodifiable(history);
      final encoded = jsonEncode(_items.map((item) => item.toJson()).toList());
      if (encoded != await _storage.read(key: 'notification_history_v1') &&
          generation == AccountAppDataEvents.viewGeneration) {
        await _storage.write(key: 'notification_history_v1', value: encoded);
        AccountAppDataEvents.changed();
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Could not refresh Cropwise notifications: $error');
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _initializationGeneration++;
    _timer?.cancel();
    unawaited(_restoreSubscription?.cancel());
    unawaited(_databaseSubscription?.cancel());
    _reviews.removeListener(_reviewsChanged);
    super.dispose();
  }
}
