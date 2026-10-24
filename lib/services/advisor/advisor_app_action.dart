/// A deterministic capability exposed by the WormWise Advisor.
///
/// The model may recommend one of these IDs, but only the Flutter application
/// resolves and executes it. This keeps navigation and future write operations
/// behind typed, auditable application code.
class AdvisorAppAction {
  const AdvisorAppAction({
    required this.id,
    required this.label,
    required this.description,
    required this.iconName,
    this.requiresConfirmation = false,
    this.fieldId,
    this.assessmentId,
    this.articleId,
  });

  final String id;
  final String label;
  final String description;
  final String? fieldId;
  final String? assessmentId;
  final String? articleId;

  AdvisorAppAction withTarget({
    String? fieldId,
    String? assessmentId,
    String? articleId,
    String? label,
  }) => AdvisorAppAction(
    id: id,
    label: label ?? this.label,
    description: description,
    iconName: iconName,
    requiresConfirmation: requiresConfirmation,
    fieldId: fieldId,
    assessmentId: assessmentId,
    articleId: articleId,
  );

  /// Semantic icon name interpreted by the presentation layer.
  final String iconName;

  /// Reserved for future mutating tools. Navigation actions are read-only.
  final bool requiresConfirmation;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'description': description,
    'iconName': iconName,
    'requiresConfirmation': requiresConfirmation,
    'fieldId': fieldId,
    'assessmentId': assessmentId,
    'articleId': articleId,
  };

  static AdvisorAppAction? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    if (id is! String) return null;
    return AdvisorAppActionCatalog.byId(id)?.withTarget(
      label: value['label'] is String ? value['label'] as String : null,
      fieldId: value['fieldId'] is String ? value['fieldId'] as String : null,
      assessmentId: value['assessmentId'] is String
          ? value['assessmentId'] as String
          : null,
      articleId: value['articleId'] is String
          ? value['articleId'] as String
          : null,
    );
  }
}

/// The single source of truth for actions an Advisor answer may expose.
///
/// Descriptions are intentionally written as tool descriptions: they are also
/// supplied to the online planner so it can choose a valid action without
/// inventing routes that do not exist.
abstract final class AdvisorAppActionCatalog {
  static const openHome = AdvisorAppAction(
    id: 'open_home',
    label: 'Open Home',
    description: 'Show the selected field overview and current next step.',
    iconName: 'home',
  );
  static const openAssess = AdvisorAppAction(
    id: 'open_assess',
    label: 'Open Assess',
    description: 'Show assessment setup, active work, and saved history.',
    iconName: 'assess',
  );
  static const openMap = AdvisorAppAction(
    id: 'open_map',
    label: 'Open Map',
    description: 'Show the selected field and its approximate outline.',
    iconName: 'map',
  );
  static const manageFields = AdvisorAppAction(
    id: 'manage_fields',
    label: 'Manage fields',
    description:
        'Open My Fields directly, also available from More > My Fields.',
    iconName: 'field',
  );
  static const manageBoundary = AdvisorAppAction(
    id: 'manage_boundary',
    label: 'Manage field outline',
    description:
        'Open the field-boundary editor for the selected field. The Map tab shows field geography; My Fields and Home also lead into boundary setup.',
    iconName: 'boundary',
  );
  static const startAssessment = AdvisorAppAction(
    id: 'start_assessment',
    label: 'Start assessment',
    description: 'Open assessment setup and the field-entry safety check.',
    iconName: 'start',
  );
  static const continueAssessment = AdvisorAppAction(
    id: 'continue_assessment',
    label: 'Continue assessment',
    description: 'Resume the selected field’s current saved assessment.',
    iconName: 'continue',
  );
  static const reviewAssessment = AdvisorAppAction(
    id: 'review_assessment',
    label: 'Review assessment',
    description: 'Open the latest assessment record and its saved progress.',
    iconName: 'review',
  );
  static const viewResults = AdvisorAppAction(
    id: 'view_results',
    label: 'View results',
    description:
        'Open completed assessment Results. Its Export menu includes Save or Share Assessment PDF. The user chooses export options and sharing; this action only opens Results.',
    iconName: 'results',
  );
  static const openGuidelines = AdvisorAppAction(
    id: 'open_guidelines',
    label: 'Browse FAW guidelines',
    description: 'Open Guidelines from More; technical review is pending.',
    iconName: 'guidelines',
  );
  static const checkPhoto = AdvisorAppAction(
    id: 'check_photo',
    label: 'Check a maize photo',
    description: 'Choose a camera or gallery image for on-device analysis.',
    iconName: 'photo',
  );
  static const openConditions = AdvisorAppAction(
    id: 'open_conditions',
    label: 'View field conditions',
    description:
        'Open Home to inspect available field-condition context. No dedicated conditions screen exists.',
    iconName: 'weather',
  );
  static const openExpertReview = AdvisorAppAction(
    id: 'open_expert_review',
    label: 'Expert review messages',
    description: 'Open submitted expert cases and reviewer messages.',
    iconName: 'expert',
  );
  static const openAccount = AdvisorAppAction(
    id: 'open_account',
    label: 'Account and sync',
    description: 'Open account access and optional cloud-sync settings.',
    iconName: 'account',
  );
  static const openMore = AdvisorAppAction(
    id: 'open_more',
    label: 'Open More',
    description: 'Open workspace tools, preferences, help and app information.',
    iconName: 'more',
  );
  static const openProfile = AdvisorAppAction(
    id: 'open_profile',
    label: 'My profile',
    description: 'Open the user profile.',
    iconName: 'account',
  );
  static const openTrends = AdvisorAppAction(
    id: 'open_trends',
    label: 'Field trends',
    description: 'Compare recorded monthly field trends.',
    iconName: 'results',
  );
  static const openLanguage = AdvisorAppAction(
    id: 'open_language',
    label: 'Change language',
    description: 'Open More > Language.',
    iconName: 'more',
  );
  static const openArtificialIntelligence = AdvisorAppAction(
    id: 'open_artificial_intelligence',
    label: 'Artificial Intelligence preferences',
    description:
        'Open More > Preferences > Artificial Intelligence to configure optional supporting sources.',
    iconName: 'more',
  );
  static const openModels = AdvisorAppAction(
    id: 'open_models',
    label: 'Models and detection preferences',
    description: 'Open More > Models and implemented detection preferences.',
    iconName: 'photo',
  );
  static const openNotifications = AdvisorAppAction(
    id: 'open_notifications',
    label: 'Notifications',
    description: 'Open recorded app notifications.',
    iconName: 'more',
  );
  static const openField = AdvisorAppAction(
    id: 'open_field',
    label: 'Field details',
    description:
        'Open a specific saved field; supply a field ID from app records.',
    iconName: 'field',
  );
  static const all = <AdvisorAppAction>[
    openMore,
    openProfile,
    openTrends,
    openLanguage,
    openModels,
    openArtificialIntelligence,
    openNotifications,
    openField,
    openHome,
    openAssess,
    openMap,
    manageFields,
    manageBoundary,
    startAssessment,
    continueAssessment,
    reviewAssessment,
    viewResults,
    openGuidelines,
    checkPhoto,
    openConditions,
    openExpertReview,
    openAccount,
  ];

