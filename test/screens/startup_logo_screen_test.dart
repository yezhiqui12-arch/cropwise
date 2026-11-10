import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/screens/startup_logo_screen.dart';

void main() {
  testWidgets('original logo finishes its animation before handing off', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: StartupLogoScreen(onFinished: () => finished = true)),
    );
    final context = tester.element(find.byType(StartupLogoScreen));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/wormwise_brand_logo.png'),
        context,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('launch_logo')), findsOneWidget);
    expect(finished, isFalse);
    await tester.pump(const Duration(milliseconds: 480));
    expect(finished, isFalse);
      for (var frame = 0; frame < 20 && !finished; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    expect(finished, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
