/// Deterministic offline Guide answers. Saved conversations keep their original
/// text; these values only change how built-in copy is displayed.
const answerLiteralFilipino = <String, String>{
  'Inspect the plant systematically': 'Suriin ang halaman nang sistematiko',
  'Check the newest leaves and whorl first, then look for fresh damage, frass, eggs, or a larva. Record what you actually observe—even when nothing is found.':
      'Suriin muna ang pinakabagong mga dahon at gitnang dahon, saka hanapin ang bagong pinsala, dumi ng uod, itlog, o uod. Itala ang aktuwal na naobserbahan—kahit walang makita.',
  'Use the consecutive plant selected by the guided station workflow.':
      'Gamitin ang magkakasunod na halamang pinili sa gabay na gawain sa istasyon.',
  'For vegetative maize, inspect the newest three or four leaves and the whorl.':
      'Para sa mais sa yugtong behetatibo, suriin ang tatlo o apat na pinakabagong dahon at gitnang dahon.',
  'Separate fresh feeding from old damage and note possible non-FAW causes.':
      'Ihiwalay ang bagong pagkakain sa lumang pinsala at itala ang posibleng sanhi na hindi FAW.',
  'Do not move to a more damaged plant because it looks more interesting.':
      'Huwag lumipat sa mas napinsalang halaman dahil lamang mas kapansin-pansin ito.',
  'Open Assess to continue the guided field assessment.':
      'Buksan ang Pagsusuri upang ipagpatuloy ang gabay na pagsusuri sa bukid.',
  'Frass is insect waste': 'Ang frass ay dumi ng insekto',
  'Fresh, coarse frass in the maize whorl can support evidence of recent caterpillar feeding, but frass alone does not confirm fall armyworm.':
      'Maaaring ebidensiya ng kamakailang pagkakain ng uod ang bago at magaspang na dumi sa gitnang dahon ng mais, ngunit hindi nito mag-isa kinukumpirma ang fall armyworm.',
  'Record whether the frass appears fresh and where it was found.':
      'Itala kung mukhang bago ang dumi ng uod at kung saan ito nakita.',
  'Look for feeding damage and, when possible, a clear view of the organism.':
      'Hanapin ang pinsala mula sa pagkakain at, kung maaari, malinaw na tanaw sa organismo.',
  'Frass coming from a stalk or cob borehole may support another pest such as Asian corn borer.':
      'Maaaring ibang peste, tulad ng Asian corn borer, ang sanhi ng dumi ng uod mula sa butas sa tangkay o bunga.',
  'Damage alone cannot confirm FAW':
      'Hindi sapat ang pinsala lamang upang kumpirmahin ang FAW',
  'Windowpanes, shot holes, ragged whorl feeding, and coarse frass are FAW-consistent signs. Confirming the species requires clear organism evidence or qualified expert review.':
      'Ang windowpane, maliliit na butas, punit-punit na pagkain sa gitnang dahon, at magaspang na dumi ng uod ay mga palatandaang maaaring tumugma sa FAW. Kailangan ng malinaw na ebidensiya ng organismo o pagrepaso ng kwalipikadong eksperto upang kumpirmahin ang uri.',
  'A supporting larval view may show a pale inverted Y on the head.':
      'Maaaring makita sa larawan ng uod ang maputlang baligtad na Y sa ulo.',
  'Four raised dark spots forming a square near the rear are another important feature.':
      'Isa pang mahalagang katangian ang apat na nakaangat na maitim na batik na bumubuo ng parisukat malapit sa hulihan.',
  'The head, body, and rear views must belong to the same specimen.':
      'Dapat iisang organismo ang nasa larawan ng ulo, katawan, at hulihan.',
  'An inverted Y by itself is not enough to confirm FAW.':
      'Hindi sapat ang baligtad na Y lamang upang kumpirmahin ang FAW.',
  'If a larva is present, capture the whole body, head, and rear markings without touching an unknown organism.':
      'Kung may uod, kunan ang buong katawan, ulo, at marka sa hulihan nang hindi hinahawakan ang hindi kilalang organismo.',
  'Different photos answer different questions':
      'Magkakaibang tanong ang nasasagot ng magkakaibang larawan',
  'One photo rarely shows the plant context, close damage, and identifying organism features. At least two guided views are needed before AI may suggest a whole-plant status.':
      'Bihirang maipakita ng isang larawan ang konteksto ng halaman, malapitang pinsala, at mga katangiang pagkakakilanlan ng organismo. Kailangan ng hindi bababa sa dalawang gabay na tanaw bago makapagmungkahi ang AI ng katayuan ng buong halaman.',
  'Overview: show the target plant part and surrounding context.':
      'Pangkalahatang larawan: ipakita ang target na bahagi ng halaman at paligid nito.',
  'Close-up: show fresh damage, frass, the whorl interior, or other evidence.':
      'Malapitang larawan: ipakita ang bagong pinsala, dumi ng uod, loob ng gitnang dahon, o ibang ebidensiya.',
  'Identification view: add a third photo when a larva, egg mass, or hidden symptom matters.':
      'Larawan para sa pagkilala: magdagdag ng ikatlong larawan kung mahalaga ang uod, kumpol ng itlog, o nakatagong sintomas.',
  'If a required view is missing or blurred, the result should remain insufficient—not guessed.':
      'Kung nawawala o malabo ang kinakailangang tanaw, dapat manatiling hindi sapat ang resulta—huwag hulaan.',
  'Keep uncertain evidence uncertain':
      'Panatilihing hindi tiyak ang hindi tiyak na ebidensiya',
  'Record what is visible, capture useful context, and mark the observation uncertain. Do not force unclear damage into a FAW diagnosis.':
      'Itala ang nakikita, kumuha ng kapaki-pakinabang na konteksto, at markahang hindi tiyak ang obserbasyon. Huwag piliting gawing diagnosis ng FAW ang hindi malinaw na pinsala.',
  'Note freshness, affected plant part, damage pattern, and any organism evidence.':
      'Itala ang pagkabago, apektadong bahagi ng halaman, anyo ng pinsala, at anumang ebidensiya ng organismo.',
  'Consider other pests, disease-like symptoms, weather, mechanical damage, and crop stress.':
      'Isaalang-alang ang ibang peste, sintomas na parang sakit, panahon, pisikal na pinsala, at stress ng pananim.',
  'A valid outcome is “not enough evidence to confirm FAW.”':
      'Katanggap-tanggap na resulta ang “hindi sapat ang ebidensiya upang kumpirmahin ang FAW.”',
  'Capture another useful view or request qualified review when the identification affects treatment or safety.':
      'Kumuha ng isa pang kapaki-pakinabang na tanaw o humingi ng kwalipikadong pagrepaso kung makaaapekto sa paggamot o kaligtasan ang pagkilala.',
  'Request qualified review when consequences matter':
      'Humingi ng kwalipikadong pagrepaso kung mahalaga ang kahihinatnan',
  'Contact a municipal agriculturist or qualified crop technician when identification remains uncertain or would affect treatment, certification, food safety, seed use, or insurance.':
      'Makipag-ugnayan sa municipal agriculturist o kwalipikadong teknisyan ng pananim kung hindi pa tiyak ang pagkilala o makaaapekto ito sa paggamot, sertipikasyon, kaligtasan ng pagkain, paggamit ng binhi, o insurance.',
  'Escalate possible unusual outbreaks or materially mixed infestations.':
      'Ipaabot sa eksperto ang posibleng hindi pangkaraniwang pagdami ng peste o mahalagang halo-halong infestation.',
  'Request review when AI and evaluator findings conflict on an important case.':
      'Humingi ng pagrepaso kung magkasalungat ang natuklasan ng AI at tagasuri sa mahalagang kaso.',
  'Stem, ear, laboratory, or molecular examination may require specialist support.':
      'Maaaring mangailangan ng espesyalista ang pagsusuri sa tangkay, bunga, laboratoryo, o molecular na antas.',
  'Cropwise does not prescribe pesticide treatment':
      'Hindi nagrereseta ang Cropwise ng paggamot na pestisidyo',
  'Do not choose or apply a pesticide from an image result or this guide alone. Use confirmed field observations and consult current product labels and qualified local agricultural guidance.':
      'Huwag pumili o gumamit ng pestisidyo batay lamang sa resulta ng larawan o gabay na ito. Gumamit ng kumpirmadong obserbasyon sa bukid at sumangguni sa kasalukuyang label ng produkto at kwalipikadong lokal na gabay sa agrikultura.',
  'Image confidence is not a treatment threshold.':
      'Hindi hangganan para sa paggamot ang confidence ng larawan.',
  'Check treatment history and required re-entry restrictions before entering a field.':
      'Suriin ang kasaysayan ng paggamot at mga tuntunin sa muling pagpasok bago pumasok sa bukid.',
  'Product choice, rate, timing, protective equipment, and legal registration require authoritative local information.':
      'Kailangan ng mapagkakatiwalaang lokal na impormasyon para sa pagpili ng produkto, dami, oras, kagamitang pangproteksiyon, at legal na rehistrasyon.',
  'Contact a qualified agricultural professional before making a consequential treatment decision.':
      'Makipag-ugnayan sa kwalipikadong propesyonal sa agrikultura bago gumawa ng mahalagang pasiya sa paggamot.',
  'Cultural and mechanical management practices':
      'Mga pangkultura at pisikal na paraan ng pamamahala',
  'Cultural methods, field sanitation, intercropping, and manual egg/larva removal provide effective non-chemical population suppression under the Cagayan Valley protocol.':
      'Ayon sa paraan ng Cagayan Valley, ang pangkulturang hakbang, kalinisan ng bukid, intercropping, at manwal na pag-alis ng itlog o uod ay mga paraang walang kemikal upang mabawasan ang populasyon ng peste.',
  'Handpick visible egg masses and young caterpillars in the whorl during early vegetative stages (VE–V6).':
      'Manwal na alisin ang nakikitang kumpol ng itlog at batang uod sa gitnang dahon sa maagang yugtong behetatibo (VE–V6).',
  'Maintain clean field margins and remove alternative weed grass hosts that shelter armyworm moths.':
      'Panatilihing malinis ang gilid ng bukid at alisin ang mga damong maaaring tirahan ng armyworm moth.',
  'Practice push-pull intercropping with companion crops like Desmodium and border trap crops.':
      'Gumamit ng push-pull intercropping kasama ang mga pananim gaya ng Desmodium at mga trap crop sa gilid.',
  'Deep tillage after harvest exposes pupae to solar heat and predatory birds.':
      'Inilalantad ng malalim na pagbubungkal pagkatapos anihin ang pupa sa init ng araw at mga ibong mandaragit.',
  'Avoid excessive nitrogen fertilization which produces overly lush foliage attractive to moths.':
      'Iwasan ang labis na nitrogen fertilizer na nagbubunga ng masyadong malagong dahong kaakit-akit sa gamu-gamo.',
  'Incorporate non-chemical cultural practices into your routine field maintenance.':
      'Isama ang mga pangkulturang hakbang na walang kemikal sa regular na pangangalaga ng bukid.',
  'Conserve natural enemies and predators':
      'Pangalagaan ang likas na kaaway at mandaragit ng peste',
  'Beneficial predators and biological control agents significantly reduce FAW survival. Protecting them helps prevent secondary pest flare-ups.':
      'Nakakatulong ang kapaki-pakinabang na mandaragit at organismong pangbiyolohikal na pagkontrol upang mabawasan ang pagdami ng FAW. Ang pangangalaga sa mga ito ay nakatutulong ding maiwasan ang pagdami ng ibang peste.',
  'Earwigs (Chelisoches morio) are nocturnal predators that crawl into whorls to consume egg masses and young larvae.':
      'Ang earwig (Chelisoches morio) ay mandaragit sa gabi na pumapasok sa gitnang dahon upang kainin ang kumpol ng itlog at batang uod.',
  'Minute pirate bugs (Orius spp.) and spiders hunt neonates and small caterpillars on leaves.':
      'Nanghuhuli ng bagong pisang uod at maliliit na higad sa dahon ang minute pirate bug (Orius spp.) at gagamba.',
  'Microscopic parasitoid wasps (Trichogramma spp.) parasitize FAW eggs before larvae can hatch.':
      'Inaatake ng napakaliit na parasitoid na putakti (Trichogramma spp.) ang itlog ng FAW bago mapisa ang uod.',
  'Avoid broad-spectrum chemical sprays that destroy beneficial insect populations in your maize field.':
      'Iwasan ang malawak na kemikal na spray na pumapatay sa kapaki-pakinabang na insekto sa bukid ng mais.',
  'Encourage flowering border plants to provide nectar and shelter for adult parasitoids.':
      'Pangalagaan ang mga namumulaklak na halaman sa gilid upang may nektar at tirahan ang ganap na parasitoid.',
  'Observe whether beneficial predators are present during plant whorl inspection.':
      'Obserbahan kung may kapaki-pakinabang na mandaragit habang sinusuri ang gitnang dahon.',
  'This offline guide has a focused scope':
      'May tiyak na saklaw ang offline na gabay na ito',
  'I can explain Cropwise scouting, FAW-consistent signs, field photographs, uncertain damage, and when to request expert help.':
      'Maaari kong ipaliwanag ang pagmamanman sa Cropwise, mga palatandaang tumutugma sa FAW, larawan sa bukid, hindi tiyak na pinsala, at kung kailan hihingi ng tulong ng eksperto.',
  'Try one of the suggested questions below.':
      'Subukan ang isa sa mga mungkahing tanong sa ibaba.',
  'You can also ask for the selected field status or latest saved assessment explanation.':
      'Maaari ka ring magtanong tungkol sa katayuan ng napiling bukid o paliwanag sa pinakahuling naka-save na pagsusuri.',
  'Cropwise offline guide': 'Offline na gabay ng Cropwise',
  'Built-in supported topics': 'Mga paksang suportado ng app',
  'Cropwise assessment protocol': 'Paraan ng pagsusuri ng Cropwise',
  'What is my current field status?':
      'Ano ang kasalukuyang katayuan ng aking bukid?',
  'Explain my latest assessment': 'Ipaliwanag ang pinakahuli kong pagsusuri',
  'How do I inspect a maize plant?':
      'Paano ko susuriin ang isang halaman ng mais?',
  'What does frass mean?': 'Ano ang ibig sabihin ng dumi ng uod?',
  'How can I recognize FAW?': 'Paano ko makikilala ang FAW?',
  'Why are two photos needed?': 'Bakit kailangan ng dalawang larawan?',
  'What if the damage is unclear?': 'Paano kung hindi malinaw ang pinsala?',
  'When should I contact a technician?':
      'Kailan ako dapat makipag-ugnayan sa teknisyan?',
  'What cultural practices help manage FAW?':
      'Anong pangkulturang hakbang ang nakatutulong sa pamamahala ng FAW?',
  'What natural predators control FAW?':
      'Anong likas na mandaragit ang kumokontrol sa FAW?',
};
