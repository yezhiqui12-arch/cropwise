import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Changes outside Drift still need automatic account backup. Restoration is
/// a separate event so consumers reload without scheduling an endless backup.
abstract final class AccountAppDataEvents {
  static final changes = StreamController<void>.broadcast(sync: true);
  static final restores = StreamController<void>.broadcast(sync: true);
  static int viewGeneration = 0;
  static final pendingWriters = <Future<void> Function()>{};
  static Future<void> flushPendingWrites() async {
    for (final writer in pendingWriters.toList()) {
      await writer();
    }
  }

  static void changed() => changes.add(null);
  static void restored() => restores.add(null);
}

/// Only these app preferences can enter a private account snapshot. Tokens,
/// passwords, authentication secrets and identity handoff markers are intentionally excluded.
class AccountAppDataService {
  AccountAppDataService({
    FlutterSecureStorage? storage,
    Future<Directory> Function()? directoryProvider,
  }) : storage = storage ?? const FlutterSecureStorage(),
       directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final FlutterSecureStorage storage;
  final Future<Directory> Function() directoryProvider;
  final Set<String> _uploadedAttachments = {};
  Map<String, String> _imageAliases = {};
  static const _imageAliasesKey = 'wormwise_advisor_photo_aliases_v1';
  String? lastMediaError;
  bool _freshMediaVerification = false;
  void requireFreshMediaVerification() {
    _freshMediaVerification = true;
    _uploadedAttachments.clear();
  }

  static final _managedImage = RegExp(
    r'^advisor-media/([a-f0-9]{64})\.(jpg|png|webp|bin)$',
  );
  static const _registryKey = 'wormwise_account_app_data_registry_v1';
  static const _pendingKey = 'wormwise_account_app_data_pending_v1';
  static const historyFile = 'wormwise_guide_history_v1.json';
  static const sessionsFile = 'wormwise_advisor_sessions_v1.json';
  static const preferenceKeys = {
    'notification_follow_up_days',
    'notification_read_ids',
    'notification_history_v1',
    'wormwise_gemini_enabled',
    'wormwise_gemini_share_field',
    'wormwise_gemini_share_location',
    'wormwise_gemini_share_photos',
    'wormwise_gemini_show_sources',
    'experimental_faw_highlighting_v1',
  };

