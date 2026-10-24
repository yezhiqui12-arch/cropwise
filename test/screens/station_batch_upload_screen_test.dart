import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wormwise/screens/station1/station_batch_upload_screen.dart';

void main() {
  testWidgets('station import saves reviewed photos under their plant slots', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('wormwise_batch_');
    addTearDown(() => directory.delete(recursive: true));
    final photos = <XFile>[];
    for (var index = 1; index <= 3; index++) {
      final file = File('${directory.path}/plant_$index.jpg');
      await file.writeAsBytes([index]);
      photos.add(XFile(file.path));
    }
    final saved = <int, String>{};
    final analyzed = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StationBatchUploadScreen(
          stationNumber: 2,
          plantPositions: const [1, 2, 3],
          pickPhotos: (_) async => photos,
          onSavePhoto: (position, path) async {
            saved[position] = path;
          },
          onAnalyzePlant: (position) async {
            analyzed.add(position);
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('choose_station_photos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('batch_plant_1')), findsOneWidget);
    expect(find.byKey(const Key('batch_plant_3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('swap_batch_plant_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swap with Plant 3'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_station_photo_assignments')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import_station_photos')));
    await tester.pumpAndSettle();

    expect(saved[1], photos[2].path);
    expect(saved[2], photos[1].path);
    expect(saved[3], photos[0].path);
    expect(analyzed, [1, 2, 3]);
    expect(find.text('3 plant photos saved and screened.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
