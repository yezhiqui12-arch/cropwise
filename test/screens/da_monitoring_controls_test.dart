import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/models/da_monitoring.dart';
import 'package:wormwise/screens/scan/da_monitoring_controls.dart';
import 'package:wormwise/screens/assess/da_monitoring_export.dart';
import '../models/da_monitoring_test.dart' show daTestModel;

void main() {
  final preview = Platform.environment['WORMWISE_DA_UI_PREVIEW'];
  const key = Key('da_ui_preview');
  setUpAll(() async {
    await (FontLoader(
      'DaPreviewRoboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    final iconFont = Platform.environment['WORMWISE_DA_ICON_FONT'];
    if (iconFont != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              iconFont,
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  Widget app(Widget child) => RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'DaPreviewRoboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF155A2C)),
      ),
      home: child,
    ),
  );
  Future<void> capture(WidgetTester tester, String name) async {
    if (preview == null) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final pic = await boundary.toImage(pixelRatio: 2);
      final bytes = await pic.toByteData(format: ui.ImageByteFormat.png);
      await Directory(preview).create(recursive: true);
      await File(
        '$preview/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      pic.dispose();
    });
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'natural-enemies confirmation supports multiple enemies and exclusive none',
    (tester) async {
      phone(tester);
      List<String>? result;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDaNaturalEnemiesDialog(context);
                  },
                  child: const Text('Finish Plant 20'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Finish Plant 20'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('da_enemy_continue')))
            .onPressed,
        null,
      );
      await tester.tap(find.byKey(const Key('da_enemy_none')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('da_enemy_predators')));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('da_enemy_none')))
            .value,
        false,
      );
      await tester.tap(find.byKey(const Key('da_enemy_parasitoids')));
      await tester.pumpAndSettle();
      await capture(tester, 'natural-enemies');
      await tester.tap(find.byKey(const Key('da_enemy_continue')));
      await tester.pumpAndSettle();
      expect(result, unorderedEquals(['predators', 'parasitoids']));
      expect(tester.takeException(), null);
      await tester.tap(find.text('Finish Plant 20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(result, ['not_recorded']);
    },
  );
  testWidgets(
    'correction is optional, saves an override and reset restores model use',
    (tester) async {
      phone(tester);
      Map<String, bool?>? saved;
      final model = daTestModel();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: DaPlantCorrectionPanel(
                finding: DaPlantFinding.fromModel(model),
                initial: const {},
                onSave: (v) async {
                  saved = v;
                },
              ),
            ),
          ),
        ),
      );
      expect(saved, null);
      expect(
        find.byKey(const Key('da_save_correction')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.text('Correct report observations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('da_correct_damage_no')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('da_save_correction')));
      await tester.tap(find.byKey(const Key('da_save_correction')));
      await tester.pumpAndSettle();
      expect(saved, {'damage': false});
      expect(model.classificationLabel, 'FAW damage');
      await capture(tester, 'optional-correction');
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('da_save_correction')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'DA export details are prefilled and optional fields stay collapsed',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const DaExportDetails(
                      initial: {
                        'farmer': 'Sample farmer',
                        'collector': 'Sample collector',
                        'week': 3,
                        'province': 'Cagayan',
                      },
                    ),
                  ),
                  child: const Text('Export PDF'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('da_report_farmer')))
            .controller!
            .text,
        'Sample farmer',
      );
      expect(find.text('L3 - Week 3'), findsOneWidget);
      await capture(tester, 'export-details');
      await tester.tap(find.text('Field and planting details'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('da_report_province')))
            .controller!
            .text,
        'Cagayan',
      );
      await tester.ensureVisible(
        find.byKey(const Key('da_report_soil_texture')),
      );
      await tester.enterText(
        find.byKey(const Key('da_report_soil_texture')),
        'Loam',
      );
      expect(tester.takeException(), null);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('confirmation remains scrollable at 200 percent text', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'DaPreviewRoboto'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDaNaturalEnemiesDialog(context),
                child: const Text('Confirm'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('da_enemy_unknown')));
    await tester.tap(find.byKey(const Key('da_enemy_unknown')));
    await tester.pumpAndSettle();
    await capture(tester, 'natural-enemies-large-text');
    expect(tester.takeException(), null);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  });
}
