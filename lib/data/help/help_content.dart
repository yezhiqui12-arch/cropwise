/// Offline product help. Keep these instructions aligned with visible screens.
/// English and Filipino copy are authored together, including searchable FAQs.
class HelpCopy {
  HelpCopy(String pair)
    : english = pair.split('|').first,
      filipino = pair.contains('|') ? pair.split('|').last : pair;
  final String english;
  final String filipino;
  String inLanguage(bool filipinoSelected) =>
      filipinoSelected ? filipino : english;
}

class HelpQuestion {
  HelpQuestion(String question, String answer)
    : question = HelpCopy(question),
      answer = HelpCopy(answer);
  final HelpCopy question;
  final HelpCopy answer;
}

enum HelpDestination {
  fields,
  assessments,
  map,
  advisor,
  profile,
  language,
  models,
  ai,
  guidelines,
  trends,
  notifications,
}

class HelpTopic {
  HelpTopic(this.id, String title, String description)
    : title = HelpCopy(title),
      description = HelpCopy(description);
  final String id;
  final HelpCopy title;
  final HelpCopy description;
}

class HelpArticle {
  HelpArticle(
    this.id,
    this.topic,
    String title,
    String summary,
    String location,
    List<String> steps,
    String outcome, {
    this.destination,
    List<HelpQuestion> questions = const [],
    this.related = const [],
  }) : title = HelpCopy(title),
       summary = HelpCopy(summary),
       location = HelpCopy(location),
       steps = List.unmodifiable(steps.map(HelpCopy.new)),
       outcome = HelpCopy(outcome),
       questions = List.unmodifiable(questions);
  final String id, topic;
  final HelpCopy title, summary, location, outcome;
  final List<HelpCopy> steps;
  final List<HelpQuestion> questions;
  final List<String> related;
  final HelpDestination? destination;
  Iterable<String> get searchableText sync* {
    for (final copy in [title, summary, location, outcome, ...steps]) {
      yield copy.english;
      yield copy.filipino;
    }
    for (final faq in questions) {
      yield faq.question.english;
      yield faq.question.filipino;
      yield faq.answer.english;
      yield faq.answer.filipino;
    }
  }
}

final helpTopics = List<HelpTopic>.unmodifiable([
  HelpTopic(
    'start',
    'Getting started|Pagsisimula',
    'Your first visit and app navigation|Unang paggamit at paghanap ng mga screen',
  ),
  HelpTopic(
    'fields',
    'Fields & crops|Mga bukid at pananim',
    'Create, select, edit, and restore fields|Gumawa, pumili, baguhin, at ibalik ang bukid',
  ),
  HelpTopic(
    'assess',
    'Assessment walkthroughs|Mga hakbang sa assessment',
    'Setup, routes, stations, and growth stages|Setup, ruta, istasyon, at yugto ng paglaki',
  ),
  HelpTopic(
    'photos',
    'Photos & screening|Mga larawan at screening',
    'Capture evidence and understand model output|Kumuha ng ebidensya at unawain ang resulta ng modelo',
  ),
  HelpTopic(
    'results',
    'Records & results|Mga rekord at resulta',
    'Resume, review, compare, and export|Ipagpatuloy, suriin, ihambing, at i-export',
  ),
  HelpTopic(
    'maps',
    'Maps & location|Mga mapa at lokasyon',
    'Outlines, GPS, and saved sample points|Hangganan, GPS, at lokasyon ng mga sample',
  ),
  HelpTopic(
    'expert',
    'Expert review|Pagsusuri ng eksperto',
    'Submission, consent, messages, and scores|Pagpapasa, pahintulot, mensahe, at marka',
  ),
  HelpTopic(
    'advisor',
    'Advisor & Guidelines|Advisor at Guidelines',
    'Questions, chats, references, and offline reading|Mga tanong, chat, sanggunian, at offline na pagbasa',
  ),
  HelpTopic(
    'account',
    'Account & backup|Account at backup',
    'Guest access, sign-in, sync, and recovery|Guest access, pag-sign in, sync, at pagbawi',
  ),
  HelpTopic(
    'preferences',
    'Preferences & alerts|Mga setting at abiso',
    'Language, models, sources, and notifications|Wika, mga modelo, sanggunian, at abiso',
  ),
  HelpTopic(
    'trouble',
    'Fix a problem|Ayusin ang problema',
    'Practical checks when something stops working|Mga hakbang kapag may hindi gumagana',
  ),
  HelpTopic(
    'privacy',
    'Privacy & support|Privacy at suporta',
    'Data sharing, limitations, and reporting issues|Pagbabahagi ng datos, limitasyon, at pag-ulat',
  ),
]);

