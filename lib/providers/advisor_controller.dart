import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/repositories/advisor_context_repository.dart';
import '../services/advisor/advisor_assessment_contract.dart';
import '../services/advisor/advisor_conversation_store.dart';
import '../services/advisor/advisor_image_analysis_service.dart';
import '../services/advisor/advisor_knowledge_service.dart';
import '../services/advisor/advisor_open_chat_service.dart';
import '../services/computer_vision/faw_computer_vision_service.dart';
import '../services/cloud/account_app_data_service.dart';

enum AdvisorMessageRole { farmer, guide }

enum AdvisorContextState { unavailable, loading, ready, error }

enum AdvisorReplyState { idle, sending, error }

enum AdvisorThinkingStage {
  reviewingRequest,
  checkingContext,
  composingResponse,
  analyzingPhoto,
  preparingModelExplanation,
}

class AdvisorMessage {
  const AdvisorMessage._({
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

  factory AdvisorMessage.farmer({
    required String id,
    required String text,
    String? imagePath,
    List<String> imagePaths = const [],
    String? replyToMessageId,
    String? replyPreview,
  }) {
    return AdvisorMessage._(
      id: id,
      role: AdvisorMessageRole.farmer,
      text: text,
      imagePath: imagePath ?? (imagePaths.isEmpty ? null : imagePaths.first),
      imagePaths: imagePaths,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview,
    );
  }

  factory AdvisorMessage.guide({
    required String id,
    required AdvisorAnswer answer,
    String? imagePath,
    List<String> imagePaths = const [],
    List<ModelDetectionBox> detectionBoxes = const [],
    String? modelFindings,
  }) {
    return AdvisorMessage._(
      id: id,
      role: AdvisorMessageRole.guide,
      text: answer.summary,
      answer: answer,
      imagePath: imagePath ?? (imagePaths.isEmpty ? null : imagePaths.first),
      imagePaths: imagePaths,
      detectionBoxes: detectionBoxes,
      modelFindings: modelFindings,
    );
  }

  factory AdvisorMessage.fromStored(AdvisorStoredMessage stored) {
    return AdvisorMessage._(
      id: stored.id,
      role: stored.role == 'farmer'
          ? AdvisorMessageRole.farmer
          : AdvisorMessageRole.guide,
      text: stored.text,
      answer: stored.answer,
      imagePath:
          stored.imagePath ??
          (stored.imagePaths.isEmpty ? null : stored.imagePaths.first),
      imagePaths: stored.imagePaths,
      detectionBoxes: stored.detectionBoxes,
      modelFindings: stored.modelFindings,
      replyToMessageId: stored.replyToMessageId,
      replyPreview: stored.replyPreview,
    );
  }

  final String id;
  final AdvisorMessageRole role;
  final String text;
  final AdvisorAnswer? answer;
  final String? imagePath;
  final List<String> imagePaths;
  List<String> get allImagePaths => imagePaths.isNotEmpty
      ? imagePaths
      : (imagePath == null ? const [] : [imagePath!]);
  final List<ModelDetectionBox> detectionBoxes;
  final String? modelFindings;
  final String? replyToMessageId;
  final String? replyPreview;

  AdvisorStoredMessage toStored() => AdvisorStoredMessage(
    id: id,
    role: role == AdvisorMessageRole.farmer ? 'farmer' : 'guide',
    text: text,
    answer: answer,
    imagePath: imagePath,
    imagePaths: imagePaths,
    detectionBoxes: detectionBoxes,
    modelFindings: modelFindings,
    replyToMessageId: replyToMessageId,
    replyPreview: replyPreview,
  );
}

/// Owns the locally persisted, read-only conversation shown by the assistant.
class AdvisorController extends ChangeNotifier {
  AdvisorController({
    this._openChatService,
    this._imageAnalysisService,
    this._conversationStore,
    this._contextRepository,
  }) {
    if (_conversationStore != null) {
      AccountAppDataEvents.pendingWriters.add(_flushConversation);
    }
  }

  Future<void> _flushConversation() => _persistenceQueue;

  final AdvisorOpenChatService? _openChatService;
  final AdvisorImageAnalysisService? _imageAnalysisService;
  final AdvisorConversationStore? _conversationStore;
  AdvisorContextRepository? _contextRepository;
  String? _contextCropCycleId;
  String? _contextAssessmentId;
  final List<AdvisorMessage> _messages = [];
  String languageCode = 'en';

  int _nextMessageId = 0;
  int _contextLoadGeneration = 0;
  int _replyGeneration = 0;
  String? _contextSignature;
  String? _activeFieldId;
  AdvisorContextState _contextState = AdvisorContextState.unavailable;
  AdvisorReplyState _replyState = AdvisorReplyState.idle;
  AdvisorThinkingStage? _thinkingStage;
  AdvisorFieldContextSnapshot? _fieldContext;
  Object? _contextError;
  Object? _replyError;
  _PendingOpenChat? _pendingOpenChat;
  bool _disposed = false;
  Future<void>? _conversationRestore;
  Future<void> _persistenceQueue = Future<void>.value();
  Timer? _thinkingTimer;

  List<AdvisorMessage> get messages => List.unmodifiable(_messages);
  bool get hasConversation => _messages.isNotEmpty;
  AdvisorContextState get contextState => _contextState;
  AdvisorReplyState get replyState => _replyState;
  AdvisorThinkingStage? get thinkingStage => _thinkingStage;
  AdvisorFieldContextSnapshot? get fieldContext => _fieldContext;
  Object? get contextError => _contextError;
  Object? get replyError => _replyError;
  bool get isReplyPending => _replyState == AdvisorReplyState.sending;
  bool get canRetryOpenChat =>
      _replyState == AdvisorReplyState.error && _pendingOpenChat != null;

  Future<void> restoreConversation() =>
      _conversationRestore ??= _restoreConversation();

  /// Account recovery replaces the backing history without writing it back.
  Future<void> reloadStoredConversation({bool accountChanged = false}) async {
    final store = _conversationStore;
    if (_disposed || store == null) {
      return;
    }
    if (accountChanged) {
      _replyGeneration++;
      _messages.clear();
      _resetReplyState();
      _notifyListeners();
    }
    final generation = _replyGeneration;
    final stored = await store.load();
    if (_disposed || generation != _replyGeneration || isReplyPending) {
      return;
    }
    _messages
      ..clear()
      ..addAll(
        stored
            .where(
              (message) =>
                  message.role == 'farmer' ||
                  (message.role == 'guide' && message.answer != null),
            )
            .map(AdvisorMessage.fromStored),
      );
    _nextMessageId = _messages.fold<int>(0, (next, message) {
      final number = int.tryParse(
        message.id.replaceFirst('advisor_message_', ''),
      );
      return number != null && number >= next ? number + 1 : next;
    });
    _conversationRestore = Future<void>.value();
    _notifyListeners();
  }

  Future<void> _restoreConversation() async {
    final store = _conversationStore;
    if (_disposed || store == null) return;
    final generation = _replyGeneration;
    try {
      final stored = await store.load();
      if (_disposed || generation != _replyGeneration || _messages.isNotEmpty) {
        return;
      }
      _messages.addAll(
        stored
            .where(
              (message) =>
                  message.role == 'farmer' ||
                  (message.role == 'guide' && message.answer != null),
            )
            .map(AdvisorMessage.fromStored),
      );
      _nextMessageId = _messages.length;

      if (_messages.isNotEmpty) _notifyListeners();
    } catch (_) {
      // Chat history is helpful but non-authoritative. A damaged or unavailable
      // history file must never block the field guide.
    }
  }

  void attachContextRepository(AdvisorContextRepository repository) {
    if (_disposed) return;
    _contextRepository = repository;
  }

  Future<void> loadContext({
    required String? fieldId,
    required String? cropCycleId,
    String? preferredAssessmentId,
    bool force = false,
  }) async {
    if (_disposed) return;
    _activeFieldId = fieldId;
    _contextCropCycleId = cropCycleId;
    _contextAssessmentId = preferredAssessmentId;
    final repository = _contextRepository;
    if (repository == null) {
      _contextState = AdvisorContextState.unavailable;
      return;
    }
    final signature = '$fieldId|$cropCycleId|$preferredAssessmentId';
    if (!force && signature == _contextSignature) return;
    _contextSignature = signature;
    final generation = ++_contextLoadGeneration;
    _contextState = AdvisorContextState.loading;
    _contextError = null;
    _notifyListeners();
    try {
      final loaded = await repository.load(
        fieldId: fieldId,
        cropCycleId: cropCycleId,
        preferredAssessmentId: preferredAssessmentId,
      );
      if (_disposed || generation != _contextLoadGeneration) return;
      _fieldContext = loaded;
      _contextState = AdvisorContextState.ready;
      _notifyListeners();
    } catch (error) {
      if (_disposed || generation != _contextLoadGeneration) return;
      _fieldContext = null;
      _contextError = error;
      _contextState = AdvisorContextState.error;
      _notifyListeners();
    }
  }

  Future<void> ask(
    String question, {
    bool allowOpenChat = true,
    String? replyToText,
    String? replyToMessageId,
  }) async {
    final restoreGeneration = _replyGeneration;
    if (_conversationStore != null) await restoreConversation();
    if (_disposed || restoreGeneration != _replyGeneration) return;
    final trimmed = question.trim();
    if (_disposed || trimmed.isEmpty || isReplyPending) return;
    final history = _openChatHistory();
    _resetReplyState();
    _messages.add(
      AdvisorMessage.farmer(
        id: _newMessageId(),
        text: trimmed,
        replyToMessageId: replyToMessageId,
        replyPreview: replyToText,
      ),
    );
    _scheduleConversationSave();

    if (!allowOpenChat || _openChatService == null) {
      _replyError = const AdvisorOnlineUnavailableException(
        'Online advisor is unavailable. Try again when connected.',
      );
      _replyState = AdvisorReplyState.error;
      _notifyListeners();
      return;
    }

    final replyContext = replyToText?.trim();
    _pendingOpenChat = _PendingOpenChat(
      question: replyContext == null || replyContext.isEmpty
          ? trimmed
          : 'The user is replying specifically to this earlier assistant response:\n'
                '"$replyContext"\n\n'
                'Their reply is: $trimmed',
      history: history,
      fieldContext: _openChatFieldContext(),
    );
    _thinkingStage = AdvisorThinkingStage.reviewingRequest;
    _replyState = AdvisorReplyState.sending;
    _notifyListeners();
    await _sendPendingOpenChat();
  }

  Future<void> analyzeImageOnDevice(
    File imageFile, {
    required String question,
  }) => analyzeImagesOnDevice([imageFile], question: question);

  Future<void> analyzeImagesOnDevice(
    List<File> imageFiles, {
    required String question,
  }) async {
    final service = _imageAnalysisService;
    final restoreGeneration = _replyGeneration;
    if (_conversationStore != null) await restoreConversation();
    if (_disposed || restoreGeneration != _replyGeneration) return;
    final trimmed = question.trim();
    if (_disposed || service == null || imageFiles.isEmpty || isReplyPending) {
      return;
    }
    final paths = imageFiles.map((file) => file.path).toList(growable: false);
    _resetReplyState();
    _messages.add(
      AdvisorMessage.farmer(
        id: _newMessageId(),
        text: trimmed,
        imagePaths: paths,
      ),
    );
    _scheduleConversationSave();
    final generation = ++_replyGeneration;
    _replyState = AdvisorReplyState.sending;
    _thinkingStage = AdvisorThinkingStage.analyzingPhoto;
    _notifyListeners();
    try {
      final analyses = <AdvisorImageAnalysisResult>[];
      for (final file in imageFiles) {
        analyses.add(await service.analyze(file));
      }
      if (_disposed || generation != _replyGeneration) return;
      final analysis = analyses.first;
      final findings = [
        for (var index = 0; index < analyses.length; index++)
          'Photo ${index + 1}: ${analyses[index].structuredFindings}',
      ].join('\n');
      final boxes = [for (final item in analyses) ...item.detectionBoxes];
      final answer = trimmed.isEmpty
          ? (analyses.length == 1
                ? analysis.answer
                : AdvisorAnswer(
                    topicId: analysis.answer.topicId,
                    title: analysis.answer.title,
                    summary:
                        'Cropwise analyzed ${analyses.length} photos on this device. Review the marked images and ask about any of the model findings.',
                    details: [
                      for (var index = 0; index < analyses.length; index++)
                        'Photo ${index + 1}: ${analyses[index].answer.summary}',
                    ],
                    nextAction:
                        'What would you like to understand about this photo or the model findings?',
                    source: analysis.answer.source,
                  ))
          : analysis.answer;
      _messages.add(
        AdvisorMessage.guide(
          id: _newMessageId(),
          answer: answer,
          imagePaths: paths,
          detectionBoxes: boxes,
          modelFindings: findings,
        ),
      );
      _replyState = AdvisorReplyState.idle;
      _thinkingStage = null;
      _scheduleConversationSave();
      _notifyListeners();
    } catch (error) {
      if (_disposed || generation != _replyGeneration) return;
      debugPrint('Cropwise on-device image analysis failed: $error');
      _showPhotoError(error);
    }
  }

  Future<void> askGeminiWithImage(String question, File imageFile) async {
    return askGeminiWithImages(question, [imageFile]);
  }

  Future<void> askGeminiWithImages(
    String question,
    List<File> imageFiles,
  ) async {
    final restoreGeneration = _replyGeneration;
    if (_conversationStore != null) await restoreConversation();
    if (_disposed || restoreGeneration != _replyGeneration) return;
    final trimmed = question.trim();
    if (_disposed ||
        _openChatService == null ||
        imageFiles.isEmpty ||
        isReplyPending) {
      return;
    }
    final paths = imageFiles.map((file) => file.path).toList(growable: false);
    _resetReplyState();
    _messages.add(
      AdvisorMessage.farmer(
        id: _newMessageId(),
        text: trimmed,
        imagePaths: paths,
      ),
    );
    _scheduleConversationSave();
    final generation = ++_replyGeneration;
    _replyState = AdvisorReplyState.sending;
    _thinkingStage = AdvisorThinkingStage.analyzingPhoto;
    _notifyListeners();
    final imageAnalysisService = _imageAnalysisService;
    if (imageAnalysisService == null) {
      _showPhotoError(
        const AdvisorOnlineUnavailableException(
          'Photo analysis could not complete. Please send the photo again.',
        ),
      );
      return;
    }
    try {
      final analyses = <AdvisorImageAnalysisResult>[];
      for (final file in imageFiles) {
        analyses.add(await imageAnalysisService.analyze(file));
      }
      if (_disposed || generation != _replyGeneration) return;
      final findings = [
        for (var index = 0; index < analyses.length; index++)
          'Photo ${index + 1}: ${analyses[index].structuredFindings}',
      ].join('\n');
      final boxes = [for (final item in analyses) ...item.detectionBoxes];
      _thinkingStage = AdvisorThinkingStage.preparingModelExplanation;
      _notifyListeners();
      _pendingOpenChat = _PendingOpenChat(
        question: trimmed.isEmpty
            ? 'Explain the on-device findings for the attached photo clearly. State what the model found, what it does not prove, and what the user should inspect next.'
            : trimmed,
        history: _openChatHistory(),
        fieldContext: _openChatFieldContext(),
        modelFindings: findings,
        photoFollowUpOnly: false,
        modelSummary: [
          for (var i = 0; i < analyses.length; i++)
            '${analyses.length > 1 ? 'Photo ${i + 1}: ' : ''}${analyses[i].answer.summary}',
        ].join('\n\n'),
        imagePaths: paths,
        detectionBoxes: boxes,
      );
      await _sendPendingOpenChat();
    } catch (error) {
      if (_disposed || generation != _replyGeneration) return;
      debugPrint('Cropwise photo explanation failed: $error');
      _showPhotoError(error);
    }
  }

  Future<void> retryOpenChat() async {
    if (_disposed || !canRetryOpenChat) return;
    await _sendPendingOpenChat();
  }

  Future<void> askPhotoSuggestedAction(
    AdvisorMessage source,
    String action, {
    bool allowOpenChat = true,
  }) async {
    final restoreGeneration = _replyGeneration;
    if (_conversationStore != null) await restoreConversation();
    if (_disposed || restoreGeneration != _replyGeneration) return;
    final trimmed = action.trim();
    final findings = source.modelFindings;
    if (_disposed || trimmed.isEmpty || findings == null || isReplyPending) {
      return;
    }
    final history = _suggestionHistory(source);
    _resetReplyState();
    _messages.add(AdvisorMessage.farmer(id: _newMessageId(), text: trimmed));
    _scheduleConversationSave();
    if (!allowOpenChat || _openChatService == null) {
      _replyError = const AdvisorOnlineUnavailableException(
        'Online advisor is unavailable. Try again when connected.',
      );
      _replyState = AdvisorReplyState.error;
      _notifyListeners();
      return;
    }
    _pendingOpenChat = _PendingOpenChat(
      question: trimmed,
      history: history,
      fieldContext: _openChatFieldContext(),
      modelFindings: findings,
      preferFastModel: true,
      modelSummary: source.answer?.topicId == 'on_device_image_analysis'
          ? source.answer?.summary
          : null,
    );
    _thinkingStage = AdvisorThinkingStage.reviewingRequest;
    _replyState = AdvisorReplyState.sending;
    _notifyListeners();
    await _sendPendingOpenChat();
  }

  Future<void> askSuggestedAction(AdvisorMessage source, String action) async {
    final trimmed = action.trim();
    if (_disposed || trimmed.isEmpty || isReplyPending) return;
    final history = _suggestionHistory(source);
    final restoreGeneration = _replyGeneration;
    if (_conversationStore != null) await restoreConversation();
    if (_disposed || restoreGeneration != _replyGeneration) return;
    _resetReplyState();
    _messages.add(AdvisorMessage.farmer(id: _newMessageId(), text: trimmed));
    _scheduleConversationSave();
    _pendingOpenChat = _PendingOpenChat(
      question: trimmed,
      history: history,
      fieldContext: _openChatFieldContext(),
      preferFastModel: true,
    );
    _thinkingStage = AdvisorThinkingStage.reviewingRequest;
    _replyState = AdvisorReplyState.sending;
    _notifyListeners();
    await _sendPendingOpenChat();
  }

  List<AdvisorOpenChatTurn> _suggestionHistory(AdvisorMessage source) {
    final answer = source.answer;
    if (answer == null) return const [];
    final sourceIndex = _messages.indexWhere((item) => item.id == source.id);
    if (sourceIndex < 0) return const [];
    final previous = sourceIndex > 0 ? _messages[sourceIndex - 1] : null;
    // The welcome guide has no preceding user turn. Sending it as the first
    // model turn makes an invalid chat transcript for some Gemini endpoints.
    if (previous?.role != AdvisorMessageRole.farmer) return const [];
    final sourceText = [source.text, ...answer.details].join('\n').trim();
    final sensitive = const {
      'field_context',
      'assessment_explanation',
      'gemini_open_chat',
    }.contains(answer.topicId);
    return [
      AdvisorOpenChatTurn(
        role: AdvisorOpenChatRole.farmer,
        text: previous!.text.length <= 1000
            ? previous.text
            : previous.text.substring(0, 1000),
        requiresFieldContextSharing: sensitive,
        requiresLocationSharing: answer.topicId == 'field_context',
      ),
      AdvisorOpenChatTurn(
        role: AdvisorOpenChatRole.advisor,
        text: sourceText.length <= 2500
            ? sourceText
            : sourceText.substring(0, 2500),
        requiresFieldContextSharing: sensitive,
        requiresLocationSharing: answer.topicId == 'field_context',
      ),
    ];
  }

  void clear() {
    if (_disposed) return;
    final hadState =
        _messages.isNotEmpty || _replyState != AdvisorReplyState.idle;
    _replyGeneration++;
    if (!hadState) {
      _scheduleConversationClear();
      return;
    }
    _messages.clear();

    _resetReplyState();
    _scheduleConversationClear();
    _notifyListeners();
  }

  void openSavedConversation(List<AdvisorStoredMessage> stored) {
    if (_disposed || isReplyPending) return;
    _replyGeneration++;
    _messages
      ..clear()
      ..addAll(
        stored
            .where(
              (message) =>
                  message.role == 'farmer' ||
                  (message.role == 'guide' && message.answer != null),
            )
            .map(AdvisorMessage.fromStored),
      );
    _nextMessageId = _messages.fold<int>(0, (next, message) {
      final number = int.tryParse(
        message.id.replaceFirst('advisor_message_', ''),
      );
      return number == null || number < next ? next : number + 1;
    });
    _resetReplyState();
    _scheduleConversationSave();
    _notifyListeners();
  }

  String _newMessageId() => 'advisor_message_${_nextMessageId++}';

  /// Build from the same transcript shown to the user, including restored turns.
  /// Keep complete exchanges, newest first within a deterministic character budget.
  /// This is a payload bound, not a claim about the model's tokenizer.
  List<AdvisorOpenChatTurn> _openChatHistory() {
    final exchanges = <List<AdvisorOpenChatTurn>>[];
    var remaining = 24000;
    for (var index = _messages.length - 1; index > 0; index--) {
      final response = _messages[index];
      final question = _messages[index - 1];
      if (response.role != AdvisorMessageRole.guide ||
          question.role != AdvisorMessageRole.farmer ||
          response.answer == null) {
        continue;
      }
      final sensitive = const {
        'field_context',
        'assessment_explanation',
        'gemini_open_chat',
      }.contains(response.answer!.topicId);
      final userText = question.text.trim().isEmpty
          ? 'Explain the attached photo findings.'
          : question.text;
      final answerText = [
        response.text,
        ...response.answer!.details,
        if (response.answer!.nextAction != null) response.answer!.nextAction!,
        if (response.modelFindings != null)
          'On-device model findings (suggestions, not confirmed diagnosis):\n${response.modelFindings}',
      ].join('\n');
      // Bound individual messages as well as the full window. Mark truncation
      // explicitly so the model does not assume it received the entire answer.
      String bounded(String value) => value.length <= 3000
          ? value
          : '${value.substring(0, 2970)}\n[Earlier message truncated]';
      final user = bounded(userText);
      final answer = bounded(answerText);
      final size = user.length + answer.length;
      if (size > remaining || exchanges.length == 24) break;
      remaining -= size;
      exchanges.add([
        AdvisorOpenChatTurn(
          role: AdvisorOpenChatRole.farmer,
          text: user,
          requiresFieldContextSharing: sensitive,
          requiresLocationSharing: response.answer!.topicId == 'field_context',
        ),
        AdvisorOpenChatTurn(
          role: AdvisorOpenChatRole.advisor,
          text: answer,
          requiresFieldContextSharing: sensitive,
          requiresLocationSharing: response.answer!.topicId == 'field_context',
        ),
      ]);
      index--;
    }
    return List.unmodifiable(exchanges.reversed.expand((exchange) => exchange));
  }

  Future<void> _sendPendingOpenChat() async {
    final service = _openChatService;
    final pending = _pendingOpenChat;
    if (service == null || pending == null || _disposed) return;
    final generation = ++_replyGeneration;
    _replyState = AdvisorReplyState.sending;
    // A text follow-up can carry findings from an earlier photo. The model is
    // composing a reply here; it is not necessarily processing a new photo.
    _thinkingStage = AdvisorThinkingStage.composingResponse;
    _replyError = null;
    _notifyListeners();
    try {
      var currentFieldContext = pending.fieldContext;
      if (currentFieldContext != null && _contextRepository != null) {
        await loadContext(
          fieldId: _activeFieldId,
          cropCycleId: _contextCropCycleId,
          preferredAssessmentId: _contextAssessmentId,
          force: true,
        );
        if (_disposed || generation != _replyGeneration) return;
        currentFieldContext = _contextState == AdvisorContextState.ready
            ? _openChatFieldContext()
            : null;
      }
      final answer = await service.answer(
        AdvisorOpenChatRequest(
          question: pending.question,
          history: pending.history,
          fieldContext: currentFieldContext,
          modelFindings: pending.modelFindings,
          modelSummary: pending.modelSummary,
          photoFollowUpOnly: pending.photoFollowUpOnly,
          preferFastModel: pending.preferFastModel,
          languageCode: languageCode,
          dataTools: _contextRepository,
          activeFieldId: _activeFieldId,
          previousSuggestions: _messages
              .where((m) => m.role == AdvisorMessageRole.guide)
              .expand((m) => m.answer?.suggestedActions ?? const <String>[])
              .toList(),
        ),
      );
      if (_disposed || generation != _replyGeneration) return;
      _thinkingTimer?.cancel();
      _messages.add(
        AdvisorMessage.guide(
          id: _newMessageId(),
          answer: answer,
          // The user attachment is already visible in the preceding bubble.
          // Do not render the same photo a second time with the response.
          imagePaths: const [],
          detectionBoxes: pending.detectionBoxes,
          modelFindings: pending.modelFindings,
        ),
      );
      _pendingOpenChat = null;
      _replyState = AdvisorReplyState.idle;
      _thinkingStage = null;
      _scheduleConversationSave();
      _notifyListeners();
    } on AdvisorOnlineUnavailableException catch (error) {
      if (_disposed || generation != _replyGeneration) return;
      _thinkingTimer?.cancel();
      _replyError = error;
      _replyState = AdvisorReplyState.error;
      _thinkingStage = null;
      _notifyListeners();
    } catch (error) {
      if (_disposed || generation != _replyGeneration) return;
      _thinkingTimer?.cancel();
      debugPrint('Cropwise online guide request failed: $error');
      _replyError = error;
      _replyState = AdvisorReplyState.error;
      _thinkingStage = null;
      _notifyListeners();
    }
  }

  void _showPhotoError(Object error) {
    _thinkingTimer?.cancel();
    _pendingOpenChat = null;
    _replyError = error;
    _replyState = AdvisorReplyState.error;
    _thinkingStage = null;
    _notifyListeners();
  }

  AdvisorOpenChatFieldContext? _openChatFieldContext() {
    final context = _fieldContext;
    if (context == null) return null;
    final assessment = context.assessment;
    final fieldLines = <String>[
      'Field name: ${context.fieldName}',
      if (context.areaHectares != null)
        'Recorded area: ${context.areaHectares} hectares',
      if (context.varietyName != null) 'Maize variety: ${context.varietyName}',
      if (context.plantingDate != null)
        'Planting date: ${context.plantingDate!.toIso8601String().split('T').first}',
      'Outline confirmed: ${context.hasConfirmedOutline}',
      if (assessment != null) ...[
        'Assessment date: ${(assessment.completedAt ?? assessment.startedAt)?.toIso8601String() ?? 'not recorded'}',
        'Sampling: ${assessment.sampling}',
        'Sampled infestation: ${assessment.sampledInfestation}',
        'Finalized expert findings: ${AdvisorAssessmentContract.finalized(assessment.expertReview)}',
        'Assessment status: ${assessment.status}',
        'Growth stage: ${assessment.growthStage}',
        'Progress: ${assessment.completedBlocks}/${assessment.totalBlocks} blocks, ${assessment.stationRecords} station records, ${assessment.plantRecords} plant records',
        if (assessment.weatherContext?.trim().isNotEmpty == true)
          'Recorded weather context: ${assessment.weatherContext!.trim()}',
        'Finding types: ${assessment.findingSummary}',
        'Block coverage: ${assessment.blockCoverage}',
        'Supporting block metrics and manual observation results are excluded. Use saved CV classifications and evidence coverage.',
      ],
    ];
    final locationLines = <String>[
      if (context.barangay?.trim().isNotEmpty == true)
        'Barangay: ${context.barangay!.trim()}',
      if (context.boundaryGeoJson?.trim().isNotEmpty == true)
        'Approximate field-boundary GeoJSON: ${context.boundaryGeoJson!.trim()}',
    ];
    return AdvisorOpenChatFieldContext(
      fieldAndAssessmentSummary: fieldLines.join('\n'),
      records: {
        'field_id': context.fieldId,
        'field_name': context.fieldName,
        'area_hectares': context.areaHectares,
        'variety': context.varietyName,
        'planting_date': context.plantingDate?.toIso8601String(),
        'outline_confirmed': context.hasConfirmedOutline,
        if (assessment != null)
          'assessment': {
            'id': assessment.id,
            'status': assessment.status,
            'growth_stage': assessment.growthStage,
            'growth_stage_uncertain': assessment.growthStageUncertain,
            'started_at': assessment.startedAt?.toIso8601String(),
            'completed_at': assessment.completedAt?.toIso8601String(),
            'total_blocks': assessment.totalBlocks,
            'completed_blocks': assessment.completedBlocks,
            'plant_records': assessment.plantRecords,
            'finding_summary': assessment.findingSummary,
            'block_coverage': assessment.blockCoverage,
            'sampling': assessment.sampling,
            'sampled_infestation': assessment.sampledInfestation,
            'expert_review': assessment.expertReview,
            'finalized_expert_findings': AdvisorAssessmentContract.finalized(
              assessment.expertReview,
            ),
            'weather': assessment.weatherContext,
            'supporting_metrics_available': false,
          },
      },
      locationSummary: locationLines.isEmpty ? null : locationLines.join('\n'),
    );
  }

  void _scheduleConversationSave() {
    final store = _conversationStore;
    if (store == null) return;
    final snapshot = _messages.map((message) => message.toStored()).toList();
    final viewGeneration = AccountAppDataEvents.viewGeneration;
    final previous = _persistenceQueue;
    _persistenceQueue = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        if (viewGeneration == AccountAppDataEvents.viewGeneration) {
          await store.save(snapshot);
        }
      } catch (_) {}
    }();
  }

