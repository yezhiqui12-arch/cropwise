import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/widgets/accessible_choice_field.dart';

void main() {
  testWidgets('choice field and bounded image preview support large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: AccessibleChoiceField<String>(
                  key: const Key('large_text_choice'),
                  label: 'How will this maize be used? (optional)',
                  sheetTitle: 'Select intended use',
                  value: 'grain',
                  onChanged: (_) {},
                  showImages: true,
                  options: const [
                    AccessibleChoiceOption(
                      value: 'grain',
                      label: 'Grain or dry corn',
                      description:
                          'Harvested when kernels have reached maturity.',
                      visualGroup: 'young_stage',
                      imageCaption: 'Young maize example',
                      assetPath:
                          'assets/images/growth_stages/maize_young_vegetative.jpg',
                    ),
                    AccessibleChoiceOption(
                      value: 'green',
                      label: 'Green corn',
                      description: 'Harvested earlier for fresh eating.',
                      visualGroup: 'young_stage',
                      imageCaption: 'Young maize example',
                      assetPath:
                          'assets/images/growth_stages/maize_young_vegetative.jpg',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('large_text_choice')));
    await tester.pumpAndSettle();

    final image = find.byKey(const ValueKey('choice_image_young_stage'));
    expect(image, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(image);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final dialogSize = tester.getSize(
      find.byKey(const ValueKey('choice_image_preview_panel')),
    );
    expect(dialogSize.height, lessThan(844));
    expect(dialogSize.width, lessThan(390));
    expect(tester.takeException(), isNull);
  });
}
