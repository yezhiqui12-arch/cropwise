/// Compatibility for existing developer-authored UI sentences. Match complete
/// shapes, preserve numbers/codes verbatim, and never run this on user notes.
String? dynamicFilipino(String value) {
  String? match(String pattern, String Function(Match) render) {
    final found = RegExp(pattern).firstMatch(value);
    return found == null ? null : render(found);
  }

  String classification(String label) => switch (label) {
    'No infestation' => 'Walang infestation',
    'Light infestation' => 'Banayad na infestation',
    'Moderate infestation' => 'Katamtamang infestation',
    'Severe infestation' => 'Matinding infestation',
    'Highly severe' => 'Napakatindi',
    'Unavailable' => 'Hindi available',
    _ => label,
  };
  return match(
        r'^DA severity classification: (.+)$',
        (m) => 'Klasipikasyon ng tindi ayon sa DA: ${classification(m[1]!)}',
      ) ??
      match(
        r'^([0-9>–]+) · (No infestation|Light infestation|Moderate infestation|Severe infestation|Highly severe)$',
        (m) => '${m[1]} · ${classification(m[2]!)}',
      ) ??
      match(
        r'^Davis (.+)/9 · (.+)$',
        (m) => 'Davis ${m[1]}/9 · ${classification(m[2]!)}',
      ) ??
      match(
        r'^Davis score: (.+)/9 · (.+)$',
        (m) => 'Davis score: ${m[1]}/9 · ${classification(m[2]!)}',
      ) ??
      match(
        r'^(No infestation|Light infestation|Moderate infestation|Severe infestation|Highly severe|Unavailable) · Mean Davis (.+)/9$',
        (m) => '${classification(m[1]!)} · Mean Davis ${m[2]}/9',
      ) ??
      match(
        r'^FAW damage incidence: (.+)$',
        (m) => 'Porsiyento ng mga halamang may pinsala ng FAW: ${m[1]}',
      ) ??
      match(
        r'^Current sampled infestation: (.+)$',
        (m) => 'Kasalukuyang infestation sa sample: ${m[1]}',
      ) ??
      match(
        r'^Block (\d+) · (\d+)/20 scored$',
        (m) => 'Block ${m[1]} · ${m[2]}/20 na-rate',
      ) ??
      match(
        r'^(\d+) of (\d+) (seedling|plant) records saved$',
        (m) =>
            '${m[1]} sa ${m[2]} tala ng ${m[3] == "seedling" ? "punla" : "halaman"} ang naka-save',
      ) ??
      match(r'^(\d+) of (\d+)$', (m) => '${m[1]} sa ${m[2]}') ??
      match(r'^Save Plant (\d+)$', (m) => 'I-save ang Halaman ${m[1]}') ??
      match(
        r'^Review or correct Plant (\d+)$',
        (m) => 'Suriin o itama ang Halaman ${m[1]}',
      ) ??
      match(r'^Next Plant (\d+)$', (m) => 'Susunod na Halaman ${m[1]}') ??
      match(
        r'^Permanently deleted in (\d+) days?$',
        (m) => 'Permanenteng mabubura pagkalipas ng ${m[1]} araw',
      ) ??
      match(r'^(\d+) days$', (m) => '${m[1]} araw') ??
      match(r'^Seedling (\d+)$', (m) => 'Punla ${m[1]}') ??
      match(
        r'^Planting spot (\d+) of (\d+)$',
        (m) => 'Puwestong taniman ${m[1]} sa ${m[2]}',
      ) ??
      match(
        r'^Station (\d+) of (\d+)$',
        (m) => 'Istasyon ${m[1]} sa ${m[2]}',
      ) ??
      match(r'^STATION (\d+)$', (m) => 'ISTASYON ${m[1]}') ??
      match(
        r'^BLOCK (\d+) · STATION (\d+)$',
        (m) => 'BLOCK ${m[1]} · ISTASYON ${m[2]}',
      ) ??
      match(
        r'^Block (\d+) · Station (\d+)$',
        (m) => 'Block ${m[1]} · Istasyon ${m[2]}',
      ) ??
      match(
        r'^Block (\d+) · Station (\d+) · Plant (\d+)/(\d+)$',
        (m) => 'Block ${m[1]} · Istasyon ${m[2]} · Halaman ${m[3]}/${m[4]}',
      ) ??
      match(
        r'^Block (\d+) · Station (\d+) · (\d+) of (\d+) confirmed$',
        (m) =>
            'Block ${m[1]} · Istasyon ${m[2]} · ${m[3]} sa ${m[4]} nakumpirma',
      ) ??
      match(
        r'^BLOCK (\d+) · STATION (\d+) · (\d+) OF (\d+) PLANTS SAVED$',
        (m) =>
            'BLOCK ${m[1]} · ISTASYON ${m[2]} · ${m[3]} SA ${m[4]} HALAMAN NAKA-SAVE',
      ) ??
      match(
        r'^BLOCK (\d+) · ROUTE PREPARATION$',
        (m) => 'BLOCK ${m[1]} · PAGHAHANDA NG RUTA',
      ) ??
      match(
        r'^I reached Station (\d+)$',
        (m) => 'Nakarating na ako sa Istasyon ${m[1]}',
      ) ??
      match(
        r'^Continue to Station (\d+)$',
        (m) => 'Magpatuloy sa Istasyon ${m[1]}',
      ) ??
      match(
        r'^Station (\d+) saved\.$',
        (m) => 'Naka-save ang Istasyon ${m[1]}.',
      ) ??
      match(
        r'^Move Station (\d+) safely$',
        (m) => 'Ilipat nang ligtas ang Istasyon ${m[1]}',
      ) ??
      match(
        r'^Review Block (\d+) sampling$',
        (m) => 'Suriin ang sampling sa Block ${m[1]}',
      ) ??
      match(
        r'^(Plant|Seedling) (\d+) details$',
        (m) => 'Detalye ng ${m[1] == 'Plant' ? 'Halaman' : 'Punla'} ${m[2]}',
      ) ??
      match(
        r'^Cannot assess Plant (\d+)$',
        (m) => 'Hindi masuri ang Halaman ${m[1]}',
      ) ??
      match(
        r'^Plant (\d+) cannot be assessed$',
        (m) => 'Hindi masuri ang Halaman ${m[1]}',
      ) ??
      match(
        r'^Plant (\d+) cannot be opened$',
        (m) => 'Hindi mabuksan ang bunga sa Halaman ${m[1]}',
      ) ??
      match(
        r'^Station (\d+) capture help$',
        (m) => 'Tulong sa pagkuha ng larawan sa Istasyon ${m[1]}',
      ) ??
      match(
        r'^What is at Seedling Position (\d+)\?$',
        (m) => 'Ano ang nasa Puwesto ng Punla ${m[1]}?',
      ) ??
      match(
        r'^Next \((Seedling|Plant) (\d+)\)$',
        (m) => 'Susunod (${m[1] == 'Seedling' ? 'Punla' : 'Halaman'} ${m[2]})',
      ) ??
      match(
        r'^Plant locations: (\d+)/(\d+)$',
        (m) => 'Lokasyon ng halaman: ${m[1]}/${m[2]}',
      ) ??
      match(r'^(\d+)/(\d+) Captured$', (m) => '${m[1]}/${m[2]} nakunan') ??
      match(r'^(\d+) recorded$', (m) => '${m[1]} naitala') ??
      match(
        r'^(\d+) photos? available$',
        (m) => '${m[1]} available na larawan',
      ) ??
      match(
        r'^Last (\d+) completed assessments$',
        (m) => 'Huling ${m[1]} natapos na pagsusuri',
      ) ??
      match(
        r'^Last 48 hours · (.+) mm$',
        (m) => 'Huling 48 oras · ${m[1]} mm',
      ) ??
      match(
        r'^(\d+) not assessable · (\d+) record issue\(s\)$',
        (m) => '${m[1]} hindi masuri · ${m[2]} problema sa rekord',
      ) ??
      match(r'^(\d+) of (\d+) plants$', (m) => '${m[1]} sa ${m[2]} halaman') ??
      match(
        r'^(\d+) of (\d+) stations$',
        (m) => '${m[1]} sa ${m[2]} istasyon',
      ) ??
      match(
        r'^([\d.]+) KB · Updated (.+)$',
        (m) => '${m[1]} KB · Na-update ${m[2]}',
      ) ??
      match(r'^([\d.]+)% confidence$', (m) => '${m[1]}% confidence') ??
      match(r'^([\d.]+)% match$', (m) => '${m[1]}% match') ??
      match(
        r'^Select end (date and time|date)$',
        (m) => m[1] == 'date'
            ? 'Piliin ang petsa ng pagtatapos'
            : 'Piliin ang petsa at oras ng pagtatapos',
      );
}
