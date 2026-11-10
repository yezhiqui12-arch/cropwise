import 'advisor_app_action.dart';
import '../scouting_sampling_protocol.dart';

/// Provenance attached to every response from the offline field guide.

class AdvisorKnowledgeSource {
  const AdvisorKnowledgeSource({
    required this.label,
    required this.reference,
    required this.version,
  });

  final String label;
  final String reference;
  final String version;
}

class AdvisorAnswer {
  const AdvisorAnswer({
    required this.topicId,
    required this.title,
    required this.summary,
    required this.details,
    required this.source,
    this.nextAction,
    this.suggestedActions = const [],
    this.appActions = const [],
    this.supportingPassages = const [],
    this.visualArticleIds = const [],
  });

  final String topicId;
  final String title;
  final String summary;
  final List<String> details;
  final AdvisorKnowledgeSource source;
  final String? nextAction;
  final List<String> suggestedActions;

  /// Validated WormWise capabilities rendered as explicit user-tappable tools.
  /// The language model never executes these directly.
  final List<AdvisorAppAction> appActions;
  final List<AdvisorSupportingPassage> supportingPassages;
  final List<String> visualArticleIds;
}

class AdvisorSupportingPassage {
  const AdvisorSupportingPassage({
    required this.articleId,
    required this.title,
    required this.quote,
    required this.claim,
    required this.version,
  });
  final String articleId;
  final String title;
  final String quote;
  final String claim;
  final String version;
  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'title': title,
    'quote': quote,
    'claim': claim,
    'version': version,
  };
  static AdvisorSupportingPassage? fromJson(Object? raw) {
    if (raw is! Map ||
        ![
          'articleId',
          'title',
          'quote',
          'claim',
          'version',
        ].every((key) => raw[key] is String)) {
      return null;
    }
    return AdvisorSupportingPassage(
      articleId: raw['articleId'] as String,
      title: raw['title'] as String,
      quote: raw['quote'] as String,
      claim: raw['claim'] as String,
      version: raw['version'] as String,
    );
  }
}

class AdvisorSuggestedQuestion {
  const AdvisorSuggestedQuestion({
    required this.id,
    required this.question,
    required this.iconName,
  });

  final String id;
  final String question;

  /// A semantic name interpreted by the presentation layer. Keeping Flutter
  /// types out of this service makes the knowledge engine easy to test.
  final String iconName;
}

/// Versioned, deterministic guidance that remains available without internet.
///
/// This service deliberately answers only approved topics. It does not invent
/// diagnoses, read assessment records, or provide pesticide instructions.
class AdvisorKnowledgeService {
  const AdvisorKnowledgeService();

  static const knowledgeVersion = 'wormwise-guide-da-2026.10';
  static const protocolVersion = ScoutingSamplingProtocol.daVersion;

  static const _protocolSource = AdvisorKnowledgeSource(
    label: 'Cropwise assessment protocol',
    reference:
        'DA-provided Harabas booklet, sampling page 5; current app workflow',
    version: protocolVersion,
  );

  static const suggestedQuestions = <AdvisorSuggestedQuestion>[
    AdvisorSuggestedQuestion(
      id: 'field_context',
      question: 'What is my current field status?',
      iconName: 'field',
    ),
    AdvisorSuggestedQuestion(
      id: 'assessment_explanation',
      question: 'Explain my latest assessment',
      iconName: 'assessment',
    ),
    AdvisorSuggestedQuestion(
      id: 'inspect_plant',
      question: 'How do I inspect a maize plant?',
      iconName: 'inspect',
    ),
    AdvisorSuggestedQuestion(
      id: 'frass',
      question: 'What does frass mean?',
      iconName: 'frass',
    ),
    AdvisorSuggestedQuestion(
      id: 'recognize_faw',
      question: 'How can I recognize FAW?',
      iconName: 'identify',
    ),
    AdvisorSuggestedQuestion(
      id: 'photos',
      question: 'How many photos can I take per plant?',
      iconName: 'photos',
    ),
    AdvisorSuggestedQuestion(
      id: 'uncertain',
      question: 'What if the damage is unclear?',
      iconName: 'uncertain',
    ),
    AdvisorSuggestedQuestion(
      id: 'expert_help',
      question: 'When should I contact a technician?',
      iconName: 'expert',
    ),
    AdvisorSuggestedQuestion(
      id: 'cultural_practices',
      question: 'What cultural practices help manage FAW?',
      iconName: 'cultural',
    ),
    AdvisorSuggestedQuestion(
      id: 'natural_predators',
      question: 'What natural predators control FAW?',
      iconName: 'predator',
    ),
  ];

