import '../services/computer_vision/faw_computer_vision_service.dart';
import 'da_monitoring.dart';

enum PlantActionKind { larva, eggs, inspectWhorl, inspectDamage }

class PlantActionReference {
  const PlantActionReference(
    this.asset,
    this.caption,
    this.credit,
    this.license,
    this.sourceUrl,
    this.licenseUrl,
  );
  final String asset, caption, credit, license, sourceUrl, licenseUrl;
}

class PlantActionGuide {
  const PlantActionGuide(
    this.kind,
    this.title,
    this.reminder,
    this.steps,
    this.recordLabel,
    this.recordedLabel,
    this.reference,
    this.compareTip,
  );
  static const version = 1;
  static const managementSource =
      'https://www.fao.org/newsroom/detail/FAO-launches-guide-to-tackle-Fall-Armyworm-in-Africa-head-on/en';
  final PlantActionKind kind;
  final String title, reminder, recordLabel, recordedLabel, compareTip;
  final List<String> steps;
  final PlantActionReference reference;
  String get id => kind.name;
  String get preferenceId => '$id:v$version';

  static const larvaReference = PlantActionReference(
    'assets/images/faw_actions/faw_larva.jpg',
    'FAW larva',
    'Frank Peairs, Colorado State University, Bugwood.org',
    'CC BY 3.0 US',
    'https://commons.wikimedia.org/wiki/File:Spodoptera_frugiperda_caterpillar01.jpg',
    'https://creativecommons.org/licenses/by/3.0/us/',
  );
  static const eggReference = PlantActionReference(
    'assets/images/faw_actions/faw_eggs.jpg',
    'Egg mass · magnified',
    'USGS Bee Inventory and Monitoring Lab',
    'Public domain (USGS)',
    'https://commons.wikimedia.org/wiki/File:Fall_armyworm,_eggs_2014-06-06-11.15.35_ZS_PMax_(15936628061).jpg',
    'https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits',
  );
  static const damageReference = PlantActionReference(
    'assets/images/faw_actions/faw_leaf_damage.jpg',
    'Leaf feeding damage',
    'Wee Hong / Wikimedia Commons',
    'CC BY-SA 4.0',
    'https://commons.wikimedia.org/wiki/File:Zea_mays_damaged_by_Spodoptera_frugiperda_(200218-0814).jpg',
    'https://creativecommons.org/licenses/by-sa/4.0/',
  );

  static const larva = PlantActionGuide(
    PlantActionKind.larva,
    'Check the detected larva',
    'Remove identified young FAW larvae.',
    [
      'Compare the larva with the reference photo before handling it.',
      'If it matches FAW and is reachable, lift it off with tweezers or small forceps. Do not tear the whorl.',
      'Put it on a firm surface and crush it with the tool. Do not release it back into the field.',
    ],
    'Removed and destroyed',
    'Removal recorded',
    larvaReference,
    'Look for the pale inverted Y on the head and four dark spots in a square near the rear. Colours vary; use several features.',
  );
  static const eggs = PlantActionGuide(
    PlantActionKind.eggs,
    'Check the detected eggs',
    'Destroy identified FAW egg masses.',
    [
      'Compare the egg cluster with the reference. This close-up includes some hatched eggs.',
      'If identified as FAW, crush the egg mass with a small tool against a firm backing, without tearing the leaf.',
      'Do not handle unknown insects or destroy beneficial organisms.',
    ],
    'Destroyed',
    'Destruction recorded',
    eggReference,
    'FAW eggs occur in clusters, often with a covering of scales. The reference is magnified, not actual size.',
  );
  static const inspectWhorl = PlantActionGuide(
    PlantActionKind.inspectWhorl,
    'Check the whorl',
    'Look inside the whorl for a feeding larva.',
    [
      'Inspect the whorl and newest leaves for a visible feeding larva.',
      'Compare any larva you find with the FAW reference. Add a closer photo if helpful.',
      'If you find an identified young FAW larva, remove it with tweezers or small forceps and crush it with the tool.',
    ],
    'Checked',
    'Inspection recorded',
    larvaReference,
    'Frass is a reason to inspect. This photo shows the larva to look for, not frass.',
  );
  static const inspectDamage = PlantActionGuide(
    PlantActionKind.inspectDamage,
    'Look for a feeding pest',
    'Inspect the damaged leaves and whorl.',
    [
      'Look on the newest leaves and inside the whorl for larvae or frass.',
      'Photograph any finding before removing an identified pest.',
      'Leaf damage alone does not tell you whether a pest is still feeding.',
    ],
    'Checked',
    'Inspection recorded',
    damageReference,
    'Compare the feeding marks. Similar damage can have other causes; inspect for the pest itself.',
  );

  /// Resolve once per plant, not once per box/photo. Explicit, current report
  /// corrections suppress or add a guide without rewriting the model result.
  static List<PlantActionGuide> resolve(
    PlantDiagnosisResult? model, {
    DaPlantFinding? finding,
  }) {
    bool seen(int id) =>
        model?.detectionBoxes.any((b) => b.classId == id) == true;
    bool observed(String name, int id) => finding?.corrected[name] == true
        ? finding!.values[name] == true
        : seen(id);
    final larvaSeen = observed('larva', 2);
    final eggsSeen = observed('egg', 3);
    final damageSeen = finding?.corrected['damage'] == true
        ? finding!.values['damage'] == true
        : model?.classificationLabel == 'FAW damage' || seen(0);
    return [
      if (larvaSeen) larva,
      if (eggsSeen) eggs,
      if (!larvaSeen && seen(1)) inspectWhorl,
      if (!larvaSeen && !eggsSeen && !seen(1) && damageSeen) inspectDamage,
    ];
  }
}

class PlantActionRecord {
  const PlantActionRecord({
    required this.guideId,
    required this.signature,
    required this.recordedAt,
    required this.imported,
  });
  final String guideId, signature;
  final DateTime recordedAt;
  final bool imported;
  Map<String, dynamic> toJson() => {
    'guide_id': guideId,
    'guide_version': PlantActionGuide.version,
    'evidence_signature': signature,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'imported': imported,
  };
  static PlantActionRecord? parse(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['recorded_at']}');
    if (time == null ||
        raw['guide_id'] is! String ||
        raw['evidence_signature'] is! String) {
      return null;
    }
    return PlantActionRecord(
      guideId: raw['guide_id'] as String,
      signature: raw['evidence_signature'] as String,
      recordedAt: time,
      imported: raw['imported'] == true,
    );
  }
}