  Future<Map<String, dynamic>> _registry() async {
    final raw = await storage.read(key: _registryKey);
    if (raw == null) return {};
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid account app data registry.');
    }
    return value;
  }

  Future<File> _file(String name) async =>
      File('${(await directoryProvider()).path}${Platform.pathSeparator}$name');

  Future<Object?> _readFile(String name) async {
    final file = await _file(name);
    return await file.exists() ? jsonDecode(await file.readAsString()) : null;
  }

  Future<void> _writeFile(String name, Object? value) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.account.tmp');
    await temporary.writeAsString(jsonEncode(value ?? []), flush: true);
    await temporary.rename(file.path);
  }

  String _hash(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  Future<Object?> _portable(Object? value, {String? key}) async {
    if (value is Map) {
      return {
        for (final item in value.entries)
          item.key.toString(): await _portable(
            item.value,
            key: item.key.toString(),
          ),
      };
    }
    if (value is List) {
      return [for (final item in value) await _portable(item, key: key)];
    }
    if (value is! String ||
        !{'imagePath', 'imagePaths', 'sourcePath'}.contains(key)) {
      return value;
    }
    if (_managedImage.hasMatch(value)) {
      return value;
    }
    final normalized = value.replaceAll('\\', '/');
    final suffix = normalized.lastIndexOf('/advisor-media/');
    if (suffix >= 0 &&
        _managedImage.hasMatch(normalized.substring(suffix + 1))) {
      return normalized.substring(suffix + 1);
    }
    final original = File(value);
    if (!await original.exists()) {
      return _imageAliases[value] ?? value;
    }
    final bytes = await original.readAsBytes();
    final checksum = sha256.convert(bytes).toString();
    final extension = normalized.split('.').last.toLowerCase();
    final relative =
        'advisor-media/$checksum.${{'jpg', 'png', 'webp'}.contains(extension) ? extension : 'bin'}';
    final target = await _file(relative);
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    }
    _imageAliases[value] = relative;
    return relative;
  }

  Future<Object?> _localPaths(Object? value, {String? key}) async {
    if (value is Map) {
      return {
        for (final item in value.entries)
          item.key.toString(): await _localPaths(
            item.value,
            key: item.key.toString(),
          ),
      };
    }
    if (value is List) {
      return [for (final item in value) await _localPaths(item, key: key)];
    }
    if (value is String &&
        {'imagePath', 'imagePaths', 'sourcePath'}.contains(key) &&
        _managedImage.hasMatch(value)) {
      return (await _file(value)).path;
    }
    return value;
  }

  Set<String> _attachments(Map<String, dynamic> entries) {
    final paths = <String>{};
    void collect(Object? value, [String? key]) {
      if (value is Map) {
        for (final item in value.entries) {
          collect(item.value, item.key.toString());
        }
      } else if (value is List) {
        for (final item in value) {
          collect(item, key);
        }
      } else if (value is String &&
          {'imagePath', 'imagePaths', 'sourcePath'}.contains(key) &&
          _managedImage.hasMatch(value)) {
        paths.add(value);
      }
    }

    for (final entry in entries.values) {
      collect((entry as Map)['value']);
    }
    return paths;
  }

  Future<bool> mediaComplete(String ownerId) async => _attachments(
    await _registry(),
  ).every((path) => _uploadedAttachments.contains('$ownerId/$path'));

  /// The durable registry is also the photo retry manifest. No photo download
  /// or upload is required before conversations and settings become available.
  Future<bool> synchronizeMedia(
    String ownerId,
    SupabaseClient client,
    String bucket, {
    required bool Function() isCurrentAccount,
  }) async {
    lastMediaError = null;
    final remote = client.storage.from(bucket);
    var complete = true;
    var downloaded = false;
    for (final path in _attachments(await _registry())) {
      if (!isCurrentAccount()) {
        return false;
      }
      try {
        final file = await _file(path);
        final checksum = _managedImage.firstMatch(path)!.group(1)!;
        var valid =
            await file.exists() &&
            sha256.convert(await file.readAsBytes()).toString() == checksum;
        if (!valid) {
          final bytes = await remote.download('$ownerId/$path');
          if (sha256.convert(bytes).toString() != checksum) {
            throw const FormatException(
              'Advisor photo checksum did not match.',
            );
          }
          if (!isCurrentAccount()) {
            return false;
          }
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.restore.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (!isCurrentAccount()) {
            await temporary.delete();
            return false;
          }
          await temporary.rename(file.path);
          valid = true;
          downloaded = true;
        }
        if (valid && !_uploadedAttachments.contains('$ownerId/$path')) {
          if (_freshMediaVerification) {
            try {
              final existing = await remote.download('$ownerId/$path');
              if (!isCurrentAccount()) {
                return false;
              }
              if (sha256.convert(existing).toString() == checksum) {
                _uploadedAttachments.add('$ownerId/$path');
                continue;
              }
            } catch (_) {
              // Repair missing/corrupt cloud copies from verified local bytes.
            }
          }
          if (!isCurrentAccount()) {
            return false;
          }
          await remote.uploadBinary(
            '$ownerId/$path',
            await file.readAsBytes(),
            fileOptions: const FileOptions(upsert: true),
          );
          if (!isCurrentAccount()) {
            return false;
          }
          final readBack = await remote.download('$ownerId/$path');
          if (sha256.convert(readBack).toString() != checksum) {
            throw const FormatException(
              'Advisor photo backup verification failed.',
            );
          }
          if (!isCurrentAccount()) {
            return false;
          }
          _uploadedAttachments.add('$ownerId/$path');
        }
      } catch (error) {
        complete = false;
        lastMediaError =
            'Some Advisor photos are still waiting to restore: $error';
      }
    }
    if (downloaded && isCurrentAccount()) {
      AccountAppDataEvents.restored();
    }
    return complete;
  }

  /// Capture changes with per-item timestamps, including explicit deletions.
  Future<Map<String, dynamic>> capture() async {
    await AccountAppDataEvents.flushPendingWrites();
    final aliases = await storage.read(key: _imageAliasesKey);
    _imageAliases = aliases == null
        ? {}
        : Map<String, String>.from(jsonDecode(aliases) as Map);
    final pending = await storage.read(key: _pendingKey);
    if (pending != null) {
      await _materialize(Map<String, dynamic>.from(jsonDecode(pending) as Map));
    }
    final registry = await _registry();
    final values = <String, Object?>{};
    for (final key in preferenceKeys) {
      values['preference:$key'] = await storage.read(key: key);
    }
    values['advisor:active'] = await _readFile(historyFile);
    final sessions = await _readFile(sessionsFile);
    if (sessions != null && sessions is! List) {
      throw const FormatException('Invalid saved Advisor conversations.');
    }
    if (sessions is List) {
      for (final session in sessions) {
        if (session is! Map || session['id'] is! String) {
          throw const FormatException('Invalid Advisor session.');
        }
        values['session:${session['id']}'] = session;
      }
    }
    for (final key in registry.keys.where(
      (key) => key.startsWith('session:'),
    )) {
      values.putIfAbsent(key, () => null);
    }
    for (final item in values.entries) {
      final portable = await _portable(item.value);
      final previous = registry[item.key];
      if (previous is Map && _hash(previous['value']) == _hash(portable)) {
        continue;
      }
      if (previous == null &&
          (item.value == null ||
              item.value == '[]' ||
              (item.value is List && (item.value as List).isEmpty))) {
        continue;
      }
      final oldTime = previous is Map ? previous['updated_at'] as int? ?? 0 : 0;
      registry[item.key] = {
        'updated_at': DateTime.now().toUtc().microsecondsSinceEpoch > oldTime
            ? DateTime.now().toUtc().microsecondsSinceEpoch
            : oldTime + 1,
        'value': portable,
      };
    }
    await storage.write(
      key: _imageAliasesKey,
      value: jsonEncode(_imageAliases),
    );
    await storage.write(key: _registryKey, value: jsonEncode(registry));
    return {'version': 1, 'entries': registry};
  }

  bool hasData(Object? value) =>
      value is Map &&
      value['entries'] is Map &&
      (value['entries'] as Map).values.any(
        (entry) => entry is Map && entry['value'] != null,
      );

  Map<String, dynamic> validate(Object? value) {
    if (value == null) {
      return {};
    }
    if (value is! Map || value['version'] != 1 || value['entries'] is! Map) {
      throw const FormatException('Invalid account app data backup.');
    }
    final entries = <String, dynamic>{};
    for (final item in (value['entries'] as Map).entries) {
      final key = item.key;
      final entry = item.value;
      if (key is! String ||
          entry is! Map ||
          entry['updated_at'] is! int ||
          !(key == 'advisor:active' ||
              key.startsWith('session:') ||
              (key.startsWith('preference:') &&
                  preferenceKeys.contains(key.substring(11))))) {
        throw const FormatException('Invalid account app data entry.');
      }
      final data = entry['value'];
      if (data != null &&
          ((key.startsWith('preference:') && data is! String) ||
              (key == 'advisor:active' && data is! List) ||
              (key.startsWith('session:') &&
                  (data is! Map || data['id'] != key.substring(8))))) {
        throw const FormatException('Invalid account app data value.');
      }
      if (data != null &&
          key.startsWith('session:') &&
          (data['title'] is! String ||
              data['messages'] is! List ||
              DateTime.tryParse(data['updatedAt']?.toString() ?? '') == null)) {
        throw const FormatException('Invalid Advisor session content.');
      }
      final messages = key == 'advisor:active'
          ? data
          : key.startsWith('session:') && data is Map
          ? data['messages']
          : null;
      if (messages is List &&
          messages.any(
            (message) =>
                message is! Map ||
                message['id'] is! String ||
                message['role'] is! String ||
                message['text'] is! String,
          )) {
        throw const FormatException('Invalid Advisor message content.');
      }
      entries[key] = Map<String, dynamic>.from(entry);
    }
    return entries;
  }

  Future<void> restore(Object? value, {bool replace = false}) async {
    final incoming = validate(value);
    final local = replace
        ? <String, dynamic>{}
        : Map<String, dynamic>.from((await capture())['entries'] as Map);
    for (final item in incoming.entries) {
      final old = local[item.key];
      final next = item.value as Map;
      // Concurrent phones have separate active chats. Keep the losing chat in
      // saved conversations instead of silently replacing its only copy.
      if (item.key == 'advisor:active' &&
          old is Map &&
          old['value'] is List &&
          next['value'] is List &&
          (old['value'] as List).isNotEmpty &&
          (next['value'] as List).isNotEmpty &&
          _hash(old['value']) != _hash(next['value'])) {
        final losing = (next['updated_at'] as int) > (old['updated_at'] as int)
            ? old
            : next;
        final messages = losing['value'] as List;
        if (messages.isNotEmpty) {
          final id = 'recovered-active-${_hash(messages)}';
          local.putIfAbsent(
            'session:$id',
            () => {
              'updated_at': losing['updated_at'],
              'value': {
                'id': id,
                'title': 'Recovered conversation',
                'updatedAt': DateTime.fromMicrosecondsSinceEpoch(
                  losing['updated_at'] as int,
                  isUtc: true,
                ).toIso8601String(),
                'messages': messages,
              },
            },
          );
        }
      }
      if (old is Map &&
          {
            'preference:notification_read_ids',
            'preference:notification_history_v1',
          }.contains(item.key) &&
          old['value'] is String &&
          next['value'] is String) {
        final first = jsonDecode(old['value'] as String);
        final second = jsonDecode(next['value'] as String);
        if (first is! List || second is! List) {
          throw const FormatException('Invalid notification history.');
        }
        final merged = <String, Object?>{};
        for (final record in [...first, ...second]) {
          final id = record is Map ? record['id'] : record;
          if (id is! String) {
            throw const FormatException('Invalid notification record.');
          }
          merged[id] = record;
        }
        local[item.key] = {
          'updated_at': (old['updated_at'] as int) > (next['updated_at'] as int)
              ? old['updated_at']
              : next['updated_at'],
          'value': jsonEncode(merged.values.toList()),
        };
        continue;
      }
      if (old == null ||
          (next['updated_at'] as int) > (old['updated_at'] as int)) {
        local[item.key] = next;
      }
    }
    if (replace) {
      AccountAppDataEvents.viewGeneration++;
    }
    await storage.write(key: _pendingKey, value: jsonEncode(local));
    await _materialize(local);
    AccountAppDataEvents.restored();
  }

  Future<void> _materialize(Map<String, dynamic> local) async {
    for (final key in preferenceKeys) {
      final entry = local['preference:$key'];
      final content = entry is Map ? entry['value'] as String? : null;
      if (content == null) {
        await storage.delete(key: key);
      } else {
        await storage.write(key: key, value: content);
      }
    }
    await _writeFile(
      historyFile,
      await _localPaths((local['advisor:active'] as Map?)?['value']),
    );
    final sessions = [
      for (final item in local.entries)
        if (item.key.startsWith('session:') &&
            (item.value as Map)['value'] != null)
          (item.value as Map)['value'],
    ];
    await _writeFile(sessionsFile, await _localPaths(sessions));
    await storage.write(key: _registryKey, value: jsonEncode(local));
    await storage.delete(key: _pendingKey);
  }
}