  AdvisorAnswer answer(String question) {
    return tryAnswer(question) ?? unsupportedQuestionAnswer;
  }

  /// Returns a local answer only when the question matches an approved topic.
  ///
  /// Keeping an explicit no-match result lets the controller route genuinely
  /// open-ended questions to an optional remote service without weakening the
  /// deterministic safety and assessment routes.
  AdvisorAnswer? tryAnswer(String question) {
    final normalized = question.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // Consequential treatment language must win over broader terms such as
    // "plant" or "help" so it can never be routed to open chat by accident.
    final safetyAnswer = answerSafetyCritical(question);
    if (safetyAnswer != null) return safetyAnswer;

    if (_containsAny(normalized, const [
      'frass',
      'dropping',
      'waste',
      'dumi ng uod',
    ])) {
      return _frassAnswer;
    }
    if (_containsAny(normalized, const [
      'photo',
      'picture',
      'image',
      'camera',
      'two view',
      'larawan',
      'litrato',
    ])) {
      return _photosAnswer;
    }
    // Specific guidance topics must be matched before broad words such as
    // `help`, `faw`, or `armyworm`; otherwise the known card destination can
    // be stolen by the generic expert/identification routes.
    if (_containsAny(normalized, const [
      'cultural',
      'mechanical',
      'intercrop',
      'push-pull',
      'sanitation',
      'hygiene',
      'clean border',
      'practice',
      'pangkultura',
      'pamamahala',
    ])) {
      return _culturalPracticesAnswer;
    }
    if (_containsAny(normalized, const [
      'predator',
      'natural enemy',
      'beneficial',
      'biocontrol',
      'earwig',
      'trichogramma',
      'parasitoid',
      'spider',
      'likas na kaaway',
      'mandaragit',
      'gagamba',
    ])) {
      return _naturalPredatorsAnswer;
    }
    if (_containsAny(normalized, const [
      'technician',
      'expert',
      'agriculturist',
      'help',
      'escalat',
      'teknisyan',
      'eksperto',
    ])) {
      return _expertHelpAnswer;
    }
    if (_containsAny(normalized, const [
      'unclear',
      'uncertain',
      'not sure',
      'confus',
      'another pest',
      'hindi tiyak',
      'hindi sigurado',
    ])) {
      return _uncertainAnswer;
    }
    if (_containsAny(normalized, const [
      'recognize',
      'identify',
      'look like',
      'armyworm',
      'faw',
      'kilalanin',
    ])) {
      return _recognizeFawAnswer;
    }
    if (_containsAny(normalized, const [
      'inspect',
      'scout',
      'plant',
      'check first',
      'what should i check',
      'suriin',
      'halaman',
      'mais',
    ])) {
      return _inspectPlantAnswer;
    }
    return null;
  }

  AdvisorAnswer? answerByTopicId(String topicId) {
    switch (topicId) {
      case 'cultural_practices':
      case 'cultural_management':
        return _culturalPracticesAnswer;
      case 'natural_predators':
        return _naturalPredatorsAnswer;
      case 'recognize_faw':
        return _recognizeFawAnswer;
      case 'inspect_plant':
        return _inspectPlantAnswer;
      case 'frass':
        return _frassAnswer;
      case 'photos':
        return _photosAnswer;
      case 'uncertain':
        return _uncertainAnswer;
      case 'expert_help':
        return _expertHelpAnswer;
      case 'treatment_safety':
        return _treatmentAnswer;
      default:
        return null;
    }
  }

