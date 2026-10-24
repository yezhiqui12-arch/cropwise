import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/models/da_monitoring.dart';

void main() {
  test('numeric observations cannot be cast to presence checkboxes', () {
    expect(
      daObservationOverrides({
        'egg': 0.5,
        'larva': true,
        'pupa': false,
        'damage': 2.9,
      }),
      {'larva': true, 'pupa': false},
    );
    final finding =
        const DaPlantFinding({
          'egg': null,
          'larva': null,
          'pupa': null,
          'damage': true,
        }).withCorrections({
          'signature': 'same-photo',
          'overrides': {'egg': 0.5, 'larva': true, 'damage': 2.9},
        }, 'same-photo');
    expect(finding.values['egg'], isNull);
    expect(finding.values['larva'], true);
    expect(finding.values['damage'], true);
    expect(finding.corrected.keys, ['larva']);
  });
}
