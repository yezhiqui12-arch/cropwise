import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/widgets/advisor/advisor_reply_reveal.dart';
import 'package:wormwise/widgets/advisor/advisor_illustrated_reply.dart';
import 'package:wormwise/screens/advisor/guideline_visual_gallery.dart';

void main() {
  testWidgets('types all reply parts before fading in follow-up bubbles', (
    tester,
  ) async {
    var completed = 0;
    var animate = true;
    late StateSetter rebuild;
    const texts = ['This reply types progressively.', 'The final next step.'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AdvisorReplyReveal(
                texts: texts,
                animate: animate,
                onComplete: () {
                  completed++;
                  setState(() => animate = false);
                },
                builder: (context, visible, complete) => Column(
                  children: [
                    for (final text in visible) Text(text),
                    if (complete)
                      const AdvisorCompletionFade(
                        child: Text(
                          'What should I check next?',
                          key: Key('suggestion'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('suggestion')), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(texts.first), findsNothing);
    expect(find.text(texts.last), findsNothing);
    expect(find.byKey(const Key('suggestion')), findsNothing);
    expect(completed, 0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester
        .pump(); // Apply message completion from the post-frame callback.
    expect(completed, 1);
    expect(find.text(texts.first), findsOneWidget);
    expect(find.text(texts.last), findsOneWidget);
    final opacity = find.ancestor(
      of: find.byKey(const Key('suggestion')),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 140));
    final midway = tester.widget<Opacity>(opacity).opacity;
    expect(midway, greaterThan(0));
    expect(midway, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(find.text(texts.last), findsOneWidget);
  });

  testWidgets('reduced motion shows the complete reply and completes once', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AdvisorReplyReveal(
            texts: const ['Full reply'],
            animate: true,
            onComplete: () => completed++,
            builder: (_, visible, complete) => Column(
              children: [
                Text(visible.single),
                if (complete)
                  const AdvisorCompletionFade(child: Text('Follow up')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Full reply'), findsOneWidget);
    expect(find.text('Follow up'), findsOneWidget);
    expect(completed, 1);
    await tester.pumpAndSettle();
    expect(completed, 1);
  });

  testWidgets(
    'future guide images and full-guide buttons stay hidden during typing',
    (tester) async {
      const id = 'identify-corn-growth-stage';
      const text =
          '### VE\n\nLook for an emerging seedling.\n\n[[guide:$id:1]]\n\n'
          '### R6\n\nCheck the kernel base.\n\n[[guide:$id:13]]';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdvisorReplyReveal(
                texts: const [text],
                animate: true,
                builder: (_, visible, complete) => AdvisorIllustratedReply(
                  text: visible.single,
                  articleIds: const [id],
                  showTrailingContent: complete,
                  onOpenArticle: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(GuidelineVisualGallery), findsNothing);
      expect(find.text('Open full illustrated guide'), findsNothing);
      await tester.pump(
        Duration(milliseconds: (text.indexOf(']]') + 2) * 5 + 30),
      );
      expect(find.byType(GuidelineVisualGallery), findsOneWidget);
      expect(find.text('Open full illustrated guide'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(GuidelineVisualGallery), findsNWidgets(2));
      expect(find.text('Open full illustrated guide'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
