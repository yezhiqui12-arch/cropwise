import '../../localization/literal_translations_guide.dart';
import 'advisor_assessment_contract.dart';

enum AdvisorEvidenceGrade {
  verifiedCore,
  operationalRule,
  expertValidationRequired,
}

class AdvisorReferenceSource {
  const AdvisorReferenceSource({
    required this.id,
    required this.label,
    required this.reference,
    required this.jurisdiction,
    this.publisher,
    this.locator,
    this.publicUrl,
    this.verifiedOn,
  });

  final String id;
  final String label;
  final String reference;
  final String jurisdiction;
  final String? publisher;
  final String? locator;
  final String? publicUrl;

  /// ISO date of an actual source check, separate from agronomic approval.
  final String? verifiedOn;

  bool get hasVerifiedReference => verifiedOn != null;
}

class AdvisorGuideVisual {
  const AdvisorGuideVisual({
    required this.asset,
    required this.title,
    required this.caption,
    this.credit,
    this.sourceUrl,
    this.figureNumber,
  });
  final String asset;
  final String title;
  final String caption;
  final String? credit;
  final String? sourceUrl;
  final int? figureNumber;
}

class AdvisorKnowledgeChunk {
  const AdvisorKnowledgeChunk({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.body,
    required this.keywords,
    required this.sourceIds,
    required this.grade,
    this.warning,
    this.country = 'PH',
    this.crop = 'maize',
    this.growthStages = const [],
    this.steps = const [],
    this.lookFor = const [],
    this.doNotAssume = const [],
    this.safetyWarnings = const [],
    this.escalateWhen = const [],
    this.relatedArticleIds = const [],
    this.visuals = const [],
    this.contentVersion = '1.0.0',
    this.reviewedOn,
    this.reviewDueOn,
    this.reviewedBy = 'Pending qualified Philippine technical review',
    this.jurisdiction = 'PH with cited international general guidance',
  });

  final String id;
  final String title;
  final String category;
  final String summary;
  final String body;
  final List<String> keywords;
  final List<String> sourceIds;
  final AdvisorEvidenceGrade grade;
  final String? warning;
  final String country;
  final String crop;
  final List<String> growthStages;
  final List<String> steps;
  final List<String> lookFor;
  final List<String> doNotAssume;
  final List<String> safetyWarnings;
  final List<String> escalateWhen;
  final List<String> relatedArticleIds;
  final List<AdvisorGuideVisual> visuals;
  final String contentVersion;
  final DateTime? reviewedOn;
  final DateTime? reviewDueOn;
  final String reviewedBy;
  final String jurisdiction;

  /// Public article text. AI behavior rules live in AdvisorFawAnswerPolicy.
  String get readerSummary => summary;
  String get readerBody => body;

  /// Content is publishable as actionable offline guidance only after a named
  /// qualified reviewer records a current review. Validation-required material
  /// remains explanatory even after ordinary editorial review.
  bool get isPublishable {
    final now = DateTime.now();
    return grade != AdvisorEvidenceGrade.expertValidationRequired &&
        reviewedOn != null &&
        reviewDueOn != null &&
        !reviewDueOn!.isBefore(now) &&
        reviewedBy != 'Pending qualified Philippine technical review';
  }

  bool get isReviewOverdue =>
      reviewDueOn != null && reviewDueOn!.isBefore(DateTime.now());
}

class AdvisorRetrievedChunk {
  const AdvisorRetrievedChunk({required this.chunk, required this.score});

  final AdvisorKnowledgeChunk chunk;
  final double score;
}

class AdvisorRagContext {
  const AdvisorRagContext({
    required this.query,
    required this.results,
    required this.sources,
  });

  final String query;
  final List<AdvisorRetrievedChunk> results;
  final Map<String, AdvisorReferenceSource> sources;

  bool get isEmpty => results.isEmpty;

  AdvisorRagContext bounded({int maxCharacters = 12000}) {
    final selected = <AdvisorRetrievedChunk>[];
    for (final result in results) {
      final candidate = AdvisorRagContext(
        query: query,
        results: [...selected, result],
        sources: sources,
      );
      if (candidate.toPromptText().length <= maxCharacters) {
        selected.add(result);
      }
    }
    return AdvisorRagContext(
      query: query,
      results: List.unmodifiable(selected),
      sources: sources,
    );
  }

  String get sourceSummary {
    final ids = results.expand((result) => result.chunk.sourceIds).toSet();
    return ids.map((id) => sources[id]?.label ?? id).join('; ');
  }

  String toPromptText() {
    if (results.isEmpty) return '';
    final buffer = StringBuffer(
      'WORMWISE CURATED REFERENCE CONTEXT — TECHNICAL REVIEW PENDING\n'
      'Use only relevant claims below for FAW guidance. The evidence grade and '
      'jurisdiction are binding. Do not turn validation-required material into '
      'field instructions. If actionable publication status is false, use the '
      'passage only for cautious explanation, not a recommendation. Use source '
      'IDs internally to track support for factual FAW claims.\n',
    );
    for (final result in results) {
      final chunk = result.chunk;
      buffer
        ..writeln('\n[${chunk.id}] ${chunk.title}')
        ..writeln('Category: ${chunk.category}')
        ..writeln('Evidence: ${chunk.grade.name}')
        ..writeln('Jurisdiction: ${chunk.jurisdiction}')
        ..writeln('Technical review: ${chunk.reviewedBy}')
        ..writeln('Actionable publication status: ${chunk.isPublishable}')
        ..writeln('Sources: ${chunk.sourceIds.join(', ')}')
        ..writeln(chunk.summary)
        ..writeln(chunk.body);
      if (chunk.steps.isNotEmpty) {
        buffer.writeln('Steps: ${chunk.steps.join(' | ')}');
      }
      if (chunk.visuals.isNotEmpty) {
        buffer.writeln(
          'Available visual article ID: ${chunk.id}. Illustrations: ${chunk.visuals.map((v) => '${v.figureNumber == null ? '' : '[[guide:${chunk.id}:${v.figureNumber}]] '} ${v.title}: ${v.caption}').join(' | ')}',
        );
      }
      if (chunk.lookFor.isNotEmpty) {
        buffer.writeln('Look for: ${chunk.lookFor.join(' | ')}');
      }
      if (chunk.doNotAssume.isNotEmpty) {
        buffer.writeln('Do not assume: ${chunk.doNotAssume.join(' | ')}');
      }
      if (chunk.safetyWarnings.isNotEmpty) {
        buffer.writeln('Safety warnings: ${chunk.safetyWarnings.join(' | ')}');
      }
      if (chunk.escalateWhen.isNotEmpty) {
        buffer.writeln('Escalate when: ${chunk.escalateWhen.join(' | ')}');
      }
      if (chunk.warning != null) {
        buffer.writeln('Required warning: ${chunk.warning}');
      }
    }
    buffer.writeln('\nSOURCE CATALOG');
    final sourceIds = results.expand((item) => item.chunk.sourceIds).toSet();
    for (final id in sourceIds) {
      final source = sources[id];
      if (source != null) {
        buffer.writeln(
          '[$id] ${source.label} (${source.jurisdiction}): ${source.reference}',
        );
      }
    }
    return buffer.toString();
  }
}

/// Small, versioned, on-device retrieval layer for WormWise's curated FAW
/// knowledge. It uses weighted lexical retrieval because the curated corpus is
/// compact; this keeps guides fully offline and avoids shipping farmer data or
/// relying on a remote vector database.
class AdvisorRagService {
  const AdvisorRagService();

  static const knowledgeVersion = 'faw-ph-2026.09-v9';

  static const pesticideWarning =
      'Use only an FPA-registered product for maize and fall armyworm, follow '
      'the complete current label, wear the required protective equipment, '
      'and observe re-entry and pre-harvest intervals. Consult the Municipal/'
      'City Agriculture Office or RCPC when uncertain.';

  static const identificationWarning =
      'A photograph or damage symptom can support screening but may not '
      'confirm species. When identification affects control decisions, request '
      'confirmation from an agriculture officer or crop-protection specialist.';

  static const decisionWarning =
      'Do not make a pesticide decision from a risk label alone. Consider '
      'current scouting, crop stage, fresh evidence, larval size, crop '
      'condition, natural enemies, local guidance, cost, and label restrictions.';

