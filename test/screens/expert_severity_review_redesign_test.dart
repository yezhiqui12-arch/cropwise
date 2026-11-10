import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/screens/expert_severity_review_screen.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/theme/app_colors.dart';

void main() {
  final output = Platform.environment['CROPWISE_RESULTS_PREVIEW'];
  setUpAll(() async {
    if (output == null) return;
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              'C:/src/flutter/bin/cache/artifacts/material_fonts/${font.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  final ratings = [
    for (var i = 0; i < 8; i++)
      ExpertPlantRating(
        stationNumber: i % 4 + 1,
        plantNumber: 1,
        blockRunId: i < 4 ? 'block1' : 'block2',
        blockSequence: i < 4 ? 1 : 2,
        protocolVersion: 'wormwise-da-scattered-20-v1',
        outcome: i < 6 ? 'scored' : 'insufficient_evidence',
        davisScore: i < 6 ? [9, 8, 7, 3, 2, 0][i] : null,
        damageFreshness: i < 2
            ? 'fresh'
            : i < 4
            ? 'old_only'
            : i == 4
            ? 'uncertain'
            : null,
        note: i == 0
            ? 'The leaf injury is extensive. Keep this plant record for comparison with a new assessment.'
            : '',
        photos: i == 0
            ? const [
                ExpertPlantPhoto(id: 'photo1', url: null),
                ExpertPlantPhoto(id: 'photo2', url: null),
              ]
            : const [],
      ),
  ];
  final review = ExpertReviewCase(
    id: 'case1',
    assessmentId: 'assessment1',
    fieldName: 'North corn field',
    location: '',
    status: 'reviewed',
    createdAt: DateTime(2026, 10, 6),
    messages: const [],
    severitySummary: ExpertSeveritySummary(
      reviewedPlants: 8,
      scoredPlants: 6,
      insufficientPlants: 2,
      medianDavisScore: 5,
      finalizedAt: DateTime(2026, 10, 11, 9, 30),
      monitoring: const {
        'monitoring_version': 2,
        'reviewer_name': 'Agriculture specialist',
        'assessed_at': '2026-10-06T11:26:00Z',
        'damage_percentage': {
          'value': 83.333,
          'numerator': 5,
          'denominator': 6,
        },
        'current_infestation_indicator': {
          'value': 40,
          'numerator': 2,
          'denominator': 5,
        },
      },
    ),
  );
  Future<void> capture(WidgetTester tester, String name) async {
    if (output == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('review_capture')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> showGrid(WidgetTester tester) async {
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final target = find.byKey(const ValueKey('expert_plant_block1:1:1'));
    for (var i = 0; i < 30; i++) {
      if (target.evaluate().isNotEmpty) {
        final top = tester.getTopLeft(target).dy;
        position.jumpTo(
          (position.pixels + top - 140).clamp(0, position.maxScrollExtent),
        );
        await tester.pumpAndSettle();
        return;
      }
      position.jumpTo(
        (position.pixels + 180).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    fail('Plant grid did not appear');
  }

  Future<void> mount(
    WidgetTester tester,
    List<ExpertPlantRating> data,
    double scale,
  ) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: output == null ? null : 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('review_capture'),
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Expert review')),
            body: ExpertSeverityReviewContent(
              reviewCase: review,
              ratings: data,
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'expert review shows photos and corresponding reviews without dropdowns at $scale text',
      (tester) async {
        await mount(tester, ratings, scale);
        expect(find.text('4.83 / 9'), findsOneWidget);
        expect(find.text('83.3%'), findsOneWidget);
        expect(find.text('40.0%'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await showGrid(tester);
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text(ratings.first.note), findsOneWidget);
        expect(find.byIcon(Icons.hide_image_outlined), findsNWidgets(2));
        expect(find.text('Davis 9 / 9'), findsOneWidget);
        final first = find.byKey(const ValueKey('expert_plant_block1:1:1'));
        final second = find.byKey(const ValueKey('expert_plant_block1:2:1'));
        if (scale == 1) {
          expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
          expect(
            tester.getTopLeft(second).dx,
            greaterThan(tester.getTopLeft(first).dx),
          );
        } else {
          expect(
            tester.getTopLeft(second).dy,
            greaterThan(tester.getTopLeft(first).dy),
          );
        }
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'expert-review-grid-${scale == 1 ? 'phone' : 'large-text'}',
        );
      },
    );
  }
  testWidgets('incomplete ratings cannot show a field mean', (tester) async {
    await mount(tester, ratings.take(2).toList(), 1);
    expect(find.text('4.83 / 9'), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.text(
        'Some ratings are missing. Distribution shows loaded plants only.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
