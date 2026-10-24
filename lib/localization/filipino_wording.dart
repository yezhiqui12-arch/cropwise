/// Farmer-facing Filipino uses familiar English for app and scientific terms.
/// Translate the explanation, never scientific codes or user-entered values.
/// These entries take precedence over the older literal dictionaries.
const farmerFilipino = <String, String>{
  'Add a field boundary to load weather.':
      'Idagdag ang hangganan ng bukid para makita ang lagay ng panahon.',
  'Current weather could not be loaded.':
      'Hindi makuha ang kasalukuyang lagay ng panahon.',
  'Damage-screened plants': 'Mga halamang nasuri para sa pinsala',
  'Saved · review complete': 'Naka-save · tapos nang suriin',
  'Saved · review required': 'Naka-save · kailangang suriin',
  'No plant observation is saved.':
      'Wala pang naka-save na obserbasyon sa halaman.',
  'No seedling observation is saved.':
      'Wala pang naka-save na obserbasyon sa punla.',
  'Home': 'Home',
  'Settings': 'Settings',
  'Guideline': 'Gabay',
  'Guidelines': 'Mga gabay',
  'Overview': 'Buod',
  'More': 'Iba pa',
  'Language': 'Wika',
  'Field interpretation': 'Paliwanag sa resulta',
  'Field Map & Telemetry': 'Mapa at datos ng bukid',
  'Field Boundary': 'Hangganan ng bukid',
  'Field boundary': 'Hangganan ng bukid',
  'Review field outline': 'Suriin ang outline ng bukid',
  'Complete field outline': 'Kumpletuhin ang outline ng bukid',
  'Save outline': 'I-save ang outline',
  'Keep current outline': 'Panatilihin ang kasalukuyang outline',
  'Calculated outline area (hectares)': 'Lawak batay sa outline (hectares)',
  'Ordinal score': 'Score ng pinsala (0–9)',
  'Injury freshness': 'Bago o luma ang pinsala?',
  'Whorl': 'Whorl',
  'Primary / uppermost marketable ear':
      'Pangunahin / pinakamataas na bungang maaaring ibenta',
  'Cultural and mechanical management practices':
      'Pangangalaga sa tanim at pisikal na pagkontrol sa peste',
  'What cultural practices help manage FAW?':
      'Anong paraan ng pangangalaga sa tanim ang makatutulong laban sa FAW?',
  'Natural-enemy details (optional)': 'Detalye ng natural enemies (opsyonal)',
  'Conserve natural enemies and predators':
      'Pangalagaan ang mga organismong kumokontrol o kumakain sa peste',
  'What natural predators control FAW?':
      'Anong mga organismo ang kumakain sa FAW?',
  'Image confidence is not a treatment threshold.':
      'Ang confidence score ng AI ay hindi sapat na batayan para gumamit ng pestisidyo.',
  'Inspect canonical evidence': 'Suriin ang naka-save na larawan',
  'Tap to inspect full-resolution evidence':
      'I-tap para makita ang malinaw na naka-save na larawan',
  'Canonical evidence could not be decoded.':
      'Hindi mabasa ang naka-save na larawan.',
  'Canonical evidence is unavailable.':
      'Hindi available ang naka-save na larawan.',
  'Completion checks passed. No required work remains.':
      'Kumpleto ang lahat ng kailangang itala.',
  'The raw path is grey; the saved outline is green.':
      'Gray ang naitalang GPS na dinaanan; berde ang naka-save na outline.',
  'ACCOUNT DETAILS': 'DETALYE NG ACCOUNT',
  'ADVISORY': 'GABAY',
  'NEXT ACTION': 'SUSUNOD NA HAKBANG',
  'IMAGE MODELS': 'IMAGE MODELS',
  'About this map': 'Tungkol sa mapang ito',
  'Add a photo': 'Magdagdag ng larawan',
  'All caught up': 'Walang bagong abiso',
  'Approximate date': 'Tinatayang petsa',
  'Approximate scouting boundary': 'Tinatayang hangganan para sa pagsusuri',
  'Boundary accuracy': 'Katumpakan ng hangganan',
  'Chats': 'Mga usapan',
  'New': 'Bago',
  'New chat': 'Bagong usapan',
  'Current conversation': 'Kasalukuyang usapan',
  'Recent chats': 'Mga nakaraang usapan',
  'No past chats yet.': 'Wala pang nakaraang usapan.',
  'Today': 'Ngayon',
  'Yesterday': 'Kahapon',
  'Choose a station': 'Pumili ng istasyon',
  'Confirm treatment before entering.':
      'Suriin ang treatment sa bukid bago pumasok.',
  'Could not change the model setting.': 'Hindi na-save ang setting ng modelo.',
  'Could not open that chat. Try again.':
      'Hindi mabuksan ang usapan. Subukan muli.',
  'Could not save the AI sharing setting.':
      'Hindi na-save ang setting ng pagbabahagi sa AI.',
  'Could not save this chat. Try again.':
      'Hindi na-save ang usapan. Subukan muli.',
  'Create PDF': 'Gumawa ng PDF',
  'Current': 'Kasalukuyan',
  'Damage screening': 'Damage screening',
  'Days': 'Araw',
  'Hours': 'Oras',
  'Exact date and time': 'Eksaktong petsa at oras',
  'Expert leaf-damage review': 'Pagsusuri ng eksperto sa pinsala sa dahon',
  'Expert note': 'Tala ng eksperto',
  'Expert review': 'Pagsusuri ng eksperto',
  'Expert-reviewed leaf-damage severity':
      'Tindi ng pinsala sa dahon ayon sa eksperto',
  'Field history is unavailable.':
      'Hindi available ang mga nakaraang rekord ng bukid.',
  'Field reminders and expert replies':
      'Mga paalala sa bukid at sagot ng eksperto',
  'Field reminders and expert replies will appear here.':
      'Dito lalabas ang mga paalala sa bukid at sagot ng eksperto.',
  'Field trends': 'Mga pagbabago sa bukid',
  'Field-entry safety': 'Kaligtasan sa pagpasok sa bukid',
  'Pest identification': 'Pagkilala sa uri ng peste',
  'On larva detection': 'Kapag may nakitang uod',
  'GPS unavailable': 'Hindi available ang GPS',
  'Locations recorded during capture':
      'Mga lokasyong naitala habang kumukuha ng larawan',
  'Manage saved map': 'Ayusin ang naka-save na mapa',
  'Map information': 'Impormasyon sa mapa',
  'Remove download': 'Alisin ang na-download na mapa',
  'My GPS position': 'Aking lokasyon sa GPS',
  'Back to field': 'Bumalik sa bukid',
  'Imagery': 'Imagery',
  'Street map': 'Street map',
  'Piat street map': 'Street map ng Piat',
  'Downloaded map': 'Na-download na mapa',
  'Models': 'Mga modelo',
  'More steps': 'Iba pang hakbang',
  'No saved fields yet.': 'Wala pang naka-save na bukid.',
  'Observed samples only. Missing months are not zero infestation.':
      'Batay lamang sa mga nasuri. Ang buwang walang rekord ay hindi nangangahulugang walang infestation.',
  'Offline field map': 'Offline na mapa ng bukid',
  'Offline scouting guide': 'Offline na gabay sa pagsusuri ng bukid',
  'Photo captured. Retry GPS or save it without a location.':
      'Nakuha ang larawan. Subukan muli ang GPS o i-save nang walang lokasyon.',
  'Photo unavailable. Refresh to try again.':
      'Hindi available ang larawan. I-refresh para subukan muli.',
  'Photos and scores could not be loaded. Check your connection and try again.':
      'Hindi ma-load ang mga larawan at score. Suriin ang internet at subukan muli.',
  'Preparing a reply': 'Inihahanda ang sagot',
  'Product label': 'Label ng produkto',
  'Spray record': 'Rekord ng pag-spray',
  'Agricultural adviser': 'Agricultural adviser',
  'Retry GPS': 'Subukan muli ang GPS',
  'Retry station GPS': 'Subukan muli ang GPS ng istasyon',
  'Retry opening account': 'Subukang buksan muli ang account',
  'Save a field boundary or location first.':
      'I-save muna ang hangganan o lokasyon ng bukid.',
  'Save photo without GPS': 'I-save ang larawan nang walang GPS',
  'Save without GPS': 'I-save nang walang GPS',
  'Sign out?': 'Mag-sign out?',
  'Showing local guidance while fresh AI advice loads.':
      'Ipinapakita muna ang offline na gabay habang inihahanda ang bagong sagot ng AI.',
  'Some plant ratings are unavailable. Refresh to try loading the complete review.':
      'Hindi available ang ilang score ng halaman. I-refresh para ma-load ang buong pagsusuri.',
  'Submitted photos are unavailable.':
      'Hindi available ang mga ipinadalang larawan.',
  'This finalized review is no longer available.':
      'Hindi na available ang natapos na pagsusuri.',
  'This field over time': 'Mga pagbabago sa bukid sa paglipas ng panahon',
  'Treatment details': 'Detalye ng treatment sa bukid',
  'Unknown': 'Hindi alam',
  'Use AI advice': 'Gamitin ang gabay ng AI',
  'Sends this assessment summary to Gemini. Off uses local guidance.':
      'Ipapadala sa Gemini ang buod ng pagsusuri. Kapag naka-off, offline na gabay ang gagamitin.',
  'View photos and plant scores': 'Tingnan ang mga larawan at score ng halaman',
  'Your saved records remain on this device.':
      'Mananatili sa teleponong ito ang mga naka-save mong rekord.',
  'Regenerate interpretation': 'Gumawa muli ng paliwanag',
  'About this result': 'Tungkol sa resultang ito',
  'Refresh photos and scores': 'I-refresh ang mga larawan at score',
  'No visible leaf damage': 'Walang nakikitang pinsala sa dahon',
  'Only pin-hole damage to leaves':
      'Maliliit na butas lamang na kasinlaki ng tusok ng karayom',
  'Pin-hole and shot-hole damage':
      'Maliliit na butas at mas malalaking bilog na butas',
  'Small elongated lesions (5–10 mm) on 1–3 leaves':
      'Maliliit na pahabang pinsala (5–10 mm) sa 1–3 dahon',
  'Mid-sized lesions (10–30 mm) on 4–7 leaves':
      'Katamtamang pinsala (10–30 mm) sa 4–7 dahon',
  'Long lesions (>30 mm) or small portions eaten on 3–5 leaves':
      'Mahahabang pinsala (>30 mm) o kaunting bahaging nakain sa 3–5 dahon',
  'Long lesions (>30 mm) and large portions eaten on 3–5 leaves':
      'Mahahabang pinsala (>30 mm) at malaking bahaging nakain sa 3–5 dahon',
  'Elongated lesions and about 50% of leaf eaten':
      'Pahabang pinsala at humigit-kumulang 50% ng dahon ang nakain',
  'Elongated lesions and about 70% of leaf eaten':
      'Pahabang pinsala at humigit-kumulang 70% ng dahon ang nakain',
  'Long lesions on most leaves with complete defoliation':
      'Mahahabang pinsala sa karamihan ng dahon, at lubos na pagkawala ng mga dahon',
  'No scorable plants': 'Walang halamang mabibigyan ng score',
  'No plants could be scored from the submitted photos':
      'Walang halamang mabibigyan ng score batay sa ipinadalang larawan',
  'Insufficient evidence': 'Hindi sapat ang ebidensiya',
  'The submitted photos did not support a leaf-damage score.':
      'Hindi sapat ang ipinadalang larawan para magbigay ng score ng pinsala sa dahon.',
  'Each score below is the expert’s saved rating for the submitted plant photos. Tap a photo to enlarge it.':
      'Ang bawat score ay mula sa pagsusuri ng eksperto sa ipinadalang larawan ng halaman. I-tap ang larawan para palakihin.',
  'Waiting for review': 'Naghihintay ng pagsusuri',
  'Pending': 'Naghihintay',
  'Under review': 'Sinusuri ng eksperto',
  'Needs information': 'Kailangan ng dagdag na impormasyon',
  'Advice sent': 'Naipadala ang payo',
  'Closed': 'Sarado na',
  'Assessment update': 'Update sa pagsusuri',
  'Completed': 'Tapos na',
  'Drafts': 'Hindi pa tapos ang setup',
  'In progress': 'Isinasagawa',
  'Incomplete': 'Hindi kumpleto',
  'Cancelled': 'Kinansela',
  'Invalid': 'May kailangang itama',
  'Setup incomplete': 'Hindi pa tapos ang setup',
  'Safety review needed': 'Kailangang suriin ang kaligtasan',
  'Recorded as completed': 'Naitalang tapos na',
  'Marked invalid': 'Naitalang may kailangang itama',
  'Unknown status': 'Hindi alam ang status',
  'Continue setup': 'Ipagpatuloy ang setup',
  'Review safety': 'Suriin ang kaligtasan',
  'Safety review': 'Pagsusuri sa kaligtasan',
  'Continue scouting': 'Ipagpatuloy ang pagsusuri sa bukid',
  'View results': 'Tingnan ang resulta',
  'View details': 'Tingnan ang detalye',
  'Sampling not started': 'Hindi pa nagsisimula ang sampling',
  'Area': 'Lawak',
  'AREA': 'LAWAK',
  'PLANTED': 'ITINANIM',
  'CROP AGE': 'EDAD NG TANIM',
  'Crop age': 'Edad ng tanim',
  'Not entered': 'Hindi pa inilagay',
  'New update': 'Bagong update',
  'FOLLOW UP': 'FOLLOW-UP',
  'FIELD REMINDER': 'PAALALA SA BUKID',
  'EXPERT REVIEW': 'PAGSUSURI NG EKSPERTO',
  'EXPERT ADVICE': 'PAYO NG EKSPERTO',
  'SEVERITY REVIEW': 'PAGSUSURI SA TINDI NG PINSALA',
  'Earlier': 'Nauna',
  'Open review': 'Buksan ang pagsusuri',
  'View assessment': 'Tingnan ang pagsusuri',
  'Open Assess': 'Buksan ang Pagsusuri',
  'No recent assessment': 'Walang bagong pagsusuri',
  'Follow up on your assessment': 'Balikan ang iyong pagsusuri',
  'Severity overview is ready': 'Handa na ang buod ng tindi ng pinsala',
  'Expert needs more information':
      'Kailangan ng eksperto ng dagdag na impormasyon',
  'Expert advice is ready': 'Handa na ang payo ng eksperto',
  'You': 'Ikaw',
  'WormWise expert': 'Eksperto ng WormWise',
  'Saved AI advice': 'Naka-save na gabay ng AI',
  'New AI advice': 'Bagong gabay ng AI',
  'Offline guidance': 'Offline na gabay',
  'Your saved assessment has not been changed.':
      'Hindi nabago ang naka-save mong pagsusuri.',
  'Your saved records have not been changed.':
      'Hindi nabago ang mga naka-save mong rekord.',
  'Guest account': 'Guest account',
  'In Progress': 'Isinasagawa',
  'On device': 'Nasa telepono',
  'No download': 'Walang na-download',
  'Saved offline': 'Naka-save offline',
  'Piat-area streets · works without internet':
      'Street map ng Piat · magagamit offline',
  'Save nearby streets for use without internet.':
      'I-save ang street map ng paligid para magamit offline.',
  'Download map': 'I-download ang mapa',
  'Update map': 'I-update ang mapa',
  'Review Assessment Safety': 'Suriin ang kaligtasan bago magsimula',
  'Saving...': 'Sine-save...',
  'Save and start scouting': 'I-save at simulan ang pagsusuri',
  'Save safety check': 'I-save ang safety check',
  'Edit Maize Field': 'I-edit ang bukid ng mais',
  'Add Maize Field': 'Magdagdag ng bukid ng mais',
  'Locating barangay...': 'Hinahanap ang barangay...',
  'Save field': 'I-save ang bukid',
  'Save changes': 'I-save ang mga pagbabago',
  'Your saved assessment setup remains on this phone. Confirm the field outline before continuing it.':
      'Naka-save pa rin sa teleponong ito ang setup ng pagsusuri. Kumpirmahin ang outline ng bukid bago magpatuloy.',
  'Confirm the field outline before setting up an assessment for {field}.':
      'Kumpirmahin ang outline ng bukid bago maghanda ng pagsusuri para sa {field}.',
  'Confirm field-entry safety first': 'Tiyaking ligtas pumasok sa bukid',
  'Do not enter the field until the reported re-entry restriction and other entry requirements have been verified.':
      'Huwag pumasok hangga’t hindi natiyak ang re-entry period at iba pang tuntunin sa pagpasok.',
  'Share the saved record for advice':
      'Ibahagi ang naka-save na rekord para humingi ng payo',
  'An agronomist can review the saved findings and photos without a new field visit.':
      'Maaaring suriin ng agronomist ang naka-save na resulta at mga larawan nang walang bagong pagbisita sa bukid.',
  'Review incomplete sample evidence':
      'Suriin ang kulang na ebidensiya sa sample',
  'Check the unscreened observations and saved record issues before treating this sample as complete evidence.':
      'Suriin ang mga obserbasyong walang screening result at mga problema sa rekord bago ituring na kumpleto ang ebidensiya ng sample.',
  'Review flagged station evidence':
      'Suriin ang ebidensiya sa mga namarkahang istasyon',
  'Revisit affected stations': 'Balikan ang mga apektadong istasyon',
  'Open the saved photos and model damage-screening findings for the flagged station before deciding what needs field confirmation.':
      'Buksan ang naka-save na mga larawan at damage-screening result ng namarkahang istasyon bago magpasiya kung ano ang kailangang kumpirmahin sa bukid.',
  'Return to the station locations with the highest recorded evidence count and compare them with the surrounding sampled area.':
      'Balikan ang mga istasyong may pinakamaraming naitalang ebidensiya at ihambing sa mga sample sa paligid.',
  'Inspect surrounding plants': 'Suriin ang mga halaman sa paligid',
  'Check neighboring maize plants to confirm whether the model-suggested damage or signs are present.':
      'Suriin ang katabing mga halaman ng mais para kumpirmahin ang pinsala o mga palatandaang iminungkahi ng modelo.',
  'Check neighboring maize plants for fresh feeding signs, frass, larvae, or eggs and record only what is directly observed.':
      'Suriin ang katabing mga halaman para sa bagong pinsala mula sa pagkain ng uod, frass, uod, o itlog. Itala lamang ang aktuwal na nakita.',
  'Recheck egg-positive locations':
      'Balikan ang mga lokasyong may naitalang itlog',
  'Revisit the locations where eggs were recorded and document any change during the next protocol-guided assessment.':
      'Balikan ang mga lokasyong may naitalang itlog at itala ang pagbabago sa susunod na pagsusuri ayon sa protocol.',
  'Review larval-positive observations':
      'Suriin ang mga obserbasyong may naitalang uod',
  'Pay attention to the recorded larval locations and compare nearby plants for continuing feeding evidence.':
      'Suriin ang lokasyon ng mga naitalang uod at ang katabing halaman para sa patuloy na pinsala mula sa pagkain.',
  'Continue protocol-based monitoring':
      'Ipagpatuloy ang monitoring ayon sa protocol',
  'Repeat scouting according to the applicable WormWise field protocol and compare the next completed assessment with this saved record.':
      'Ulitin ang pagsusuri ayon sa WormWise protocol at ihambing ang susunod na natapos na pagsusuri sa rekord na ito.',
  'Use local agricultural support when needed':
      'Humingi ng tulong sa lokal na agriculture office kung kailangan',
  'Share the completed assessment with the appropriate local agriculture office when follow-up support or management decisions are needed.':
      'Ibahagi ang natapos na pagsusuri sa angkop na lokal na agriculture office kung kailangan ng follow-up o payo sa pamamahala ng peste.',
  'Review entry safety': 'Suriin ang kaligtasan sa pagpasok',
  'View saved evidence': 'Tingnan ang naka-save na ebidensiya',
  'View next step': 'Tingnan ang susunod na hakbang',
  'Could not load field options. Reopen Assess to retry.':
      'Hindi ma-load ang mga bukid. Buksan muli ang Pagsusuri para subukan muli.',
  'Selected field unavailable': 'Hindi available ang napiling bukid',
  'Some saved map information could not be loaded.':
      'Hindi ma-load ang ilang naka-save na detalye ng mapa.',
  'Could not remove the saved map.': 'Hindi maalis ang naka-save na mapa.',
  'Edit display name': 'Palitan ang pangalan sa profile',
  'Display name': 'Pangalan sa profile',
  'Enter a display name.': 'Maglagay ng pangalan sa profile.',
  'Display name updated.': 'Na-update ang pangalan sa profile.',
  'Could not save the profile photo.': 'Hindi na-save ang larawan sa profile.',
  'Could not update your name.': 'Hindi na-update ang iyong pangalan.',
  'Name saved on this phone. Account update will retry later.':
      'Naka-save ang pangalan sa teleponong ito. Susubukan muli ang update sa account mamaya.',
  // Templates are translated before inserting names, measurements, and dates.
  '{count} days': '{count} araw',
  '{count} new updates': '{count} bagong update',
  'Station {number}': 'Istasyon {number}',
  'Station {number} of {total}': 'Istasyon {number} sa {total}',
  'Plant {number}': 'Halaman {number}',
  'Station {station} · Plant {plant}': 'Istasyon {station} · Halaman {plant}',
  '{count} of {total}': '{count} sa {total}',
  '{stations} of {total} station records · {photos} photos':
      '{stations} sa {total} rekord ng istasyon · {photos} larawan',
  'Median Davis score: {score}/9': 'Median Davis score: {score}/9',
  'Davis score: {score}/9': 'Davis score: {score}/9',
  '{reviewed} plants reviewed · {scored} scored · {insufficient} insufficient evidence':
      '{reviewed} halamang nasuri · {scored} may score · {insufficient} kulang ang ebidensiya',
  '{scored} scored · {insufficient} insufficient evidence':
      '{scored} may score · {insufficient} kulang ang ebidensiya',
  'Submitted photo {number} of {total}':
      'Ipinadalang larawan {number} sa {total}',
  'Submitted {date}': 'Ipinadala noong {date}',
  'Finalized {date}': 'Natapos noong {date}',
  'Generated {date}': 'Ginawa noong {date}',
  'Page {number} of {total}': 'Pahina {number} sa {total}',
  '{label} submitted evidence': 'Ipinadalang ebidensiya: {label}',
  'Open and zoom {caption}': 'Buksan at palakihin: {caption}',
  'stage photo': 'larawan ng growth stage',
  "It's been {days} days since you added {field}. Consider assessing it.":
      '{days} araw na mula nang idagdag mo ang {field}. Maaari mo itong suriin.',
  "It's been {days} days since you assessed {field}. Consider checking it again.":
      '{days} araw na mula nang suriin mo ang {field}. Maaari mo itong balikan.',
  'Consider revisiting {field} after your recent assessment.':
      'Maaaring balikan ang {field} pagkatapos ng huling pagsusuri.',
  'An expert finalized the severity overview for {field}.':
      'Natapos na ng eksperto ang buod ng tindi ng pinsala para sa {field}.',
  'An expert needs more information about {field}.':
      'Kailangan ng eksperto ng dagdag na impormasyon tungkol sa {field}.',
  'Advice is ready for {field}.': 'Handa na ang payo para sa {field}.',
  'You have a message about {field}.': 'May mensahe tungkol sa {field}.',
  'Expert severity review is ready for {field}.':
      'Handa na ang pagsusuri ng eksperto sa tindi ng pinsala para sa {field}.',
  '{field} is waiting for review.': 'Naghihintay ng pagsusuri ang {field}.',
  'An expert is reviewing {field}.': 'Sinusuri ng eksperto ang {field}.',
  'More information is needed for {field}.':
      'Kailangan ng dagdag na impormasyon para sa {field}.',
  'The review for {field} is closed.':
      'Sarado na ang pagsusuri para sa {field}.',
  'There is an update for {field}.': 'May update para sa {field}.',
  'Could not create the PDF report. Please try again.':
      'Hindi magawa ang PDF report. Subukan muli.',
  'FIELD SCOUTING': 'PAGSUSURI SA BUKID',
  'FIELD TOOLS': 'MGA GAMIT SA BUKID',
  'FIELD RECORD': 'REKORD NG BUKID',
  'Crop details': 'Detalye ng tanim',
  'Intended use': 'Gamit ng ani',
  'Municipality / City': 'Bayan / Lungsod',
  'Landmark / notes': 'Palatandaan / tala',
  'Mapped': 'May outline sa mapa',
  'Not mapped': 'Wala pang outline',
  'Dry grain': 'Tuyong butil',
  'Green corn / fresh ears': 'Murang mais / sariwang bunga',
  'Seed production': 'Produksiyon ng binhi',
  'Other use': 'Ibang gamit',
  'Clear sky': 'Maaliwalas',
  'Mostly clear': 'Kadalasang maaliwalas',
  'Partly cloudy': 'Bahagyang maulap',
  'Overcast': 'Maulap',
  'Foggy': 'Mahamog',
  'Drizzle': 'Ambon',
  'Rain': 'Ulan',
  'Snow': 'Snow',
  'Rain showers': 'Pabugso-bugsong ulan',
  'Snow showers': 'Snow showers',
  'Thunderstorm': 'Ulan na may pagkulog',
  'Current weather': 'Kasalukuyang panahon',
  'Weather is unavailable.': 'Hindi available ang datos ng panahon.',
  'Temperature': 'Temperatura',
  'Humidity': 'Humidity',
  'Wind': 'Hangin',
  'Soil moisture': 'Soil moisture',
  'No data': 'Walang datos',
  'Good morning!': 'Magandang umaga!',
  'Good afternoon!': 'Magandang hapon!',
  'Good evening!': 'Magandang gabi!',
  'Set up a maize field to begin.':
      'Magdagdag ng bukid ng mais para magsimula.',
  'The latest assessment for {field} is complete.':
      'Tapos na ang pinakahuling pagsusuri para sa {field}.',
  '{field} is your active field.': 'Ang {field} ang kasalukuyan mong bukid.',
  'Capture Seedlings 1–10': 'Kunan ang mga Punla 1–10',
  'Capture Plants 1–10': 'Kunan ang mga Halaman 1–10',
  'Both required views accepted': 'Naitala na ang dalawang kailangang larawan',
  'Required overview accepted': 'Naitala na ang kailangang overview photo',
  'Review station': 'Suriin ang istasyon',
  'Saving…': 'Sine-save…',
  'Save plant': 'I-save ang halaman',
  'Save Plant 10 and review': 'I-save ang Halaman 10 at suriin ang istasyon',
  'Current FAW-consistent evidence':
      'Bagong ebidensiyang maaaring tumugma sa FAW',
  'Current FAW-consistent signs detected':
      'May nakitang bagong palatandaang maaaring tumugma sa FAW',
  'No current signs detected on newest leaves.':
      'Walang nakitang bagong palatandaan sa pinakabagong mga dahon.',
  'No current signs recorded': 'Walang naitalang bagong palatandaan',
  'Old damage only': 'Lumang pinsala lamang',
  'Possible non-FAW': 'Posibleng ibang sanhi bukod sa FAW',
  'Empty spot documented': 'Naitala ang puwestong walang tanim',
  'Remnant documented': 'Naitala ang natirang bahagi ng punla',
  'Manual fallback documented': 'Naitala ang manual na paraan',
  'sampled plants screened': 'halamang nasuri ng screening',
  'Model damage-screen positive plants':
      'Mga halamang may pinsalang nakita ng modelo',
  'First recorded evidence baseline saved.':
      'Naka-save na ang unang rekord ng ebidensiya para sa paghahambing.',
  'Recorded evidence decreased since the previous assessment.':
      'Bumaba ang naitalang ebidensiya mula sa huling pagsusuri.',
  'Recorded evidence increased since the previous assessment.':
      'Tumaas ang naitalang ebidensiya mula sa huling pagsusuri.',
  'Straight-line distance': 'Distansiya sa tuwid na linya',
  'Approximate direction': 'Tinatayang direksiyon',
  'Phone accuracy': 'Katumpakan ng GPS',
  'Sample on the right when accessible.':
      'Kumuha ng sample sa kanan kung ligtas marating.',
  'Sample on the left when accessible.':
      'Kumuha ng sample sa kaliwa kung ligtas marating.',
  'Waiting for phone location…': 'Hinahanap ang lokasyon ng telepono…',
  'Capturing photo…': 'Kinukunan ang larawan…',
  'Saving location…': 'Sine-save ang lokasyon…',
  'Retry location for saved photo': 'Subukan muli ang GPS para sa larawan',
  'Download failed. Check your internet and try again. Any previous download is kept.':
      'Hindi na-download ang mapa. Suriin ang internet at subukan muli. Naka-save pa rin ang naunang download.',
  'GPS unavailable. Enable location permission and try outside.':
      'Hindi available ang GPS. Payagan ang lokasyon at subukan sa labas.',
  'Assessor': 'Tagasuri',
  'About Model 2': 'Tungkol sa Model 2',
  'About boundary accuracy': 'Tungkol sa katumpakan ng hangganan',
  'OPEN IN WORMWISE': 'BUKSAN SA WORMWISE',
  'Product used (optional)': 'Produktong ginamit (opsyonal)',
  'Re-entry period': 'Re-entry period',
  'Source of re-entry period': 'Pinagbatayan ng re-entry period',
  'When did spraying end?': 'Kailan natapos ang pag-spray?',
  'Unit': 'Unit',
  'Permanent deletion pending': 'Naghihintay ng permanenteng pagbura',
  'Permanently deleted in {days} days':
      'Permanenteng mabubura pagkalipas ng {days} araw',
  'Export assessment report': 'I-export ang report ng pagsusuri',
  'Save or share a PDF report for a crop expert.':
      'I-save o ibahagi ang PDF report para sa eksperto sa pananim.',
  'Save or Share Assessment PDF': 'I-save o ibahagi ang PDF ng pagsusuri',
  'Include evidence photos': 'Isama ang mga larawang ebidensiya',
  'Include field map and stations': 'Isama ang mapa at mga istasyon',
  'Include precise station coordinates':
      'Isama ang eksaktong coordinates ng istasyon',
  'Included': 'Kasama',
  'Adds available saved photos to the PDF; the file may be large.':
      'Isasama ang mga available na naka-save na larawan; maaaring lumaki ang PDF file.',
  'Only stations recorded with phone GPS will show coordinates.':
      'Coordinates lamang ng mga istasyong naitala gamit ang GPS ng telepono ang ipapakita.',
  'Shows the saved outline and phone-GPS station markers without aerial imagery.':
      'Ipinapakita ang naka-save na outline at mga istasyon mula sa GPS ng telepono, nang walang aerial imagery.',
  'Offline report with sample counts, station findings, treatment safety, and evidence inventory.':
      'Offline na report ng bilang ng sample, resulta bawat istasyon, kaligtasan sa treatment, at mga ebidensiya.',
  'The PDF contains saved field findings and reported treatment safety details. Add the field map and available evidence photos for expert review. Expert severity review remains separate.':
      'Kasama sa PDF ang naitalang resulta at kaligtasan sa treatment sa bukid. Maaaring isama ang mapa at mga larawan para masuri ng eksperto. Hiwalay ang severity review ng eksperto.',
  'Keep your fields and assessments when you create an account.':
      'Isama ang iyong mga bukid at pagsusuri kapag gumawa ka ng account.',
  'Keep your guest fields and assessments with your account.':
      'Isama sa account ang mga bukid at pagsusuring ginawa bilang guest.',
  'Save guest profile to an account': 'Isama ang guest profile sa account',
  'Model damage screening and sign hints need review; they are not confirmed FAW infestation.':
      'Kailangang suriin ang damage screening at mga mungkahi ng modelo. Hindi pa kumpirmadong FAW infestation ang mga ito.',
  'The percentage of screened plants with damage detected by Model 1. Each plant is counted once. Plants without a screening result are excluded. Expert-reviewed severity is reported separately.':
      'Porsiyento ng mga halaman na may pinsalang nakita ng Model 1. Isang beses lamang binibilang ang bawat halaman. Hindi kasama ang walang screening result. Hiwalay ang severity score mula sa eksperto.',
  'The photo will be saved with location marked unavailable.':
      'Ise-save ang larawan na may markang hindi available ang lokasyon.',
  'This photo can still be saved. Its location will be marked unavailable.':
      'Maaari pa ring i-save ang larawan. Mamarkahang hindi available ang lokasyon nito.',
  'The saved assessment does not confirm that field entry is allowed. Check the treatment record, product label, and any other entry requirements before visiting a station.':
      'Hindi kinukumpirma ng naka-save na pagsusuri na ligtas pumasok sa bukid. Suriin ang treatment record, label ng produkto, at iba pang tuntunin bago pumunta sa istasyon.',
  'The suggested next action above is the current guidance.':
      'Ang mungkahing hakbang sa itaas ang kasalukuyang gabay.',
  'Approximate phone GPS. Nearby plants may overlap. To record missing plant GPS, return to that plant and retake its photo.':
      'Tinatayang lokasyon mula sa GPS ng telepono. Maaaring magpatong sa mapa ang magkakalapit na halaman. Para maidagdag ang nawawalang GPS, balikan ang halaman at kunan muli ng larawan.',
  'The Piat-area street map is stored in the app and works offline. It contains OpenStreetMap roads and waterways. Your field boundary and station markers appear on top. Imagery needs internet. For fields outside the Piat-area map, you can download a small nearby map.':
      'Naka-save sa app ang street map ng Piat at magagamit offline. Kasama ang mga daan at daluyan ng tubig mula sa OpenStreetMap. Makikita rin ang hangganan at mga istasyon ng iyong bukid. Kailangan ng internet para sa imagery. Para sa bukid sa labas ng mapang ito, maaaring mag-download ng maliit na mapa ng paligid.',
  'Version 1.0.0+1 · Structured field scouting':
      'Version 1.0.0+1 · Gabay na pagsusuri sa bukid',
};

/// Keep terminology consistent in older paragraphs without touching their keys.
String simplifyFilipino(String text) => text
    .replaceAll('yugtong behetatibo', 'vegetative stage')
    .replaceAll('kuwelyo ng dahon', 'leaf collar')
    .replaceAll('kuwelyo', 'leaf collar')
    .replaceAll('gitnang dahon', 'whorl')
    .replaceAll('pangkulturang hakbang', 'hakbang sa pangangalaga ng tanim')
    .replaceAll('pagpapakahulugan', 'paliwanag')
    .replaceAll('balangkas', 'outline')
    .replaceAll('paggamot', 'treatment');
