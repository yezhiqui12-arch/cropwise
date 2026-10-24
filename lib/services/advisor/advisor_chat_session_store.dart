import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'advisor_conversation_store.dart';
import '../cloud/account_app_data_service.dart';

class AdvisorChatSession {
  const AdvisorChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AdvisorStoredMessage> messages;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  static AdvisorChatSession? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final title = value['title'];
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    final rawMessages = value['messages'];
    if (id is! String ||
        title is! String ||
        updatedAt == null ||
        rawMessages is! List) {
      return null;
    }
    final messages = rawMessages
        .map(AdvisorStoredMessage.fromJson)
        .whereType<AdvisorStoredMessage>()
        .toList();
    if (messages.isEmpty) return null;
    return AdvisorChatSession(
      id: id,
      title: title,
      updatedAt: updatedAt,
      messages: messages,
    );
  }
}

class AdvisorChatSessionStore {
  const AdvisorChatSessionStore({
    this.directoryProvider = getApplicationDocumentsDirectory,
  });

  final Future<Directory> Function() directoryProvider;

  Future<List<AdvisorChatSession>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final sessions = decoded
          .map(AdvisorChatSession.fromJson)
          .whereType<AdvisorChatSession>()
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(AdvisorChatSession session) async {
    final bounded = AdvisorChatSession(
      id: session.id,
      title: session.title,
      updatedAt: session.updatedAt,
      messages: session.messages,
    );
    final sessions = [
      bounded,
      ...await load().then(
        (existing) => existing.where((item) => item.id != session.id),
      ),
    ];
    await _write(sessions);
  }

  Future<AdvisorChatSession?> take(String id) async {
    final sessions = await load();
    final matches = sessions.where((session) => session.id == id);
    if (matches.isEmpty) return null;
    await _write(sessions.where((session) => session.id != id).toList());
    return matches.first;
  }

  Future<void> _write(List<AdvisorChatSession> sessions) async {
    final generation = AccountAppDataEvents.viewGeneration;
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    if (generation != AccountAppDataEvents.viewGeneration) {
      return;
    }
    await temporary.writeAsString(
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
      flush: true,
    );
    if (generation != AccountAppDataEvents.viewGeneration) {
      await temporary.delete();
      return;
    }
    await temporary.rename(file.path);
    AccountAppDataEvents.changed();
  }

  Future<File> _file() async {
    final directory = await directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}wormwise_advisor_sessions_v1.json',
    );
  }
}
