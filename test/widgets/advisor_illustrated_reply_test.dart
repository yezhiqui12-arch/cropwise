import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/screens/advisor/guideline_visual_gallery.dart';
import 'package:wormwise/widgets/advisor/advisor_illustrated_reply.dart';
import 'package:wormwise/widgets/advisor/advisor_reply_content.dart';

// Loads only the two real reference files used here, without packaging models.
class _ReferenceAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

void main() {
  testWidgets('reference figures stay between their explanations and can zoom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const article = 'identify-corn-growth-stage';
    var opened = '';
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _ReferenceAssets(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AdvisorIllustratedReply(
                  text:
                      '### VE — Emergence\n\nLook for the emerging seedling.\n\n'
                      '[[guide:$article:1]]\n\n'
                      '### R6 — Maturity\n\nLook for a black layer at the kernel base.\n\n'
                      '[[guide:$article:13]]',
                  articleIds: const [article],
                  onOpenArticle: (id) => opened = id,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final prose = find.byType(AdvisorReplyContent);
    final images = find.byType(GuidelineVisualGallery);
    expect(prose, findsNWidgets(2));
    expect(images, findsNWidgets(2));
    expect(
      tester.getTopLeft(prose.at(0)).dy,
      lessThan(tester.getTopLeft(images.at(0)).dy),
    );
    expect(
      tester.getTopLeft(images.at(0)).dy,
      lessThan(tester.getTopLeft(prose.at(1)).dy),
    );
    expect(
      tester.getTopLeft(prose.at(1)).dy,
      lessThan(tester.getTopLeft(images.at(1)).dy),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Reference image unavailable'), findsNothing);
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open full illustrated guide'));
    await tester.tap(find.text('Open full illustrated guide'));
    expect(opened, article);
    expect(tester.takeException(), isNull);
  });
}