  void _scheduleConversationClear() {
    final store = _conversationStore;
    if (store == null) return;
    final previous = _persistenceQueue;
    final viewGeneration = AccountAppDataEvents.viewGeneration;
    _persistenceQueue = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        if (viewGeneration == AccountAppDataEvents.viewGeneration) {
          await store.clear();
        }
      } catch (_) {}
    }();
  }

  void _resetReplyState() {
    _thinkingTimer?.cancel();
    _pendingOpenChat = null;
    _replyError = null;
    _replyState = AdvisorReplyState.idle;
    _thinkingStage = null;
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      _persistenceQueue.whenComplete(() {
        AccountAppDataEvents.pendingWriters.remove(_flushConversation);
      }),
    );
    _thinkingTimer?.cancel();
    _contextLoadGeneration++;
    _replyGeneration++;
    super.dispose();
  }

  // Four recent exchanges preserve conversational continuity without resending
  // the entire chat to Gemini on every request.
}

class _PendingOpenChat {
  const _PendingOpenChat({
    required this.question,
    required this.history,
    this.fieldContext,
    this.modelFindings,
    this.modelSummary,
    this.photoFollowUpOnly = false,
    this.preferFastModel = false,
    this.imagePaths = const [],
    this.detectionBoxes = const [],
  });

  final String question;
  final List<AdvisorOpenChatTurn> history;
  final AdvisorOpenChatFieldContext? fieldContext;
  final String? modelFindings;
  final String? modelSummary;
  final bool photoFollowUpOnly;
  final bool preferFastModel;
  final List<String> imagePaths;
  final List<ModelDetectionBox> detectionBoxes;
}
