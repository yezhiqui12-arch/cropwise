import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/models/da_batch_import.dart';
import 'package:wormwise/screens/scan/da_batch_import_screen.dart';
import 'package:wormwise/services/da_batch_import_store.dart';

void main() {
  final previews = Platform.environment['CROPWISE_DA_BULK_PREVIEW'];
  const renderKey = Key('bulk_preview');
  late AppDatabase db;
  late Directory root;
  late DaBatchImportStore store;
  final saved = <String, String>{};
  final saveCalls = <String>[];
  final screenCalls = <int>[];
  final screened = <int>{};
  var failPlantTwo = false;
  var pickerCalls = 0;
  var finishCalls = 0;
  const paths = [
    'assets/images/growth_stages/maize_young_vegetative.jpg',
    'assets/images/growth_stages/maize_tall_vegetative.jpg',
    'assets/images/growth_stages/maize_emergence.jpg',
    'assets/images/growth_stages/maize_silks.jpg',
    'assets/images/growth_stages/clemson/figure_07.jpeg',
    'assets/images/growth_stages/clemson/figure_08.jpeg',
  ];
  setUpAll(() async {
    await (FontLoader(
      'BulkRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    final icon = Platform.environment['CROPWISE_DA_ICON_FONT'];
    if (icon != null)
      await (FontLoader(
        'MaterialIcons',
      )..addFont(File(icon).readAsBytes().then(ByteData.sublistView))).load();
  });
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('wormwise_batch_ui_');
    store = DaBatchImportStore(db, rootDirectory: () async => root);
    saved.clear();
    saveCalls.clear();
    screenCalls.clear();
    screened.clear();
    failPlantTwo = false;
    pickerCalls = 0;
    finishCalls = 0;
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Widget app({double scale = 1, List<int> plants = const [1, 2, 3]}) =>
      RepaintBoundary(
        key: renderKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'BulkRoboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF155A2C),
            ),
          ),
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DaBatchImportScreen(
            store: store,
            assessmentId: 'a',
            blockId: 'b',
            blockNumber: 1,
            plantNumbers: plants,
            primaryViewType: 'overview',
            supportViewTypes: const ['close', 'detail'],
            pickPhotos: (limit) async {
              pickerCalls++;
              expect(limit, plants.length * 3);
              return paths.map(XFile.new).toList();
            },
            onSavePhoto: (plant, view, photo) async {
              saveCalls.add(photo.id);
              saved[photo.id] = '$plant:$view';
            },
            onValidatePhoto: (plant, view, id) async =>
                saved[id] == '$plant:$view',
            onValidateScreening: (plant, ids) async => screened.contains(plant),
            onScreenPlant: (plant, ids) async {
              screenCalls.add(plant);
              expect(ids.every(saved.containsKey), true);
              if (plant == 2 && failPlantTwo)
                throw StateError('Screening interrupted');
              screened.add(plant);
            },
            onFinish: () async {
              finishCalls++;
              return false;
            },
          ),
        ),
      );
  void phone(WidgetTester t, {double width = 390}) {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 100; i++) {
      await t.runAsync(() async {
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await t.runAsync(() => t.pumpAndSettle());
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
    }
    await t.ensureVisible(f);
    await t.tap(f);
    await settle(t);
  }

  Future<void> capture(WidgetTester t, String name) async {
    if (previews == null) return;
    await settle(t);
    await t.runAsync(() async {
      final context = t.element(find.byType(DaBatchImportScreen));
      await Future.wait(
        t
            .widgetList<Image>(find.byType(Image))
            .map((img) => precacheImage(img.image, context)),
      ).timeout(const Duration(seconds: 10));
    });
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(find.byKey(renderKey))
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(previews).create(recursive: true);
      await File(
        '$previews/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'one selection groups mixed photos; overview switches; restart retries only failed plant',
    (t) async {
      phone(t);
      await t.pumpWidget(app());
      await settle(t);
      await capture(t, '01_choose');
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(pickerCalls, 1);
      expect(
        (await t.runAsync(() => store.load('a', 'b')))!.photos,
        hasLength(6),
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('batch_primary')))
            .onPressed,
        isNull,
      );
      await tap(t, find.byKey(const Key('batch_boundary_3')));
      await tap(t, find.byKey(const Key('batch_boundary_4')));
      final d = (await t.runAsync(() => store.load('a', 'b')))!;
      expect(d.groups.map((g) => g.length), [3, 1, 2]);
      await t.drag(find.byType(ListView).first, const Offset(0, 800));
      await settle(t);
      await capture(t, '02_arrange');
      await tap(t, find.byKey(const Key('batch_arrange')));
      await tap(t, find.byKey(Key('batch_photo_${d.photos[2].id}')));
      await tap(t, find.text('Use as overview'));
      expect(
        (await t.runAsync(() => store.load('a', 'b')))!.groups.first.first.id,
        d.photos[2].id,
      );
      await t.drag(find.byType(ListView).first, const Offset(0, 800));
      await settle(t);
      await capture(t, '03_plant');
      await tap(t, find.byKey(const Key('batch_confirm_groups')));
      failPlantTwo = true;
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(saveCalls, hasLength(6));
      expect(screenCalls, [1, 2, 3]);
      expect(find.text('Retry unfinished plants'), findsOneWidget);
      await capture(t, '04_retry');
      await t.pumpWidget(const SizedBox());
      await settle(t);
      await t.pumpWidget(app());
      await settle(t);
      failPlantTwo = false;
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(saveCalls, hasLength(6));
      expect(screenCalls, [1, 2, 3, 2]);
      expect(find.text('Continue to sample'), findsOneWidget);
      await capture(t, '05_complete');
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(finishCalls, 1);
      expect(await t.runAsync(() => store.load('a', 'b')), isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'restart checks stored screening instead of trusting a finished marker',
    (t) async {
      phone(t);
      final draft = (await t.runAsync(() async {
        final d = await store.create(
          assessmentId: 'a',
          blockId: 'b',
          plantNumbers: [1, 2, 3],
          paths: paths.take(3).toList(),
        );
        d.confirmed = true;
        d.locked = true;
        for (var i = 0; i < 3; i++) {
          saved[d.photos[i].id] = '${i + 1}:overview';
          d.saved.add(d.photos[i].id);
          d.screened.add(i + 1);
        }
        screened.addAll([1, 3]); // Plant 2's saved output is missing.
        await store.save(d);
        return d;
      }))!;
      await t.pumpWidget(app());
      await settle(t);
      expect((await t.runAsync(() => store.load('a', 'b')))!.screened, {1, 3});
      expect(find.text('Retry unfinished plants'), findsOneWidget);
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(screenCalls, [2]);
      expect(saveCalls, isEmpty);
      expect((await t.runAsync(() => store.load('a', 'b')))!.complete, true);
      expect(draft.photos, hasLength(3));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'a successful callback without durable output remains unfinished',
    (t) async {
      phone(t);
      await t.runAsync(() async {
        final d = await store.create(
          assessmentId: 'a',
          blockId: 'b',
          plantNumbers: [1, 2, 3],
          paths: paths.take(3).toList(),
        );
        d.confirmed = true;
        await store.save(d);
      });
      final base = app();
      final boundary = base as RepaintBoundary;
      final material = boundary.child! as MaterialApp;
      final original = material.home! as DaBatchImportScreen;
      await t.pumpWidget(
        MaterialApp(
          home: DaBatchImportScreen(
            store: store,
            assessmentId: 'a',
            blockId: 'b',
            blockNumber: 1,
            plantNumbers: const [1, 2, 3],
            primaryViewType: 'overview',
            supportViewTypes: const ['close', 'detail'],
            onSavePhoto: original.onSavePhoto,
            onValidatePhoto: original.onValidatePhoto,
            onScreenPlant: (plant, ids) async {
              screenCalls.add(plant);
            },
            onValidateScreening: (plant, ids) async => false,
            onFinish: original.onFinish,
          ),
        ),
      );
      await settle(t);
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(screenCalls, [1, 2, 3]);
      expect((await t.runAsync(() => store.load('a', 'b')))!.screened, isEmpty);
      expect(find.text('Retry unfinished plants'), findsOneWidget);
      expect(finishCalls, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'all 20 plants and 60 photos screen as 20 plants; small screen at 200 percent',
    (t) async {
      phone(t, width: 320);
      await t.runAsync(() async {
        final d = await store.create(
          assessmentId: 'a',
          blockId: 'b',
          plantNumbers: List.generate(20, (i) => i + 1),
          paths: paths,
        );
        final originals = List.of(d.photos);
        d.photos.clear();
        d.starts.clear();
        for (var i = 0; i < 60; i++) {
          final p = originals[i % originals.length];
          d.photos.add(
            DaBatchPhoto(id: 'test-$i', path: p.path, checksum: '$i'),
          );
          if (i == 0) d.starts.add('test-$i');
        }
        await store.save(d);
      });
      final plants = List.generate(20, (i) => i + 1);
      await t.pumpWidget(app(scale: 2, plants: plants));
      await settle(t);
      await capture(t, '06_large_text');
      expect(t.takeException(), isNull);
      await tap(t, find.byKey(const Key('batch_group_by_3')));
      await capture(t, '07_large_arrangement');
      expect(t.takeException(), isNull);
      await tap(t, find.byKey(const Key('batch_confirm_groups')));
      await tap(t, find.byKey(const Key('batch_primary')));
      expect(saveCalls, hasLength(60));
      expect(screenCalls, plants);
      final restored = (await t.runAsync(() => store.load('a', 'b')))!;
      expect(restored.complete, true);
      expect(restored.screened, hasLength(20));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
}
