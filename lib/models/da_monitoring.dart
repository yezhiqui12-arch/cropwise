import 'dart:convert';
import '../services/computer_vision/faw_computer_vision_service.dart';
import '../data/local/app_database.dart';

const daSignLabels = {
  'egg': 'Eggs',
  'larva': 'Larvae',
  'pupa': 'Pupae',
  'damage': 'Damage',
};
const daEnemyLabels = {
  'none': 'None observed',
  'predators': 'Predators',
  'pathogens': 'Pathogens',
  'parasitoids': 'Parasitoids',
  'unknown': 'Cannot identify',
  'not_recorded': 'Not recorded',
};

/// Legacy/corrupt numeric values are not presence checkboxes. Keep them on Auto.
Map<String, bool?> daObservationOverrides(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final key in daSignLabels.keys)
      if (raw[key] is bool) key: raw[key] == true,
  };
}

String daPhotoSignature(Iterable<EvidenceMediaRecord> photos) {
  final values =
      photos
          .where((p) => p.deletedAt == null && p.storageState == 'ready')
          .map((p) => '${p.id}:${p.sha256Checksum}')
          .toList()
        ..sort();
  return values.join('|');
}

/// Report observations are separate from the original model and Davis scores.
class DaPlantFinding {
  const DaPlantFinding(this.values, {this.corrected = const {}});
  final Map<String, bool?> values;
  final Map<String, bool> corrected;
  factory DaPlantFinding.fromModel(PlantDiagnosisResult? model) {
    final detectorRan = model?.classifierStage == 'overlay_complete';
    bool? detected(int id) =>
        model?.detectionBoxes.any((b) => b.classId == id) == true
        ? true
        : detectorRan
        ? false
        : null;
    return DaPlantFinding({
      'egg': detected(3),
      'larva': detected(2),
      'pupa': null,
      'damage': model?.classificationLabel == 'FAW damage'
          ? true
          : model?.classificationLabel == 'No FAW damage'
          ? false
          : null,
    });
  }
  DaPlantFinding withCorrections(
    Map<String, dynamic>? record,
    String signature,
  ) {
    if (record == null || record['signature'] != signature) return this;
    final overrides = daObservationOverrides(record['overrides']);
    final edited = <String, bool>{};
    final result = Map<String, bool?>.from(values);
    for (final key in daSignLabels.keys) {
      if (overrides[key] is bool) {
        result[key] = overrides[key];
        edited[key] = true;
      }
    }
    return DaPlantFinding(result, corrected: edited);
  }
}

class DaMonitoringRecord {
  DaMonitoringRecord({Map<String, dynamic>? data})
    : data = data ?? {'version': 1};
  final Map<String, dynamic> data;
  factory DaMonitoringRecord.parse(String? json) {
    try {
      final value = jsonDecode(json ?? '{}');
      return DaMonitoringRecord(
        data: value is Map<String, dynamic> ? value : null,
      );
    } catch (_) {
      return DaMonitoringRecord();
    }
  }
  Map<String, dynamic> get fields =>
      Map<String, dynamic>.from(data['fields'] as Map? ?? {});
  Map<String, dynamic>? plant(String block, int number) {
    final plants = data['plants'];
    final value = plants is Map ? plants['$block:$number'] : null;
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<String>? enemies(String block) {
    final blocks = data['blocks'];
    final value = blocks is Map ? blocks[block] : null;
    final items = value is Map ? value['natural_enemies'] : null;
    return items is List ? items.whereType<String>().toList() : null;
  }
}

class DaReportRain {
  const DaReportRain({
    this.rained,
    this.millimeters,
    this.periodEnd,
    this.source = 'Unavailable',
  });
  final bool? rained;
  final double? millimeters;
  final DateTime? periodEnd;
  final String source;
  factory DaReportRain.fromContext(String? context) {
    final pairs = <String, String>{};
    for (final item in (context ?? '').split(';')) {
      final pos = item.indexOf('=');
      if (pos > 0) pairs[item.substring(0, pos)] = item.substring(pos + 1);
    }
    final mm = double.tryParse(
      pairs['open_meteo_precipitation_last_48h_mm'] ?? '',
    );
    if (mm != null && mm.isFinite && mm >= 0) {
      return DaReportRain(
        rained: mm > 0,
        millimeters: mm,
        periodEnd: DateTime.tryParse(pairs['weather_period_end_utc'] ?? ''),
        source: 'Open-Meteo',
      );
    }
    final manual = pairs['rain_wet_field_last_48h'];
    final yes = manual == 'yes' || manual == 'true';
    final no = manual == 'no' || manual == 'false';
    return DaReportRain(
      rained: yes
          ? true
          : no
          ? false
          : null,
      source: yes || no ? 'Farmer report' : 'Unavailable',
    );
  }
}
