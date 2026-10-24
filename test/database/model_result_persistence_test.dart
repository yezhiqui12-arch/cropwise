import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/field_repository.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  test('model result survives database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('wormwise_model_');
    final file = File(
      '${directory.path}${Platform.pathSeparator}results.sqlite',
    );
    try {
      final original = PlantDiagnosisResult.fawInfested(
        confidence: 0.87,
        larvaSeen: true,
        larvaSize: 'small',
        frassSeen: true,
      );
      final firstDatabase = AppDatabase(NativeDatabase(file));
      await FieldRepository(firstDatabase).savePreferenceValue(
        'plant_model_station-1_2',
        jsonEncode({
          'signature': 'photo-checksum',
          'result': original.toJson(),
        }),
      );
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase(NativeDatabase(file));
      try {
        final stored = await FieldRepository(
          reopenedDatabase,
        ).readPreferenceValue('plant_model_station-1_2');
        final decoded = jsonDecode(stored!) as Map<String, dynamic>;
        final restored = PlantDiagnosisResult.fromJson(
          Map<String, dynamic>.from(decoded['result'] as Map),
        );
        expect(decoded['signature'], 'photo-checksum');
        expect(restored.toJson(), original.toJson());
      } finally {
        await reopenedDatabase.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