  static AdvisorAppAction? byId(String id) {
    for (final action in all) {
      if (action.id == id) return action;
    }
    return null;
  }

  static String get plannerDescription =>
      all.map((action) => '${action.id}: ${action.description}').join('\n');

  /// Canonical, code-owned location guidance for implemented destinations.
  /// This prevents a model from inventing a menu or screen that is not wired.
  static String guidanceFor(AdvisorAppAction action) => switch (action.id) {
    'manage_fields' =>
      'To find or manage your maize fields, open More > My Fields.\n\n'
          'For instant navigation, tap Manage fields below.',
    'manage_boundary' =>
      'To change a field boundary:\n'
          '1. Open More.\n'
          '2. Choose My Fields.\n'
          '3. Select the field, then open its boundary editor.\n\n'
          'For instant navigation, tap Manage field outline below.',
    'open_home' =>
      'To view the selected field overview, tap Home in the bottom navigation. You can also tap Open Home below.',
    'open_assess' =>
      'To open your assessments:\n'
          '1. Tap Assess in the bottom navigation.\n'
          '2. Choose active work, assessment history, or a saved result.\n\n'
          'For instant navigation, tap Open Assess below.',
    'open_map' =>
      'To view the field map, tap Map in the bottom navigation. For instant navigation, tap Open Map below.',
    'continue_assessment' =>
      'To continue manually, open Assess and select the current in-progress assessment. For instant navigation, tap Continue assessment below.',
    'start_assessment' =>
      'To start an assessment:\n'
          '1. Open Assess.\n'
          '2. Choose the option to start an assessment.\n'
          '3. Complete setup and the field-entry safety check.\n\n'
          'For instant navigation, tap Start assessment below.',
    'review_assessment' =>
      'To review it manually, open Assess and select the saved assessment. For instant navigation, tap Review assessment below.',
    'view_results' =>
      'To find completed results, open Assess, choose assessment history, and select the completed assessment. For instant navigation, tap View results below.',
    'open_guidelines' =>
      'To open Guidelines, open More > Guidelines.\n\n'
          'For instant navigation, tap Browse FAW guidelines below.',
    'check_photo' =>
      'To attach a maize photo here, tap the paperclip beside the message box and choose Camera or Gallery. You can also tap Check a maize photo below.',
    'open_conditions' =>
      'To inspect available field conditions, open Home.\n\n'
          'For instant navigation, tap View field conditions below.',
    'open_expert_review' =>
      'To see expert review messages, open Assess and tap the message icon in the top-right corner. For instant navigation, tap Expert review messages below.',
    'open_account' =>
      'To open account access:\n'
          '1. Open More.\n'
          '2. Tap My Profile.\n\n'
          'For instant navigation, tap Account and sync below.',
    _ => action.description,
  };
}

