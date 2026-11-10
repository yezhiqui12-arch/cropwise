/// PDF copy is translated separately from names, notes, and scientific codes.
const reportFilipino = <String, String>{
  'Cropwise field assessment record':
      'Cropwise na rekord ng pagsusuri sa bukid',
  'FIELD ASSESSMENT RECORD': 'REKORD NG PAGSUSURI SA BUKID',
  'Assessment findings for professional review':
      'Mga resulta para suriin ng eksperto',
  'This report contains saved field observations and sample calculations. Expert leaf-damage severity is not included; check the Expert Review screen for any finalized rating. This report does not identify a pesticide, dose, or treatment decision.':
      'Kasama rito ang naka-save na obserbasyon at pagkalkula sa sample. Hiwalay ang severity score ng eksperto; tingnan ang Expert Review para sa natapos na rating. Walang tinutukoy na pestisidyo, dosis, o pasiya sa treatment ang report na ito.',
  'Field and assessment': 'Bukid at pagsusuri',
  'Location': 'Lokasyon',
  'Maize variety': 'Uri ng mais',
  'Growth stage': 'Growth stage',
  'Evaluator': 'Tagasuri',
  'Assessment completed': 'Natapos ang pagsusuri',
  'Approximate field area': 'Tinatayang lawak ng bukid',
  'Scouting route': 'Ruta ng pagsusuri',
  'Assessment ID': 'Assessment ID',
  'Sampled result': 'Resulta ng sample',
  'Result': 'Resulta',
  'Unavailable - no valid denominator':
      'Hindi available — walang wastong bilang ng nasuri',
  'This value is a model damage-screening result, not a measurement of current FAW infestation. Model signs are suggestions pending field or expert confirmation.':
      'Resulta ito ng damage screening ng modelo. Hindi nito sinusukat ang kasalukuyang FAW infestation. Kailangang kumpirmahin sa bukid o ng eksperto ang mga mungkahi ng modelo.',
  'This value describes the sampled observations only. It does not estimate a whole-field severity class or establish FAW identity.':
      'Batay lamang ito sa mga nasuring sample. Hindi nito tinutukoy ang severity ng buong bukid o kinukumpirma ang FAW.',
  'Reviewed stations': 'Mga nasuring istasyon',
  'Assessable observations': 'Mga obserbasyong maaaring suriin',
  'Record verification': 'Pagsuri sa mga rekord',
  'Current checks passed': 'Walang nakitang kulang sa kasalukuyang checks',
  'Requires verification - {count} issue(s)':
      'Kailangang suriin — {count} problemang naitala',
  'Station findings': 'Resulta bawat istasyon',
  'Positive counts and visible-sign counts are distinct. Signs can overlap on the same sampled plant. Photo counts describe saved evidence files, not independently confirmed findings.':
      'Magkaiba ang bilang ng positive na halaman at bilang ng bawat palatandaan. Maaaring may higit sa isang palatandaan ang isang halaman. Bilang ng naka-save na larawan ang photo count; hindi ito bilang ng kumpirmadong resulta.',
  'No station observations are available.':
      'Walang available na obserbasyon sa mga istasyon.',
  'Station': 'Istasyon',
  'Damage + / assessed': 'May pinsala / nasuri',
  'Positive / assessed': 'Positive / nasuri',
  'Recorded': 'Naitala',
  'Rate': 'Porsiyento',
  'Damage': 'Pinsala',
  'Frass': 'Dumi ng uod',
  'Larva': 'Uod',
  'Egg': 'Itlog',
  'Photos': 'Larawan',
  'Recorded station coordinates': 'Naitalang coordinates ng istasyon',
  'Only coordinates marked as captured by phone GPS are listed. All locations and field outlines are approximate.':
      'Coordinates lamang na naitala gamit ang GPS ng telepono ang kasama. Tinataya lamang ang lahat ng lokasyon at outline ng bukid.',
  'Phone GPS not recorded': 'Hindi naitala ang GPS ng telepono',
  'Recent treatment and field-entry safety':
      'Huling treatment at kaligtasan sa pagpasok',
  'Saved safety result': 'Naka-save na resulta ng safety check',
  'Treatment application ended': 'Natapos ang paglalapat ng treatment',
  'Reported re-entry period': 'Iniulat na re-entry period',
  'Period source': 'Pinagbatayan ng re-entry period',
  'Calculated end of period': 'Nakalkulang katapusan ng re-entry period',
  'Reported treatment details': 'Iniulat na detalye ng treatment',
  'These are reported safety facts. A calculated end time does not verify the product label, protective equipment rules, or any other entry restriction.':
      'Iniulat na safety information ang mga ito. Ang nakalkulang oras ay hindi kumpirmasyon ng label ng produkto, tuntunin sa protective equipment, o iba pang pagbabawal sa pagpasok.',
  'Other saved metrics': 'Iba pang naka-save na sukatan',
  'Any evaluator-recorded leaf score below is separate from the later expert review.':
      'Hiwalay ang leaf score na naitala ng tagasuri sa pagsusuri ng eksperto sa ibang pagkakataon.',
  'No additional block metrics are available.':
      'Walang available na dagdag na resulta bawat block.',
  'incomplete data': 'hindi kumpletong datos',
  'Evidence and review limits': 'Ebidensiya at limitasyon ng pagsusuri',
  'Saved evidence photos': 'Naka-save na larawang ebidensiya',
  '{saved} saved; {included} included in the photo appendix':
      '{saved} naka-save; {included} kasama sa photo appendix',
  '{saved} saved; photos excluded from this PDF':
      '{saved} naka-save; hindi kasama ang mga larawan sa PDF na ito',
  'Protocol version': 'Protocol version',
  'Formula version': 'Formula version',
  'Review the original observations and available photos for any expert determination. Current infestation, visible damage, and a later expert severity score are different findings. A pesticide decision requires professional review of current activity, crop stage, treatment history, and the applicable product label.':
      'Suriin ang orihinal na obserbasyon at mga larawan para sa pasiya ng eksperto. Magkahiwalay na resulta ang kasalukuyang infestation, nakikitang pinsala, at severity score ng eksperto. Kailangang suriin ng propesyonal ang kasalukuyang aktibidad ng peste, growth stage, treatment history, at label ng produkto bago magpasiya sa pestisidyo.',
  'Station unknown': 'Hindi alam ang istasyon',
  'Evidence photos {start}-{end} of {total}':
      'Larawang ebidensiya {start}–{end} sa {total}',
  'Saved field evidence; image findings require expert review.':
      'Naka-save na ebidensiya sa bukid; kailangang suriin ng eksperto ang resulta ng larawan.',
  'Field map and sampled stations': 'Mapa ng bukid at mga istasyon ng sampling',
  'North is up. This offline plot uses the saved approximate field outline and phone-GPS station positions; no aerial imagery is included.':
      'Nasa itaas ang hilaga. Ginagamit ng offline na mapa ang naka-save na outline at lokasyon ng mga istasyon mula sa GPS ng telepono. Walang kasamang aerial imagery.',
  '{plotted} of {total} stations plotted from phone GPS. {unplotted} station(s) remain in the findings table.':
      '{plotted} sa {total} istasyon ang ipinakita gamit ang GPS ng telepono. Nasa talahanayan pa rin ang {unplotted} istasyong hindi ipinakita sa mapa.',
  '{count} phone-GPS station(s) lie outside this field-focused map frame.':
      '{count} istasyong may GPS ang nasa labas ng saklaw ng mapang ito.',
  'Marker colors show sampled station rates only: green below 10%, amber 10-20%, red above 20%, gray when no assessable observations. They are display bands, not severity or pesticide-treatment thresholds.':
      'Porsiyento lamang ng sample bawat istasyon ang ipinapakita ng kulay: berde kung mas mababa sa 10%, amber kung 10–20%, pula kung higit sa 20%, at gray kung walang maaaring suriin. Mga kulay para sa display ang mga ito; hindi severity score o batayan ng paggamit ng pestisidyo.',
  'A saved field outline is unavailable; only located stations are shown.':
      'Walang available na naka-save na outline; mga istasyon lamang na may lokasyon ang ipinakita.',
  'Not recorded': 'Hindi naitala',
  'Product label (reported)': 'Label ng produkto (iniulat)',
  'Spray record (reported)': 'Spray record (iniulat)',
  'Agricultural adviser (reported)': 'Agricultural adviser (iniulat)',
  'No recent treatment reported': 'Walang iniulat na bagong treatment',
  'Reported re-entry period elapsed': 'Tapos na ang iniulat na re-entry period',
  'Re-entry period active - do not enter':
      'Hindi pa tapos ang re-entry period — huwag pumasok',
  'Entry safety cannot be confirmed': 'Hindi makumpirma na ligtas pumasok',
};
