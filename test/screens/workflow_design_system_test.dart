import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/screens/station1/field_workflow_components.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/theme/app_theme.dart';

void main() {
  testWidgets('workflow shell remains usable at 360 px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: FieldWorkflowShell(
              bottomBar: StickyWorkflowActionBar(
                message:
                    'A long translated status message remains readable and does not hide the available next action.',
                actionLabel: 'Save and return to station review',
                secondaryLabel: 'Cancel and keep reviewing',
                onSecondary: () {},
                onPressed: () {},
              ),
              children: const [
                WorkflowContextHeader(
                  stageLabel: 'V3–V12',
                  blockNumber: 12,
                  stationNumber: 5,
                  title: 'Confirm the selected plant observation',
                  subtitle:
                      'This deliberately long translated copy checks wrapping in direct-sun field layouts without truncating important context.',
                  completedCount: 7,
                  totalCount: 10,
                  attentionCount: 3,
                ),
                WorkflowFormSection(
                  title: 'Evidence and field confirmation',
                  subtitle: 'Missing photo · action required before completion',
                  icon: Icons.photo_library_outlined,
                  children: [
                    Text(
                      'The required photo file is missing. Retake it or record why the camera cannot be used.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline ready'), findsOneWidget);
    expect(find.text('Save and return to station review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('sunlight-critical palette pairs meet WCAG AA contrast', () {
    expect(
      _contrast(AppColors.textPrimary, AppColors.background),
      greaterThan(4.5),
    );
    expect(_contrast(AppColors.onPrimary, AppColors.primary), greaterThan(4.5));
    expect(
      _contrast(AppColors.highContrastGreen, AppColors.primaryLight),
      greaterThan(4.5),
    );
    expect(
      _contrast(AppColors.severeSeverityRing, AppColors.severeSeverityBg),
      greaterThan(4.5),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