/// Enforces the product rule that navigation is offered only for explicit
/// user requests to open, continue, start, view, manage, or change something.
/// Model output is always treated as untrusted input.
abstract final class AdvisorAppActionPolicy {
  static List<AdvisorAppAction> validateForUserRequest(
    String request,
    Iterable<AdvisorAppAction> proposed,
  ) {
    final text = request.trim().toLowerCase();
    if (!_hasExplicitActionIntent(text)) return const [];
    // A rejection of the previous answer is not another request to navigate.
    if (RegExp(
      r"\b(didn['’]?t|did not|don['’]?t|do not|not asking|never asked)\b",
    ).hasMatch(text)) {
      return const [];
    }

    final allowedIds = <String>{};
    void allow(AdvisorAppAction action) => allowedIds.add(action.id);

    if (_containsAny(text, const [
      'more',
      'preferences',
      'help',
      'support',
      'about',
    ])) {
      allow(AdvisorAppActionCatalog.openMore);
    }
    if (_containsAny(text, const ['profile'])) {
      allow(AdvisorAppActionCatalog.openProfile);
    }
    if (_containsAny(text, const [
      'trend',
      'trends',
      'comparison',
      'compare',
    ])) {
      allow(AdvisorAppActionCatalog.openTrends);
    }
    if (_containsAny(text, const ['language', 'filipino', 'english'])) {
      allow(AdvisorAppActionCatalog.openLanguage);
    }
    if (_containsAny(text, const [
      'artificial intelligence',
      'supporting sources',
      'ai preferences',
    ])) {
      allow(AdvisorAppActionCatalog.openArtificialIntelligence);
    }
    if (_containsAny(text, const ['model', 'models', 'detection'])) {
      allow(AdvisorAppActionCatalog.openModels);
    }
    if (_containsAny(text, const ['notification', 'notifications'])) {
      allow(AdvisorAppActionCatalog.openNotifications);
    }

    if (_containsAny(text, const ['boundary', 'outline', 'polygon'])) {
      allow(AdvisorAppActionCatalog.manageBoundary);
    }
    if (_containsAny(text, const ['map'])) {
      allow(AdvisorAppActionCatalog.openMap);
    }
    if (_containsAny(text, const ['continue', 'resume'])) {
      allow(AdvisorAppActionCatalog.continueAssessment);
    }
    if (_containsAny(text, const ['start', 'begin', 'new assessment'])) {
      allow(AdvisorAppActionCatalog.startAssessment);
    }
    if (_containsAny(text, const ['result', 'results'])) {
      allow(AdvisorAppActionCatalog.viewResults);
    }
    if (_containsAny(text, const ['pdf', 'export', 'report'])) {
      allow(AdvisorAppActionCatalog.viewResults);
    }
    if (_containsAny(text, const ['assessment', 'assess', 'record'])) {
      allow(AdvisorAppActionCatalog.openAssess);
      allow(AdvisorAppActionCatalog.reviewAssessment);
    }
    if (_containsAny(text, const ['field', 'fields'])) {
      allow(AdvisorAppActionCatalog.openField);
      allow(AdvisorAppActionCatalog.manageFields);
    }
    if (_containsAny(text, const ['photo', 'camera', 'gallery', 'image'])) {
      allow(AdvisorAppActionCatalog.checkPhoto);
    }
    if (_containsAny(text, const ['weather', 'conditions'])) {
      allow(AdvisorAppActionCatalog.openConditions);
    }
    if (_containsAny(text, const ['expert', 'reviewer', 'technician'])) {
      allow(AdvisorAppActionCatalog.openExpertReview);
    }
    if (_containsAny(text, const ['account', 'sync', 'sign in', 'login'])) {
      allow(AdvisorAppActionCatalog.openAccount);
    }
    if (_containsAny(text, const ['home', 'overview'])) {
      allow(AdvisorAppActionCatalog.openHome);
    }
    if (_containsAny(text, const [
      'guideline',
      'guidelines',
      'reference',
      'references',
      'library',
    ])) {
      allow(AdvisorAppActionCatalog.openGuidelines);
    }

    if (allowedIds.length > 1) {
      allowedIds.remove(AdvisorAppActionCatalog.openMore.id);
    }

    final validated = proposed
        .where((action) => allowedIds.contains(action.id))
        .take(1)
        .toList(growable: false);
    if (validated.isNotEmpty || allowedIds.isEmpty) return validated;

    // For a single clear destination, recover when the model answered in text
    // but forgot the action ID. The first match follows the specificity order
    // above (for example boundary before map, continue before Assess).
    final fallback = AdvisorAppActionCatalog.byId(allowedIds.first);
    return fallback == null ? const [] : [fallback];
  }

  static bool _hasExplicitActionIntent(String value) =>
      _containsAny(value, const [
        'open',
        'go to',
        'take me',
        'show me',
        'continue',
        'resume',
        'start',
        'begin',
        'view',
        'where',
        'find',
        'access',
        'link',
        'button',
        'how do i',
        'how can i',
        'steps',
        'manage',
        'change',
        'edit',
        'add',
        'select',
        'switch',
        'check a photo',
        'upload',
      ]);

  static bool _containsAny(String value, List<String> terms) => terms.any(
    (term) => RegExp(r'\b' + RegExp.escape(term) + r'\b').hasMatch(value),
  );
}
