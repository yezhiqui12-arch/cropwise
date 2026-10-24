import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/database_codes.dart';
import 'package:wormwise/providers/advisor_controller.dart';
import 'package:wormwise/services/advisor/advisor_conversation_store.dart';
import 'package:wormwise/services/advisor/advisor_image_analysis_service.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';
import 'package:wormwise/services/advisor/advisor_open_chat_service.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  test(
    'clearing during restoration prevents stale history and request',
    () async {
      final store = _DelayedConversationStore();
      final service = _RecordingOpenChatService();
      final controller = AdvisorController(
        openChatService: service,
        conversationStore: store,
      );
      addTearDown(controller.dispose);
      final pending = controller.ask('Follow up on the old conversation');
      controller.clear();
      store.loaded.complete(const [
        AdvisorStoredMessage(id: 'old-q', role: 'farmer', text: 'Old question'),
        AdvisorStoredMessage(
          id: 'old-a',
          role: 'guide',
          text: 'Old answer',
          answer: _openChatAnswer,
        ),
      ]);
      await pending;
      expect(controller.messages, isEmpty);
      expect(service.requests, isEmpty);
      await controller.ask('Fresh question');
      expect(service.requests.single.history, isEmpty);
    },
  );

  test(
    'retains more than four exchanges and bounds the context window',
    () async {
      final service = _RecordingOpenChatService();
      final controller = AdvisorController(openChatService: service);
      addTearDown(controller.dispose);
      for (var i = 0; i < 30; i++) {
        await controller.ask('Question $i');
      }
      final history = service.requests.last.history;
      expect(history, hasLength(48));
      expect(history.first.text, 'Question 5');
      expect(history[history.length - 2].text, 'Question 28');
      expect(history.map((turn) => turn.text), isNot(contains('Question 29')));
      expect(
        history.fold<int>(0, (sum, turn) => sum + turn.text.length),
        lessThanOrEqualTo(24000),
      );
    },
  );

  test('oversized messages are bounded without splitting exchanges', () async {
    final service = _RecordingOpenChatService();
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);
    for (var i = 0; i < 12; i++) {
      await controller.ask(
        'Long question $i ${List.filled(10000, "x").join()}',
      );
    }
    final history = service.requests.last.history;
    expect(history.length.isEven, isTrue);
    expect(history.first.role, AdvisorOpenChatRole.farmer);
    expect(history.last.role, AdvisorOpenChatRole.advisor);
    expect(history.every((turn) => turn.text.length <= 3000), isTrue);
    expect(
      history.fold<int>(0, (sum, turn) => sum + turn.text.length),
      lessThanOrEqualTo(24000),
    );
    expect(history.first.text, contains('[Earlier message truncated]'));
  });

  test(
    'first request awaits restoration and includes photo findings',
    () async {
      final store = _MemoryConversationStore(
        messages: const [
          AdvisorStoredMessage(
            id: 'p',
            role: 'farmer',
            text: 'Explain my photo',
          ),
          AdvisorStoredMessage(
            id: 'a',
            role: 'guide',
            text: 'Earlier answer',
            answer: _openChatAnswer,
            modelFindings: 'Larva confidence 80%',
          ),
        ],
      );
      final service = _RecordingOpenChatService();
      final controller = AdvisorController(
        openChatService: service,
        conversationStore: store,
      );
      addTearDown(controller.dispose);
      await controller.ask('What does that confidence mean?');
      expect(service.requests.single.history, hasLength(2));
      expect(
        service.requests.single.history.last.text,
        contains('Larva confidence 80%'),
      );
      controller.clear();
      await controller.ask('New conversation');
      expect(service.requests.last.history, isEmpty);
    },
  );

  test(
    'retry reuses identical context and does not duplicate failed turns',
    () async {
      final service = _RecordingOpenChatService(failuresBeforeSuccess: 1);
      final controller = AdvisorController(openChatService: service);
      addTearDown(controller.dispose);
      await controller.ask('What does frass mean?', allowOpenChat: false);
      await controller.ask('Explain that again');
      await controller.retryOpenChat();
      expect(service.requests[1].history, same(service.requests[0].history));
      expect(controller.messages, hasLength(4));
    },
  );

  test('offline safety-critical treatment questions stay local', () async {
    final service = _RecordingOpenChatService();
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);

    await controller.ask(
      'Which pesticide treatment should I use on this maize plant?',
      allowOpenChat: false,
    );

    expect(service.requests, isEmpty);
    expect(controller.messages, hasLength(2));
    expect(controller.messages.last.answer!.topicId, 'treatment_safety');
  });

  test('an unmatched question uses the optional open chat boundary', () async {
    final service = _RecordingOpenChatService();
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);

    await controller.ask('Why do maize leaves curl at noon?');

    expect(service.requests, hasLength(1));
    expect(
      service.requests.single.question,
      'Why do maize leaves curl at noon?',
    );
    expect(service.requests.single.history, isEmpty);
    expect(controller.replyState, AdvisorReplyState.idle);
    expect(controller.messages.last.answer!.topicId, 'open_chat_test');
  });

  test(
    'open chat history includes earlier local field-guide exchanges',
    () async {
      final service = _RecordingOpenChatService();
      final controller = AdvisorController(openChatService: service);
      addTearDown(controller.dispose);

      await controller.ask('What does frass mean?', allowOpenChat: false);
      await controller.ask('Why do maize leaves curl at noon?');
      await controller.ask('Does the curling change later in the day?');

      expect(service.requests, hasLength(2));
      expect(service.requests.first.history, hasLength(2));
      expect(service.requests.last.history, hasLength(4));
      expect(
        service.requests.last.history.map((turn) => turn.text),
        containsAll([
          'Why do maize leaves curl at noon?',
          _openChatAnswer.summary,
        ]),
      );
      expect(
        service.requests.last.history.map((turn) => turn.text).join(' '),
        contains('What does frass mean?'),
      );
    },
  );

  test('failed open chat can retry without duplicating the question', () async {
    final service = _RecordingOpenChatService(failuresBeforeSuccess: 1);
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);

    await controller.ask('Tell me something outside the built-in guide.');

    expect(controller.replyState, AdvisorReplyState.error);
    expect(controller.canRetryOpenChat, isTrue);
    expect(controller.messages, hasLength(1));

    await controller.retryOpenChat();

    expect(service.requests, hasLength(2));
    expect(controller.replyState, AdvisorReplyState.idle);
    expect(controller.messages, hasLength(2));
  });

  test(
    'online request failure is shown instead of disguised as offline',
    () async {
      final controller = AdvisorController(
        openChatService: const _OfflineOpenChatService(),
      );
      addTearDown(controller.dispose);

      await controller.ask('Tell me something outside the built-in guide.');

      expect(controller.replyState, AdvisorReplyState.error);
      expect(controller.canRetryOpenChat, isTrue);
      expect(controller.messages, hasLength(1));
    },
  );

  test(
    'online photo without a query asks a refined follow-up from model findings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wormwise-guide-photo-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = File('${directory.path}${Platform.pathSeparator}maize.jpg');
      await image.writeAsBytes([1, 2, 3]);
      final openChat = _RecordingOpenChatService();
      final controller = AdvisorController(
        openChatService: openChat,
        imageAnalysisService: AdvisorImageAnalysisService(_BoxImageModel()),
      );
      addTearDown(controller.dispose);

      await controller.askGeminiWithImage('', image);

      expect(openChat.requests, hasLength(1));
      expect(openChat.requests.single.question, isEmpty);
      expect(openChat.requests.single.modelFindings, contains('Larval damage'));
      expect(openChat.requests.single.photoFollowUpOnly, isTrue);
      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.text, isEmpty);
      expect(controller.messages.first.imagePath, image.path);
      expect(controller.messages.last.imagePath, image.path);
      expect(controller.messages.last.detectionBoxes, hasLength(1));
      expect(controller.messages.last.modelFindings, contains('Larval damage'));

      await controller.askPhotoSuggestedAction(
        controller.messages.last,
        'Explain the detected damage',
      );

      expect(openChat.requests, hasLength(2));
      expect(openChat.requests.last.question, 'Explain the detected damage');
      expect(openChat.requests.last.photoFollowUpOnly, isFalse);
      expect(openChat.requests.last.modelFindings, contains('Larval damage'));
    },
  );

  test(
    'multiple photos are sent as one message with combined findings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wormwise-guide-multi-photo-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = File('${directory.path}${Platform.pathSeparator}first.jpg');
      final second = File(
        '${directory.path}${Platform.pathSeparator}second.jpg',
      );
      await first.writeAsBytes([1]);
      await second.writeAsBytes([2]);
      final openChat = _RecordingOpenChatService();
      final controller = AdvisorController(
        openChatService: openChat,
        imageAnalysisService: AdvisorImageAnalysisService(_BoxImageModel()),
      );
      addTearDown(controller.dispose);

      await controller.askGeminiWithImages('', [first, second]);

      expect(controller.messages.first.allImagePaths, [
        first.path,
        second.path,
      ]);
      expect(controller.messages.last.allImagePaths, [first.path, second.path]);
      expect(openChat.requests.single.modelFindings, contains('Photo 1:'));
      expect(openChat.requests.single.modelFindings, contains('Photo 2:'));
    },
  );

  test('photo model failure still returns a guide reply', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wormwise-guide-failed-photo-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}${Platform.pathSeparator}maize.jpg');
    await image.writeAsBytes([1, 2, 3]);
    final controller = AdvisorController(
      imageAnalysisService: AdvisorImageAnalysisService(_FailingImageModel()),
    );
    addTearDown(controller.dispose);

    await controller.analyzeImageOnDevice(image, question: 'Check this photo');

    expect(controller.replyState, AdvisorReplyState.idle);
    expect(controller.messages, hasLength(2));
    expect(controller.messages.last.role, AdvisorMessageRole.guide);
    expect(controller.messages.last.answer?.topicId, 'photos');
    expect(controller.messages.last.allImagePaths, [image.path]);
  });

  test('online photo failure returns the completed on-device result', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wormwise-guide-photo-fallback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}${Platform.pathSeparator}maize.jpg');
    await image.writeAsBytes([1, 2, 3]);
    final controller = AdvisorController(
      openChatService: _RecordingOpenChatService(failuresBeforeSuccess: 1),
      imageAnalysisService: AdvisorImageAnalysisService(_BoxImageModel()),
    );
    addTearDown(controller.dispose);

    await controller.askGeminiWithImage('', image);

    expect(controller.replyState, AdvisorReplyState.idle);
    expect(controller.messages, hasLength(2));
    expect(
      controller.messages.last.answer?.topicId,
      'on_device_image_analysis',
    );
    expect(controller.messages.last.modelFindings, contains('Larval damage'));
    expect(controller.messages.last.allImagePaths, [image.path]);
  });

  test('clearing a pending reply ignores its late completion', () async {
    final completer = Completer<AdvisorAnswer>();
    final service = _CompletingOpenChatService(completer);
    final controller = AdvisorController(openChatService: service);
    addTearDown(controller.dispose);

    final pending = controller.ask('An open question for later.');
    expect(controller.replyState, AdvisorReplyState.sending);
    expect(controller.thinkingStage, AdvisorThinkingStage.reviewingRequest);

    controller.clear();
    completer.complete(_openChatAnswer);
    await pending;

    expect(controller.replyState, AdvisorReplyState.idle);
    expect(controller.messages, isEmpty);
  });

  test(
    'restores, updates, and clears persisted conversation history',
    () async {
      final store = _MemoryConversationStore(
        messages: const [
          AdvisorStoredMessage(id: 'saved-1', role: 'farmer', text: 'Saved Q'),
          AdvisorStoredMessage(
            id: 'saved-2',
            role: 'guide',
            text: 'Saved A',
            answer: _openChatAnswer,
          ),
        ],
      );
      final controller = AdvisorController(conversationStore: store);
      addTearDown(controller.dispose);

      await controller.restoreConversation();
      expect(controller.messages, hasLength(2));

      await controller.ask('What does frass mean?');
      await Future<void>.delayed(Duration.zero);
      expect(store.messages, hasLength(4));

      controller.clear();
      await Future<void>.delayed(Duration.zero);
      expect(store.messages, isEmpty);
    },
  );
}