final helpArticles = List<HelpArticle>.unmodifiable([
  HelpArticle(
    'first-visit',
    'start',
    'Start using WormWise|Simulang gamitin ang WormWise',
    'Set up one maize field, then begin a guided assessment.|Magrehistro muna ng isang bukid ng mais bago magsimula ng assessment.',
    'Home → My Fields; or More → My Fields|Home → My Fields; o More → My Fields',
    [
      'Choose guest access or sign in to your account.|Pumili ng guest access o mag-sign in sa account.',
      'Open My Fields, add a field, and enter its crop and location details.|Buksan ang My Fields, magdagdag ng bukid, at ilagay ang detalye ng pananim at lokasyon.',
      'Confirm the approximate outline and select that field for your workspace.|Kumpirmahin ang tinatayang hangganan at piliin ang bukid na gagamitin.',
      'Return to Home and open the assessment action.|Bumalik sa Home at buksan ang aksyon para sa assessment.',
    ],
    'The selected field becomes the context for your next assessment.|Ang napiling bukid ang gagamitin sa susunod na assessment.',
    destination: HelpDestination.fields,
    related: ['create-field', 'first-assessment', 'offline'],
    questions: [
      HelpQuestion(
        'Do I need an account to collect field data?|Kailangan ba ng account para magtala sa bukid?',
        'Guest access supports local fieldwork. An account and internet are needed for online account services.|Maaaring magtala nang lokal bilang guest. Kailangan ng account at internet para sa online na serbisyo ng account.',
      ),
    ],
  ),
  HelpArticle(
    'navigation',
    'start',
    'Find your way around the app|Hanapin ang mga bahagi ng app',
    'The bottom navigation connects your workspace, records, map, Advisor, and more tools.|Nasa ibabang navigation ang workspace, rekord, mapa, Advisor, at iba pang kagamitan.',
    'Bottom navigation → Home / Assess / Map / Guide / More|Ibabang navigation → Home / Assess / Map / Guide / More',
    [
      'Use Home for your selected field and current assessment shortcuts.|Gamitin ang Home para sa napiling bukid at kasalukuyang assessment.',
      'Use Assess for saved records and Map for field location context.|Gamitin ang Assess para sa mga rekord at Map para sa lokasyon ng bukid.',
      'Use Guide for Advisor conversations and More for fields, preferences, and Help.|Gamitin ang Guide para sa Advisor at More para sa bukid, setting, at Help.',
    ],
    'Active scouting opens its own assessment screen; return to the saved record to resume.|May sariling screen ang aktibong assessment; buksan ang rekord upang ipagpatuloy.',
    related: ['resume', 'help-guidelines'],
  ),
  HelpArticle(
    'offline',
    'start',
    'What works without internet?|Ano ang gumagana kahit walang internet?',
    'Field recording, saved evidence, on-device screening, and this Help Center work locally.|Lokal na gumagana ang pagtatala, ebidensya, screening sa device, at Help Center.',
    'Throughout the app|Sa buong app',
    [
      'Set up your field and check the outline before going to the field.|Ihanda ang bukid at tingnan ang hangganan bago pumunta sa bukid.',
      'Continue supported assessment steps and save accepted evidence on the phone.|Ipagpatuloy ang mga hakbang sa assessment at i-save ang tinanggap na ebidensya sa telepono.',
      'Reconnect for sync, account backup, online Advisor replies, and expert review.|Kumonekta muli para sa sync, backup, online na Advisor, at expert review.',
    ],
    'Online map imagery and weather may be unavailable; use available fallbacks and the manual weather question.|Maaaring mawala ang online na mapa at panahon; gamitin ang fallback at manwal na tanong sa panahon.',
    related: ['map-offline', 'backup', 'advisor-offline'],
  ),
  HelpArticle(
    'create-field',
    'fields',
    'Add a maize field|Magdagdag ng bukid ng mais',
    'Keep each field and its current crop details together.|Pagsamahin ang rekord ng bukid at kasalukuyang pananim.',
    'More → My Fields → Add Field|More → My Fields → Add Field',
    [
      'Enter a recognizable field name and select its barangay.|Maglagay ng madaling makilalang pangalan at piliin ang barangay.',
      'Enter the variety, planting date, and other crop details requested by the form.|Ilagay ang variety, petsa ng pagtatanim, at iba pang hinihinging detalye.',
      'Use the boundary setup to confirm an approximate outline, then save the field.|Gamitin ang boundary setup para kumpirmahin ang tinatayang hangganan, saka i-save.',
    ],
    'The field is saved locally and can be selected for assessment.|Naka-save nang lokal ang bukid at maaari nang piliin para sa assessment.',
    destination: HelpDestination.fields,
    related: ['boundary', 'varieties', 'select-field'],
  ),
  HelpArticle(
    'select-field',
    'fields',
    'Switch your active field|Palitan ang aktibong bukid',
    'Select the correct field before starting an assessment or asking about its records.|Piliin ang tamang bukid bago mag-assessment o magtanong tungkol sa rekord nito.',
    'More → My Fields → Field Details → Use this field|More → My Fields → Field Details → Use this field',
    [
      'Open My Fields and select the field you want to work on.|Buksan ang My Fields at piliin ang bukid na gagamitin.',
      'Check its name, location, and crop details.|Tingnan ang pangalan, lokasyon, at detalye ng pananim.',
      'Choose Use this field and confirm the selected field on Home.|Piliin ang Use this field at tingnan ang napiling bukid sa Home.',
    ],
    'New work uses the selected field. Existing assessments remain linked to their original field.|Gagamitin ng bagong assessment ang napiling bukid. Mananatili ang dating ugnayan ng mga lumang rekord.',
    destination: HelpDestination.fields,
    related: ['edit-field', 'resume'],
  ),
  HelpArticle(
    'edit-field',
    'fields',
    'Edit field and crop details|Baguhin ang detalye ng bukid at pananim',
    'Correct field information from its details screen.|Itama ang impormasyon mula sa Field Details.',
    'My Fields → Field Details → Edit field|My Fields → Field Details → Edit field',
    [
      'Open the field and choose Edit field.|Buksan ang bukid at piliin ang Edit field.',
      'Update the details you need to correct and review the location and crop entries.|Baguhin ang kailangang itama at suriin ang lokasyon at pananim.',
      'Save, then check the field details again.|I-save at tingnan muli ang Field Details.',
    ],
    'Changes are saved locally. An assessment keeps the boundary version recorded for that assessment.|Naka-save nang lokal ang pagbabago. Pinapanatili ng assessment ang boundary version na ginamit dito.',
    destination: HelpDestination.fields,
    related: ['boundary', 'growth-stage'],
  ),
  HelpArticle(
    'varieties',
    'fields',
    'Choose a variety or suggest one|Pumili o magmungkahi ng variety',
    'Use the available variety list and review possible duplicate names.|Gamitin ang listahan ng variety at suriin ang posibleng magkaparehong pangalan.',
    'Add Field / Edit field → Variety|Add Field / Edit field → Variety',
    [
      'Search the variety choices using the name on your seed information.|Hanapin ang variety gamit ang pangalan sa impormasyon ng binhi.',
      'If you enter another name, review any suggested existing match.|Kung ibang pangalan ang ilalagay, suriin ang mungkahing kapareho nito.',
      'Save the field; a submitted catalog suggestion may need expert or administrator review.|I-save ang bukid; maaaring kailanganin ang pagsusuri ng eksperto o admin para sa mungkahi.',
    ],
    'A variety name describes the crop; it is not proof of pest resistance or a treatment recommendation.|Ang pangalan ng variety ay detalye ng pananim, hindi patunay ng resistensya o rekomendasyon ng paggamot.',
    destination: HelpDestination.fields,
    related: ['create-field'],
  ),
  HelpArticle(
    'delete-field',
    'fields',
    'Delete or restore a field|Burahin o ibalik ang bukid',
    'Deleted fields go to Recently Deleted; read the confirmation before proceeding.|Napupunta sa Recently Deleted ang bukid; basahin muna ang kumpirmasyon.',
    'My Fields → Field Details → Delete field; My Fields → Recently Deleted|My Fields → Field Details → Delete field; My Fields → Recently Deleted',
    [
      'Check that you selected the correct field before choosing Delete field.|Tiyaking tamang bukid ang napili bago piliin ang Delete field.',
      'Read the retention details in the confirmation and move it to Recently Deleted.|Basahin ang detalye ng retention at ilipat sa Recently Deleted.',
      'To restore it, open Recently Deleted and use its available restore action before expiry.|Para ibalik, buksan ang Recently Deleted at gamitin ang restore bago matapos ang retention.',
    ],
    'A field that has already been permanently removed cannot be restored from Recently Deleted.|Hindi na maibabalik mula sa Recently Deleted ang permanenteng nabura.',
    destination: HelpDestination.fields,
    related: ['backup', 'privacy-data'],
  ),
  HelpArticle(
    'first-assessment',
    'assess',
    'Complete your first assessment|Tapusin ang unang assessment',
    'Follow one guided session from setup to a saved result.|Sundin ang gabay mula setup hanggang sa naka-save na resulta.',
    'Home → Assessment action; or selected field → Assessment|Home → Aksyon sa assessment; o napiling bukid → Assessment',
    [
      'Select a maize field with a confirmed outline. Open the assessment action.|Pumili ng bukid na may kumpirmadong hangganan. Buksan ang assessment.',
      'Confirm the growth stage, complete treatment and weather questions, and check that field entry is allowed.|Kumpirmahin ang yugto ng paglaki, sagutin ang paggamot at panahon, at tingnan kung pinapayagan ang pagpasok.',
      'Follow Guided scouting to record 20 different plants in each sampling block, no larger than one hectare.|Sundin ang Guided scouting upang itala ang 20 magkakaibang halaman sa bawat sampling block na hindi lalampas sa isang ektarya.',
      'Review the saved samples, confirm natural enemies, and finish each block before completing the assessment.|Suriin ang mga naka-save na sample, kumpirmahin ang likas na mga kaaway, at tapusin ang bawat block bago kumpletuhin ang assessment.',
      'Open the saved results and decide whether to submit them for expert review.|Buksan ang resulta at magpasya kung ipapasa para sa expert review.',
    ],
    'A completed record contains sampled findings and evidence; expert scores are published separately after review.|May sample findings at ebidensya ang rekord; hiwalay na ilalathala ang marka ng eksperto matapos ang review.',
    related: ['safety', 'route', 'stations', 'complete', 'submit-expert'],
  ),
  HelpArticle(
    'growth-stage',
    'assess',
    'Choose or correct the growth stage|Piliin o itama ang yugto ng paglaki',
    'Growth stage controls which workflow and observations the app requests.|Ang yugto ng paglaki ang batayan ng workflow at mga obserbasyon.',
    'Assessment Setup → Growth stage; assessment → growth-stage correction when available|Assessment Setup → Growth stage; assessment → pagwawasto ng yugto kung available',
    [
      'Compare the crop with the available growth-stage choices and references.|Ihambing ang pananim sa pagpipilian at mga sanggunian.',
      'Select your best estimate and record uncertainty when the form offers it.|Piliin ang pinakamalapit na yugto at itala ang pag-aalinlangan kung may opsyon.',
      'If correcting an existing assessment, review the correction explanation before confirming.|Kung itatama ang lumang assessment, basahin ang paliwanag bago kumpirmahin.',
    ],
    'Use the updated prompts for that stage; a planting date alone does not confirm the actual stage.|Sundin ang bagong mga hakbang para sa yugto; hindi sapat ang petsa ng pagtatanim para kumpirmahin ito.',
    related: [
      'stage-early',
      'stage-vegetative',
      'stage-reproductive',
      'stage-late',
    ],
  ),
  HelpArticle(
    'safety',
    'assess',
    'Complete the field-entry safety check|Kumpletuhin ang pagsusuri bago pumasok sa bukid',
    'The setup checks recent treatment and the waiting period before collection.|Sinusuri ng setup ang kamakailang paggamot at panahon ng paghihintay.',
    'Assessment Setup → Treatment history and waiting period|Assessment Setup → Treatment history at waiting period',
    [
      'Choose no recent treatment, treatment applied, or unknown history truthfully.|Piliin nang tapat kung walang paggamot, may paggamot, o hindi alam.',
      'For a treatment, enter the application time and verified re-entry information requested.|Kung may paggamot, ilagay ang oras at beripikadong impormasyon sa muling pagpasok.',
      'Read the safety result. If entry is blocked or information is unknown, verify it before collecting samples.|Basahin ang resulta. Kung bawal pumasok o kulang ang impormasyon, beripikahin muna bago mangolekta.',
    ],
    'Saving setup does not override a blocked entry decision.|Hindi binabago ng pag-save ng setup ang pagbabawal sa pagpasok.',
    related: ['weather', 'cannot-start'],
    questions: [
      HelpQuestion(
        'Can I skip an unknown waiting period?|Maaari bang laktawan ang hindi alam na waiting period?',
        'Do not guess. Verify the treatment record, label, or adviser information requested by the setup.|Huwag manghula. Beripikahin ang treatment record, label, o impormasyon ng tagapayo na hinihingi sa setup.',
      ),
    ],
  ),
  HelpArticle(
    'weather',
    'assess',
    'Answer the recent weather question|Sagutin ang tanong sa kamakailang panahon',
    'Recent rain is context for the assessment, with a manual fallback.|Konteksto ng assessment ang kamakailang ulan at may manwal na fallback.',
    'Assessment Setup → Recent weather|Assessment Setup → Recent weather',
    [
      'Wait for the recent-weather lookup when connected.|Hintayin ang pagkuha ng impormasyon ng panahon kung online.',
      'Check whether rain wet this field in the last 48 hours.|Tingnan kung nabasa ng ulan ang bukid nitong nakaraang 48 oras.',
      'Use Yes, No, or I am not sure based on what you know; retry the lookup if useful.|Piliin ang Yes, No, o I am not sure batay sa alam mo; ulitin ang lookup kung kailangan.',
    ],
    'Unavailable weather does not require inventing a value or bypassing the safety check.|Hindi kailangang mag-imbento ng sagot o laktawan ang safety check kung walang weather data.',
    related: ['offline', 'safety'],
  ),
  HelpArticle(
    'route',
    'assess',
    'Prepare and follow the scouting route|Ihanda at sundin ang ruta',
    'Guided scouting shows the next plant location and your saved progress.|Ipinapakita ng Guided scouting ang susunod na lokasyon at naka-save na progreso.',
    'Active assessment → Guided scouting|Aktibong assessment → Guided scouting',
    [
      'Review the field outline and the 20 dispersed plant pins for the current block.|Suriin ang hangganan at 20 nakakalat na pin ng halaman para sa kasalukuyang block.',
      'Follow the highlighted next pin. Tap a pin to view its sample; expand the map when needed.|Sundin ang naka-highlight na susunod na pin. I-tap ang pin para makita ang sample; palawakin ang mapa kung kailangan.',
      'At the next plant, tap the arrival action, take photos, and save before continuing.|Sa susunod na halaman, i-tap ang aksyon sa pagdating, kumuha ng larawan, at i-save bago magpatuloy.',
    ],
    'A proposed target is not a recorded GPS fix. The Map tab does not replace the active scouting workflow.|Hindi GPS fix ang iminungkahing target. Hindi pamalit sa aktibong workflow ang Map tab.',
    related: ['stations', 'gps', 'map-offline'],
  ),
  HelpArticle(
    'stations',
    'assess',
    'Record 20 plant samples per block|Itala ang 20 sample ng halaman bawat block',
    'Sample different plants across each block, no larger than one hectare.|Pumili ng magkakaibang halaman sa bawat block na hindi lalampas sa isang ektarya.',
    'Active assessment → Guided scouting → Current plant|Aktibong assessment → Guided scouting → Kasalukuyang halaman',
    [
      'Follow the map to each of the 20 plant locations and save the sample before moving on.|Sundin ang mapa sa bawat isa sa 20 lokasyon at i-save ang sample bago magpatuloy.',
      'Take or import up to three photos of the same plant. Extra views do not count as extra plants.|Kumuha o mag-import ng hanggang tatlong larawan ng parehong halaman. Hindi dagdag na halaman ang dagdag na view.',
      'For batch import, group each photo with its actual plant before saving and screening. Review the samples and confirm natural enemies before finishing the block.|Sa batch import, itugma ang bawat larawan sa totoong halaman bago i-save at i-screen. Suriin ang mga sample at kumpirmahin ang likas na mga kaaway bago tapusin ang block.',
    ],
    'An assessment with several blocks requires 20 different plants in each block. Older saved assessments retain their original sampling requirements.|Kailangan ng 20 magkakaibang halaman sa bawat block ng assessment na may maraming block. Nananatili ang orihinal na sampling requirements ng mga lumang assessment.',
    related: ['stage-early', 'stage-vegetative', 'photos', 'complete'],
  ),
  HelpArticle(
    'stage-early',
    'assess',
    'Assess seedlings at VE–V2|Suriin ang punla sa VE–V2',
    'Early-stage prompts distinguish planting positions from living seedlings.|Magkaiba ang puwesto ng pagtatanim at buhay na punla sa unang yugto.',
    'Assessment with VE, V1, or V2 → Station workflow|Assessment na VE, V1, o V2 → Station workflow',
    [
      'Complete the station context and planting-position prompts shown.|Kumpletuhin ang konteksto at tanong sa mga puwesto.',
      'Record the seedlings or screening evidence requested for each position.|Itala ang punla o screening evidence na hinihingi sa bawat puwesto.',
      'Use the offered unavailable or uncertain choices when observation cannot be completed, then review the station.|Gamitin ang available na opsyon para sa kulang o hindi tiyak na obserbasyon, saka suriin ang istasyon.',
    ],
    'A missing seedling is not automatically a confirmed FAW observation.|Ang nawawalang punla ay hindi awtomatikong kumpirmadong FAW observation.',
    related: ['growth-stage', 'stations', 'screening'],
  ),
  HelpArticle(
    'stage-vegetative',
    'assess',
    'Assess vegetative maize at V3–V12|Suriin ang mais sa V3–V12',
    'Capture each sampled plant and follow the stage-specific inspection prompts.|Kunan ang bawat sample at sundin ang tanong para sa yugto nito.',
    'V3–V6 or V7–V12 assessment → Plant workflow|Assessment na V3–V6 o V7–V12 → Plant workflow',
    [
      'Visit the station and open the current plant position.|Puntahan ang istasyon at buksan ang kasalukuyang posisyon.',
      'Capture the requested plant views, review screening, and enter any requested observations.|Kunan ang hinihinging mga view, suriin ang screening, at sagutin ang hinihinging obserbasyon.',
      'For eligible manual V7–V12 records, keep the recorded leaf-damage score separate from current infestation.|Para sa angkop na manwal na V7–V12 record, ihiwalay ang leaf-damage score sa kasalukuyang infestation.',
    ],
    'Automatic image screening does not generate a Davis 0–9 score.|Hindi gumagawa ng Davis 0–9 score ang awtomatikong screening.',
    related: ['photos', 'screening', 'measurements', 'expert-scores'],
  ),
  HelpArticle(
    'stage-reproductive',
    'assess',
    'Assess maize at VT–R2|Suriin ang mais sa VT–R2',
    'Use the reproductive-stage prompts for external plant and ear evidence.|Gamitin ang tanong sa reproductive stage para sa panlabas na halaman at bunga.',
    'VT–R2 assessment → Plant workflow|Assessment na VT–R2 → Plant workflow',
    [
      'Confirm the stage and follow the station route.|Kumpirmahin ang yugto at sundin ang ruta.',
      'Capture the requested external plant views and record the observations offered.|Kunan ang panlabas na view at itala ang hinihinging obserbasyon.',
      'Review every sampled plant and station before completion.|Suriin ang bawat sample at istasyon bago tapusin.',
    ],
    'Use the workflow for the selected stage rather than applying a seedling or vegetative form.|Gamitin ang workflow ng napiling yugto sa halip na form para sa punla o vegetative stage.',
    related: ['growth-stage', 'stations', 'photos'],
  ),
  HelpArticle(
    'stage-late',
    'assess',
    'Assess ears at R3–R6|Suriin ang bunga sa R3–R6',
    'Late-stage workflows separate external examination from permitted ear opening.|Magkahiwalay ang panlabas na pagsusuri at pinahihintulutang pagbubukas ng bunga.',
    'R3–R6 assessment → Late-season setup and ear workflow|Assessment na R3–R6 → Late-season setup at ear workflow',
    [
      'Record harvest context and the ear-opening permission requested by setup.|Itala ang konteksto ng ani at pahintulot na hinihingi sa setup.',
      'Capture external ear evidence first.|Kunan muna ang panlabas na ebidensya ng bunga.',
      'If the workflow allows opening, follow its selected subsample and limits; record the requested internal findings.|Kung pinapayagan, sundin ang napiling subsample at limitasyon at itala ang panloob na findings.',
    ],
    'External evidence and opened-ear findings are separate records; do not open additional ears outside the permission.|Magkahiwalay ang panlabas at panloob na findings; huwag lumampas sa pahintulot.',
    related: ['growth-stage', 'photos', 'complete'],
  ),
  HelpArticle(
    'photos',
    'photos',
    'Capture useful assessment photos|Kumuha ng kapaki-pakinabang na larawan',
    'Use the guided camera so each accepted photo belongs to the right sample.|Gamitin ang guided camera para maiugnay ang larawan sa tamang sample.',
    'Active assessment → Plant or station → Capture evidence|Aktibong assessment → Halaman o istasyon → Capture evidence',
    [
      'Read the requested view and position the plant inside the camera guide.|Basahin ang hinihinging view at iposisyon ang halaman sa gabay ng camera.',
      'Hold steady, use clear light, and keep the subject in focus.|Panatilihing steady, gumamit ng malinaw na ilaw, at tiyaking naka-focus.',
      'Review the preview and any quality warnings. Retake if needed, then accept the photo.|Suriin ang preview at babala sa kalidad. Ulitin kung kailangan, saka tanggapin.',
    ],
    'Accepted evidence is saved privately on the phone. A camera preview alone is not an accepted saved photo.|Pribadong naka-save sa telepono ang tinanggap na ebidensya. Hindi pa naka-save na ebidensya ang preview lamang.',
    related: ['photo-quality', 'screening', 'photo-viewer'],
  ),
  HelpArticle(
    'photo-quality',
    'photos',
    'Retake or resolve a photo warning|Ulitin ang larawan o ayusin ang babala',
    'A clear view gives the app and reviewer more usable evidence.|Mas magagamit ng app at eksperto ang malinaw na larawan.',
    'Guided camera → Preview / quality feedback|Guided camera → Preview / quality feedback',
    [
      'Read whether the issue is blur, lighting, framing, or another capture problem.|Basahin kung blur, ilaw, framing, o ibang problema ang dahilan.',
      'Adjust your distance or light, stabilize the phone, and retake the requested view.|Ayusin ang layo o ilaw, patatagin ang telepono, at kunan muli.',
      'Accept the improved image; use a fallback only when the workflow explicitly offers it.|Tanggapin ang mas malinaw na larawan; gumamit lang ng fallback kapag may ganoong opsyon.',
    ],
    'Passing a technical quality check does not confirm pest identity.|Hindi kumpirmasyon ng pagkakakilanlan ng peste ang pagpasa sa quality check.',
    related: ['camera-problem', 'photos'],
  ),
  HelpArticle(
    'screening',
    'photos',
    'Understand image screening and detection boxes|Unawain ang screening at detection boxes',
    'Models suggest visible damage or signs; they do not replace expert review.|Nagmumungkahi ng pinsala o palatandaan ang modelo; hindi ito pamalit sa eksperto.',
    'Plant analysis / saved plant evidence; More → Models|Plant analysis / naka-save na ebidensya; More → Models',
    [
      'Read whether screening found damage, found no damage, or was unavailable.|Basahin kung may pinsala, walang pinsala, o hindi available ang screening.',
      'When enabled, inspect detection boxes and their suggested signs rather than treating confidence as certainty.|Kapag enabled, suriin ang mga kahon at palatandaan; hindi katiyakan ang confidence.',
      'Keep uncertain evidence and seek expert review when needed.|Panatilihin ang ebidensyang hindi tiyak at humingi ng expert review kung kailangan.',
    ],
    'A model-positive sample is not a confirmed diagnosis, field-wide severity, or Davis score.|Hindi diagnosis, marka ng buong bukid, o Davis score ang model-positive na sample.',
    destination: HelpDestination.models,
    related: ['model-settings', 'measurements', 'submit-expert'],
    questions: [
      HelpQuestion(
        'Does no damage detected mean the field has no FAW?|Ibig bang sabihin ng no damage detected ay walang FAW sa bukid?',
        'No. It describes screening of that image and can miss signs. It does not establish the condition of the whole field.|Hindi. Resulta ito ng isang larawan at maaaring may hindi makita. Hindi nito pinatutunayan ang kalagayan ng buong bukid.',
      ),
      HelpQuestion(
        'Are larva, frass, egg, and damage boxes confirmed observations?|Kumpirmadong obserbasyon ba ang mga kahon para sa uod, frass, itlog, at pinsala?',
        'They are model suggestions. Additional pest suggestions may be shown for detected larva crops.|Mungkahi lamang ang mga ito. Maaaring magpakita ng dagdag na mungkahi sa uri ng peste para sa bahagi ng larawang may uod.',
      ),
    ],
  ),
  HelpArticle(
    'photo-viewer',
    'photos',
    'View saved plant and station evidence|Tingnan ang ebidensya ng halaman at istasyon',
    'Open evidence from the saved record to preserve its context.|Buksan ang ebidensya mula sa rekord upang makita ang konteksto.',
    'Assess → Assessment → Station → Plant / Evidence|Assess → Assessment → Istasyon → Halaman / Ebidensya',
    [
      'Open the assessment and the station or plant you want to review.|Buksan ang assessment at istasyon o halaman.',
      'Open the evidence image and use the available zoom or viewer controls.|Buksan ang larawan at gamitin ang zoom o mga kontrol.',
      'Check the recorded capture and location details alongside the image.|Tingnan ang detalye ng pagkuha at lokasyon kasama ng larawan.',
    ],
    'Evidence belongs to its saved sample; viewing it does not create a new observation.|Nakaugnay ang ebidensya sa sample; hindi bagong obserbasyon ang pagtingin dito.',
    destination: HelpDestination.assessments,
    related: ['missing-photos', 'gps'],
  ),
  HelpArticle(
    'resume',
    'results',
    'Save and resume an assessment|I-save at ipagpatuloy ang assessment',
    'Resume the existing record instead of starting another visit.|Ipagpatuloy ang lumang rekord sa halip na gumawa ng panibago.',
    'Assess → Open an unfinished record → Resume / available continuation action|Assess → Buksan ang hindi pa tapos → Resume / available na aksyon',
    [
      'Accept and save the current plant or station entry before leaving.|Tanggapin at i-save ang kasalukuyang entry bago umalis.',
      'Open Assess and choose the correct unfinished record.|Buksan ang Assess at piliin ang tamang hindi pa tapos na rekord.',
      'Use the continuation action and check the next required step.|Gamitin ang aksyon para magpatuloy at tingnan ang susunod na kailangan.',
    ],
    'Saved progress is reconstructed from the record. Unsaved previews or form changes may need to be repeated.|Ibinabalik mula sa rekord ang naka-save na progreso. Maaaring ulitin ang hindi naka-save na preview o pagbabago.',
    destination: HelpDestination.assessments,
    related: ['complete', 'records', 'missing-records'],
  ),
  HelpArticle(
    'complete',
    'results',
    'Finish an assessment with missing requirements|Tapusin ang assessment na may kulang',
    'Completion is available after all required samples and block reviews are saved.|Maaaring tapusin kapag naka-save na ang lahat ng kinakailangang sample at review ng block.',
    'Active assessment → Review / completion; Assess → Required work|Aktibong assessment → Review / completion; Assess → Required work',
    [
      'Read the missing-work summary rather than repeatedly tapping completion.|Basahin ang buod ng kulang sa halip na paulit-ulit na tapusin.',
      'Return to each listed plant and resolve its required entry or evidence.|Balikan ang nakalistang halaman at kumpletuhin ang entry o ebidensya.',
      'Confirm natural enemies, review each block, and complete when the app allows it.|Kumpirmahin ang likas na mga kaaway, suriin ang bawat block, at tapusin kapag pinapayagan.',
    ],
    'Completed results use the saved samples. Unavailable observations must use an explicit supported outcome.|Gagamitin ang naka-save na sample. Gumamit ng tamang opsyon para sa hindi available na obserbasyon.',
    destination: HelpDestination.assessments,
    related: ['stations', 'photo-quality', 'resume'],
  ),
  HelpArticle(
    'records',
    'results',
    'Find assessments and read their status|Hanapin ang assessment at status nito',
    'Assess is your entry point for saved visits and their details.|Sa Assess makikita ang mga naka-save na pagbisita at detalye.',
    'Assess → Assessment record|Assess → Rekord ng assessment',
    [
      'Open Assess and use the available field and status filters.|Buksan ang Assess at gamitin ang filter ng bukid at status.',
      'Check the field, stage, and date before opening a record.|Tingnan ang bukid, yugto, at petsa bago buksan.',
      'Read its progress, results action, and any continuation or recovery notice.|Basahin ang progreso, aksyon sa resulta, at abiso sa pagpapatuloy o recovery.',
    ],
    'Draft or in-progress work can need more collection. Completed, submitted, and recovered records have different available actions.|Maaaring may kulang sa draft o in-progress. Magkakaiba ang aksyon sa completed, submitted, at recovered.',
    destination: HelpDestination.assessments,
    related: ['resume', 'measurements', 'recovery'],
  ),
  HelpArticle(
    'measurements',
    'results',
    'What do the result numbers mean?|Ano ang ibig sabihin ng mga bilang sa resulta?',
    'Read the measurement label, count, denominator, and uncertainty together.|Basahin nang magkasama ang pangalan, bilang, denominator, at pag-aalinlangan.',
    'Assess → Assessment → Results|Assess → Assessment → Results',
    [
      'Check whether the result describes image damage screening or recorded current infestation.|Tingnan kung screening ng larawan o naitalang kasalukuyang infestation ang resulta.',
      'Read the sampled count and percentage, including excluded or unavailable samples.|Basahin ang bilang at porsyento, pati ang hindi isinama o hindi available na sample.',
      'Open expert review separately for finalized Davis leaf-damage scores.|Hiwalay na buksan ang expert review para sa pinal na Davis leaf-damage scores.',
    ],
    'For sampled infestation, 8 infested out of 20 assessable plants is 40% of those samples. Davis severity is a separate expert score from 0 to 9.|Sa sampled infestation, 8 infested sa 20 assessable na halaman ay 40% ng sample. Hiwalay na marka ng eksperto mula 0 hanggang 9 ang Davis severity.',
    destination: HelpDestination.assessments,
    related: ['screening', 'expert-scores', 'result-map'],
    questions: [
      HelpQuestion(
        'Why does the denominator differ from the number visited?|Bakit iba ang denominator sa dami ng binisita?',
        'Unavailable or non-assessable samples can be excluded according to the metric. Read the displayed basis and warnings.|Maaaring hindi isama ang hindi available o hindi assessable ayon sa metric. Basahin ang batayan at babala.',
      ),
      HelpQuestion(
        'Is a colored station a low, moderate, or severe diagnosis?|Diagnosis ba ang kulay ng istasyon?',
        'Station colors visualize recorded sample values. They do not establish a whole-field diagnosis or an interpolated severity surface.|Ipinapakita ng kulay ang halaga ng sample. Hindi ito diagnosis ng buong bukid o hinulaang severity surface.',
      ),
    ],
  ),
  HelpArticle(
    'export',
    'results',
    'Export an assessment report|I-export ang ulat ng assessment',
    'Use the report action on a saved result to create a PDF.|Gamitin ang report action sa resulta upang gumawa ng PDF.',
    'Assess → Assessment → Results → Report / PDF action|Assess → Assessment → Results → Aksyon sa report / PDF',
    [
      'Open the correct saved assessment and review its findings.|Buksan ang tamang assessment at suriin ang findings.',
      'Choose the available report or PDF action.|Piliin ang available na report o PDF action.',
      'Use the system preview, print, save, or sharing options available on your device.|Gamitin ang preview, print, save, o sharing option ng device.',
    ],
    'Check the exported content before sharing, especially field location and personal information.|Suriin ang nilalaman bago ibahagi, lalo na ang lokasyon at personal na impormasyon.',
    destination: HelpDestination.assessments,
    related: ['measurements', 'privacy-sharing'],
  ),
  HelpArticle(
    'trends',
    'results',
    'Compare previous field assessments|Ihambing ang dating assessment ng bukid',
    'Field trends help you review recorded visits over time.|Nakakatulong ang Field trends sa pagtingin sa mga pagbisita sa paglipas ng panahon.',
    'More → Field trends|More → Field trends',
    [
      'Choose the field you want to compare.|Piliin ang bukid na ihahambing.',
      'Review the available assessment history and measurement labels.|Suriin ang history at pangalan ng mga sukat.',
      'Check crop stage, sample availability, and measurement basis before comparing values.|Tingnan ang yugto, availability ng sample, at batayan bago maghambing.',
    ],
    'A change in samples or screening method can affect a comparison. A trend does not predict future pest spread.|Maaaring makaapekto ang pagbabago ng sample o paraan. Hindi hinuhulaan ng trend ang pagkalat ng peste.',
    destination: HelpDestination.trends,
    related: ['measurements', 'records'],
  ),
  HelpArticle(
    'boundary',
    'maps',
    'Set up and confirm a field outline|Ihanda at kumpirmahin ang hangganan',
    'An approximate confirmed outline is needed before a new assessment.|Kailangan ng kumpirmadong tinatayang hangganan bago ang bagong assessment.',
    'Add / Edit field → Boundary setup; setup → Complete field outline|Add / Edit field → Boundary setup; setup → Complete field outline',
    [
      'Choose the available drawing, imagery, or walk-boundary method appropriate to your situation.|Piliin ang pagguhit, imagery, o paglakad ayon sa sitwasyon.',
      'Place or record the boundary points and review the shape and area.|Ilagay o itala ang mga punto at suriin ang hugis at lawak.',
      'Correct obvious errors and confirm the outline before starting assessment.|Itama ang malinaw na mali at kumpirmahin bago magsimula.',
    ],
    'The outline supports scouting; it is not a surveyed legal property boundary.|Gabay sa scouting ang hangganan; hindi ito legal na sukat ng pag-aari.',
    destination: HelpDestination.fields,
    related: ['gps', 'cannot-start'],
  ),
  HelpArticle(
    'map-tab',
    'maps',
    'Use the field map|Gamitin ang mapa ng bukid',
    'View your selected field and its boundary context.|Tingnan ang napiling bukid at hangganan nito.',
    'Map tab|Map tab',
    [
      'Select the intended field and open Map.|Piliin ang bukid at buksan ang Map.',
      'Use available zoom and map controls to inspect its outline.|Gamitin ang zoom at mga kontrol para suriin ang hangganan.',
      'For active station navigation, return to the assessment session.|Para sa aktibong pagpunta sa istasyon, bumalik sa assessment.',
    ],
    'Background imagery provides orientation; it is not a live satellite monitoring service.|Gabay sa lokasyon ang imagery; hindi ito live satellite monitoring.',
    destination: HelpDestination.map,
    related: ['route', 'result-map', 'map-offline'],
  ),
  HelpArticle(
    'result-map',
    'maps',
    'Read a completed assessment map|Basahin ang mapa ng natapos na assessment',
    'The result map shows the saved outline, route, and sampled stations.|Makikita ang naka-save na hangganan, ruta, at mga sample station.',
    'Assess → Assessment → Results → Map|Assess → Assessment → Results → Map',
    [
      'Check that the map belongs to the assessment you selected.|Tiyaking para sa napiling assessment ang mapa.',
      'Tap a station to inspect the sample values and evidence context.|Pindutin ang istasyon para sa sample values at ebidensya.',
      'Distinguish actual recorded coordinates from route targets or missing locations.|Ihiwalay ang naitalang koordinado sa target ng ruta o nawawalang lokasyon.',
    ],
    'Recorded station values do not estimate conditions between stations.|Hindi tinatantiya ng mga halaga sa istasyon ang kondisyon sa pagitan ng mga ito.',
    destination: HelpDestination.assessments,
    related: ['gps', 'measurements'],
  ),
  HelpArticle(
    'gps',
    'maps',
    'Record location and understand GPS accuracy|Itala ang lokasyon at unawain ang GPS accuracy',
    'Grant location access and record fixes when the workflow requests them.|Pahintulutan ang lokasyon at itala ito kapag hinihingi.',
    'Station / plant capture → Location; device settings → WormWise permissions|Pagkuha sa istasyon / halaman → Location; device settings → Pahintulot ng WormWise',
    [
      'Enable device location and allow the app to use it while you work.|I-on ang location at pahintulutan ang app habang ginagamit.',
      'Wait for a usable fix in an open area when safe, then use the offered location action.|Hintayin ang lokasyon sa ligtas at bukas na lugar, saka gamitin ang aksyon.',
      'Check accuracy and provenance. Record a missing or unverified location honestly.|Tingnan ang accuracy at pinagmulan. Itala nang tapat ang kulang o hindi beripikadong lokasyon.',
    ],
    'GPS has measurement error. A generated route target must not be described as your actual captured position.|May error ang GPS. Hindi aktwal na posisyon ang target na ginawa ng ruta.',
    related: ['location-problem', 'route', 'privacy-sharing'],
  ),
  HelpArticle(
    'map-offline',
    'maps',
    'Why is imagery missing offline?|Bakit walang imagery kapag offline?',
    'Online map tiles need connectivity; available local map or illustrated views can still provide context.|Kailangan ng internet ang online tiles; maaaring may lokal o illustrated na mapa.',
    'Map / active assessment map|Map / mapa ng aktibong assessment',
    [
      'Check your connection if the basemap is blank.|Tingnan ang koneksyon kung walang basemap.',
      'Use any available local or illustrated fallback and the saved outline.|Gamitin ang lokal o illustrated na fallback at naka-save na hangganan.',
      'Reconnect to load imagery; do not assume an unloaded map erased your field record.|Kumonekta para sa imagery; hindi ibig sabihin ng blangkong mapa na nabura ang bukid.',
    ],
    'Fallback coverage depends on the screen and stored map data.|Nakadepende sa screen at naka-save na mapa ang fallback.',
    related: ['offline', 'boundary'],
  ),
  HelpArticle(
    'submit-expert',
    'expert',
    'Send an assessment to an expert|Ipadala ang assessment sa eksperto',
    'Send the completed assessment with its results, photos and field location.|Ipadala ang natapos na assessment kasama ang resulta, larawan at lokasyon ng bukid.',
    'Assess → Completed assessment → Results → Send to an expert|Assess → Natapos na assessment → Results → Send to an expert',
    [
      'Connect to the internet and open the completed result.|Kumonekta sa internet at buksan ang natapos na resulta.',
      'Confirm the farmer name and add a message if needed.|Kumpirmahin ang pangalan ng magsasaka at magdagdag ng mensahe kung kailangan.',
      'Send the report. Results, photos and field location are included automatically; wait for submission confirmation.|Ipadala ang report. Awtomatikong kasama ang resulta, larawan at lokasyon; hintayin ang kumpirmasyon ng pagpapasa.',
    ],
    'A submitted case can be reviewed when an expert takes responsibility; submission does not guarantee an immediate reply.|Masusuri ang kaso kapag may ekspertong nakatalaga; hindi garantisado ang agarang sagot.',
    destination: HelpDestination.assessments,
    related: ['expert-messages', 'expert-scores', 'privacy-sharing'],
    questions: [
      HelpQuestion(
        'Can an expert score plants without shared photos?|Maaari bang markahan ang halaman kung walang ibinahaging larawan?',
        'Photo-based Davis review requires shared plant-linked evidence. Reviewers may report insufficient evidence instead of a score.|Kailangan ng larawan na nakaugnay sa halaman para sa Davis review. Maaaring insufficient evidence ang resulta sa halip na marka.',
      ),
    ],
  ),
  HelpArticle(
    'expert-messages',
    'expert',
    'Find expert replies and review status|Hanapin ang sagot at status ng eksperto',
    'Expert conversations are separate from AI Advisor chats.|Hiwalay ang usapan sa eksperto sa AI Advisor chat.',
    'Home → Notifications → Expert reply; available expert-review action|Home → Notifications → Sagot ng eksperto; available na expert-review action',
    [
      'Open the expert conversation linked to the assessment.|Buksan ang usapan sa eksperto na kaugnay ng assessment.',
      'Read the status and any request for more information. The assigned expert’s name and saved phone appear above the conversation; use Copy phone number if needed.|Basahin ang status at kahilingan sa dagdag na impormasyon. Makikita sa itaas ang pangalan at numero ng nakatalagang eksperto; gamitin ang Copy phone number kung kailangan.',
      'Reply through the conversation while connected; refresh if newer messages are not shown.|Sumagot sa usapan habang online; i-refresh kung kulang ang bagong mensahe.',
    ],
    'Pending, under review, needs information, advice sent, and closed describe case progress, not a severity score.|Ang mga status ng kaso ay progreso ng review, hindi severity score.',
    destination: HelpDestination.notifications,
    related: ['submit-expert', 'expert-scores', 'online-problem'],
  ),
  HelpArticle(
    'expert-scores',
    'expert',
    'View finalized Davis scores|Tingnan ang pinal na Davis scores',
    'An expert rates submitted plant evidence on the Davis 0–9 leaf-damage scale.|Minamarkahan ng eksperto ang ebidensya gamit ang Davis 0–9 leaf-damage scale.',
    'Expert conversation → Finalized severity summary|Usapan sa eksperto → Pinal na severity summary',
    [
      'Open the finalized summary message from the expert case.|Buksan ang mensahe ng pinal na buod.',
      'Tap the summary to see individual plant scores, notes, and submitted photos.|Pindutin ang buod para makita ang marka, tala, at larawan ng bawat halaman.',
      'Check how many plants were scored versus insufficient evidence and read the median.|Tingnan ang dami ng may marka at kulang ang ebidensya, saka basahin ang median.',
    ],
    'Insufficient evidence has no score and is not zero. The summary covers photo-linked reviewed plants.|Walang marka ang insufficient evidence at hindi ito zero. Saklaw ng buod ang mga halamang may larawang sinuri.',
    related: ['measurements', 'expert-messages'],
    questions: [
      HelpQuestion(
        'Why is there no finalized summary yet?|Bakit wala pang pinal na buod?',
        'The assigned expert must finish reviewing the submitted photo-linked plants and finalize the review. Check the conversation for progress.|Kailangang matapos at i-finalize ng eksperto ang review ng mga larawang nakaugnay sa halaman. Tingnan ang usapan para sa progreso.',
      ),
    ],
  ),
  HelpArticle(
    'ask-advisor',
    'advisor',
    'Ask the Advisor a useful question|Magtanong nang malinaw sa Advisor',
    'Describe your task or finding so the Advisor can explain relevant information.|Ilarawan ang gawain o finding para makapagpaliwanag ang Advisor.',
    'Guide → Advisor conversation|Guide → Usapan sa Advisor',
    [
      'Check your selected field if the question is about its records.|Tingnan ang napiling bukid kung tungkol sa rekord nito ang tanong.',
      'Describe the crop stage, observation, and what you want to understand.|Ilarawan ang yugto, obserbasyon, at gustong malaman.',
      'Read the reply, references when shown, and any suggested app action.|Basahin ang sagot, sanggunian kung ipinapakita, at mungkahing aksyon.',
    ],
    'Advisor responses support understanding and guidance. They do not establish a diagnosis or replace an expert assessment.|Tulong sa pag-unawa ang sagot ng Advisor. Hindi ito diagnosis o pamalit sa eksperto.',
    destination: HelpDestination.advisor,
    related: ['advisor-photo', 'advisor-chats', 'sources', 'advisor-offline'],
  ),
  HelpArticle(
    'advisor-photo',
    'advisor',
    'Ask about a photo in the Advisor|Magtanong tungkol sa larawan sa Advisor',
    'Use the photo action for on-device image screening and explanations.|Gamitin ang photo action para sa screening sa device at paliwanag.',
    'Guide → Advisor → Photo action|Guide → Advisor → Photo action',
    [
      'Use the offered capture or image-selection option.|Gamitin ang opsyon sa pagkuha o pagpili ng larawan.',
      'Review the model findings and ask a focused question about them.|Suriin ang findings at magtanong nang tiyak tungkol dito.',
      'Use an assessment for structured station records and expert submission.|Gumamit ng assessment para sa organisadong rekord at pagpapasa sa eksperto.',
    ],
    'An Advisor photo does not automatically become an assessment sample. Online explanations use structured model findings rather than raw photo uploads through the Advisor.|Hindi awtomatikong sample ang larawan sa Advisor. Structured model findings ang ginagamit sa online na paliwanag, hindi raw na larawan sa Advisor.',
    destination: HelpDestination.advisor,
    related: ['photos', 'privacy-sharing', 'screening'],
  ),
  HelpArticle(
    'advisor-chats',
    'advisor',
    'Find or start Advisor conversations|Hanapin o simulan ang chat sa Advisor',
    'Chats keeps your saved conversations accessible.|Makikita sa Chats ang mga naka-save na usapan.',
    'Guide → Chats|Guide → Chats',
    [
      'Open Chats and select the conversation you want to continue.|Buksan ang Chats at piliin ang usapang ipagpapatuloy.',
      'Use the new-conversation action when you want a separate topic.|Gamitin ang bagong usapan para sa hiwalay na paksa.',
      'Wait until a pending reply finishes before switching chats; the current conversation is saved when starting a new one.|Hintaying matapos ang sagot bago lumipat; nai-save ang kasalukuyang usapan kapag nagsimula ng bago.',
    ],
    'Starting a new chat does not delete or complete your field assessment. This chat list does not offer a bulk-delete control.|Hindi binubura o tinatapos ng bagong chat ang assessment. Walang bulk-delete control sa listahang ito.',
    destination: HelpDestination.advisor,
    related: ['expert-messages', 'privacy-data'],
  ),
  HelpArticle(
    'help-guidelines',
    'advisor',
    'Help Center or Guidelines: which should I use?|Help Center o Guidelines: alin ang gagamitin?',
    'Help teaches app controls. Guidelines explains scouting and agricultural reference information.|Itinuturo ng Help ang app. Ipinapaliwanag ng Guidelines ang scouting at sangguniang pang-agrikultura.',
    'More → Help & Support / Guidelines|More → Help & Support / Guidelines',
    [
      'Use Help to find a feature, follow its steps, or fix a problem.|Gamitin ang Help para hanapin ang feature, sundin ang hakbang, o ayusin ang problema.',
      'Use Guidelines to read the agricultural explanation behind observations and scouting.|Gamitin ang Guidelines para sa paliwanag sa obserbasyon at scouting.',
      'Use expert review for submitted evidence that needs human assessment.|Gamitin ang expert review para sa ebidensyang kailangang suriin ng tao.',
    ],
    'The two resources complement each other and are available for local reading.|Magkaugnay ang dalawang gabay at maaaring basahin nang lokal.',
    destination: HelpDestination.guidelines,
    related: ['first-assessment', 'ask-advisor'],
  ),
  HelpArticle(
    'advisor-offline',
    'advisor',
    'Use guidance when the Advisor is offline|Gumamit ng gabay kapag offline ang Advisor',
    'Saved chats and bundled Guidelines remain useful when online replies are unavailable.|Magagamit ang naka-save na chat at Guidelines kahit walang online na sagot.',
    'Guide; More → Guidelines|Guide; More → Guidelines',
    [
      'Read available local guidance or open a saved conversation.|Basahin ang lokal na gabay o buksan ang naka-save na usapan.',
      'Continue recording assessment observations locally.|Ipagpatuloy ang lokal na pagtatala ng assessment.',
      'Reconnect and retry if the question requires a new online reply.|Kumonekta at ulitin kung kailangan ng bagong online na sagot.',
    ],
    'An online failure does not mean local assessment records were lost.|Hindi ibig sabihin ng online failure na nawala ang lokal na rekord.',
    destination: HelpDestination.guidelines,
    related: ['offline', 'online-problem'],
  ),
  HelpArticle(
    'guest-account',
    'account',
    'Guest access or a registered account?|Guest access o rehistradong account?',
    'Guest access supports local work; registered accounts support account backup and online services.|Para sa lokal na gawain ang guest; may backup at online na serbisyo ang rehistradong account.',
    'Access screen; More → My Profile|Access screen; More → My Profile',
    [
      'Use guest access when you need to start local fieldwork.|Gamitin ang guest access para simulan ang lokal na gawain.',
      'Open My Profile to view account access or sign-in options.|Buksan ang My Profile para sa account o sign-in.',
      'Before switching, follow the displayed save, backup, or handoff instructions for your current data.|Bago lumipat, sundin ang tagubilin sa save, backup, o handoff ng kasalukuyang datos.',
    ],
    'Guest records are not proof of a verified cloud backup.|Hindi patunay ng beripikadong cloud backup ang guest records.',
    destination: HelpDestination.profile,
    related: ['backup', 'switch-account', 'privacy-data'],
  ),
  HelpArticle(
    'profile',
    'account',
    'Update your profile or password|Baguhin ang profile o password',
    'Use My Profile for the account controls available to your identity.|Gamitin ang My Profile para sa kontrol na available sa account.',
    'More → Profile card; or side menu → My Profile|More → Profile card; o side menu → My Profile',
    [
      'Open My Profile and check whether you are signed in or using guest access.|Buksan ang My Profile at tingnan kung signed in o guest.',
      'Use the available name, phone number, email, avatar, or password action. A contact phone is separate from your sign-in method.|Gamitin ang available na pangalan, numero ng telepono, email, avatar, o password action. Hiwalay sa sign-in method ang contact number.',
      'Follow the confirmation requirements and check that the change succeeded.|Sundin ang kumpirmasyon at tiyaking matagumpay ang pagbabago.',
    ],
    'Some account changes require internet or additional verification.|May mga pagbabago sa account na nangangailangan ng internet o beripikasyon.',
    destination: HelpDestination.profile,
    related: ['switch-account', 'online-problem'],
  ),
  HelpArticle(
    'backup',
    'account',
    'Verify that records and photos are backed up|Beripikahin ang backup ng rekord at larawan',
    'Check the account backup indicator before relying on another device.|Tingnan ang backup bago umasa sa ibang device.',
    'My Profile → Account backup → Verify backup|My Profile → Account backup → Verify backup',
    [
      'Sign in to the correct registered account and connect to the internet.|Mag-sign in sa tamang rehistradong account at kumonekta.',
      'Open the backup status and choose Verify backup when available.|Buksan ang status at piliin ang Verify backup kung available.',
      'Wait for the verified state and read any remaining photo or sync warnings.|Hintayin ang beripikadong status at basahin ang babala sa larawan o sync.',
    ],
    'Records and photos can finish syncing at different times. A submitted expert case alone does not prove your full account backup is verified.|Maaaring magkaiba ang oras ng sync ng rekord at larawan. Hindi sapat ang expert submission bilang patunay ng buong backup.',
    destination: HelpDestination.profile,
    related: ['recovery', 'sync-problem', 'missing-photos'],
  ),
  HelpArticle(
    'recovery',
    'account',
    'Recover records on another phone|Bawiin ang rekord sa ibang telepono',
    'Account records and photo recovery are separate stages.|Magkahiwalay ang pagbawi ng rekord at larawan.',
    'Sign in → Account recovery; My Profile → Backup status|Sign in → Account recovery; My Profile → Backup status',
    [
      'Use the same registered account that held the verified backup.|Gamitin ang rehistradong account ng beripikadong backup.',
      'Follow the recovery screen and allow records to load before collecting new work.|Sundin ang recovery at hayaang ma-load ang rekord bago gumawa ng bago.',
      'Retry interrupted recovery and check photo readiness separately.|Ulitin ang naputol na recovery at hiwalay na tingnan ang larawan.',
    ],
    'A summary-only recovered record may be read-only. Guest-only data cannot be assumed to exist in an account backup.|Maaaring read-only ang summary-only na rekord. Hindi dapat ipalagay na may account backup ang guest-only na datos.',
    destination: HelpDestination.profile,
    related: ['backup', 'missing-records', 'missing-photos'],
  ),
  HelpArticle(
    'switch-account',
    'account',
    'Sign out or switch accounts safely|Mag-sign out o lumipat ng account',
    'Check which account owns the data before switching views.|Tingnan kung aling account ang may-ari ng datos bago lumipat.',
    'More → Sign out; My Profile → Account actions|More → Sign out; My Profile → Account actions',
    [
      'Save current entries and verify account backup while online when using a registered account.|I-save ang entry at beripikahin ang backup habang online kung rehistrado.',
      'Read the sign-out or handoff confirmation before proceeding.|Basahin ang kumpirmasyon sa sign-out o handoff.',
      'Sign in to the intended account and allow its data view to prepare.|Mag-sign in sa gustong account at hintayin ang paghahanda ng datos.',
    ],
    'Signing out does not mean every saved record should be visible to a different account.|Hindi ibig sabihin ng sign-out na makikita ng ibang account ang lahat ng rekord.',
    destination: HelpDestination.profile,
    related: ['backup', 'guest-account', 'missing-records'],
  ),
  HelpArticle(
    'language',
    'preferences',
    'Change the app language|Palitan ang wika ng app',
    'Choose English or Filipino for supported interface text and this Help Center.|Pumili ng English o Filipino para sa interface at Help Center.',
    'More → Language; side menu → Language|More → Language; side menu → Language',
    [
      'Open Language and select English or Filipino.|Buksan ang Language at piliin ang English o Filipino.',
      'Return to the screen you were using.|Bumalik sa dating screen.',
      'Use either language when searching this Help Center.|Gamitin ang alinmang wika sa paghahanap sa Help Center.',
    ],
    'Your field names and personal notes remain as entered; changing language does not rewrite observations.|Mananatili ang pangalan at tala ayon sa pagkakalagay; hindi nito binabago ang obserbasyon.',
    destination: HelpDestination.language,
    related: ['ask-advisor'],
  ),
  HelpArticle(
    'model-settings',
    'preferences',
    'Manage the image model setting|Ayusin ang setting ng image model',
    'The Models screen describes damage screening and the optional supporting detection setting.|Inilalarawan ng Models ang damage screening at dagdag na detection setting.',
    'More → Models|More → Models',
    [
      'Open Models and read the status of damage screening.|Buksan ang Models at basahin ang status ng damage screening.',
      'Review the second-model setting and use its control if you want supporting detections.|Suriin ang ikalawang modelo at gamitin ang kontrol para sa dagdag na detection.',
      'Return to your plant workflow and read the actual result available there.|Bumalik sa halaman at basahin ang aktwal na resulta.',
    ],
    'The supporting-model choice is fixed for an assessment and may be locked while one is open. It does not create an expert Davis score.|Nakatakda para sa assessment ang pagpili ng dagdag na modelo at maaaring naka-lock habang bukas ito. Hindi ito gumagawa ng Davis score.',
    destination: HelpDestination.models,
    related: ['screening', 'analysis-problem'],
  ),
  HelpArticle(
    'sources',
    'preferences',
    'Show supporting sources below Advisor replies|Ipakita ang sanggunian sa sagot ng Advisor',
    'Use the Artificial Intelligence preference to display supporting references.|Gamitin ang Artificial Intelligence setting para ipakita ang sanggunian.',
    'More → Artificial Intelligence → Supporting sources|More → Artificial Intelligence → Supporting sources',
    [
      'Open Artificial Intelligence.|Buksan ang Artificial Intelligence.',
      'Turn Supporting sources on or off and wait for the setting to save.|I-on o i-off ang Supporting sources at hintaying ma-save.',
      'Read the supporting references when they are available under replies.|Basahin ang sanggunian kapag available sa ilalim ng sagot.',
    ],
    'A cited reference helps you inspect the basis of guidance; it does not guarantee every generated statement is correct.|Tulong sa pagsusuri ang sanggunian; hindi garantiya na tama ang bawat pahayag.',
    destination: HelpDestination.ai,
    related: ['ask-advisor', 'help-guidelines'],
  ),
  HelpArticle(
    'notifications',
    'preferences',
    'Find notifications and expert updates|Hanapin ang mga abiso at update ng eksperto',
    'The notification screen collects available app and review updates.|Makikita sa notifications ang available na update ng app at review.',
    'Home → Notification bell|Home → Notification bell',
    [
      'Open the bell on Home.|Buksan ang bell sa Home.',
      'Read the update and open its linked item if available.|Basahin ang update at buksan ang kaugnay na item kung mayroon.',
      'For missing expert updates, connect and open the expert conversation directly.|Kung kulang ang update, kumonekta at direktang buksan ang usapan sa eksperto.',
    ],
    'An empty notification list does not prove no expert case exists.|Hindi patunay na walang expert case ang walang laman na listahan.',
    destination: HelpDestination.notifications,
    related: ['expert-messages', 'online-problem'],
  ),
  HelpArticle(
    'cannot-start',
    'trouble',
    'Why can’t I start an assessment?|Bakit hindi ako makapagsimula ng assessment?',
    'Check the selected field, confirmed outline, open assessment, and safety result.|Tingnan ang napiling bukid, hangganan, bukas na assessment, at safety result.',
    'Home / Assessment Setup|Home / Assessment Setup',
    [
      'Select a field and complete any requested outline confirmation.|Pumili ng bukid at kumpirmahin ang hangganan kung hinihingi.',
      'If an unfinished assessment exists, resume it or follow the available workflow instead of duplicating it.|Kung may hindi pa tapos, ipagpatuloy ito o sundin ang workflow sa halip na gumawa ng duplicate.',
      'Read any entry restriction and verify treatment information before proceeding.|Basahin ang pagbabawal sa pagpasok at beripikahin ang paggamot bago magpatuloy.',
    ],
    'Follow the specific message on the screen; Help cannot override a safety restriction.|Sundin ang mensahe sa screen; hindi nalalampasan ng Help ang safety restriction.',
    related: ['boundary', 'safety', 'resume'],
  ),
  HelpArticle(
    'camera-problem',
    'trouble',
    'Camera won’t open or save a photo|Hindi bumubukas ang camera o nai-save ang larawan',
    'Check permission, camera availability, and storage before retrying.|Tingnan ang pahintulot, camera, at storage bago ulitin.',
    'Device settings → Apps → WormWise → Permissions; guided camera|Device settings → Apps → WormWise → Permissions; guided camera',
    [
      'Allow camera access in device settings and close other apps using the camera.|Pahintulutan ang camera sa settings at isara ang ibang gumagamit nito.',
      'Check available storage and reopen the capture step.|Tingnan ang libreng storage at buksan muli ang pagkuha.',
      'Retry and accept the preview; check that evidence appears before moving on.|Ulitin at tanggapin ang preview; tingnan kung lumitaw ang ebidensya bago magpatuloy.',
    ],
    'Do not clear app data to fix the camera; it can remove local records and photos.|Huwag i-clear ang app data para ayusin ang camera; maaaring mabura ang lokal na rekord at larawan.',
    related: ['photos', 'photo-quality', 'privacy-data'],
  ),
  HelpArticle(
    'location-problem',
    'trouble',
    'Location is missing or inaccurate|Kulang o hindi tumpak ang lokasyon',
    'GPS fixes depend on permissions, signal, and device location settings.|Nakadepende ang GPS sa pahintulot, signal, at device settings.',
    'Device location settings; station / plant location prompt|Device location settings; tanong sa lokasyon ng istasyon / halaman',
    [
      'Enable location and allow the requested WormWise location permission.|I-on ang location at pahintulutan ang WormWise.',
      'When safe, move to an open area and wait before retrying the fix.|Kung ligtas, pumunta sa bukas na lugar at maghintay bago ulitin.',
      'Keep an unavailable or unverified location marked honestly if no usable fix arrives.|Itala bilang unavailable o unverified kung walang magagamit na lokasyon.',
    ],
    'Do not replace an actual GPS observation with a generated route point.|Huwag palitan ng target ng ruta ang aktwal na GPS observation.',
    related: ['gps', 'map-offline'],
  ),
  HelpArticle(
    'analysis-problem',
    'trouble',
    'Image analysis is unavailable or unexpected|Hindi available o kakaiba ang image analysis',
    'An unavailable result differs from a negative result.|Magkaiba ang unavailable at negative na resulta.',
    'Plant analysis / Advisor photo; More → Models|Plant analysis / larawan sa Advisor; More → Models',
    [
      'Read the exact error or unavailable message.|Basahin ang eksaktong error o unavailable na mensahe.',
      'Try a clear accepted view and check the supporting-model setting if relevant.|Subukan ang malinaw na tinanggap na larawan at tingnan ang setting ng modelo kung kailangan.',
      'Preserve the evidence and use a supported unavailable outcome or request expert review.|Panatilihin ang ebidensya at gamitin ang unavailable na opsyon o expert review.',
    ],
    'Do not interpret an analysis failure as no damage or force a positive result to match expectations.|Huwag ituring na walang pinsala ang failure o piliting positibo ang resulta.',
    destination: HelpDestination.models,
    related: ['screening', 'photo-quality', 'submit-expert'],
  ),
  HelpArticle(
    'online-problem',
    'trouble',
    'Advisor or expert messages won’t load|Hindi naglo-load ang Advisor o mensahe ng eksperto',
    'Online replies and review messages require a working connection and access.|Kailangan ng koneksyon at access ang online na sagot at mensahe.',
    'Guide / Expert conversation|Guide / Usapan sa eksperto',
    [
      'Check connectivity and the account you are using.|Tingnan ang koneksyon at account.',
      'Use the retry or refresh action after the current request finishes.|Gamitin ang retry o refresh matapos ang kasalukuyang request.',
      'Read local Guidelines while offline; avoid repeatedly submitting the same question or case.|Basahin ang lokal na Guidelines habang offline; iwasang paulit-ulit na magpasa.',
    ],
    'Temporary online failures do not erase accepted local assessment evidence.|Hindi binubura ng pansamantalang online failure ang lokal na ebidensya.',
    related: ['advisor-offline', 'expert-messages', 'offline'],
  ),
  HelpArticle(
    'sync-problem',
    'trouble',
    'Backup or synchronization needs attention|Kailangan ng pansin ang backup o sync',
    'Read the account status to see what still needs syncing or verification.|Basahin ang status para malaman kung ano ang kulang sa sync o verification.',
    'My Profile → Account backup|My Profile → Account backup',
    [
      'Check the registered account and internet connection.|Tingnan ang rehistradong account at koneksyon.',
      'Read the displayed error and use Verify backup or the available retry action.|Basahin ang error at gamitin ang Verify backup o retry.',
      'Wait for verification of records and photos before relying on cloud recovery.|Hintayin ang verification ng rekord at larawan bago umasa sa cloud recovery.',
    ],
    'Keep local data intact while troubleshooting. Reinstallation is not a backup repair step.|Panatilihin ang lokal na datos habang inaayos. Hindi paraan ng pag-aayos ng backup ang reinstall.',
    destination: HelpDestination.profile,
    related: ['backup', 'recovery', 'report-problem'],
  ),
  HelpArticle(
    'missing-records',
    'trouble',
    'I can’t find my field or assessment|Hindi ko makita ang bukid o assessment',
    'Check your account view, filters, and deleted fields first.|Tingnan muna ang account, filter, at naburang bukid.',
    'My Profile; My Fields; Assess|My Profile; My Fields; Assess',
    [
      'Confirm you are using the same guest or registered account view as before.|Tiyaking pareho ang guest o account na gamit noon.',
      'Clear relevant list filters and check Recently Deleted for a missing field.|Alisin ang filter at tingnan ang Recently Deleted.',
      'On a new phone, follow recovery and check whether the previous account backup was verified.|Sa bagong telepono, sundin ang recovery at tingnan kung beripikado ang dating backup.',
    ],
    'Do not recreate missing records immediately while recovery is still pending.|Huwag agad gumawa ng kapalit habang hindi pa tapos ang recovery.',
    destination: HelpDestination.assessments,
    related: ['delete-field', 'switch-account', 'recovery'],
  ),
  HelpArticle(
    'missing-photos',
    'trouble',
    'A saved photo is missing after recovery|Kulang ang larawan matapos ang recovery',
    'Records can recover before their photo files finish downloading.|Maaaring maunang maibalik ang rekord bago ang mga larawan.',
    'Recovered assessment → Evidence; account recovery / backup status|Naibalik na assessment → Evidence; recovery / backup status',
    [
      'Check whether the record is summary-only or whether photo recovery is pending.|Tingnan kung summary-only ang rekord o hinihintay pa ang larawan.',
      'Reconnect and use the available recovery retry.|Kumonekta at gamitin ang retry sa recovery.',
      'Reopen evidence after recovery finishes; preserve the original phone data if still available.|Buksan muli ang ebidensya matapos ang recovery; panatilihin ang datos sa dating telepono kung mayroon.',
    ],
    'Missing files must not be replaced with a different plant’s photo.|Huwag palitan ng larawan ng ibang halaman ang nawawalang file.',
    related: ['backup', 'recovery', 'photo-viewer'],
  ),
  HelpArticle(
    'privacy-data',
    'privacy',
    'Where are my records and photos stored?|Saan nakaimbak ang rekord at larawan?',
    'The app stores fieldwork locally and uses cloud services for configured account and review features.|Lokal ang fieldwork at may cloud para sa account at review.',
    'My Profile → Account backup; assessment → Evidence|My Profile → Account backup; assessment → Evidence',
    [
      'Treat accepted local records and private photo files as data on this device.|Ituring na datos sa device ang lokal na rekord at pribadong larawan.',
      'Check verified account backup before changing phones or clearing device storage.|Tingnan ang beripikadong backup bago magpalit ng telepono o mag-clear ng storage.',
      'Expert reports include assessment results, photos and field location when you send them.|Kasama ang resulta, larawan at lokasyon ng bukid kapag ipinadala ang report sa eksperto.',
    ],
    'Clearing app data or uninstalling can remove local data. A guest session does not guarantee remote recovery.|Maaaring mabura ang lokal na datos sa clear app data o uninstall. Walang garantisadong remote recovery ang guest.',
    related: ['backup', 'privacy-sharing', 'delete-field'],
  ),
  HelpArticle(
    'privacy-sharing',
    'privacy',
    'What is shared with an expert or Advisor?|Ano ang ibinabahagi sa eksperto o Advisor?',
    'Expert reports include results, photos and field location; Advisor sharing has separate settings.|Kasama sa expert report ang resulta, larawan at lokasyon; hiwalay ang settings ng pagbabahagi sa Advisor.',
    'Results → Send to an expert; Guide → Advisor|Results → Send to an expert; Guide → Advisor',
    [
      'Sending an expert report automatically includes its assessment results, photos and field location.|Awtomatikong kasama ang resulta, larawan at lokasyon ng bukid kapag ipinadala ang expert report.',
      'For Advisor questions, remember that relevant field context and structured findings may be sent online.|Sa Advisor, maaaring maipadala online ang kaugnay na konteksto at structured findings.',
      'Avoid entering passwords or unrelated sensitive information into questions or shared notes.|Huwag maglagay ng password o hindi kaugnay na sensitibong datos sa tanong o tala.',
    ],
    'Expert evidence uploads and account backup are distinct from the Advisor’s structured image findings.|Magkahiwalay ang upload sa eksperto, account backup, at structured image findings ng Advisor.',
    related: ['submit-expert', 'advisor-photo', 'privacy-data'],
  ),
  HelpArticle(
    'limitations',
    'privacy',
    'What can WormWise tell me—and what needs an expert?|Ano ang masasabi ng WormWise at kailan kailangan ang eksperto?',
    'Use sampled findings, screening, and guidance with their stated limits.|Gamitin ang sample findings, screening, at gabay ayon sa limitasyon.',
    'Results; Guide; expert review|Results; Guide; expert review',
    [
      'Read the measurement basis and uncertainty rather than relying on a color alone.|Basahin ang batayan at pag-aalinlangan, hindi kulay lamang.',
      'Use Guidelines and supporting sources to understand the recorded observations.|Gamitin ang Guidelines at sanggunian upang unawain ang obserbasyon.',
      'Ask an agricultural expert about uncertain evidence or decisions needing field judgment.|Magtanong sa eksperto tungkol sa hindi tiyak na ebidensya o desisyon sa bukid.',
    ],
    'WormWise does not provide laboratory identification, a continuous whole-field severity prediction, or an automatic pesticide prescription.|Hindi nagbibigay ang WormWise ng laboratory identification, hula ng severity sa buong bukid, o awtomatikong reseta ng pestisidyo.',
    related: ['measurements', 'screening', 'submit-expert'],
  ),
  HelpArticle(
    'report-problem',
    'privacy',
    'What should I include when reporting an app problem?|Ano ang isasama sa pag-ulat ng problema sa app?',
    'Prepare a clear description for the person or team who provided your app.|Maghanda ng malinaw na paliwanag para sa nagbigay ng app.',
    'The screen where the problem happened|Screen kung saan nagkaproblema',
    [
      'Write the feature, steps you took, expected result, and exact error message.|Isulat ang feature, ginawa mong hakbang, inaasahang resulta, at eksaktong error.',
      'Include app version, phone model, whether you were offline, and guest or signed-in status.|Isama ang version, modelo ng telepono, koneksyon, at guest o signed-in na status.',
      'If sharing a screenshot, hide personal information and use the support contact supplied by your project team.|Kung may screenshot, takpan ang personal na datos at gamitin ang contact ng project team.',
    ],
    'No in-app technical-support inbox is configured here. Expert review is for agricultural evidence, not software support.|Walang naka-configure na technical-support inbox dito. Para sa ebidensyang pang-agrikultura ang expert review, hindi software support.',
    related: ['camera-problem', 'sync-problem', 'online-problem'],
  ),
]);

