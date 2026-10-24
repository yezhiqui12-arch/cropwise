import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/computer_vision/maize_leaf_classifier.dart';

void main() {
  group('Stage 1 FAW damage screen', () {
    test(
      'missing files fail rather than returning a negative screen',
      () async {
        await expectLater(
          MaizeLeafClassifier().classifyImage(File('non_existent.jpg')),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('only the FAW probability controls the binary screen', () {
      const positive = MaizeClassificationResult(
        topClass: 'faw_damage',
        topConfidence: .72,
        probabilities: {'faw_damage': .72, 'no_faw_damage': .28},
      );
      const negative = MaizeClassificationResult(
        topClass: 'no_faw_damage',
        topConfidence: .90,
        probabilities: {'faw_damage': .10, 'no_faw_damage': .90},
      );

      expect(positive.binaryLabel, 'FAW damage');
      expect(positive.isFawSuspected, true);
      expect(negative.binaryLabel, 'No FAW damage');
      expect(negative.isFawSuspected, false);
    });

    test('FAW screening threshold includes elevated FAW probability', () {
      const result = MaizeClassificationResult(
        topClass: 'faw_damage',
        topConfidence: .50,
        probabilities: {'faw_damage': .50, 'no_faw_damage': .50},
      );
      expect(result.isFawSuspected, true);
    });
  });
}