class _RecordingOpenChatService implements AdvisorOpenChatService {
  _RecordingOpenChatService({this.failuresBeforeSuccess = 0});

  final int failuresBeforeSuccess;
  final List<AdvisorOpenChatRequest> requests = [];

  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) async {
    requests.add(request);
    if (requests.length <= failuresBeforeSuccess) {
      throw StateError('Simulated open chat failure');
    }
    return _openChatAnswer;
  }
}

class _CompletingOpenChatService implements AdvisorOpenChatService {
  const _CompletingOpenChatService(this.completer);

  final Completer<AdvisorAnswer> completer;

  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) {
    return completer.future;
  }
}

class _OfflineOpenChatService implements AdvisorOpenChatService {
  const _OfflineOpenChatService();

  @override
  Future<AdvisorAnswer> answer(AdvisorOpenChatRequest request) {
    throw const AdvisorOnlineUnavailableException('No internet connection.');
  }
}

class _BoxImageModel implements FawComputerVisionService {
  @override
  bool get isModelLoaded => true;

  @override
  String get modelIdentifier => 'box-test-model';

  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) async {
    return PlantDiagnosisResult(
      isInfested: true,
      pestLabel: 'Larval damage',
      confidenceScore: 0.8,
      suggestedPlantStatus: DatabaseCodes.plantCurrentPositive,
      detectionBoxes: [
        ModelDetectionBox(
          sourcePath: imageFile.path,
          classId: 0,
          label: 'Larval damage',
          confidence: 0.8,
          left: 0.1,
          top: 0.1,
          right: 0.5,
          bottom: 0.5,
          imageWidth: 100,
          imageHeight: 100,
        ),
      ],
    );
  }
}