HelpArticle helpArticleById(String id) =>
    helpArticles.firstWhere((a) => a.id == id);

class HelpQuestionLink {
  HelpQuestionLink(String question, this.articleId)
    : question = HelpCopy(question);
  final HelpCopy question;
  final String articleId;
}

final helpQuestionLinks = List<HelpQuestionLink>.unmodifiable([
  HelpQuestionLink(
    'Where should I start?|Saan ako magsisimula?',
    'first-visit',
  ),
  HelpQuestionLink(
    'Where do I find each feature?|Saan ko makikita ang bawat feature?',
    'navigation',
  ),
  HelpQuestionLink(
    'Do I need internet in the field?|Kailangan ba ng internet sa bukid?',
    'offline',
  ),
  HelpQuestionLink(
    'How do I add another field?|Paano magdagdag ng ibang bukid?',
    'create-field',
  ),
  HelpQuestionLink(
    'How do I change the selected field?|Paano palitan ang napiling bukid?',
    'select-field',
  ),
  HelpQuestionLink(
    'Can I correct my crop details?|Maaari bang itama ang detalye ng pananim?',
    'edit-field',
  ),
  HelpQuestionLink(
    'My variety is not listed. What should I do?|Wala sa listahan ang variety. Ano ang gagawin?',
    'varieties',
  ),
  HelpQuestionLink(
    'Can I restore a deleted field?|Maaari bang ibalik ang naburang bukid?',
    'delete-field',
  ),
  HelpQuestionLink(
    'How do I perform an assessment?|Paano gumawa ng assessment?',
    'first-assessment',
  ),
  HelpQuestionLink(
    'What if I chose the wrong growth stage?|Paano kung mali ang napiling yugto?',
    'growth-stage',
  ),
  HelpQuestionLink(
    'Why is field entry blocked?|Bakit bawal pumasok sa bukid?',
    'safety',
  ),
  HelpQuestionLink(
    'What if recent weather cannot load?|Paano kung walang weather data?',
    'weather',
  ),
  HelpQuestionLink(
    'Where do I follow the guided scouting map?|Saan susundan ang mapa ng Guided scouting?',
    'route',
  ),
  HelpQuestionLink(
    'How many plants should I record per block?|Ilang halaman ang itatala bawat block?',
    'stations',
  ),
  HelpQuestionLink(
    'How do I assess seedlings?|Paano suriin ang punla?',
    'stage-early',
  ),
  HelpQuestionLink(
    'How do I assess vegetative maize?|Paano suriin ang vegetative na mais?',
    'stage-vegetative',
  ),
  HelpQuestionLink(
    'Which steps apply at VT–R2?|Ano ang mga hakbang sa VT–R2?',
    'stage-reproductive',
  ),
  HelpQuestionLink(
    'Can I open ears during assessment?|Maaari bang buksan ang bunga sa assessment?',
    'stage-late',
  ),
  HelpQuestionLink(
    'How do I capture and accept evidence?|Paano kumuha at tumanggap ng ebidensya?',
    'photos',
  ),
  HelpQuestionLink(
    'Why is my photo rejected or blurry?|Bakit rejected o malabo ang larawan?',
    'photo-quality',
  ),
  HelpQuestionLink(
    'Does no damage detected mean no FAW?|Wala bang FAW kapag walang nakitang pinsala?',
    'screening',
  ),
  HelpQuestionLink(
    'Are detection boxes a confirmed diagnosis?|Diagnosis ba ang detection boxes?',
    'screening',
  ),
  HelpQuestionLink(
    'Where are my saved photos?|Saan ang naka-save na larawan?',
    'photo-viewer',
  ),
  HelpQuestionLink(
    'Can I stop and continue later?|Maaari bang huminto at magpatuloy mamaya?',
    'resume',
  ),
  HelpQuestionLink(
    'Why can’t I complete the assessment?|Bakit hindi matapos ang assessment?',
    'complete',
  ),
  HelpQuestionLink(
    'What do draft, completed, and submitted mean?|Ano ang draft, completed, at submitted?',
    'records',
  ),
  HelpQuestionLink(
    'Is infestation percentage the same as a Davis score?|Pareho ba ang infestation percentage at Davis score?',
    'measurements',
  ),
  HelpQuestionLink(
    'Why are some plants excluded from the percentage?|Bakit may hindi kasamang halaman sa porsyento?',
    'measurements',
  ),
  HelpQuestionLink(
    'How do I save or share a PDF report?|Paano mag-save o magbahagi ng PDF?',
    'export',
  ),
  HelpQuestionLink(
    'Can I compare visits over time?|Maaari bang ihambing ang mga pagbisita?',
    'trends',
  ),
  HelpQuestionLink(
    'Why is a confirmed field outline required?|Bakit kailangan ang kumpirmadong hangganan?',
    'boundary',
  ),
  HelpQuestionLink(
    'Is the field outline a legal survey?|Legal na sukat ba ang hangganan?',
    'boundary',
  ),
  HelpQuestionLink(
    'Does the map show live satellite monitoring?|Live satellite monitoring ba ang mapa?',
    'map-tab',
  ),
  HelpQuestionLink(
    'What do colored station markers mean?|Ano ang kulay ng mga istasyon?',
    'result-map',
  ),
  HelpQuestionLink(
    'Is a route target my recorded GPS location?|GPS location ko ba ang target ng ruta?',
    'gps',
  ),
  HelpQuestionLink(
    'Why is my map blank offline?|Bakit blangko ang mapa kapag offline?',
    'map-offline',
  ),
  HelpQuestionLink(
    'How do I send findings to an expert?|Paano ipadala ang findings sa eksperto?',
    'submit-expert',
  ),
  HelpQuestionLink(
    'Will an expert answer immediately?|Sasagot ba agad ang eksperto?',
    'submit-expert',
  ),
  HelpQuestionLink(
    'Where do I read and reply to expert messages?|Saan babasahin at sasagutin ang eksperto?',
    'expert-messages',
  ),
  HelpQuestionLink(
    'Where do I see finalized plant scores?|Saan makikita ang pinal na marka ng halaman?',
    'expert-scores',
  ),
  HelpQuestionLink(
    'Does insufficient evidence count as zero?|Zero ba ang insufficient evidence?',
    'expert-scores',
  ),
  HelpQuestionLink(
    'What can I ask the Advisor?|Ano ang maaaring itanong sa Advisor?',
    'ask-advisor',
  ),
  HelpQuestionLink(
    'Does an Advisor photo become an assessment?|Nagiging assessment ba ang larawan sa Advisor?',
    'advisor-photo',
  ),
  HelpQuestionLink(
    'How do I find an old chat or start a new one?|Paano hanapin ang lumang chat o magsimula ng bago?',
    'advisor-chats',
  ),
  HelpQuestionLink(
    'How is Help different from Guidelines?|Ano ang kaibahan ng Help at Guidelines?',
    'help-guidelines',
  ),
  HelpQuestionLink(
    'What can I read when the Advisor is offline?|Ano ang mababasa kapag offline ang Advisor?',
    'advisor-offline',
  ),
  HelpQuestionLink(
    'What is the difference between guest and account access?|Ano ang kaibahan ng guest at account?',
    'guest-account',
  ),
  HelpQuestionLink(
    'How do I change my password or profile?|Paano baguhin ang password o profile?',
    'profile',
  ),
  HelpQuestionLink(
    'Are all my records and photos backed up?|May backup ba ang lahat ng rekord at larawan?',
    'backup',
  ),
  HelpQuestionLink(
    'Can I recover data on a new phone?|Maaari bang bawiin ang datos sa bagong telepono?',
    'recovery',
  ),
  HelpQuestionLink(
    'What happens when I sign out?|Ano ang mangyayari kapag nag-sign out?',
    'switch-account',
  ),
  HelpQuestionLink(
    'How do I switch to Filipino?|Paano lumipat sa Filipino?',
    'language',
  ),
  HelpQuestionLink(
    'Can I turn supporting detections on or off?|Maaari bang i-on o i-off ang dagdag na detection?',
    'model-settings',
  ),
  HelpQuestionLink(
    'How do I show Advisor references?|Paano ipakita ang sanggunian ng Advisor?',
    'sources',
  ),
  HelpQuestionLink(
    'Where do I find notifications?|Saan makikita ang mga abiso?',
    'notifications',
  ),
  HelpQuestionLink(
    'Why can’t I start collecting samples?|Bakit hindi makapagsimulang mangolekta?',
    'cannot-start',
  ),
  HelpQuestionLink(
    'Why won’t the camera open or save?|Bakit hindi bumubukas o nagse-save ang camera?',
    'camera-problem',
  ),
  HelpQuestionLink(
    'Why is GPS unavailable or inaccurate?|Bakit walang GPS o hindi ito tumpak?',
    'location-problem',
  ),
  HelpQuestionLink(
    'Does analysis unavailable mean a negative result?|Negative ba ang analysis unavailable?',
    'analysis-problem',
  ),
  HelpQuestionLink(
    'Why won’t Advisor or expert messages load?|Bakit hindi naglo-load ang Advisor o mensahe?',
    'online-problem',
  ),
  HelpQuestionLink(
    'What should I do when backup fails?|Ano ang gagawin kung hindi gumana ang backup?',
    'sync-problem',
  ),
  HelpQuestionLink(
    'Why did my fields or assessments disappear?|Bakit nawala ang bukid o assessment?',
    'missing-records',
  ),
  HelpQuestionLink(
    'Why did records recover without photos?|Bakit bumalik ang rekord pero walang larawan?',
    'missing-photos',
  ),
  HelpQuestionLink(
    'Will reinstalling remove local data?|Mabubura ba ang lokal na datos sa reinstall?',
    'privacy-data',
  ),
  HelpQuestionLink(
    'What is shared online and with experts?|Ano ang ibinabahagi online at sa eksperto?',
    'privacy-sharing',
  ),
  HelpQuestionLink(
    'Can WormWise diagnose pests or prescribe pesticides?|Maaari bang mag-diagnose o magreseta ang WormWise?',
    'limitations',
  ),
  HelpQuestionLink(
    'Who do I contact about an app problem?|Sino ang kakausapin para sa problema sa app?',
    'report-problem',
  ),
]);