  static const sources = <String, AdvisorReferenceSource>{
    'CLEMSON-GROWTH': AdvisorReferenceSource(
      id: 'CLEMSON-GROWTH',
      label: 'Clemson Extension: Visual Guide to Corn Growth Stages',
      reference:
          'Plumblee M, Harrelson B, Halladay S. Visual Guide to Corn Growth Stages. Clemson Cooperative Extension, Land-Grant Press; June 2023. LGP 1170.',
      publisher: 'Clemson Cooperative Extension',
      locator: 'Vegetative and Reproductive Growth Stages',
      jurisdiction: 'US field corn; general morphological stage identification',
      publicUrl:
          'https://lgpress.clemson.edu/publication/visual-guide-to-corn-growth-stages/',
      verifiedOn: '2026-09-30',
    ),
    'DA-BPI-FAW-LEAFLET': AdvisorReferenceSource(
      id: 'DA-BPI-FAW-LEAFLET',
      label:
          'DA Bureau of Plant Industry, Detection and Management of Fall Armyworm',
      reference:
          'Printed Crop Pest Management Division leaflet; six photographed pages supplied to the WormWise project. Publication date and public URL unverified.',
      jurisdiction:
          'Philippines; general guidance, not a field-specific treatment decision',
    ),
    'ACCESS-SCOUT': AdvisorReferenceSource(
      id: 'ACCESS-SCOUT',
      label:
          'Access Agriculture: Scouting for fall armyworms (2018), hosted by FAO',
      reference: 'https://www.fao.org/family-farming/detail/en/c/1334654/',
      jurisdiction: 'International educational guidance',
      publisher: 'Access Agriculture; produced by Agro-Insight and FAO',
      locator:
          'Scouting for fall armyworms, English page summary: twice weekly during first six weeks; no Philippine treatment approval',
      publicUrl: 'https://www.accessagriculture.org/scouting-fall-armyworms',
      verifiedOn: '2026-09-30',
    ),
    'CIMMYT-THRESHOLDS-2021': AdvisorReferenceSource(
      id: 'CIMMYT-THRESHOLDS-2021',
      label: 'CIMMYT Asia IPM Guide (2021), Chapter 2, Table 2 and Section 5',
      reference:
          'https://repository.cimmyt.org/server/api/core/bitstreams/4b6c4442-e04c-440d-a711-0bbc0c163f3b/content',
      jurisdiction: 'Asia reference; applicability in Piat not confirmed',
      publisher: 'CIMMYT',
      locator: 'Fall Armyworm in Asia (2021), Chapter 2, Table 2 and Section 5',
      publicUrl:
          'https://repository.cimmyt.org/server/api/core/bitstreams/4b6c4442-e04c-440d-a711-0bbc0c163f3b/content',
    ),
    'DA-MO26-2021': AdvisorReferenceSource(
      id: 'DA-MO26-2021',
      label: 'Philippine DA Memorandum Order No. 26',
      reference:
          'https://www.da.gov.ph/wp-content/uploads/2021/04/mo26_s2021.pdf',
      jurisdiction: 'Philippines',
      publisher: 'Philippine Department of Agriculture',
      locator: 'Memorandum Order No. 26, series of 2021',
      publicUrl:
          'https://www.da.gov.ph/wp-content/uploads/2021/04/mo26_s2021.pdf',
      verifiedOn: '2026-09-29',
    ),
    'FAO-SCOUT': AdvisorReferenceSource(
      id: 'FAO-SCOUT',
      label: 'FAO Fall Armyworm Scouting Guidance Note',
      reference:
          'https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_guidance-note-2.pdf',
      jurisdiction: 'International general guidance',
      publisher: 'FAO',
      locator: 'Fall Armyworm Guidance Note 2, pages 1–2',
      publicUrl:
          'https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_guidance-note-2.pdf',
      verifiedOn: '2026-09-29',
    ),
    'FAO-SAFETY': AdvisorReferenceSource(
      id: 'FAO-SAFETY',
      label: 'FAO pesticide risk reduction guidance',
      reference:
          'https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_guidance-note-1-.pdf',
      jurisdiction: 'International general guidance',
      publisher: 'FAO',
      locator:
          'Fall Armyworm Guidance Note 1, pages 1–4; international risk reduction',
      publicUrl:
          'https://www.fao.org/fileadmin/templates/fcc/Fall_Armyworm/web_guidance-note-1-.pdf',
      verifiedOn: '2026-09-29',
    ),
    'CABI-HANDBOOK': AdvisorReferenceSource(
      id: 'CABI-HANDBOOK',
      label: 'CABI Fall Armyworm Field Handbook',
      reference: 'https://www.cabi.org/wp-content/uploads/FAW-pocket-guide.pdf',
      jurisdiction: 'International general guidance',
      publisher: 'FAO and CABI',
      locator:
          'Fall Armyworm Field Handbook (2019), identification pages 4–8; monitoring pages 19–24',
      publicUrl: 'https://www.cabi.org/wp-content/uploads/FAW-pocket-guide.pdf',
      verifiedOn: '2026-09-29',
    ),
    'CIMMYT-ASIA': AdvisorReferenceSource(
      id: 'CIMMYT-ASIA',
      label: 'CIMMYT Fall Armyworm in Asia IPM Guide',
      reference:
          'https://repository.cimmyt.org/items/ff2b5489-1d88-4b96-94a0-143ca7af3f77/full',
      jurisdiction: 'Asia; requires Philippine adaptation',
    ),
    'FPA': AdvisorReferenceSource(
      id: 'FPA',
      label: 'Philippine Fertilizer and Pesticide Authority',
      reference: 'https://fpa.da.gov.ph/',
      jurisdiction: 'Philippines; current registration check required',
      publisher: 'Philippine Fertilizer and Pesticide Authority',
      locator:
          'FPA home page; does not verify an individual product registration or label',
      publicUrl: 'https://fpa.da.gov.ph/',
      verifiedOn: '2026-09-29',
    ),
    'PHILRICE-WEEDS': AdvisorReferenceSource(
      id: 'PHILRICE-WEEDS',
      label: 'PhilRice Philippine FAW alternate-host research',
      reference:
          'https://www.philrice.gov.ph/wp-content/uploads/2024/09/RBBJ_Vol11_Issue2_Aug2023.pdf',
      jurisdiction: 'Philippines',
    ),
    'ATI-10': AdvisorReferenceSource(
      id: 'ATI-10',
      label: 'ATI Regional Training Center X FAW guide',
      reference:
          'https://ati2.da.gov.ph/ati-10/content/sites/default/files/users/user24/FAW%20Trifold%20Borchure.pdf',
      jurisdiction: 'Philippines; regional education material',
      publisher:
          'Philippine Agricultural Training Institute, Regional Training Center X',
      locator:
          'FAW trifold brochure, pages 1–2; Cebuano regional education material',
      publicUrl:
          'https://ati2.da.gov.ph/ati-10/content/sites/default/files/users/user24/FAW%20Trifold%20Borchure.pdf',
      verifiedOn: '2026-09-29',
    ),
    'FAO-IPM': AdvisorReferenceSource(
      id: 'FAO-IPM',
      label: 'FAO integrated management of FAW on maize',
      reference: 'https://www.fao.org/family-farming/detail/en/c/1112643/',
      jurisdiction: 'International general guidance',
      publisher: 'FAO',
      locator:
          'Integrated management of the Fall Armyworm on maize (2018), Farmer Field Schools in Africa; natural-enemy sections',
      publicUrl:
          'https://assets.accessagriculture.org/s3fs-public/FAO_FFS_guide_for_FAW_control.pdf',
      verifiedOn: '2026-09-30',
    ),
    'FAO-TRAPS': AdvisorReferenceSource(
      id: 'FAO-TRAPS',
      label: 'FAO guidance on FAW traps and natural allies',
      reference:
          'https://www.fao.org/transboundary-plant-pests-diseases/news/detail/fao-and-kenyan-farmers-deploy-natural-allies-against-fall-armyworm-through-fao-china-south-south-cooperation-project/en',
      jurisdiction: 'International principle; Kenyan operational context',
      publisher: 'FAO',
      locator:
          'FAO-China South-South Cooperation project news, Early warning through pheromone trap-based monitoring; Kenya',
      publicUrl:
          'https://www.fao.org/transboundary-plant-pests-diseases/news/detail/fao-and-kenyan-farmers-deploy-natural-allies-against-fall-armyworm-through-fao-china-south-south-cooperation-project/en',
      verifiedOn: '2026-09-30',
    ),
    'WORMWISE-PROTOCOL': AdvisorReferenceSource(
      id: 'WORMWISE-PROTOCOL',
      label: 'WormWise assessment protocol',
      reference:
          'Current DA sampling implementation and saved-result definitions',
      jurisdiction: 'WormWise operational rule',
    ),
    'DA-PROVIDED-HARABAS': AdvisorReferenceSource(
      id: 'DA-PROVIDED-HARABAS',
      label: 'DA-provided Harabas monitoring booklet',
      reference: 'User-supplied booklet photographs: pages 5–6 and 8–10',
      jurisdiction:
          'Philippine monitoring guidance supplied by the project team',
      locator:
          'Page 5: 20 dispersed plants per hectare and 3 m edge margin; page 6: Davis scale; pages 8–10: weekly monitoring form',
      verifiedOn: '2026-10-07',
    ),
  };