class _FailingImageModel implements FawComputerVisionService {
  @override
  bool get isModelLoaded => false;

  @override
  String get modelIdentifier => 'failing-test-model';

  @override
  Future<PlantDiagnosisResult> analyzeImage(File imageFile) {
    throw StateError('Simulated image analysis failure');
  }
}

class _MemoryConversationStore implements AdvisorConversationStore {
  _MemoryConversationStore({List<AdvisorStoredMessage>? messages})
    : messages = [...?messages];

  List<AdvisorStoredMessage> messages;

  @override
  Future<void> clear() async => messages = [];

  @override
  Future<List<AdvisorStoredMessage>> load() async => [...messages];

  @override
  Future<void> save(List<AdvisorStoredMessage> messages) async {
    this.messages = [...messages];
  }
}

const _openChatAnswer = AdvisorAnswer(
  topicId: 'open_chat_test',
  title: 'Open chat response',
  summary: 'A simulated response for controller testing.',
  details: [],
  source: AdvisorKnowledgeSource(
    label: 'Test open chat',
    reference: 'Test double',
    version: 'test-v1',
  ),
);

class _DelayedConversationStore implements AdvisorConversationStore {
  final loaded = Completer<List<AdvisorStoredMessage>>();
  @override
  Future<List<AdvisorStoredMessage>> load() => loaded.future;
  @override
  Future<void> save(List<AdvisorStoredMessage> messages) async {}
  @override
  Future<void> clear() async {}
}