  AdvisorAnswer? answerSafetyCritical(String question) {
    final normalized = question.trim().toLowerCase();
    if (_containsAny(normalized, const [
      'pesticide',
      'spray',
      'chemical',
      'treatment',
      'dose',
      'dosage',
      'rate',
      'insecticide',
      'pestisidyo',
      'isprey',
      'gamot',
    ])) {
      return _treatmentAnswer;
    }
    return null;
  }

  AdvisorAnswer get unsupportedQuestionAnswer => _unknownAnswer;

  AdvisorAnswer answerSuggested(String topicId) {
    return switch (topicId) {
      'inspect_plant' => _inspectPlantAnswer,
      'frass' => _frassAnswer,
      'recognize_faw' => _recognizeFawAnswer,
      'photos' => _photosAnswer,
      'uncertain' => _uncertainAnswer,
      'expert_help' => _expertHelpAnswer,
      'cultural_practices' => _culturalPracticesAnswer,
      'natural_predators' => _naturalPredatorsAnswer,
      _ => _unknownAnswer,
    };
  }

  static bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }

  static const _inspectPlantAnswer = AdvisorAnswer(
    topicId: 'inspect_plant',
    title: 'Inspect the plant systematically',
    summary:
        'Check the newest leaves and whorl first, then look for fresh damage, frass, eggs, or a larva. Record what you actually observe—even when nothing is found.',
    details: [
      'Follow Guided scouting to inspect 20 dispersed plants per sampling block of at most 1 hectare.',
      'For vegetative maize, inspect the newest three or four leaves and the whorl.',
      'Separate fresh feeding from old damage and note possible non-FAW causes.',
      'Do not move to a more damaged plant because it looks more interesting.',
    ],
    nextAction: 'Open Assess to continue the guided field assessment.',
    source: _protocolSource,
  );

  static const _frassAnswer = AdvisorAnswer(
    topicId: 'frass',
    title: 'Frass is insect waste',
    summary:
        'Fresh, coarse frass in the maize whorl can support evidence of recent caterpillar feeding, but frass alone does not confirm fall armyworm.',
    details: [
      'Record whether the frass appears fresh and where it was found.',
      'Look for feeding damage and, when possible, a clear view of the organism.',
      'Frass coming from a stalk or cob borehole may support another pest such as Asian corn borer.',
    ],
    source: _protocolSource,
  );

  static const _recognizeFawAnswer = AdvisorAnswer(
    topicId: 'recognize_faw',
    title: 'Damage alone cannot confirm FAW',
    summary:
        'Windowpanes, shot holes, ragged whorl feeding, and coarse frass are FAW-consistent signs. Confirming the species requires clear organism evidence or qualified expert review.',
    details: [
      'A supporting larval view may show a pale inverted Y on the head.',
      'Four raised dark spots forming a square near the rear are another important feature.',
      'The head, body, and rear views must belong to the same specimen.',
      'An inverted Y by itself is not enough to confirm FAW.',
    ],
    nextAction:
        'If a larva is present, capture the whole body, head, and rear markings without touching an unknown organism.',
    source: _protocolSource,
  );

  static const _photosAnswer = AdvisorAnswer(
    topicId: 'photos',
    title: 'Different photos answer different questions',
    summary:
        'Capture or import one to three photos for the same plant. Add a closer view when it helps show the damage or organism clearly.',
    details: [
      'Overview: show the target plant part and surrounding context.',
      'Close-up: show fresh damage, frass, the whorl interior, or other evidence.',
      'Identification view: add a third photo when a larva, egg mass, or hidden symptom matters.',
      'Batch import assigns photos to individual plants before processing. Several photos of one plant still count as one sample.',
    ],
    source: _protocolSource,
  );

  static const _uncertainAnswer = AdvisorAnswer(
    topicId: 'uncertain',
    title: 'Keep uncertain evidence uncertain',
    summary:
        'Capture a clearer view of the same plant or check its saved photos and model result. Do not force unclear damage into a FAW diagnosis.',
    details: [
      'Note freshness, affected plant part, damage pattern, and any organism evidence.',
      'Consider other pests, disease-like symptoms, weather, mechanical damage, and crop stress.',
      'Plant overview offers an optional correction for DA report presence observations. This does not change the original model prediction or expert grade.',
    ],
    nextAction:
        'Capture another useful view or request qualified review when the identification affects treatment or safety.',
    source: _protocolSource,
  );

  static const _expertHelpAnswer = AdvisorAnswer(
    topicId: 'expert_help',
    title: 'Request qualified review when consequences matter',
    summary:
        'Contact a municipal agriculturist or qualified crop technician when identification remains uncertain or would affect treatment, certification, food safety, seed use, or insurance.',
    details: [
      'Escalate possible unusual outbreaks or materially mixed infestations.',
      'Request review when AI and evaluator findings conflict on an important case.',
      'Stem, ear, laboratory, or molecular examination may require specialist support.',
    ],
    source: _protocolSource,
  );

  static const _treatmentAnswer = AdvisorAnswer(
    topicId: 'treatment_safety',
    title: 'Cropwise does not prescribe pesticide treatment',
    summary:
        'Do not choose or apply a pesticide from an image result or this guide alone. Use confirmed field observations and consult current product labels and qualified local agricultural guidance.',
    details: [
      'Image confidence is not a treatment threshold.',
      'Check treatment history and required re-entry restrictions before entering a field.',
      'Product choice, rate, timing, protective equipment, and legal registration require authoritative local information.',
    ],
    nextAction:
        'Contact a qualified agricultural professional before making a consequential treatment decision.',
    source: _protocolSource,
  );

  static const _culturalPracticesAnswer = AdvisorAnswer(
    topicId: 'cultural_practices',
    title: 'Cultural and mechanical management practices',
    summary:
        'Cultural methods, field sanitation, intercropping, and manual egg/larva removal provide effective non-chemical population suppression under the Cagayan Valley protocol.',
    details: [
      'Handpick visible egg masses and young caterpillars in the whorl during early vegetative stages (VE–V6).',
      'Maintain clean field margins and remove alternative weed grass hosts that shelter armyworm moths.',
      'Practice push-pull intercropping with companion crops like Desmodium and border trap crops.',
      'Deep tillage after harvest exposes pupae to solar heat and predatory birds.',
      'Avoid excessive nitrogen fertilization which produces overly lush foliage attractive to moths.',
    ],
    nextAction:
        'Incorporate non-chemical cultural practices into your routine field maintenance.',
    source: _protocolSource,
  );

  static const _naturalPredatorsAnswer = AdvisorAnswer(
    topicId: 'natural_predators',
    title: 'Conserve natural enemies and predators',
    summary:
        'Beneficial predators and biological control agents significantly reduce FAW survival. Protecting them helps prevent secondary pest flare-ups.',
    details: [
      'Earwigs (Chelisoches morio) are nocturnal predators that crawl into whorls to consume egg masses and young larvae.',
      'Minute pirate bugs (Orius spp.) and spiders hunt neonates and small caterpillars on leaves.',
      'Microscopic parasitoid wasps (Trichogramma spp.) parasitize FAW eggs before larvae can hatch.',
      'Avoid broad-spectrum chemical sprays that destroy beneficial insect populations in your maize field.',
      'Encourage flowering border plants to provide nectar and shelter for adult parasitoids.',
    ],
    nextAction:
        'Observe whether beneficial predators are present during plant whorl inspection.',
    source: _protocolSource,
  );

  static const _unknownAnswer = AdvisorAnswer(
    topicId: 'unknown',
    title: 'This offline guide has a focused scope',
    summary:
        'I can explain Cropwise scouting, FAW-consistent signs, field photographs, uncertain damage, and when to request expert help.',
    details: [
      'Try one of the suggested questions below.',
      'You can also ask for the selected field status or latest saved assessment explanation.',
    ],
    source: AdvisorKnowledgeSource(
      label: 'Cropwise offline guide',
      reference: 'Built-in supported topics',
      version: knowledgeVersion,
    ),
  );
}