  static const chunks = <AdvisorKnowledgeChunk>[
    AdvisorKnowledgeChunk(
      id: 'identify-corn-growth-stage',
      title: 'Identify your corn growth stage',
      category: 'Scouting Protocol',
      summary:
          'Identify the stage from visible plant features, rather than height or planting date alone.',
      body:
          'VE means emergence. For V1 to Vn, count leaves with visible collars: the band joining blade and sheath. An unexpanded whorl leaf does not count. VT has a fully extended tassel before silks; R1 has silks outside the husk. R2 has white blister kernels; R3 has milky fluid; R4 has pasty starch; R5 has dented kernels; R6 has a brown or black layer at the kernel base. Check several plants: a field stage begins when at least half reach it.',
      keywords: [
        'identify',
        'determine',
        'growth stage',
        'corn',
        'maize',
        'leaf collar',
        'count leaves',
        'vegetative',
        'reproductive',
        'tassel',
        'tasseling',
        'silking',
        'development',
        'maturity',
        'collars',
        'silk',
        'kernel',
        'blister',
        'milk',
        'dough',
        'dent',
        'black layer',
        'paano',
        'malalaman',
        'yugto',
        'mais',
        'dahon',
        'edad',
      ],
      sourceIds: ['CLEMSON-GROWTH'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      jurisdiction:
          'General field-corn morphology; US source, not Philippine treatment guidance',
      steps: [
        'Check collars before tasseling; examine silks and kernels after tasseling.',
        'Use WormWise groups VE–V2, V3–V6, V7–V12, VT–R2 or R3–R6 only when the observed stage fits. V13–Vn is not covered by the current groups; do not force it into V7–V12.',
      ],
      doNotAssume: [
        'A photo or days since planting alone establishes the stage. Clemson timing estimates are not a fixed Philippine calendar.',
      ],
      relatedArticleIds: ['scout-growth-stage'],
      contentVersion: '2.0.0',
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_01.jpeg",
          title: "Figure 1 · Corn plant emerging from soil. VE growth stage.",
          caption:
              "Figure 1. VE (vegetative emergence) depends on soil temperature and moisture.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-emerging-from-soil-ve-growth-stage-.jpeg",
          figureNumber: 1,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_02.gif",
          title:
              "Figure 2 · Description of a corn plant during early development.",
          caption:
              "Figure 2. Description of corn plant during early development.",
          credit: "Steven Ritchie, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/description-of-a-corn-plant-during-early-developme.gif",
          figureNumber: 2,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_03.png",
          title: "Figure 3 · Corn leaf fully expanded.",
          caption:
              "Figure 3. V1 growth stage occurs when the first true leaf is fully expanded and a leaf collar has formed, denoted by the 1 in the picture.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-leaf-fully-expanded-.png",
          figureNumber: 3,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_04.png",
          title: "Figure 4 · Corn plant with three leaves and leaf collars.",
          caption:
              "Figure 4. V3 growth stage occurs when three leaves are fully expanded and have visible leaf collars, denoted by the numbers in the picture.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-with-three-leaves-and-leaf-collars-.png",
          figureNumber: 4,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_05.jpeg",
          title: "Figure 5 · Corn plant at tassel growth stage, VT.",
          caption:
              "Figure 5. VT growth stage occurs when a fully extended tassel has formed prior to silk emergence.",
          credit: "Lori Abendroth, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-tassel-growth-stage-vt-.jpeg",
          figureNumber: 5,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_06.gif",
          title: "Figure 6 · Development of a corn tassel.",
          caption:
              "Figure 6. Tassel growth and development from the V9 growth stage until pollen shed.",
          credit: "Seven Ritchie, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/development-of-a-corn-tassel--331x213.gif",
          figureNumber: 6,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_07.jpeg",
          title:
              "Figure 7 · Corn plant at R1 growth stage, when silks are present.",
          caption:
              "Figure 7. R1 occurs when silks are first visible outside the husks.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r1-growth-stage-when-silks-are-pres.jpeg",
          figureNumber: 7,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_08.jpeg",
          title:
              "Figure 8 · Corn plant at R2 growth stage when kernels have blistered appearance.",
          caption:
              "Figure 8. R2 occurs when kernels are developing and have a white blistered appearance.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r2-growth-stage-when-kernels-have-bl.jpeg",
          figureNumber: 8,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_09.jpeg",
          title:
              "Figure 9 · Close-up of a developing kernels with a blistered appearance.",
          caption:
              "Figure 9. Close-up of developing kernels at the R2 or blister growth stage.",
          credit: "Bob Nielsen, Purdue University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/close-up-of-a-developing-kernels-with-a-blistered.jpeg",
          figureNumber: 9,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_10.jpeg",
          title: "Figure 10 · Corn plant at R3 growth stage, or milk stage.",
          caption:
              "Figure 10. R3 occurs when kernels are pale yellow and filled with milk-colored fluid.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r3-growth-stage-or-milk-stage-.jpeg",
          figureNumber: 10,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_11.jpeg",
          title: "Figure 11 · Corn at R4 growth stage, or dough stage.",
          caption:
              "Figure 11. R4 occurs when kernels are darker yellow and filled with starch that is thick and pasty in consistency.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r4-growth-stage-or-dough-stage-.jpeg",
          figureNumber: 11,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_12.jpeg",
          title: "Figure 12 · Corn at R5 growth stage, or dent.",
          caption: "Figure 12. R5 occurs when most kernels are dented.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r5-growth-stage-or-dent-.jpeg",
          figureNumber: 12,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_13.png",
          title:
              "Figure 13 · Corn at R6 or black layer. Corn has reached physiological maturity.",
          caption:
              "Figure 13. R6 occurs when kernels have reached their maximum dry matter weight and a black abscission has formed.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r6-or-black-layer-corn-has-reached-physio.png",
          figureNumber: 13,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-emergence",
      title: "Corn growth: VE Stage",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "Vegetative growth stages in corn begin with seedling emergence (VE stage) (figure 1). Prior to germination, the corn seed absorbs water equal to approximately 50% of its weight. [2,3] Once germination begins, the mesocotyl, which connects the developing root with the developing shoot, pushes the coleoptile, or developing shoot, to the soil surface. During this time, the developing root, known as the primary root, begins to grow downward in the opposite direction and develops lateral roots making up the seminal root system (figure 2). [2,3,4] This seminal root system absorbs water and nutrients until the V3 growth stage. [3]\n\nFollowing emergence, the coleoptile and mesocotyl elongation stop. The growth continues from the growing point (stem apex), located just above the mesocotyl and below the soil surface until the V5–V6 growth stage. The rapidly developing embryonic leaves grow through the coleoptile tip. [2,3]",
      keywords: [
        "emergence",
        "seedling",
        "roots",
        "coleoptile",
        "mesocotyl",
        "ve",
        "germination",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_01.jpeg",
          title: "Figure 1 · Corn plant emerging from soil. VE growth stage.",
          caption:
              "Figure 1. VE (vegetative emergence) depends on soil temperature and moisture.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-emerging-from-soil-ve-growth-stage-.jpeg",
          figureNumber: 1,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_02.gif",
          title:
              "Figure 2 · Description of a corn plant during early development.",
          caption:
              "Figure 2. Description of corn plant during early development.",
          credit: "Steven Ritchie, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/description-of-a-corn-plant-during-early-developme.gif",
          figureNumber: 2,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-leaf-collars",
      title: "Corn growth: V1, V2, V3 to V(n) Stages",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "Stages between VE and VT are designated numerically as V1, V2, …through V(n). The (n) represents the stage with the top leaf fully expanded before the VT stage. A leaf is considered fully expanded if a leaf collar (the discolored line between the leaf blade and leaf sheath) is visible (figure 3 and figure 4). [2,3]",
      keywords: [
        "vegetative",
        "leaf",
        "collars",
        "count",
        "v1",
        "v2",
        "v3",
        "leaves",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_03.png",
          title: "Figure 3 · Corn leaf fully expanded.",
          caption:
              "Figure 3. V1 growth stage occurs when the first true leaf is fully expanded and a leaf collar has formed, denoted by the 1 in the picture.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-leaf-fully-expanded-.png",
          figureNumber: 3,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_04.png",
          title: "Figure 4 · Corn plant with three leaves and leaf collars.",
          caption:
              "Figure 4. V3 growth stage occurs when three leaves are fully expanded and have visible leaf collars, denoted by the numbers in the picture.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-with-three-leaves-and-leaf-collars-.png",
          figureNumber: 4,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-tasseling",
      title: "Corn growth: VT Stage",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "Vegetative growth stages in corn cease with the production of a tassel, VT. This stage occurs when a tassel is fully extended (figure 5 and figure 6) prior to the production of silks (figure 7). Tassels will be visible for approximately two to three days before the formation of silks. [2,3] This growth stage indicates the total vegetative growth that will occur on the plant, with all the leaves present.",
      keywords: [
        "vt",
        "tassel",
        "tasseling",
        "pollen",
        "flowering",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_05.jpeg",
          title: "Figure 5 · Corn plant at tassel growth stage, VT.",
          caption:
              "Figure 5. VT growth stage occurs when a fully extended tassel has formed prior to silk emergence.",
          credit: "Lori Abendroth, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-tassel-growth-stage-vt-.jpeg",
          figureNumber: 5,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_06.gif",
          title: "Figure 6 · Development of a corn tassel.",
          caption:
              "Figure 6. Tassel growth and development from the V9 growth stage until pollen shed.",
          credit: "Seven Ritchie, Iowa State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/development-of-a-corn-tassel--331x213.gif",
          figureNumber: 6,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-silking-blister",
      title: "Corn growth: R1 and R2 Stages",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "At the R1 growth stage, or silking (figure 7), silks are first visible outside the husks. Silks emerge at the base growing towards the tip of the developing ear in two to five days and remain receptive to pollen for up to two weeks. [2,5] Pollination occurs when falling pollen grains from the tassel are caught by the silks. For successful pollination, it is important that silks emerge and pollinate simultaneously. Moisture stress during this stage causes poor pollination and reduced seed set, reducing yield.\n\nR2, or blister stage (figure 8), occurs when the kernels begin to expand, dare white on the outside, and have a blistered appearance (figure 9). This growth stage typically occurs ten to fourteen days after R1, with silks beginning to dry down and turn brown. [2,5,6,7]",
      keywords: [
        "r1",
        "r2",
        "silking",
        "silks",
        "pollination",
        "blister",
        "kernels",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_07.jpeg",
          title:
              "Figure 7 · Corn plant at R1 growth stage, when silks are present.",
          caption:
              "Figure 7. R1 occurs when silks are first visible outside the husks.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r1-growth-stage-when-silks-are-pres.jpeg",
          figureNumber: 7,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_08.jpeg",
          title:
              "Figure 8 · Corn plant at R2 growth stage when kernels have blistered appearance.",
          caption:
              "Figure 8. R2 occurs when kernels are developing and have a white blistered appearance.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r2-growth-stage-when-kernels-have-bl.jpeg",
          figureNumber: 8,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_09.jpeg",
          title:
              "Figure 9 · Close-up of a developing kernels with a blistered appearance.",
          caption:
              "Figure 9. Close-up of developing kernels at the R2 or blister growth stage.",
          credit: "Bob Nielsen, Purdue University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/close-up-of-a-developing-kernels-with-a-blistered.jpeg",
          figureNumber: 9,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-milk-dough",
      title: "Corn growth: R3 and R4 Stages",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "In the R3, or milk growth stage (figure 10), the kernel is pale yellow outside and filled with a milk-colored fluid which is mainly starch. Kernels at this stage have 80% moisture. This growth stage typically occurs eighteen to twenty-two days after R1. [2,5,6,7]\n\nIn the R4, or dough stage (figure 11), starch continues to accumulate and thickens to a pasty consistency. As the kernels develop through the R4 stage, they begin to expand and turn darker yellow. This growth stage typically occurs twenty-four to twenty-eight days after R1. [2,5,6,7]",
      keywords: [
        "r3",
        "r4",
        "milk",
        "dough",
        "fluid",
        "starch",
        "kernels",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_10.jpeg",
          title: "Figure 10 · Corn plant at R3 growth stage, or milk stage.",
          caption:
              "Figure 10. R3 occurs when kernels are pale yellow and filled with milk-colored fluid.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-plant-at-r3-growth-stage-or-milk-stage-.jpeg",
          figureNumber: 10,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_11.jpeg",
          title: "Figure 11 · Corn at R4 growth stage, or dough stage.",
          caption:
              "Figure 11. R4 occurs when kernels are darker yellow and filled with starch that is thick and pasty in consistency.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r4-growth-stage-or-dough-stage-.jpeg",
          figureNumber: 11,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-dent-maturity",
      title: "Corn growth: R5 and R6 Stages",
      category: "Scouting Protocol",
      summary: "Stage reference from Clemson Extension, LGP 1170.",
      body:
          "In the R5, or dent stage (figure 12), most kernels are dented. The kernels at the R5 stage are drying down, beginning at the top, where a small hard white layer of starch forms. The line indicating the hard starch layer will advance toward the base of the kernel. This growth stage occurs approximately thirty-five to forty-two days after R1. [2,3,6,7]\n\nR6, or the black layer (figure 13), occurs when the hard starch layer has advanced completely to the cob and formed a brown or black abscission layer (black layer) right above the kernel tip. The “black layer” is an indication of physiological maturity, and kernels are at their maximum dry matter weight. Kernels at the R6 stage have 30% to 35% moisture content. This growth stage occurs approximately fifty-five to sixty-five days after R1. [2,5,6]",
      keywords: [
        "r5",
        "r6",
        "dent",
        "black layer",
        "maturity",
        "dry matter",
        "kernels",
        "corn",
        "maize",
        "growth",
        "stage",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      contentVersion: "2.0.0",
      jurisdiction:
          "US field corn; morphology transfers, timing is source-specific",
      doNotAssume: [
        "Timing and moisture values describe the source context, not fixed Philippine schedules or harvest instructions.",
      ],
      relatedArticleIds: ["identify-corn-growth-stage"],
      visuals: [
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_12.jpeg",
          title: "Figure 12 · Corn at R5 growth stage, or dent.",
          caption: "Figure 12. R5 occurs when most kernels are dented.",
          credit: "Eric Larson, Mississippi State University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r5-growth-stage-or-dent-.jpeg",
          figureNumber: 12,
        ),
        AdvisorGuideVisual(
          asset: "assets/images/growth_stages/clemson/figure_13.png",
          title:
              "Figure 13 · Corn at R6 or black layer. Corn has reached physiological maturity.",
          caption:
              "Figure 13. R6 occurs when kernels have reached their maximum dry matter weight and a black abscission has formed.",
          credit: "Michael Plumblee, Clemson University.",
          sourceUrl:
              "https://lgpress.clemson.edu/wp-content/uploads/sites/3/2023/06/corn-at-r6-or-black-layer-corn-has-reached-physio.png",
          figureNumber: 13,
        ),
      ],
    ),
    AdvisorKnowledgeChunk(
      id: "clemson-growth-development",
      title: "Corn growth: vegetative and reproductive development",
      category: "Scouting Protocol",
      summary: "Whole-field stage and development reference.",
      body:
          "Identifying corn growth stages is essential for successful crop management of pests, irrigation, and fertility. This guide will help growers, consultants, Extension, and research personnel properly identify corn growth stages in field corn hybrids.\n\nGenerally, corn growth and development can be divided into vegetative (V) and reproductive (R) growth stages. The beginning of each stage starts when at least 50% of plants in the area are at that stage. [1,2,3] The vegetative growth stage begins with corn emergence and is completed by tasseling. The reproductive growth stages start with silking and end when a black layer forms, indicating physiological maturity.",
      keywords: [
        "corn",
        "maize",
        "development",
        "growth",
        "stage",
        "field",
        "half",
        "50%",
      ],
      sourceIds: ["CLEMSON-GROWTH"],
      grade: AdvisorEvidenceGrade.verifiedCore,
      relatedArticleIds: ["identify-corn-growth-stage"],
    ),
    AdvisorKnowledgeChunk(
      id: 'identify-overview',
      title: 'What fall armyworm is',
      category: 'Identification',
      summary:
          'Fall armyworm, or FAW, is the caterpillar stage of the moth Spodoptera frugiperda.',
      body:
          'FAW can feed on maize and other host plants. WormWise currently limits its assessment protocol to maize. A field symptom or photograph may support screening, but species confirmation requires multiple compatible features or qualified review.',
      keywords: [
        'faw',
        'fall armyworm',
        'what is faw',
        'armyworm',
        'spodoptera frugiperda',
        'maize pest',
        'corn pest',
      ],
      sourceIds: ['CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      doNotAssume: [
        'Do not treat any caterpillar, leaf injury, or photograph as confirmed FAW by itself.',
        'Do not apply the maize assessment protocol to another crop.',
      ],
      escalateWhen: [
        'Request qualified identification when the result affects control, reporting, food safety, or another consequential decision.',
      ],
      relatedArticleIds: ['identify-larva', 'identify-eggs', 'look-alikes'],
      warning: identificationWarning,
      jurisdiction: 'International biology; WormWise scope is Philippine maize',
    ),
    AdvisorKnowledgeChunk(
      id: 'identify-larva',
      title: 'Recognize a possible FAW larva',
      category: 'Identification',
      summary: 'Use several features together; no single marking confirms FAW.',
      body:
          'A mature FAW-compatible larva may have a pale inverted Y on the head and four prominent dark spots arranged roughly as a square near the rear. Color varies, and small larvae may not show these markings clearly. Similar caterpillars can share individual features.',
      keywords: [
        'identify',
        'recognize',
        'larva',
        'caterpillar',
        'uod',
        'inverted y',
        'head',
        'spots',
        'look alike',
      ],
      sourceIds: ['CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'identify-eggs',
      title: 'Check an egg mass',
      category: 'Identification',
      summary:
          'FAW eggs occur in clusters and may be covered with pale or gray scales.',
      body:
          'Photograph the complete egg mass and nearby leaf without touching it. Other moths also lay clustered eggs, so an egg-mass image alone is not definitive.',
      keywords: ['egg', 'eggs', 'egg mass', 'itlog', 'cluster', 'scales'],
      sourceIds: ['CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'look-alikes',
      title: 'Rule out look-alikes',
      category: 'Identification',
      summary:
          'Compare the organism, plant location, damage pattern, and behavior.',
      body:
          'Possible look-alikes include other Spodoptera species, corn earworm, armyworms, cutworms, and maize stem borers. Wind, hail, tools, disease, nutrient stress, herbicide injury, drought, and old feeding can also resemble pest damage.',
      keywords: [
        'look alike',
        'another pest',
        'not faw',
        'stem borer',
        'cutworm',
        'damage',
        'confused',
        'uncertain',
      ],
      sourceIds: ['CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'life-cycle',
      title: 'Understand the FAW life cycle',
      category: 'Identification',
      summary:
          'FAW develops through egg, larva, pupa, and adult moth stages, but timing varies with conditions.',
      body:
          'The FAO/CABI handbook describes eggs hatching in about two to three days in warm conditions. An ATI regional brochure describes a larval period of about 14 to 22 days. Larvae then usually drop to soil to pupate before adults emerge. These attributed ranges are orientation only: temperature and other conditions change development, so they cannot date an infestation or confirm identity.',
      keywords: [
        'life cycle',
        'lifecycle',
        'egg',
        'itlog',
        'larva',
        'uod',
        'pupa',
        'moth',
        'gamu gamo',
        'instar',
        'development',
      ],
      sourceIds: ['CABI-HANDBOOK', 'ATI-10'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'field-ecology',
      title: 'Understand FAW movement and field ecology',
      category: 'Identification',
      summary:
          'FAW can move within and between fields, so one observation does not describe the whole area.',
      body:
          'Young larvae can disperse on silk carried by wind, older larvae often move into protected plant structures, and adult moths can travel beyond one field. Philippine research also found several grass weeds capable of supporting FAW feeding or egg laying. Manage crop and fallow weeds according to local agronomy, but do not clear all non-crop vegetation indiscriminately because some habitat can support beneficial organisms.',
      keywords: [
        'ecology',
        'movement',
        'dispersal',
        'wind',
        'hangin',
        'migration',
        'weed',
        'damo',
        'alternate host',
        'volunteer maize',
        'field edge',
      ],
      sourceIds: ['CABI-HANDBOOK', 'PHILRICE-WEEDS', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'evidence-frass',
      title: 'Understand frass and fresh feeding',
      category: 'Symptoms & Evidence',
      summary:
          'Frass supports recent caterpillar feeding but is not species-specific.',
      body:
          'Fresh coarse frass in the whorl can accompany active feeding. Dry debris and old holes are weaker evidence. Frass at a stalk or cob borehole may fit another pest, including a stem borer.',
      keywords: [
        'frass',
        'droppings',
        'dumi',
        'waste',
        'fresh',
        'whorl',
        'feeding',
        'holes',
      ],
      sourceIds: ['CABI-HANDBOOK', 'FAO-SCOUT'],
      grade: AdvisorEvidenceGrade.verifiedCore,
    ),
    AdvisorKnowledgeChunk(
      id: 'evidence-leaf',
      title: 'Read maize leaf damage carefully',
      category: 'Symptoms & Evidence',
      summary:
          'Separate current feeding from expanded or healed older-leaf damage.',
      body:
          'Small larvae can cause windowpanes and pinholes. Larger larvae can produce ragged whorl injury. Do not count a plant as currently affected when it shows only old damage and no clear current evidence.',
      keywords: [
        'leaf damage',
        'windowpane',
        'pinhole',
        'shot hole',
        'ragged',
        'old damage',
        'new damage',
      ],
      sourceIds: ['FAO-SCOUT', 'CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
    ),
    AdvisorKnowledgeChunk(
      id: 'evidence-ear',
      title: 'Inspect tassel, silk, husk, and ear evidence',
      category: 'Symptoms & Evidence',
      growthStages: ['VT', 'R1', 'R2', 'R3', 'R4', 'R5', 'R6'],
      summary:
          'Reproductive maize needs careful inspection because several pests and diseases can affect the ear.',
      body:
          'Look around the emerging tassel, silks, husk, ear tip, entry points, and kernels for fresh feeding, frass, or a larva. Keep exterior observations separate from any opened-ear check required by the protocol. Ear damage, mold, and rot have multiple causes and must not be attributed to FAW from appearance alone.',
      keywords: [
        'ear',
        'cob',
        'tenga',
        'bunga',
        'tassel',
        'silk',
        'husk',
        'kernel',
        'entry hole',
        'reproductive',
        'mold',
      ],
      sourceIds: ['CABI-HANDBOOK', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-plant',
      title: 'Inspect one maize plant',
      category: 'Scouting Protocol',
      summary:
          'Inspect the selected plant consistently and record what is actually present.',
      body:
          'For vegetative maize, check the newest leaves and whorl for fresh feeding, frass, eggs, or a larva. Do not replace the selected plant with a more damaged one. Record zero when nothing is observed rather than leaving the observation ambiguous.',
      keywords: [
        'inspect plant',
        'scout plant',
        'whorl',
        'station',
        'observation',
        'selected plant',
      ],
      sourceIds: ['WORMWISE-PROTOCOL', 'FAO-SCOUT'],
      grade: AdvisorEvidenceGrade.operationalRule,
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-schedule',
      title: 'When to scout',
      category: 'Scouting Protocol',
      summary:
          'Check regularly so fresh feeding and young larvae are found early.',
      body:
          'Access Agriculture recommends scouting twice a week during the first six weeks. FAO Scouting Guidance Note 2 recommends at least weekly visits, with more frequent checks when conditions change. These are attributed reference schedules; follow local agricultural guidance and any pesticide re-entry restrictions.',
      steps: [
        'In WormWise, follow Guided scouting to inspect 20 dispersed plants per sampling block of at most 1 hectare.',
        'Look for recent feeding and fresh frass in the whorl. Old leaf damage alone does not count as current infestation.',
        'Record the date, crop stage, plants checked, current signs, and beneficial organisms before taking management action.',
        'Save a new assessment on the next visit so changes can be compared with the earlier record.',
      ],
      keywords: [
        'scout',
        'schedule',
        'twice',
        'week',
        'six weeks',
        'monitoring',
        'frequency',
      ],
      sourceIds: ['ACCESS-SCOUT', 'FAO-SCOUT'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      relatedArticleIds: ['scout-field', 'management-after-finding-faw'],
    ),
    AdvisorKnowledgeChunk(
      id: 'management-after-finding-faw',
      title: 'What you can do after finding FAW',
      category: 'Management',
      summary:
          'Record current evidence, consider practical manual control, and keep monitoring.',
      body:
          'Access Agriculture describes manual destruction of identified egg masses and young armyworms during early scouting. This can be practical where plants are accessible and the affected area is manageable. FAO also recommends observing natural enemies as part of scouting.',
      steps: [
        'Record the sampled plants and evidence before removing eggs or larvae.',
        'Where identification is clear and access is safe, manually remove and destroy FAW egg masses and young larvae where practical.',
        'Look for predators, parasitized eggs, and dead larvae. Protect beneficial organisms and avoid unnecessary broad-spectrum spraying.',
        'Continue scouting and record whether fresh feeding persists. Ask the agriculture office for management advice when infestation continues or manual removal is impractical.',
      ],
      doNotAssume: [
        'Old damage means larvae are still feeding.',
        'A percentage or Davis score alone selects a pesticide or dose.',
      ],
      safetyWarnings: [
        'Observe pesticide re-entry restrictions before entering a treated field.',
      ],
      keywords: [
        'handpick',
        'manual',
        'remove',
        'egg masses',
        'young larvae',
        'control',
        'action',
      ],
      sourceIds: ['ACCESS-SCOUT', 'FAO-SCOUT', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      relatedArticleIds: [
        'scout-schedule',
        'management-natural-enemies',
        'management-reference-thresholds',
      ],
    ),
    AdvisorKnowledgeChunk(
      id: 'management-reference-thresholds',
      title: 'Understanding reference action thresholds',
      category: 'Management',
      growthStages: [
        'V1',
        'V2',
        'V3',
        'V4',
        'V5',
        'V6',
        'V7',
        'V8',
        'V9',
        'V10',
        'V11',
        'V12',
        'VT',
        'R1',
        'R2',
      ],
      summary:
          'CIMMYT Asia guide (2021): educational reference thresholds by maize growth stage.',
      body:
          'An action threshold indicates when treatment should be considered. Table 2 gives these reference values:\n\nV1–V6 (early whorl): 20%, range 10–30%.\nV7–V12 (late whorl): 50%, range 40–60%.\nVT–R2 (tassel and early ear): 20%, range 10–30%.\n\nFor vegetative stages, count plants with small fresh windowpanes and/or infested whorls. The reproductive-stage value uses percent infested plants. Do not extend these stage ranges to VE or R3–R6. WormWise uses 20 separate plants per sampling block; the sampling layout alone does not determine treatment.\n\nExample: 8 of 20 qualifying plants = 40%. This exceeds the early-whorl midpoint, lies within the late-whorl range, and exceeds the tassel/early-ear midpoint. It is not a Davis score or an automatic spray instruction.',
      lookFor: [
        'Above the early-whorl threshold, the guide distinguishes mostly small larvae (recommended foliar treatment) from larger larvae in whorls (selective whorl-directed treatment). Mixed sizes may require reassessment and follow-up management.',
        'At VT–R2, the guide adds conditions for low human toxicity and availability of the required protective equipment because taller plants increase application exposure.',
        'A local treatment decision also considers current feeding, larval size, crop condition, natural enemies, weather, cost, and current product labels.',
      ],
      doNotAssume: [
        'The app percentage uses exactly the same infestation definition as this reference.',
        'Below the midpoint means no further monitoring is needed.',
        'The published ranges are validated treatment thresholds for Piat.',
      ],
      keywords: [
        'threshold',
        '20%',
        '40%',
        '50%',
        '20/50',
        'early whorl',
        'late whorl',
        'treatment',
        'reference',
      ],
      sourceIds: ['CIMMYT-THRESHOLDS-2021'],
      grade: AdvisorEvidenceGrade.expertValidationRequired,
      warning:
          'Educational reference only. Applicability in Piat has not been confirmed. Ask the Municipal/City Agriculture Office to interpret the reference for the field; follow current Philippine registration and label requirements for any treatment.',
      relatedArticleIds: [
        'management-after-finding-faw',
        'management-threshold',
        'scout-growth-stage',
      ],
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-field',
      title: 'Run a representative field assessment',
      category: 'Scouting Protocol',
      summary:
          'Follow Guided scouting to inspect 20 dispersed plants per sampling block of at most 1 hectare.',
      body:
          'Current WormWise assessments follow the DA-provided Harabas booklet: select 20 dispersed plants per sampling block of at most 1 hectare, at least 3 m inside the field edge. Guided scouting shows Plant 1–20 and the next walking destination; the app generates location aids and records the actual sampled plants. Inspect the upper 3–4 leaves and whorl. Capture or import 1–3 photos of the same plant. Batch import assigns photos to individual plants. Count plants once regardless of photo count. Larger fields have multiple sampling blocks. Model 1 screens damage; optional eggs, larvae or frass detection supports provisional sampled infestation, counted once per plant over the planned sample (20 plants per DA block); unavailable detection remains unknown. Finalized expert results provide Davis mean severity on 0–9 with the supplied DA classification wording and current sampled infestation based on recorded freshness. The Davis classification describes leaf-damage severity, not a percentage or proof of pest absence. Damage percentage, infestation percentage and Davis mean are separate results.',
      contentVersion: AdvisorAssessmentContract.version,
      keywords: [
        'field assessment',
        'station',
        'route',
        '20 plants',
        'per hectare',
        'guided scouting',
        'batch upload',
        'davis severity',
        'sampled infestation',
        'sample',
        'scouting',
      ],
      sourceIds: ['DA-PROVIDED-HARABAS', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.operationalRule,
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-growth-stage',
      title: 'Inspect maize according to growth stage',
      category: 'Scouting Protocol',
      growthStages: [
        'VE',
        'V1',
        'V2',
        'V3',
        'V4',
        'V5',
        'V6',
        'V7',
        'V8',
        'V9',
        'V10',
        'V11',
        'V12',
        'VT',
        'R1',
        'R2',
        'R3',
        'R4',
        'R5',
        'R6',
      ],
      summary:
          'The plant zones that matter change as maize develops; this is an inspection guide, not a treatment table.',
      body:
          'At VE to V2, inspect the whole seedling and distinguish missing or cut plants from non-emergence, drought, disease, or cutworm injury. At V3 to V6, emphasize the newest leaves and whorl. At V7 to V12, inspect the newest three or four leaves, deeper whorl, and emerging tassel. At VT to R2, include tassel, ear base, silks, and leaf axils. At R3 to R6, inspect the exterior ear tip, husk, silk, base, shank, and axils; open ears only when the approved protocol calls for it.',
      keywords: [
        'growth stage',
        'stage',
        'yugto',
        've',
        'v2',
        'v3',
        'v6',
        'v7',
        'v12',
        'vt',
        'r2',
        'r3',
        'r6',
        'seedling',
        'whorl',
        'tassel',
        'ear',
      ],
      sourceIds: ['CABI-HANDBOOK', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.operationalRule,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-traps',
      title: 'Use pheromone traps as an early-warning tool',
      category: 'Scouting Protocol',
      summary:
          'Male-moth trap catches should trigger field scouting, not an automatic spray decision.',
      body:
          'Pheromone traps monitor adult male moth activity; they do not directly measure larvae or crop injury and do not prove that a field is infested. Respond to a catch by checking the field for egg masses, larvae, and fresh damage. Follow only locally approved instructions for trap type, lure replacement, placement, servicing, and disposal; treat any insecticidal strip as a labeled hazardous product.',
      keywords: [
        'pheromone',
        'trap',
        'bitag',
        'moth catch',
        'gamu gamo',
        'lure',
        'monitoring',
        'early warning',
      ],
      sourceIds: ['FAO-TRAPS', 'CABI-HANDBOOK', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'scout-boundary',
      title: 'Keep the boundary to one comparable maize field',
      category: 'Scouting Protocol',
      summary: 'Exclude roads, houses, ponds, trees, and non-maize land.',
      body:
          'Sample separately when planting date, crop stage, variety, irrigation, or management differs materially. Divide large areas only along meaningful and accessible field divisions, not arbitrary geometry that crosses hazards or mixed land cover.',
      keywords: [
        'boundary',
        'road',
        'pond',
        'house',
        'divide',
        'block',
        'large field',
        'mixed field',
      ],
      sourceIds: ['FAO-SCOUT', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.operationalRule,
    ),
    AdvisorKnowledgeChunk(
      id: 'management-ipm',
      title: 'Use an integrated management approach',
      category: 'Management',
      summary:
          'Base decisions on current scouting, crop stage, field condition, natural enemies, feasibility, and safety.',
      body:
          'Early monitoring, sound crop management, conservation of natural enemies, and locally appropriate mechanical or cultural measures form an IPM approach. A dramatic-looking leaf does not by itself establish economic loss or a need to spray.',
      keywords: [
        'management',
        'ipm',
        'control',
        'cultural',
        'mechanical',
        'natural enemies',
        'predator',
      ],
      sourceIds: ['DA-BPI-FAW-LEAFLET', 'CIMMYT-ASIA', 'CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'management-bpi-prevention',
      title: 'DA-BPI prevention and field sanitation guidance',
      category: 'Management',
      summary:
          'The Philippine BPI leaflet lists crop management and regular field sanitation as preventive measures.',
      body:
          'The DA-BPI leaflet lists crop diversification or rotation, synchronous planting with quality seed, and cleaning field weeds among prevention measures. Choose practices suited to the field and local extension advice; these measures do not prove that FAW is present or replace scouting.',
      keywords: [
        'bpi',
        'department of agriculture',
        'prevention',
        'crop rotation',
        'diversification',
        'synchronous planting',
        'field sanitation',
        'weeds',
        'ipm',
      ],
      sourceIds: ['DA-BPI-FAW-LEAFLET'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      jurisdiction: 'Philippines; DA-BPI general prevention guidance',
      warning: decisionWarning,
      relatedArticleIds: [
        'management-ipm',
        'scout-traps',
        'management-after-finding-faw',
      ],
    ),
    AdvisorKnowledgeChunk(
      id: 'management-bpi-response',
      title: 'DA-BPI monitoring and expert response',
      category: 'Management',
      summary:
          'Use field checks and local pest-management offices when suspected FAW needs confirmation.',
      body:
          'The DA-BPI leaflet describes field surveys, pheromone traps for monitoring, and collection of suspected larvae for identification by the appropriate crop-pest office. It also lists physical removal of egg masses or larvae and biological control as management categories. Biological organisms and pesticides require current local authorization and qualified advice; a trap catch, photograph, or WormWise percentage does not select a treatment.',
      keywords: [
        'bpi',
        'department of agriculture',
        'monitoring',
        'pheromone',
        'trap',
        'handpick',
        'egg masses',
        'larvae',
        'biological control',
        'report suspected faw',
      ],
      sourceIds: ['DA-BPI-FAW-LEAFLET'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      jurisdiction:
          'Philippines; DA-BPI general monitoring and escalation guidance',
      warning: decisionWarning,
      relatedArticleIds: [
        'scout-traps',
        'management-natural-enemies',
        'expert-escalation',
      ],
    ),
    AdvisorKnowledgeChunk(
      id: 'management-natural-enemies',
      title: 'Recognize and conserve natural enemies',
      category: 'Management',
      summary:
          'Predators, parasitoids, and pathogens can contribute to natural FAW mortality.',
      body:
          'Broad beneficial groups include ants, earwigs, spiders, beetles, predatory bugs, lacewings, social wasps, parasitoid wasps, parasitoid flies, and naturally occurring microbial pathogens. Philippine ATI material also discusses earwigs, lacewings, Trichogramma, NPV, and Metarhizium. Avoid unnecessary broad-spectrum pesticide use and avoid directly spraying visible beneficial organisms. Do not rear, transport, release, formulate, or spread an organism based on this guide; species identification and biological-control use require Philippine authorization and expert supervision.',
      keywords: [
        'natural enemy',
        'natural enemies',
        'beneficial',
        'predator',
        'parasitoid',
        'ant',
        'langgam',
        'earwig',
        'spider',
        'gagamba',
        'lacewing',
        'wasp',
        'trichogramma',
        'npv',
        'metarhizium',
      ],
      sourceIds: ['ATI-10', 'FAO-IPM', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning:
          'Do not rear, transport, release, formulate, or spread biological-control organisms or pathogens without applicable Philippine authorization and expert supervision.',
    ),
    AdvisorKnowledgeChunk(
      id: 'management-weather-follow-up',
      title: 'Use weather as a reason to reassess',
      category: 'Management',
      summary:
          'Rain and field conditions can change what is observable, but they do not rewrite an assessment.',
      body:
          'Heavy rain may reduce some exposed eggs or young larvae, but it does not guarantee FAW control. Recent rain, crop condition, natural enemies, and recent treatment may call for another field check. Keep the earlier assessment unchanged and record a new assessment when local field conditions make it appropriate. There is no universal interval for scouting again.',
      keywords: [
        'weather',
        'rain',
        'ulan',
        'bagyo',
        'ecology',
        'reassess',
        'rescout',
        'follow up',
        'field conditions',
      ],
      sourceIds: ['CABI-HANDBOOK', 'CIMMYT-ASIA'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'management-decision-frame',
      title: 'Frame a management decision safely',
      category: 'Management',
      summary:
          'Consider evidence, crop stage, context, feasibility, and follow-up together.',
      body:
          'First confirm crop stage and current evidence. Then consider distribution, larval size when reliably observed, crop condition, weather, natural enemies, recent interventions, safe re-entry, inaccessible stations, and uncertainty. Review any option for cost, efficacy, safety, accessibility, and scalability. A no-treatment decision still needs follow-up scouting. Foreign trial performance or a WormWise risk label alone is not a Philippine treatment recommendation.',
      keywords: [
        'decision',
        'decide',
        'management decision',
        'cesas',
        'cost',
        'efficacy',
        'safety',
        'accessibility',
        'scalability',
        'follow up',
        'risk result',
      ],
      sourceIds: ['CIMMYT-ASIA', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.expertValidationRequired,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'management-threshold',
      title: 'Interpret risk without inventing a treatment threshold',
      category: 'Management',
      summary:
          'WormWise risk is a scouting summary, not an automatic spray instruction.',
      body:
          'Published action thresholds from other regions have not been validated for Piat or for WormWise\'s exact sampling definitions. Treat them as background information and ask a qualified local adviser to interpret current field observations before any treatment decision.',
      keywords: [
        'threshold',
        'risk',
        'percentage',
        'moderate',
        'high risk',
        'spray decision',
        'action level',
      ],
      sourceIds: ['CIMMYT-ASIA', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.expertValidationRequired,
      warning: decisionWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'safety-pesticide',
      title: 'Make pesticide decisions safely',
      category: 'Safety',
      summary:
          'For product choice and dosage, consult a qualified local adviser and the current approved label.',
      body:
          'Registration and labels can change. Verify the exact maize-and-FAW use through the Philippine FPA and current approved label. Image confidence and trap catches are not treatment thresholds. Never bypass PPE, re-entry, pre-harvest, storage, disposal, or environmental restrictions.',
      keywords: [
        'pesticide',
        'spray',
        'chemical',
        'insecticide',
        'dose',
        'rate',
        'mixture',
        'ppe',
        're-entry',
        'pre-harvest',
      ],
      sourceIds: ['FPA', 'FAO-SAFETY'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning: pesticideWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'safety-ear-grain',
      title: 'Treat damaged or moldy ears as a food-safety concern',
      category: 'Safety',
      growthStages: ['R3', 'R4', 'R5', 'R6'],
      summary:
          'An image cannot establish whether damaged grain is safe for people or animals.',
      body:
          'Ear feeding can create openings for fungal infection and affect grain quality, but several insects and diseases can cause similar injury. Keep suspicious moldy or badly damaged grain separate and request current food- or feed-safety advice from the appropriate agriculture or food-safety authority. Do not classify grain as safe, edible, or suitable for feed from a photo or FAW assessment.',
      keywords: [
        'grain safety',
        'food safety',
        'feed safety',
        'ear damage',
        'cob damage',
        'mold',
        'amag',
        'rot',
        'kernel',
        'harvest',
      ],
      sourceIds: ['CABI-HANDBOOK'],
      grade: AdvisorEvidenceGrade.verifiedCore,
      warning:
          'Do not eat, feed, sell, or mix suspicious moldy grain based on an app or image assessment; obtain current local food/feed-safety guidance.',
    ),
    AdvisorKnowledgeChunk(
      id: 'expert-escalation',
      title: 'Know when to request expert help',
      category: 'Expert Help',
      summary:
          'Escalate uncertainty when identification or action has important consequences.',
      body:
          'Contact the Municipal or City Agriculture Office, RCPC, or a qualified crop-protection specialist when identity remains uncertain, damage is unusual or severe, findings conflict, or a pesticide, food-safety, certification, insurance, or quarantine decision is involved.',
      keywords: [
        'expert',
        'technician',
        'agriculturist',
        'help',
        'contact',
        'uncertain',
        'severe',
        'report',
      ],
      sourceIds: ['DA-MO26-2021'],
      grade: AdvisorEvidenceGrade.verifiedCore,
    ),
    AdvisorKnowledgeChunk(
      id: 'expert-photo-evidence',
      title: 'Capture useful evidence photographs',
      category: 'Expert Help',
      summary:
          'A small set of clear, contextual images is more useful than one close-up.',
      body:
          'Photograph the whole plant first, then the damaged plant zone, the organism from more than one useful angle, and a safe scale reference. For a possible larva, include the head and rear when visible without unsafe handling. Keep images linked to the correct field, block, station, plant, date, and evaluator. Record uncertainty when focus, lighting, scale, or diagnostic features are inadequate.',
      keywords: [
        'photo',
        'picture',
        'larawan',
        'camera',
        'evidence',
        'capture',
        'head',
        'rear',
        'scale',
        'focus',
      ],
      sourceIds: ['CABI-HANDBOOK', 'WORMWISE-PROTOCOL'],
      grade: AdvisorEvidenceGrade.operationalRule,
      warning: identificationWarning,
    ),
    AdvisorKnowledgeChunk(
      id: 'expert-field-report',
      title: 'Prepare a field report for local agriculture officers',
      category: 'Expert Help',
      summary:
          'Provide location, crop context, assessment method, evidence, and recent treatment history.',
      body:
          'With the farmer\'s permission, prepare the field and barangay, municipality or city, province, crop and variety when known, planting date, growth stage, affected area and distribution, assessment date and method, and clear evidence photographs. Include recent pesticide applications and re-entry status. Start reporting with the Municipal/City or Provincial Agriculture Office or the relevant DA Regional Crop Protection Center. Collect or transport a specimen only when an officer explains how to do so safely.',
      keywords: [
        'report',
        'ulat',
        'reporting',
        'agriculture office',
        'municipal agriculturist',
        'city agriculturist',
        'provincial agriculture',
        'rcpc',
        'barangay',
        'specimen',
        'outbreak',
      ],
      sourceIds: ['DA-MO26-2021'],
      grade: AdvisorEvidenceGrade.verifiedCore,
    ),
  ];

  List<String> get categories => const [
    'Identification',
    'Scouting Protocol',
    'Symptoms & Evidence',
    'Management',
    'Safety',
    'Expert Help',
  ];

  List<AdvisorKnowledgeChunk> byCategory(String category) => chunks
      .where((chunk) => chunk.category == category)
      .toList(growable: false);

  AdvisorRagContext retrieve(
    String query, {
    int maxResults = 5,
    String? category,
    String? growthStage,
    bool forAi = false,
  }) {
    final normalized = _normalize(query);
    final tokens = _expandedTokens(normalized);
    if (tokens.isEmpty || maxResults <= 0) {
      return AdvisorRagContext(
        query: query.trim(),
        results: const [],
        sources: sources,
      );
    }
    // Identification teaches how to establish a stage. An already selected
    // field stage must not narrow that lesson to its vegetative range.
    final stage =
        _stageIn(normalized) ??
        (growthStageGuideArticle(query) != null
            ? null
            : _stageIn(_normalize(growthStage ?? '')));
    final topicBoosts = _topicBoosts(normalized, tokens);
    final safetyQuery = _containsAnyTerm(normalized, const [
      'pesticide',
      'spray',
      'chemical',
      'insecticide',
      'dose',
      'dosage',
      'rate',
      'mixture',
      'treatment',
      'threshold',
      'pestisidyo',
      'gamot',
      'pag-spray',
      'isprey',
    ]);
    final scored = <AdvisorRetrievedChunk>[];
    for (final chunk in chunks) {
      if (forAi && !isAiEligible(chunk)) continue;
      if (category != null && chunk.category != category) continue;
      if (stage != null &&
          chunk.growthStages.isNotEmpty &&
          !chunk.growthStages.contains(stage)) {
        continue;
      }
      final title = _normalize(chunk.title);
      final keywords = _normalize(chunk.keywords.join(' '));
      final summary = _normalize(chunk.summary);
      final body = _normalize(chunk.body);
      final titleTokens = _tokenSet(title);
      final keywordTokens = _tokenSet(keywords);
      final summaryTokens = _tokenSet(summary);
      final bodyTokens = _tokenSet(body);
      final filipinoTitle = _normalize(guideLiteralFilipino[chunk.title] ?? '');
      final filipinoSummary = _normalize(
        guideLiteralFilipino[chunk.summary] ?? '',
      );
      final filipinoBody = _normalize(guideLiteralFilipino[chunk.body] ?? '');
      final filipinoTitleTokens = _tokenSet(filipinoTitle);
      final filipinoSummaryTokens = _tokenSet(filipinoSummary);
      final filipinoBodyTokens = _tokenSet(filipinoBody);
      var score = 0.0;
      var meaningfulMatch = false;
      if (normalized.length > 3 && _containsTerm(title, normalized)) {
        score += 12;
      }
      if (normalized.length > 3 && _containsTerm(filipinoTitle, normalized)) {
        score += 12;
      }
      for (final token in tokens) {
        final distinctive = !_genericTerms.contains(token);
        if (titleTokens.contains(token)) {
          score += 5;
          meaningfulMatch |= distinctive;
        }
        if (keywordTokens.contains(token)) {
          score += 3.5;
          meaningfulMatch |= distinctive;
        }
        if (summaryTokens.contains(token)) {
          score += 2;
          meaningfulMatch |= distinctive;
        }
        if (bodyTokens.contains(token)) score += 1;
        if (filipinoTitleTokens.contains(token)) {
          score += 5;
          meaningfulMatch |= distinctive;
        }
        if (filipinoSummaryTokens.contains(token)) {
          score += 2;
          meaningfulMatch |= distinctive;
        }
        if (filipinoBodyTokens.contains(token)) score += 1;
      }
      final topicBoost = topicBoosts[chunk.id] ?? 0;
      score += topicBoost;
      if (stage != null && chunk.growthStages.contains(stage)) score += 6;
      if (safetyQuery && chunk.id == 'safety-pesticide') score += 40;
      if (safetyQuery && chunk.id == 'management-threshold') score += 14;
      if (score >= 5.5 &&
          (meaningfulMatch ||
              topicBoost > 0 ||
              (safetyQuery && chunk.id == 'safety-pesticide'))) {
        scored.add(AdvisorRetrievedChunk(chunk: chunk, score: score));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.chunk.id.compareTo(b.chunk.id);
    });
    final selected = scored.take(maxResults).toList(growable: true);
    if (safetyQuery &&
        (category == null || category == 'Safety') &&
        !selected.any((item) => item.chunk.id == 'safety-pesticide')) {
      selected.insert(
        0,
        AdvisorRetrievedChunk(
          chunk: chunks.firstWhere((item) => item.id == 'safety-pesticide'),
          score: 1000,
        ),
      );
    }
    if (safetyQuery && (category == null || category == 'Safety')) {
      selected.sort(
        (a, b) => a.chunk.id == 'safety-pesticide'
            ? -1
            : b.chunk.id == 'safety-pesticide'
            ? 1
            : b.score.compareTo(a.score),
      );
    }
    return AdvisorRagContext(
      query: query,
      results: List.unmodifiable(selected.take(maxResults)),
      sources: sources,
    );
  }

  static bool isAiEligible(AdvisorKnowledgeChunk chunk) =>
      !chunk.isReviewOverdue &&
      chunk.grade != AdvisorEvidenceGrade.expertValidationRequired &&
      chunk.sourceIds.every(
        (id) =>
            id == 'WORMWISE-PROTOCOL' ||
            sources[id]?.hasVerifiedReference == true,
      );

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Set<String> _expandedTokens(String normalized) {
    final tokens = normalized
        .split(' ')
        .where((token) => token.length > 2 && !_stopWords.contains(token))
        .toSet();
    const aliases = <String, List<String>>{
      'mais': ['maize', 'corn'],
      'corn': ['maize'],
      'maize': ['corn'],
      'uod': ['larva', 'caterpillar'],
      'dumi': ['frass', 'droppings'],
      'itlog': ['egg'],
      'pestisidyo': ['pesticide'],
      'pamatay-insekto': ['insecticide'],
      'isprey': ['spray'],
      'busbos': ['whorl', 'frass'],
      'pinsala': ['damage'],
      'dahon': ['leaf'],
      'bukid': ['field'],
      'hangganan': ['boundary'],
      'ulan': ['rain', 'weather'],
      'amag': ['mold'],
      'gamot': ['pesticide'],
      'suriin': ['inspect'],
      'kilalanin': ['identify'],
      'pagmamanman': ['scout'],
      'mag-inspeksyon': ['inspect', 'scout'],
      'inspeksyon': ['inspect', 'scout'],
      'kadalas': ['frequency', 'schedule'],
      'detect': ['identify', 'larva'],
      'characteristics': ['identify', 'larva'],
      'features': ['identify', 'larva'],
      'katangian': ['identify', 'larva'],
    };
    for (final token in List<String>.from(tokens)) {
      tokens.addAll(aliases[token] ?? const []);
    }
    return tokens;
  }

  static Set<String> _tokenSet(String normalized) =>
      normalized.split(' ').where((token) => token.isNotEmpty).toSet();

  static bool _containsTerm(String value, String term) =>
      ' $value '.contains(' $term ');

  static bool _containsAnyTerm(String value, List<String> terms) =>
      terms.any((term) => _containsTerm(value, term));

  static String? _stageIn(String normalized) {
    final match = RegExp(
      r'\b(ve|vt|v[1-9][0-9]?|r[1-6])\b',
    ).firstMatch(normalized);
    return match?.group(1)?.toUpperCase();
  }

  /// Selects the breadth of the identification lesson, not a farmer's stage.
  /// Specific stage questions retain their focused source; broad questions
  /// receive the complete, compact overview before other lexical matches.
  static String? growthStageGuideArticle(String query) {
    final value = _normalize(query);
    final corn = _containsAnyTerm(value, const [
      'corn',
      'maize',
      'mais',
      'crop',
    ]);
    final identification = _containsAnyTerm(value, const [
      'identify',
      'determine',
      'recognize',
      'know',
      'tell',
      'learn',
      'malalaman',
      'kilalanin',
    ]);
    final stageQuestion =
        _containsAnyTerm(value, const [
          'growth stage',
          'growth stages',
          'crop stage',
          'crop stages',
          'leaf collar',
          'leaf collars',
          'count leaves',
          'stage ng mais',
        ]) ||
        (_containsAnyTerm(value, const ['development', 'yugto']) && corn) ||
        (corn &&
            identification &&
            _containsAnyTerm(value, const ['stage', 'stages'])) ||
        (_stageIn(value) != null &&
            _containsAnyTerm(value, const [
              'identify',
              'determine',
              'recognize',
              'look',
              'looks',
              'what is',
              'difference',
              'malalaman',
              'kilalanin',
            ]));
    if (!stageQuestion) return null;
    if (_containsTerm(value, 'vegetative') &&
        _containsTerm(value, 'reproductive')) {
      return 'identify-corn-growth-stage';
    }
    for (final (terms, id) in [
      (['emergence', 'seedling'], 'clemson-growth-emergence'),
      (['tasseling', 'tassel'], 'clemson-growth-tasseling'),
      (['silking', 'blister'], 'clemson-growth-silking-blister'),
      (['milk', 'dough'], 'clemson-growth-milk-dough'),
      (['dent', 'black layer', 'maturity'], 'clemson-growth-dent-maturity'),
    ]) {
      if (_containsAnyTerm(value, terms)) return id;
    }
    if (_containsAnyTerm(value, const [
      'leaf collar',
      'leaf collars',
      'count leaves',
      'vegetative',
    ])) {
      return 'clemson-growth-leaf-collars';
    }
    final stage = _stageIn(value);
    if (stage == 'VE') return 'clemson-growth-emergence';
    if (stage == 'VT') return 'clemson-growth-tasseling';
    if (stage != null && stage.startsWith('V')) {
      return 'clemson-growth-leaf-collars';
    }
    if (stage == 'R1' || stage == 'R2') return 'clemson-growth-silking-blister';
    if (stage == 'R3' || stage == 'R4') return 'clemson-growth-milk-dough';
    if (stage == 'R5' || stage == 'R6') return 'clemson-growth-dent-maturity';
    return 'identify-corn-growth-stage';
  }

  static Map<String, double> _topicBoosts(String query, Set<String> tokens) {
    final boosts = <String, double>{};
    void prefer(String id, [double value = 24]) {
      if ((boosts[id] ?? 0) < value) boosts[id] = value;
    }

    final growthGuide = growthStageGuideArticle(query);
    if (growthGuide != null) prefer(growthGuide, 1000);

    if (tokens.intersection(const {
      'frequency',
      'schedule',
      'often',
      'kadalas',
    }).isNotEmpty) {
      prefer('scout-schedule', 30);
    }

    if (_containsAnyTerm(query, const [
      'what is faw',
      'what is fall armyworm',
      'ano ang faw',
      'ano ang fall armyworm',
    ])) {
      prefer('identify-overview', 30);
    }
    if (tokens.intersection(const {
      'larva',
      'caterpillar',
      'uod',
      'identify',
      'kilalanin',
    }).isNotEmpty) {
      prefer('identify-larva');
    }
    if (tokens.intersection(const {'egg', 'eggs', 'itlog'}).isNotEmpty) {
      prefer('identify-eggs');
    }
    if (tokens.intersection(const {'frass', 'droppings', 'dumi'}).isNotEmpty) {
      prefer('evidence-frass', 30);
    }
    if (tokens.intersection(const {
      'boundary',
      'outline',
      'polygon',
      'road',
      'pond',
      'house',
      'hangganan',
    }).isNotEmpty) {
      prefer('scout-boundary');
    }
    if (tokens.intersection(const {
      'station',
      'stations',
      'sample',
      'sampling',
      'route',
      'pattern',
    }).isNotEmpty) {
      prefer('scout-field');
    }
    if (tokens.intersection(const {
      'risk',
      'threshold',
      'percentage',
      'moderate',
    }).isNotEmpty) {
      prefer('management-threshold');
    }
    if (tokens.intersection(const {'rain', 'weather', 'ulan'}).isNotEmpty) {
      prefer('management-weather-follow-up');
    }
    if (tokens.intersection(const {
      'mold',
      'amag',
      'rot',
      'grain',
    }).isNotEmpty) {
      prefer('safety-ear-grain');
    }
    if (tokens.intersection(const {
      'photo',
      'picture',
      'larawan',
      'litrato',
    }).isNotEmpty) {
      prefer('expert-photo-evidence', 12);
    }
    if (_stageIn(query) != null &&
        tokens.intersection(const {
          'inspect',
          'scout',
          'check',
          'suriin',
          'stage',
          'growth',
        }).isNotEmpty) {
      prefer('scout-growth-stage', 30);
    }
    return boosts;
  }

  static const _genericTerms = <String>{
    'faw',
    'fall',
    'armyworm',
    'maize',
    'corn',
    'mais',
    'field',
    'bukid',
    'plant',
    'plants',
    'assessment',
    'wormwise',
  };

  static const _stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'what',
    'when',
    'where',
    'which',
    'how',
    'does',
    'this',
    'that',
    'from',
    'about',
    'into',
    'have',
    'should',
    'can',
    'ang',
    'mga',
    'para',
    'kung',
    'isang',
    'ito',
    'iyan',
    'paano',
    'ano',
  };
}
