import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/widgets/advisor/advisor_reply_content.dart';

const sample =
    '''Your saved assessment has **50 plant records**. Here is the summary.

## Recorded results

| Item | Recorded result |
| --- | --- |
| Field | hahaha |
| Status | Completed |
| Crop stage | V3 to V6 |
| Coverage | 1 block, 5 stations |
| Manual observations | 20 of 50 eligible plants |

## What this means

- These are saved observations from your sampled plants.
- Model damage screening was not recorded for this assessment.

## Next steps

1. Review the plant observations for uncertain findings.
2. Record fresh observations during your next scouting visit.
''';

Widget host(String text, {double scale = 1, Key? captureKey}) => MaterialApp(
  theme: ThemeData(fontFamily: 'AdvisorPreview'),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: const Color(0xFFF2F7EF),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AdvisorReplyContent(text: text),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final file = File('C:/Windows/Fonts/arial.ttf');
    if (await file.exists()) {
      final loader = FontLoader('AdvisorPreview')
        ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });
  testWidgets('formats a phone reply with headings, lists and a table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    await tester.pumpWidget(host(sample, captureKey: capture));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Recorded results', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    final path = Platform.environment['ADVISOR_PREVIEW_PATH'];
    if (path != null) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  testWidgets('wide comparison scrolls at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host('''## Comparison

| Measure | Previous | Current |
| --- | --- | --- |
| Sample coverage | 50 recorded plants | 3 recorded plants |
| Status | Completed | In progress |
''', scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsOneWidget);
    await tester.drag(horizontal, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('legacy paragraph reflow preserves all recorded text', () {
    final input = List.filled(
      10,
      'The recorded rate is 40.0 percent with 20 of 50 plants.',
    ).join(' ');
    final output = AdvisorReplyContent.prepare(input);
    expect(output, contains('\n\n'));
    expect(output.replaceAll(RegExp(r'\s+'), ' '), input);
    expect(AdvisorReplyContent.prepare(sample), sample.trim());
  });
}
