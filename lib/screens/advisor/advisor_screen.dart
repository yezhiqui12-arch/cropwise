import 'dart:async';
import '../../localization/app_language.dart';
import '../../localization/app_text.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../widgets/advisor/advisor_illustrated_reply.dart';
import '../../services/advisor/advisor_visual_reference.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/advisor_context_repository.dart';
import '../../providers/advisor_controller.dart';
import '../../providers/assessment_workspace_provider.dart';
import '../../providers/field_workspace_provider.dart';
import '../../services/advisor/advisor_app_action.dart';
import '../../services/advisor/advisor_knowledge_service.dart';
import '../../services/advisor/advisor_conversation_store.dart';
import '../../services/advisor/advisor_chat_session_store.dart';
import '../../services/advisor/advisor_connectivity_service.dart';
import '../../services/advisor/advisor_gemini_settings.dart';
import '../../services/advisor/advisor_image_analysis_service.dart';
import '../../services/advisor/advisor_open_chat_service.dart';
import '../../services/advisor/gemini_advisor_open_chat_service.dart';
import '../../services/computer_vision/faw_computer_vision_service.dart';
import '../../services/cloud/expert_review_service.dart';
import '../../services/cloud/account_app_data_service.dart';
import '../../services/computer_vision/two_stage_faw_cv_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/advisor/advisor_reply_content.dart';
import '../../widgets/advisor/advisor_reply_reveal.dart';
import '../account_access_screen.dart';
import '../assessment_session_screen.dart';
import '../assessment_setup_screen.dart';
import '../boundary_map_screen.dart';
import '../expert_review_screen.dart';
import '../my_profile_screen.dart';
import '../fields_screen.dart';
import '../field_details_screen.dart';
import '../field_trends_screen.dart';
import '../language_screen.dart';
import '../models_screen.dart';
import '../artificial_intelligence_screen.dart';
import '../more_screen.dart';
import '../notifications_screen.dart';
import '../assess/assessment_details_screen.dart';
import '../assess/assessment_results_screen.dart';
import '../assess/assessments_screen.dart';
import '../station1/model_detection_image.dart';
import 'guidelines_redesign.dart';
import 'advisor_chats_page.dart';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({
    super.key,
    this.controller,
    this.refreshToken = 0,
    this.geminiSettingsStore,
    this.imagePicker,
    this.connectivityService,
    this.initialQuestion,
    this.assessmentId,
    this.fieldId,
    this.cropCycleId,
    this.onSelectDestination,
  });

  final AdvisorController? controller;
  final int refreshToken;
  final AdvisorGeminiSettingsStore? geminiSettingsStore;
  final ImagePicker? imagePicker;
  final AdvisorConnectivityService? connectivityService;
  final String? initialQuestion;
  final String? assessmentId;
  final String? fieldId;
  final String? cropCycleId;
  final ValueChanged<int>? onSelectDestination;

  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen> {
  late final AdvisorController _controller;
  late final bool _ownsController;
  late final AdvisorGeminiSettingsStore _geminiSettingsStore;
  late final ImagePicker _imagePicker;
  TwoStageFawCvService? _ownedImageModel;
  late final AdvisorConnectivityService _connectivityService;
  final _questionController = TextEditingController();
  final _questionFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<_QueuedGuideSubmission> _submissionQueue = [];
  StreamSubscription<AdvisorConnectionStatus>? _connectivitySubscription;
  StreamSubscription<void>? _accountRestoreSubscription;
  int _accountViewGeneration = AccountAppDataEvents.viewGeneration;
  late final AppLifecycleListener _lifecycleListener;
  final List<File> _pendingPhotos = [];
  final _chatSessionStore = const AdvisorChatSessionStore();
  String _currentSessionId = DateTime.now().microsecondsSinceEpoch.toString();
  String? _animatedReplyId;
  AdvisorMessage? _replyingTo;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  AdvisorConnectionStatus _connectionStatus = AdvisorConnectionStatus.checking;
  bool _drainingSubmissionQueue = false;
  bool _showSupportingSources = false;
  int _availabilityGeneration = 0;
  String? _fieldId;
  String? _cropCycleId;
  String? _assessmentId;
  String? _scheduledContextSignature;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _geminiSettingsStore =
        widget.geminiSettingsStore ?? const SecureAdvisorGeminiSettingsStore();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _connectivityService =
        widget.connectivityService ?? InternetAdvisorConnectivityService();
    _controller =
        widget.controller ??
        AdvisorController(
          openChatService: GeminiAdvisorOpenChatService(
            settingsStore: _geminiSettingsStore,
          ),
          imageAnalysisService: AdvisorImageAnalysisService(
            _ownedImageModel = TwoStageFawCvService(),
          ),
          conversationStore: const FileAdvisorConversationStore(),
        );
    _controller.addListener(_handleConversationChanged);
    _accountRestoreSubscription = AccountAppDataEvents.restores.stream.listen((
      _,
    ) {
      final changed =
          _accountViewGeneration != AccountAppDataEvents.viewGeneration;
      _accountViewGeneration = AccountAppDataEvents.viewGeneration;
      if (changed) {
        _submissionQueue.clear();
        _pendingPhotos.clear();
        _replyingTo = null;
        _questionController.clear();
        _currentSessionId = DateTime.now().microsecondsSinceEpoch.toString();
      }
      if (_ownsController) {
        unawaited(
          _controller.reloadStoredConversation(accountChanged: changed),
        );
      }
      unawaited(_refreshGuideAvailability());
    });
    _connectivitySubscription = _connectivityService.statusChanges.listen(
      _handleConnectionChanged,
      onError: (_, _) =>
          _handleConnectionChanged(AdvisorConnectionStatus.offline),
    );
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_refreshGuideAvailability()),
    );
    unawaited(_refreshGuideAvailability());
    if (_ownsController) unawaited(_controller.restoreConversation());
    if (widget.initialQuestion != null &&
        widget.initialQuestion!.trim().isNotEmpty) {
      _questionController.text = widget.initialQuestion!.trim();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.languageCode =
        AppWords.of(context).language == AppLanguage.filipino ? 'fil' : 'en';
    if (!_ownsController) return;
    final database = Provider.of<AppDatabase?>(context, listen: false);
    final fields = Provider.of<FieldWorkspaceProvider?>(context);
    final assessments = Provider.of<AssessmentWorkspaceProvider?>(context);
    if (database != null) {
      final reviews = Provider.of<ExpertReviewService?>(context, listen: false);
      _controller.attachContextRepository(
        AdvisorContextRepository(
          database,
          readExpertReview: reviews?.assessmentReviewFacts,
        ),
      );
    }
    final workspace = fields?.activeWorkspace;
    _fieldId = widget.fieldId ?? workspace?.field.id;
    _cropCycleId = widget.cropCycleId ?? workspace?.cropCycle?.id;
    _assessmentId = widget.assessmentId ?? assessments?.currentAssessment?.id;
    final signature = '$_fieldId|$_cropCycleId|$_assessmentId';
    if (signature == _scheduledContextSignature) return;
    _scheduledContextSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || signature != _scheduledContextSignature) return;
      _loadContext();
    });
  }

  @override
  void didUpdateWidget(covariant AdvisorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      unawaited(_refreshGuideAvailability(checkConnection: false));
    }
    if (!_ownsController || widget.refreshToken == oldWidget.refreshToken) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadContext(force: true);
    });
  }

  @override
  void dispose() {
    _availabilityGeneration++;
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_accountRestoreSubscription?.cancel());
    _lifecycleListener.dispose();
    _controller.removeListener(_handleConversationChanged);
    if (_ownsController) _controller.dispose();
    final model = _ownedImageModel;
    if (model != null) {
      unawaited(
        model.close().catchError((Object error, StackTrace stack) {
          debugPrint('Advisor model cleanup failed: $error');
        }),
      );
    }
    _questionController.dispose();
    _questionFocusNode.dispose();
    _highlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  int _lastHandledMessageCount = 0;
  AdvisorReplyState _lastReplyState = AdvisorReplyState.idle;

  void _handleConversationChanged() {
    if (!mounted) return;
    final currentCount = _controller.messages.length;
    final currentReplyState = _controller.replyState;
    if (currentCount == _lastHandledMessageCount + 1 &&
        currentCount > 1 &&
        _controller.messages.last.role == AdvisorMessageRole.guide) {
      _animatedReplyId = _controller.messages.last.id;
    }
    final shouldScroll =
        currentCount > _lastHandledMessageCount ||
        (currentReplyState != AdvisorReplyState.idle &&
            _lastReplyState == AdvisorReplyState.idle);
    _lastHandledMessageCount = currentCount;
    _lastReplyState = currentReplyState;

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldScroll && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: AppMotion.standard,
          curve: Curves.easeOut,
        );
      }
      if (!_controller.isReplyPending && _submissionQueue.isNotEmpty) {
        unawaited(_drainSubmissionQueue());
      }
    });
  }

  void _submitQuestion() {
    final question = _questionController.text;
    final photos = List<File>.unmodifiable(_pendingPhotos);
    final replyContext = _replyingTo?.text;
    final replyToMessageId = _replyingTo?.id;
    if (question.trim().isEmpty && photos.isEmpty) return;
    _questionController.clear();
    setState(() {
      if (photos.isNotEmpty) _pendingPhotos.clear();
      _replyingTo = null;
    });
    _submissionQueue.add(
      _QueuedGuideSubmission(
        question: question.trim(),
        photos: photos,
        replyContext: replyContext,
        replyToMessageId: replyToMessageId,
      ),
    );
    unawaited(_drainSubmissionQueue());
  }

  void _replyToMessage(AdvisorMessage message) {
    setState(() => _replyingTo = message);
    _questionFocusNode.requestFocus();
  }

  Future<void> _jumpToMessage(String messageId) async {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: .18,
    );
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _drainSubmissionQueue() async {
    if (_drainingSubmissionQueue || !mounted) return;
    _drainingSubmissionQueue = true;
    try {
      while (mounted && _submissionQueue.isNotEmpty) {
        if (_controller.isReplyPending) return;
        final submission = _submissionQueue.removeAt(0);
        await _sendSubmission(submission);
      }
    } finally {
      _drainingSubmissionQueue = false;
      if (mounted &&
          !_controller.isReplyPending &&
          _submissionQueue.isNotEmpty) {
        unawaited(_drainSubmissionQueue());
      }
    }
  }

  Future<void> _sendSubmission(_QueuedGuideSubmission submission) async {
    if (_connectionStatus == AdvisorConnectionStatus.checking) {
      await _refreshGuideAvailability();
      if (!mounted) return;
    }
    final question = submission.question;
    final photos = submission.photos;
    if (photos.isEmpty) {
      // Let the online service report a recoverable availability/configuration
      // error. The normal chat experience must not silently become an offline
      // keyword guide.
      await _controller.ask(
        question,
        allowOpenChat: true,
        replyToText: submission.replyContext,
        replyToMessageId: submission.replyToMessageId,
      );
      return;
    }
    await _controller.askGeminiWithImages(question, photos);
    if (mounted) unawaited(_refreshGuideAvailability());
  }

  void _handleConnectionChanged(AdvisorConnectionStatus status) {
    if (!mounted || status == _connectionStatus) return;
    setState(() => _connectionStatus = status);
  }

  Future<void> _refreshGuideAvailability({bool checkConnection = true}) async {
    final generation = ++_availabilityGeneration;
    final connectionFuture = checkConnection
        ? _connectivityService.check()
        : Future.value(_connectionStatus);
    final status = await connectionFuture;
    AdvisorGeminiPreferences? preferences;
    try {
      preferences = await _geminiSettingsStore.loadPreferences();
    } catch (_) {
      /* Keep chat available if the preference store cannot be read. */
    }
    if (!mounted || generation != _availabilityGeneration) return;
    setState(() {
      _connectionStatus = status;
      if (preferences != null) {
        _showSupportingSources = preferences.showSupportingSources;
      }
    });
  }

  Future<void> _handleSuggestedAction(
    AdvisorMessage message,
    String action,
  ) async {
    if (message.modelFindings?.trim().isNotEmpty == true) {
      await _controller.askPhotoSuggestedAction(
        message,
        action,
        allowOpenChat: true,
      );
    } else {
      await _controller.askSuggestedAction(message, action);
    }
    if (mounted) {
      unawaited(_refreshGuideAvailability());
    }
  }

  Future<void> _attachPhoto({bool autoSubmit = false}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _PhotoSourceSheet(),
    );
    if (!mounted || source == null) return;
    try {
      final remaining = 5 - _pendingPhotos.length;
      if (remaining <= 0) {
        _showPhotoLimitMessage();
        return;
      }
      final List<XFile> selected;
      if (source == ImageSource.gallery) {
        selected = await _imagePicker.pickMultiImage(
          imageQuality: 92,
          limit: remaining,
        );
      } else {
        final photo = await _imagePicker.pickImage(
          source: source,
          imageQuality: 92,
        );
        selected = photo == null ? const [] : [photo];
      }
      if (!mounted || selected.isEmpty) return;
      final existing = _pendingPhotos.map((file) => file.path).toSet();
      final additions = selected
          .where((photo) => existing.add(photo.path))
          .take(remaining)
          .map((photo) => File(photo.path))
          .toList(growable: false);
      if (additions.isEmpty) return;

      if (autoSubmit) {
        final question = _questionController.text.trim();
        _questionController.clear();
        setState(_pendingPhotos.clear);
        _submissionQueue.add(
          _QueuedGuideSubmission(question: question, photos: additions),
        );
        unawaited(_drainSubmissionQueue());
      } else {
        setState(() => _pendingPhotos.addAll(additions));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('The selected photo could not be read.'),
        ),
      );
    }
  }

  void _showPhotoLimitMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: AppText('You can attach up to 5 photos.')),
    );
  }

  Future<void> _loadContext({bool force = false}) {
    if (!mounted) return Future<void>.value();
    return _controller.loadContext(
      fieldId: _fieldId,
      cropCycleId: _cropCycleId,
      preferredAssessmentId: _assessmentId,
      force: force,
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _loadContext(force: true);
    if (mounted) await _refreshGuideAvailability(checkConnection: false);
  }

  Future<void> _executeAction(AdvisorAppAction action) async {
    final fieldContext = _controller.fieldContext;
    var assessmentId = action.assessmentId;
    final fieldId = action.fieldId ?? fieldContext?.fieldId ?? _fieldId;
    final database = Provider.of<AppDatabase?>(context, listen: false);
    if (database == null &&
        const [
          'continue_assessment',
          'review_assessment',
          'view_results',
        ].contains(action.id)) {
      await _push(const AssessmentsScreen());
      return;
    }
    Map<String, dynamic>? record;
    if (database != null &&
        fieldId != null &&
        const [
          'continue_assessment',
          'review_assessment',
          'view_results',
        ].contains(action.id)) {
      final tools = AdvisorContextRepository(database);
      if (assessmentId == null) {
        final history = await tools.read('list_assessments', {
          'field_id': fieldId,
        });
        final rows = (history['assessments'] as List? ?? const [])
            .whereType<Map>();
        final eligible = rows.where(
          (r) => action.id == 'view_results'
              ? r['status'] == 'completed'
              : action.id == 'continue_assessment'
              ? const ['draft', 'in_progress'].contains(r['status'])
              : true,
        );
        if (eligible.isNotEmpty) assessmentId = eligible.first['id'] as String;
      }
      if (assessmentId != null) {
        record = await tools.read('get_assessment', {
          'field_id': fieldId,
          'assessment_id': assessmentId,
        });
      }
      if (!mounted) return;
      if (record?['assessment_id'] == null ||
          (action.id == 'view_results' && record?['status'] != 'completed') ||
          (action.id == 'continue_assessment' &&
              !const ['draft', 'in_progress'].contains(record?['status']))) {
        await _push(const AssessmentsScreen());
        return;
      }
    }
    switch (action.id) {
      case 'open_more':
        await _push(const MoreScreen());
        return;
      case 'open_profile':
        await _push(const MyProfileScreen());
        return;
      case 'open_trends':
        await _push(FieldTrendsScreen(initialFieldId: action.fieldId));
        return;
      case 'open_language':
        await _push(const LanguageScreen());
        return;
      case 'open_artificial_intelligence':
        await _push(const ArtificialIntelligenceScreen());
        return;
      case 'open_models':
        await _push(const ModelsScreen());
        return;
      case 'open_notifications':
        await _push(
          NotificationsScreen(
            onOpenAssess: () => _push(const AssessmentsScreen()),
          ),
        );
        return;
      case 'open_field':
        final fields = Provider.of<FieldWorkspaceProvider?>(
          context,
          listen: false,
        );
        final matches = fields?.workspaces.where(
          (w) => w.field.id == action.fieldId,
        );
        if (matches != null && matches.isNotEmpty) {
          await _push(FieldDetailsScreen(workspace: matches.first));
        } else {
          await _push(const FieldsScreen());
        }
        return;
      case 'open_home':
        final select = widget.onSelectDestination;
        if (select != null) {
          select(0);
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      case 'open_assess':
        final select = widget.onSelectDestination;
        if (select != null) {
          select(1);
        } else {
          await _push(const AssessmentsScreen());
        }
        return;
      case 'open_map':
        final select = widget.onSelectDestination;
        if (select != null) {
          select(2);
        } else {
          await _push(const BoundaryMapScreen());
        }
        return;
      case 'manage_fields':
        await _push(const FieldsScreen());
        return;
      case 'manage_boundary':
        await _push(const ManageFieldBoundaryScreen());
        return;
      case 'start_assessment':
        await _push(const AssessmentSetupScreen());
        return;
      case 'continue_assessment':
        if (assessmentId != null) {
          await _push(AssessmentSessionScreen(assessmentId: assessmentId));
        } else {
          await _push(const AssessmentSetupScreen());
        }
        return;
      case 'review_assessment':
        if (assessmentId != null) {
          await _push(
            record?['status'] == 'completed'
                ? AssessmentResultsScreen(assessmentId: assessmentId)
                : AssessmentDetailsScreen(assessmentId: assessmentId),
          );
        } else {
          await _push(const AssessmentsScreen());
        }
        return;
      case 'view_results':
        if (assessmentId != null) {
          await _push(AssessmentResultsScreen(assessmentId: assessmentId));
        } else {
          await _push(const AssessmentsScreen());
        }
        return;
      case 'open_guidelines':
        await _push(
          AdvisorOfflineGuidesScreen(initialArticleId: action.articleId),
        );
        return;
      case 'check_photo':
        await _attachPhoto(autoSubmit: true);
        return;
      case 'open_conditions':
        if (widget.onSelectDestination != null) {
          widget.onSelectDestination!(0);
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      case 'open_expert_review':
        await _push(const ExpertReviewScreen());
        return;
      case 'open_account':
        await _push(const AccountAccessScreen());
        return;
      default:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('That app action is not available.')),
        );
    }
  }

  bool get _canSwitchChats =>
      !_controller.isReplyPending && _submissionQueue.isEmpty;

  Future<void> _archiveCurrentChat() async {
    final messages = _controller.messages;
    if (messages.isEmpty) return;
    await _chatSessionStore.save(
      AdvisorChatSession(
        id: _currentSessionId,
        title: _titleForMessages(messages),
        updatedAt: DateTime.now(),
        messages: messages.map((message) => message.toStored()).toList(),
      ),
    );
  }

  Future<void> _startNewChat() async {
    if (!_canSwitchChats) return;
    try {
      await _archiveCurrentChat();
      if (!mounted) return;
      _controller.clear();
      _currentSessionId = DateTime.now().microsecondsSinceEpoch.toString();
      _questionController.clear();
      setState(() {
        _pendingPhotos.clear();
        _replyingTo = null;
        _animatedReplyId = null;
        _messageKeys.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not save this chat. Try again.'),
        ),
      );
    }
  }

  String get _currentChatTitle {
    if (!_controller.hasConversation) return 'New chat';
    return _titleForMessages(_controller.messages);
  }

  String _titleForMessages(List<AdvisorMessage> messages) {
    final questions = messages
        .where((message) => message.role == AdvisorMessageRole.farmer)
        .map((message) => message.text.trim());
    final value =
        questions.where((text) => text.length >= 12).firstOrNull ??
        questions.firstOrNull ??
        '';
    if (value.isEmpty) return 'Photo discussion';
    return value.length > 58 ? '${value.substring(0, 58)}…' : value;
  }

  Future<void> _showSavedChats() async {
    if (!_canSwitchChats) return;
    final sessions = await _chatSessionStore.load();
    if (!mounted) return;
    final selection = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => AdvisorChatsPage(
          sessions: sessions,
          currentTitle: _currentChatTitle,
          currentPreview: _controller.messages.isEmpty
              ? null
              : _controller.messages.last.text,
          hasCurrentChat: _controller.hasConversation,
        ),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == AdvisorChatNavigation.newChat) {
      await _startNewChat();
    } else if (selection is AdvisorChatSession) {
      await _openSavedChat(selection);
    }
  }

  Future<void> _openSavedChat(AdvisorChatSession selected) async {
    if (!_canSwitchChats) return;
    try {
      final restored = await _chatSessionStore.take(selected.id);
      if (restored == null) return;
      try {
        await _archiveCurrentChat();
      } catch (_) {
        await _chatSessionStore.save(restored);
        rethrow;
      }
      if (!mounted) {
        await _chatSessionStore.save(restored);
        return;
      }
      _currentSessionId = restored.id;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _controller.openSavedConversation(restored.messages);
      _questionController.clear();
      setState(() {
        _pendingPhotos.clear();
        _replyingTo = null;
        _animatedReplyId = null;
        _messageKeys.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not open that chat. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppText('Advisor'),
        actions: [
          IconButton(
            key: const Key('advisor_saved_chats_button'),
            tooltip: AppWords.of(context).translate('Chats'),
            onPressed: _canSwitchChats ? _showSavedChats : null,
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _controller.hasConversation
                  ? _ConversationList(
                      showSupportingSources: _showSupportingSources,
                      controller: _scrollController,
                      messages: _controller.messages,
                      animatedReplyId: _animatedReplyId,
                      onReplyRevealed: (id) {
                        if (mounted && _animatedReplyId == id) {
                          setState(() => _animatedReplyId = null);
                        }
                      },
                      replyState: _controller.replyState,
                      thinkingStage: _controller.thinkingStage,
                      error: _controller.replyError,
                      canRetry: _controller.canRetryOpenChat,
                      onRetry: () => _controller.retryOpenChat(),
                      onAppAction: (action) =>
                          unawaited(_executeAction(action)),
                      onSuggestedAction: (message, action) =>
                          unawaited(_handleSuggestedAction(message, action)),
                      onReply: _replyToMessage,
                      messageKeys: _messageKeys,
                      highlightedMessageId: _highlightedMessageId,
                      onOpenReplyTarget: (id) => unawaited(_jumpToMessage(id)),
                    )
                  : const _GuideWelcome(),
            ),
            _QuestionComposer(
              controller: _questionController,
              focusNode: _questionFocusNode,
              enabled: true,
              pendingPhotos: _pendingPhotos,
              replyingTo: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
              onRemovePhoto: (index) =>
                  setState(() => _pendingPhotos.removeAt(index)),
              onAttach: _attachPhoto,
              onSubmitted: (_) => _submitQuestion(),
              onSend: _submitQuestion,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuedGuideSubmission {
  const _QueuedGuideSubmission({
    required this.question,
    this.photos = const [],
    this.replyContext,
    this.replyToMessageId,
  });

  final String question;
  final List<File> photos;
  final String? replyContext;
  final String? replyToMessageId;
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4DBD4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppText(
            'Add a photo',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PhotoSourceOption(
                  key: const Key('guide_photo_camera_option'),
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PhotoSourceOption(
                  key: const Key('guide_photo_gallery_option'),
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PhotoSourceOption extends StatelessWidget {
  const _PhotoSourceOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF3F7F2),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: AppColors.highContrastGreen, size: 27),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.highContrastGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GuideWelcome extends StatelessWidget {
  const _GuideWelcome();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('guide_welcome_scroll_view'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height * .55,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.highContrastGreen,
                    size: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppText(
                  'How can I help?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppText(
                  'Ask about fall armyworm, your assessments, or how to use WormWise.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.showSupportingSources,
    required this.controller,
    required this.messages,
    required this.animatedReplyId,
    required this.onReplyRevealed,
    required this.replyState,
    required this.thinkingStage,
    required this.error,
    required this.canRetry,
    required this.onRetry,
    required this.onAppAction,
    required this.onSuggestedAction,
    required this.onReply,
    required this.messageKeys,
    required this.highlightedMessageId,
    required this.onOpenReplyTarget,
  });

  final ScrollController controller;
  final bool showSupportingSources;
  final List<AdvisorMessage> messages;
  final String? animatedReplyId;
  final ValueChanged<String> onReplyRevealed;
  final AdvisorReplyState replyState;
  final AdvisorThinkingStage? thinkingStage;
  final Object? error;
  final bool canRetry;
  final VoidCallback onRetry;
  final ValueChanged<AdvisorAppAction> onAppAction;
  final void Function(AdvisorMessage message, String action) onSuggestedAction;
  final ValueChanged<AdvisorMessage> onReply;
  final Map<String, GlobalKey> messageKeys;
  final String? highlightedMessageId;
  final ValueChanged<String> onOpenReplyTarget;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('guide_conversation_list'),
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount:
          messages.length + (replyState == AdvisorReplyState.idle ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final hasStatus = replyState != AdvisorReplyState.idle;
        if (hasStatus && index == 0) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.workflowMaxWidth,
              ),
              child: _ReplyStatus(
                state: replyState,
                thinkingStage: thinkingStage,
                error: error,
                canRetry: canRetry,
                onRetry: onRetry,
              ),
            ),
          );
        }
        final messageIndex =
            messages.length - 1 - (hasStatus ? index - 1 : index);
        final message = messages[messageIndex];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.workflowMaxWidth,
            ),
            child: _MessageBubble(
              showSupportingSources: showSupportingSources,
              key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
              message: message,
              animateSummary: message.id == animatedReplyId,
              onRevealComplete: () => onReplyRevealed(message.id),
              showSuggestions:
                  messageIndex == messages.length - 1 &&
                  replyState == AdvisorReplyState.idle,
              highlighted: highlightedMessageId == message.id,
              onOpenReplyTarget: onOpenReplyTarget,
              onAppAction: onAppAction,
              onSuggestedAction: (action) => onSuggestedAction(message, action),
              onReply: () => onReply(message),
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.showSupportingSources,
    super.key,
    required this.message,
    required this.animateSummary,
    required this.onRevealComplete,
    required this.showSuggestions,
    required this.onAppAction,
    required this.onSuggestedAction,
    required this.onReply,
    required this.highlighted,
    required this.onOpenReplyTarget,
  });

  final AdvisorMessage message;
  final bool showSupportingSources;
  final bool animateSummary;
  final VoidCallback onRevealComplete;
  final bool showSuggestions;
  final ValueChanged<AdvisorAppAction> onAppAction;
  final ValueChanged<String> onSuggestedAction;
  final VoidCallback onReply;
  final bool highlighted;
  final ValueChanged<String> onOpenReplyTarget;

  @override
  Widget build(BuildContext context) {
    final isFarmer = message.role == AdvisorMessageRole.farmer;
    final hasText = message.text.trim().isNotEmpty;
    return Semantics(
      container: true,
      label: isFarmer
          ? (hasText ? 'Your question' : 'Your photo')
          : 'WormWise guide response',
      child: Align(
        alignment: isFarmer ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * (isFarmer ? .80 : .90),
          ),
          child: Column(
            crossAxisAlignment: isFarmer
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isFarmer) ...[
                const _AdvisorIdentity(),
                const SizedBox(height: 8),
              ],
              if (message.allImagePaths.isNotEmpty) ...[
                _GuideMessageGallery(
                  imagePaths: message.allImagePaths,
                  boxes: message.detectionBoxes,
                ),
                if (hasText || !isFarmer) const SizedBox(height: AppSpacing.xs),
              ],
              if (hasText || !isFarmer)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? AppColors.primaryLight
                        : isFarmer
                        ? AppColors.highContrastGreen
                        : const Color(0xFFF3F7F2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: highlighted
                          ? AppColors.highContrastGreen
                          : isFarmer
                          ? AppColors.highContrastGreen
                          : AppColors.cardBorder,
                      width: highlighted ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: isFarmer
                        ? _FarmerMessageContent(
                            message: message,
                            onOpenReplyTarget: onOpenReplyTarget,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _GuideAnswer(
                                showSupportingSources: showSupportingSources,
                                answer: message.answer!,
                                animateSummary: animateSummary,
                                onRevealComplete: onRevealComplete,
                                showSuggestions: showSuggestions,
                                onSuggestedAction: onSuggestedAction,
                              ),
                              if (!animateSummary) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                AdvisorCompletionFade(
                                  child: _AssistantMessageActions(
                                    messageId: message.id,
                                    text: message.text,
                                    onReply: onReply,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              if (!isFarmer &&
                  !animateSummary &&
                  message.answer!.appActions.isNotEmpty) ...[
                const SizedBox(height: 9),
                AdvisorCompletionFade(
                  child: _AdvisorRouteActions(
                    actions: message.answer!.appActions,
                    onAppAction: onAppAction,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FarmerMessageContent extends StatelessWidget {
  const _FarmerMessageContent({
    required this.message,
    required this.onOpenReplyTarget,
  });

  final AdvisorMessage message;
  final ValueChanged<String> onOpenReplyTarget;

  @override
  Widget build(BuildContext context) {
    final replyId = message.replyToMessageId;
    final preview = message.replyPreview?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyId != null && preview != null && preview.isNotEmpty) ...[
          Material(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: AppRadii.controlBorder,
            child: InkWell(
              key: ValueKey('open_reply_target_${message.id}'),
              borderRadius: AppRadii.controlBorder,
              onTap: () => onOpenReplyTarget(replyId),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.white70, width: 3),
                  ),
                ),
                child: Text(
                  _plainAdvisorText(preview).replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: .88),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          message.text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white, height: 1.4),
        ),
      ],
    );
  }
}

class _AdvisorIdentity extends StatelessWidget {
  const _AdvisorIdentity();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppText(
        'WormWise',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.highContrastGreen,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _GuideMessageGallery extends StatelessWidget {
  const _GuideMessageGallery({required this.imagePaths, required this.boxes});

  final List<String> imagePaths;
  final List<ModelDetectionBox> boxes;

  @override
  Widget build(BuildContext context) {
    if (imagePaths.length == 1) {
      return _GuideMessageImage(
        key: const ValueKey('guide_message_photo_0'),
        imagePath: imagePaths.first,
        boxes: boxes
            .where((box) => box.sourcePath == imagePaths.first)
            .toList(growable: false),
        onTap: () => _showGuidePhotos(context, imagePaths, 0, boxes),
      );
    }
    return GridView.builder(
      key: const Key('guide_message_photo_grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: imagePaths.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) => Stack(
        fit: StackFit.expand,
        children: [
          _GuideMessageImage(
            key: ValueKey('guide_message_photo_$index'),
            imagePath: imagePaths[index],
            boxes: boxes
                .where((box) => box.sourcePath == imagePaths[index])
                .toList(growable: false),
            gridTile: true,
            onTap: () => _showGuidePhotos(context, imagePaths, index, boxes),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: AppText(
                '${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideMessageImage extends StatelessWidget {
  const _GuideMessageImage({
    super.key,
    required this.imagePath,
    required this.boxes,
    this.gridTile = false,
    this.onTap,
  });

  final String imagePath;
  final List<ModelDetectionBox> boxes;
  final bool gridTile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return const AppText(
        'Attached photo is no longer available on this phone.',
      );
    }
    final aspectRatio = boxes.isEmpty
        ? null
        : boxes.first.imageWidth / boxes.first.imageHeight;
    final image = ClipRRect(
      borderRadius: AppRadii.controlBorder,
      child: boxes.isEmpty
          ? Image.file(
              file,
              width: gridTile ? double.infinity : null,
              height: gridTile ? double.infinity : null,
              fit: gridTile ? BoxFit.cover : BoxFit.contain,
            )
          : ModelDetectionImage(
              file: file,
              boxes: boxes,
              fit: gridTile ? BoxFit.cover : BoxFit.contain,
            ),
    );
    final tappable = GestureDetector(
      key: ValueKey('open_guide_message_photo_$imagePath'),
      onTap: onTap ?? () => _showGuidePhotos(context, [imagePath], 0, boxes),
      child: image,
    );
    if (gridTile) return SizedBox.expand(child: tappable);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180, maxHeight: 240),
      child: aspectRatio == null
          ? tappable
          : AspectRatio(aspectRatio: aspectRatio, child: tappable),
    );
  }
}

class _AdvisorRouteActions extends StatelessWidget {
  const _AdvisorRouteActions({
    required this.actions,
    required this.onAppAction,
  });

  final List<AdvisorAppAction> actions;
  final ValueChanged<AdvisorAppAction> onAppAction;

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              elevation: 2,
              shadowColor: const Color(0x261D5D25),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: ValueKey('advisor_action_${action.id}'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => onAppAction(action),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 76),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDCE9DB)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F2E5),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          _advisorActionIcon(action.iconName),
                          size: 23,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              words.translate('OPEN IN WORMWISE'),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.9,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              words.translate(action.label),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GuideAnswer extends StatelessWidget {
  const _GuideAnswer({
    required this.showSupportingSources,
    required this.answer,
    required this.animateSummary,
    required this.onRevealComplete,
    required this.showSuggestions,
    required this.onSuggestedAction,
  });

  final AdvisorAnswer answer;
  final bool showSupportingSources;
  final bool animateSummary;
  final VoidCallback onRevealComplete;
  final bool showSuggestions;
  final ValueChanged<String> onSuggestedAction;

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    String display(String value) =>
        answer.topicId.startsWith('gemini') ? value : words.translate(value);
    return AdvisorReplyReveal(
      texts: [
        display(answer.title.trim()),
        display(answer.summary),
        ...answer.details.map(display),
        if (answer.nextAction != null) display(answer.nextAction!),
      ],
      animate: animateSummary,
      onComplete: onRevealComplete,
      builder: (context, visible, complete) =>
          _buildContent(context, visible, complete),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<String> visible,
    bool complete,
  ) {
    final displayTitle = visible[0];
    final words = AppWords.of(context);
    String display(String value) =>
        answer.topicId.startsWith('gemini') ? value : words.translate(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (displayTitle.isNotEmpty) ...[
          Text(displayTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
        ],
        AdvisorIllustratedReply(
          text: visible[1],
          articleIds: answer.visualArticleIds,
          showTrailingContent: complete,
          onOpenArticle: (articleId) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AdvisorOfflineGuidesScreen(initialArticleId: articleId),
            ),
          ),
        ),
        if (visible
            .skip(2)
            .take(answer.details.length)
            .any((s) => s.isNotEmpty)) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final detail
              in visible
                  .skip(2)
                  .take(answer.details.length)
                  .where((s) => s.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: AdvisorReplyContent(text: detail)),
                ],
              ),
            ),
        ],
        if (answer.nextAction != null && visible.last.isNotEmpty) ...[
          const Divider(),
          Text(
            visible.last,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.highContrastGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (complete &&
            showSupportingSources &&
            answer.supportingPassages.isNotEmpty) ...[
          const SizedBox(height: 16),
          AdvisorCompletionFade(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                leading: const Icon(
                  Icons.menu_book_outlined,
                  size: 21,
                  color: AppColors.primary,
                ),
                title: const AppText(
                  'Supporting sources',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${answer.supportingPassages.length} references',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: [
                  for (final passage in answer.supportingPassages)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Material(
                        color: const Color(0xFFF6F9F5),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AdvisorOfflineGuidesScreen(
                                initialArticleId: passage.articleId,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        passage.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        passage.quote,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.3,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (complete &&
            showSuggestions &&
            answer.suggestedActions.isNotEmpty) ...[
          const SizedBox(height: 14),
          AdvisorCompletionFade(
            child: Semantics(
              label: 'Suggested follow-up messages',
              child: Column(
                key: const Key('guide_suggestion_rail'),
                children: [
                  for (final suggestion in answer.suggestedActions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          key: ValueKey('guide_suggestion_$suggestion'),
                          borderRadius: BorderRadius.circular(13),
                          onTap: () => onSuggestedAction(suggestion),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    display(suggestion),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.highContrastGreen,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.north_east_rounded,
                                  size: 18,
                                  color: AppColors.highContrastGreen,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

IconData _advisorActionIcon(String name) => switch (name) {
  'home' => Icons.home_outlined,
  'assess' => Icons.fact_check_outlined,
  'map' => Icons.map_outlined,
  'field' => Icons.agriculture_outlined,
  'boundary' => Icons.polyline_outlined,
  'start' => Icons.play_circle_outline,
  'continue' => Icons.play_arrow_rounded,
  'review' => Icons.description_outlined,
  'results' => Icons.analytics_outlined,
  'guidelines' => Icons.menu_book_outlined,
  'photo' => Icons.add_a_photo_outlined,
  'weather' => Icons.cloud_outlined,
  'expert' => Icons.support_agent_outlined,
  'account' => Icons.account_circle_outlined,
  'settings' => Icons.settings_suggest_outlined,
  _ => Icons.arrow_forward_rounded,
};

String _plainAdvisorText(String text) {
  return AdvisorVisualReference.plainText(text)
      .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'^\s*#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '• ')
      .replaceAll(RegExp(r'\s*\((?:[A-Z][A-Z0-9-]*(?:,\s*)?)+\)'), '');
}

class _AssistantMessageActions extends StatelessWidget {
  const _AssistantMessageActions({
    required this.messageId,
    required this.text,
    required this.onReply,
  });

  final String messageId;
  final String text;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('copy_advisor_message_$messageId'),
          tooltip: AppWords.of(context).translate('Copy response'),
          visualDensity: VisualDensity.compact,
          iconSize: 19,
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: _plainAdvisorText(text).trim()),
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: AppText('Response copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          icon: const Icon(Icons.copy_all_outlined),
        ),
        IconButton(
          key: ValueKey('reply_to_advisor_message_$messageId'),
          tooltip: AppWords.of(context).translate('Reply to response'),
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onReply,
          icon: const Icon(Icons.reply_rounded),
        ),
      ],
    );
  }
}

class _QuestionComposer extends StatelessWidget {
  const _QuestionComposer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.pendingPhotos,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onRemovePhoto,
    required this.onAttach,
    required this.onSubmitted,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final List<File> pendingPhotos;
  final AdvisorMessage? replyingTo;
  final VoidCallback onCancelReply;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onAttach;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      shape: const Border(top: BorderSide(color: AppColors.cardBorder)),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.workflowMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (replyingTo != null) ...[
                    _ReplyPreview(
                      message: replyingTo!,
                      onCancel: onCancelReply,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  if (pendingPhotos.isNotEmpty) ...[
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: pendingPhotos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (context, index) =>
                            _PendingPhotoAttachment(
                              file: pendingPhotos[index],
                              index: index,
                              total: pendingPhotos.length,
                              onOpen: () => _showGuidePhotos(
                                context,
                                pendingPhotos.map((file) => file.path).toList(),
                                index,
                                const [],
                              ),
                              onRemove: () => onRemovePhoto(index),
                            ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F8F5),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  key: const Key('attach_guide_photo_button'),
                                  tooltip: AppWords.of(
                                    context,
                                  ).translate('Attach maize photo'),
                                  onPressed: enabled ? onAttach : null,
                                  icon: const Icon(Icons.add_rounded),
                                  color: AppColors.highContrastGreen,
                                ),
                                Expanded(
                                  child: TextField(
                                    key: const Key('guide_question_input'),
                                    controller: controller,
                                    focusNode: focusNode,
                                    enabled: enabled,
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: onSubmitted,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    decoration: InputDecoration(
                                      hintText: AppWords.of(
                                        context,
                                      ).translate('Ask WormWise'),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.fromLTRB(
                                        0,
                                        13,
                                        12,
                                        13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton.filled(
                          key: const Key('send_guide_question_button'),
                          tooltip: AppWords.of(
                            context,
                          ).translate('Send question'),
                          onPressed:
                              enabled &&
                                  (value.text.trim().isNotEmpty ||
                                      pendingPhotos.isNotEmpty)
                              ? onSend
                              : null,
                          constraints: const BoxConstraints(
                            minWidth: AppSizes.minimumTouchTarget,
                            minHeight: AppSizes.minimumTouchTarget,
                          ),
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.onCancel});

  final AdvisorMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final compact = _plainAdvisorText(
      message.text,
    ).trim().replaceAll(RegExp(r'\s+'), ' ');
    return Container(
      key: const Key('advisor_reply_preview'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: AppRadii.controlBorder,
        border: const Border(
          left: BorderSide(color: AppColors.highContrastGreen, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.reply_rounded,
            size: 18,
            color: AppColors.highContrastGreen,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'Replying',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.highContrastGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  compact,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('cancel_advisor_reply_button'),
            tooltip: AppWords.of(context).translate('Cancel reply'),
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _PendingPhotoAttachment extends StatelessWidget {
  const _PendingPhotoAttachment({
    required this.file,
    required this.index,
    required this.total,
    required this.onOpen,
    required this.onRemove,
  });

  final File file;
  final int index;
  final int total;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Material(
        key: ValueKey('pending_guide_photo_$index'),
        color: AppColors.primaryLight,
        borderRadius: AppRadii.controlBorder,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 92, maxHeight: 92),
          child: Stack(
            children: [
              Image.file(file, width: 92, height: 92, fit: BoxFit.cover),
              Positioned(
                left: 6,
                bottom: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: AppText(
                      '${index + 1}/$total',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton.filled(
                  key: const Key('remove_pending_guide_photo'),
                  tooltip: AppWords.of(
                    context,
                  ).translate('Remove attached photo'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showGuidePhotos(
  BuildContext context,
  List<String> imagePaths,
  int initialIndex,
  List<ModelDetectionBox> boxes,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _GuidePhotoViewer(
      imagePaths: imagePaths,
      initialIndex: initialIndex,
      boxes: boxes,
    ),
  );
}

class _GuidePhotoViewer extends StatefulWidget {
  const _GuidePhotoViewer({
    required this.imagePaths,
    required this.initialIndex,
    required this.boxes,
  });

  final List<String> imagePaths;
  final int initialIndex;
  final List<ModelDetectionBox> boxes;

  @override
  State<_GuidePhotoViewer> createState() => _GuidePhotoViewerState();
}

class _GuidePhotoViewerState extends State<_GuidePhotoViewer> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.imagePaths.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              key: const Key('guide_photo_page_view'),
              controller: _pageController,
              itemCount: widget.imagePaths.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) {
                final path = widget.imagePaths[index];
                final file = File(path);
                final boxes = widget.boxes
                    .where((box) => box.sourcePath == path)
                    .toList(growable: false);
                final aspectRatio = boxes.isEmpty
                    ? null
                    : boxes.first.imageWidth / boxes.first.imageHeight;
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: aspectRatio == null
                        ? Image.file(file, fit: BoxFit.contain)
                        : AspectRatio(
                            aspectRatio: aspectRatio,
                            child: ModelDetectionImage(
                              file: file,
                              boxes: boxes,
                              fit: BoxFit.contain,
                            ),
                          ),
                  ),
                );
              },
            ),
            if (widget.imagePaths.length > 1)
              Positioned(
                top: AppSpacing.md,
                left: 0,
                right: 0,
                child: Center(
                  child: Chip(
                    key: const Key('guide_photo_position'),
                    label: AppText(
                      '${_index + 1} / ${widget.imagePaths.length}',
                    ),
                    backgroundColor: Colors.black54,
                    labelStyle: const TextStyle(color: Colors.white),
                    side: BorderSide.none,
                  ),
                ),
              ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: IconButton.filled(
                tooltip: AppWords.of(context).translate('Close photo gallery'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyStatus extends StatelessWidget {
  const _ReplyStatus({
    required this.state,
    required this.thinkingStage,
    required this.error,
    required this.canRetry,
    required this.onRetry,
  });

  final AdvisorReplyState state;
  final AdvisorThinkingStage? thinkingStage;
  final Object? error;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AdvisorReplyState.idle => const SizedBox.shrink(),
      AdvisorReplyState.sending => _ThinkingIndicator(stage: thinkingStage),
      AdvisorReplyState.error => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88,
          ),
          child: Material(
            key: const Key('guide_open_chat_error'),
            color: const Color(0xFFFFF8E1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadii.card),
                topRight: const Radius.circular(AppRadii.card),
                bottomLeft: const Radius.circular(3),
                bottomRight: const Radius.circular(AppRadii.card),
              ),
              side: const BorderSide(color: Color(0xFFE8D18A)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF6F4E00),
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          AppWords.of(context).translate(_errorMessage(error)),
                        ),
                      ),
                    ],
                  ),
                  if (canRetry)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const Key('retry_guide_open_chat_button'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const AppText('Try again'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    };
  }

  static String _errorMessage(Object? error) {
    if (error is AdvisorGeminiNotConfiguredException) {
      return 'WormWise AI needs this app to be built with its Supabase URL and publishable key.';
    }
    if (error is AdvisorGeminiDisabledException) {
      return 'WormWise AI is currently unavailable.';
    }
    if (error is AdvisorGeminiApiException) return error.message;
    if (error is AdvisorOnlineUnavailableException) return error.message;
    return 'WormWise could not complete that response. Please try again.';
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.stage});

  final AdvisorThinkingStage? stage;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.stage) {
      AdvisorThinkingStage.analyzingPhoto => 'Checking the photo',
      AdvisorThinkingStage.preparingModelExplanation =>
        'Preparing photo guidance',
      _ => 'Preparing a reply',
    };
    return Semantics(
      liveRegion: true,
      label: AppWords.of(context).translate(title),
      child: Align(
        key: const Key('guide_open_chat_loading'),
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .90,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AdvisorIdentity(),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7F2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => Row(
                        children: [
                          for (var index = 0; index < 3; index++) ...[
                            if (index > 0) const SizedBox(width: 4),
                            Opacity(
                              opacity:
                                  .3 +
                                  .7 *
                                      (1 -
                                          (((_pulse.value + index / 3) % 1) -
                                                      .5)
                                                  .abs() *
                                              2),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.highContrastGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        AppWords.of(context).translate(title),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.highContrastGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
