import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'advisor_knowledge_service.dart';
import 'advisor_app_action.dart';
import '../computer_vision/faw_computer_vision_service.dart';
import '../cloud/account_app_data_service.dart';

class AdvisorStoredMessage {
  const AdvisorStoredMessage({
    required this.id,
    required this.role,
    required this.text,
    this.answer,
    this.imagePath,
    this.imagePaths = const [],
    this.detectionBoxes = const [],
    this.modelFindings,
    this.replyToMessageId,
    this.replyPreview,
  });

  final String id;
  final String role;
  final String text;
  final AdvisorAnswer? answer;
  final String? imagePath;
  final List<String> imagePaths;
  final List<ModelDetectionBox> detectionBoxes;
  final String? modelFindings;
  final String? replyToMessageId;
  final String? replyPreview;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    if (imagePath != null) 'imagePath': imagePath,
    if (imagePaths.isNotEmpty) 'imagePaths': imagePaths,
    if (detectionBoxes.isNotEmpty)
      'detectionBoxes': detectionBoxes.map((box) => box.toJson()).toList(),
    if (modelFindings != null) 'modelFindings': modelFindings,
    if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    if (replyPreview != null) 'replyPreview': replyPreview,
    if (answer != null)
      'answer': {
        'topicId': answer!.topicId,
        'title': answer!.title,
        'summary': answer!.summary,
        'details': answer!.details,
        'nextAction': answer!.nextAction,
        'suggestedActions': answer!.suggestedActions,
        'visualArticleIds': answer!.visualArticleIds,
        'supportingPassages': answer!.supportingPassages
            .map((p) => p.toJson())
            .toList(),
        'appActions': answer!.appActions
            .map((action) => action.toJson())
            .toList(),
        'source': {
          'label': answer!.source.label,
          'reference': answer!.source.reference,
          'version': answer!.source.version,
        },
      },
  };

  static AdvisorStoredMessage? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final role = value['role'];
    final text = value['text'];
    if (id is! String || role is! String || text is! String) return null;
    final rawAnswer = value['answer'];
    final rawBoxes = value['detectionBoxes'];
    final rawImagePaths = value['imagePaths'];
    AdvisorAnswer? answer;
    if (rawAnswer is Map<String, dynamic>) {
      final rawSource = rawAnswer['source'];
      final details = rawAnswer['details'];
      final suggestedActions = rawAnswer['suggestedActions'];
      final rawAppActions = rawAnswer['appActions'];
      if (rawSource is Map<String, dynamic> &&
          rawAnswer['topicId'] is String &&
          rawAnswer['title'] is String &&
          rawAnswer['summary'] is String &&
          rawSource['label'] is String &&
          rawSource['reference'] is String &&
          rawSource['version'] is String) {
        answer = AdvisorAnswer(
          topicId: rawAnswer['topicId'] as String,
          title: rawAnswer['title'] as String,
          summary: rawAnswer['summary'] as String,
          details: details is List
              ? details.whereType<String>().toList(growable: false)
              : const [],
          nextAction: rawAnswer['nextAction'] as String?,
          visualArticleIds:
              (rawAnswer['visualArticleIds'] is List
                      ? rawAnswer['visualArticleIds'] as List
                      : const [])
                  .whereType<String>()
                  .toSet()
                  .take(2)
                  .toList(),
          supportingPassages:
              (rawAnswer['supportingPassages'] is List
                      ? rawAnswer['supportingPassages'] as List
                      : const [])
                  .map(AdvisorSupportingPassage.fromJson)
                  .whereType<AdvisorSupportingPassage>()
                  .toList(),
          suggestedActions: suggestedActions is List
              ? suggestedActions.whereType<String>().toList(growable: false)
              : const [],
          appActions: rawAppActions is List
              ? rawAppActions
                    .map(AdvisorAppAction.fromJson)
                    .whereType<AdvisorAppAction>()
                    .toList(growable: false)
              : const [],
          source: AdvisorKnowledgeSource(
            label: rawSource['label'] as String,
            reference: rawSource['reference'] as String,
            version: rawSource['version'] as String,
          ),
        );
      }
    }
    final detectionBoxes = rawBoxes is List
        ? rawBoxes
              .whereType<Map<String, dynamic>>()
              .map(_detectionBoxFromJson)
              .whereType<ModelDetectionBox>()
              .toList(growable: false)
        : const <ModelDetectionBox>[];
    return AdvisorStoredMessage(
      id: id,
      role: role,
      text: text,
      answer: answer,
      imagePath: value['imagePath'] as String?,
      imagePaths: rawImagePaths is List
          ? rawImagePaths.whereType<String>().toList(growable: false)
          : const [],
      detectionBoxes: detectionBoxes,
      modelFindings: value['modelFindings'] as String?,
      replyToMessageId: value['replyToMessageId'] as String?,
      replyPreview: value['replyPreview'] as String?,
    );
  }
}

ModelDetectionBox? _detectionBoxFromJson(Map<String, dynamic> json) {
  final sourcePath = json['sourcePath'];
  final classId = json['classId'];
  final label = json['label'];
  final confidence = json['confidence'];
  final left = json['left'];
  final top = json['top'];
  final right = json['right'];
  final bottom = json['bottom'];
  final imageWidth = json['imageWidth'];
  final imageHeight = json['imageHeight'];
  if (sourcePath is! String ||
      classId is! int ||
      label is! String ||
      confidence is! num ||
      left is! num ||
      top is! num ||
      right is! num ||
      bottom is! num ||
      imageWidth is! int ||
      imageHeight is! int) {
    return null;
  }
  return ModelDetectionBox(
    sourcePath: sourcePath,
    classId: classId,
    label: label,
    confidence: confidence.toDouble(),
    left: left.toDouble(),
    top: top.toDouble(),
    right: right.toDouble(),
    bottom: bottom.toDouble(),
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
}

abstract interface class AdvisorConversationStore {
  Future<List<AdvisorStoredMessage>> load();
  Future<void> save(List<AdvisorStoredMessage> messages);
  Future<void> clear();
}

typedef AdvisorHistoryDirectoryProvider = Future<Directory> Function();

class FileAdvisorConversationStore implements AdvisorConversationStore {
  const FileAdvisorConversationStore({
    this.directoryProvider = getApplicationDocumentsDirectory,
  });

  final AdvisorHistoryDirectoryProvider directoryProvider;

  @override
  Future<List<AdvisorStoredMessage>> load() async {
    final file = await _historyFile();
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const [];
    return decoded
        .map(AdvisorStoredMessage.fromJson)
        .whereType<AdvisorStoredMessage>()
        .toList(growable: false);
  }

  @override
  Future<void> save(List<AdvisorStoredMessage> messages) async {
    final generation = AccountAppDataEvents.viewGeneration;
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    if (generation != AccountAppDataEvents.viewGeneration) {
      return;
    }
    await temporary.writeAsString(
      jsonEncode(messages.map((message) => message.toJson()).toList()),
      flush: true,
    );
    if (generation != AccountAppDataEvents.viewGeneration) {
      await temporary.delete();
      return;
    }
    await temporary.rename(file.path);
    AccountAppDataEvents.changed();
  }

  @override
  Future<void> clear() async {
    final generation = AccountAppDataEvents.viewGeneration;
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    if (generation != AccountAppDataEvents.viewGeneration) {
      return;
    }
    await file.writeAsString('[]', flush: true);
    AccountAppDataEvents.changed();
  }

  Future<File> _historyFile() async {
    final directory = await directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}wormwise_guide_history_v1.json',
    );
  }
}