/// Both languages are indexed. Tokens must all match somewhere in the article;
/// title and FAQ matches rank before matches in the body.
List<HelpArticle> searchHelp(String query, {String? topic}) {
  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u00c0-\u024f]+'), ' ')
      .trim();
  final tokens = normalize(
    query,
  ).split(' ').where((t) => t.isNotEmpty).toList();
  final results = <({HelpArticle article, int score})>[];
  for (final article in helpArticles) {
    if (topic != null && article.topic != topic) continue;
    final linkedQuestions = helpQuestionLinks
        .where((q) => q.articleId == article.id)
        .map((q) => '${q.question.english} ${q.question.filipino}')
        .join(' ');
    final body = normalize(
      '${article.searchableText.join(' ')} $linkedQuestions',
    );
    if (!tokens.every(body.contains)) continue;
    final title = normalize(
      '${article.title.english} ${article.title.filipino}',
    );
    final questions = normalize(
      '$linkedQuestions ${article.questions.map((q) => '${q.question.english} ${q.question.filipino}').join(' ')}',
    );
    final score = tokens.fold<int>(
      0,
      (score, token) =>
          score +
          (title.contains(token)
              ? 8
              : questions.contains(token)
              ? 4
              : 1),
    );
    results.add((article: article, score: score));
  }
  results.sort(
    (a, b) => b.score != a.score
        ? b.score.compareTo(a.score)
        : helpArticles
              .indexOf(a.article)
              .compareTo(helpArticles.indexOf(b.article)),
  );
  return results.map((r) => r.article).toList(growable: false);
}
