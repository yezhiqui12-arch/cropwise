import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/cloud/case_message_service.dart';
import 'package:wormwise/services/cloud/expert_review_service.dart';
import 'package:wormwise/services/cloud/wormwise_identity_service.dart';
import 'package:wormwise/services/evidence_storage_service.dart';
import 'package:wormwise/theme/app_colors.dart';
import 'package:wormwise/widgets/expert_case_message_media.dart';
import 'package:wormwise/widgets/expert_review_presentation.dart';

class _Media extends CaseMessageService {
  _Media(this.draft, Directory root)
    : super(
        WormWiseIdentityService.localOnly(),
        files: EvidenceStorageService(rootDirectory: () async => root),
      );
  CaseMessageDraft draft;
  int sent = 0, plans = 0;
  @override
  Future<CaseMessageDraft> loadDraft(String owner, String caseId) async =>
      draft;
  @override
  Future<void> saveDraft(
    String owner,
    String caseId,
    CaseMessageDraft value,
  ) async {
    draft = value;
  }

  @override
  Future<({bool da, Map<String, int> blocks})> photoPlan(
    String assessmentId,
  ) async {
    plans++;
    throw StateError('The automatic target should not need this query');
  }

  @override
  Future<void> send({
    required String owner,
    required String caseId,
    required CaseMessageDraft draft,
    required void Function(String) progress,
  }) async {
    sent++;
  }
}

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
  final request = ExpertMessage(
    id: 'request',
    senderId: 'expert',
    body:
        'Please send a clear view of the whole plant and the whorl. Keep the camera steady and photograph the same sampled plant in good light.',
    createdAt: DateTime(2026, 10, 11, 9),
    kind: 'evidence_request',
    requestedBlockId: 'block2',
    requestedBlockSequence: 2,
    requestedStation: 8,
    requestedPlant: 1,
    evidenceStatus: 'awaiting_photos',
    requestedViews: const ['whole_plant', 'whorl'],
  );
  ExpertReviewCase makeCase(String name, {List<ExpertMessage>? messages}) =>
      ExpertReviewCase(
        id: name,
        assessmentId: 'assessment',
        fieldName: name,
        location: 'Piat, Cagayan',
        status: 'needs_information',
        createdAt: DateTime(2026, 10, 6),
        messages: messages ?? [request],
        severitySummary: null,
        expertId: 'expert',
        expertName: 'Agriculture specialist',
      );
  late Directory root;
  late _Media media;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('wormwise-conversation-');
    await File('${root.path}/photo.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    media = _Media(CaseMessageDraft(), root);
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> mount(WidgetTester tester, Widget child, double scale) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(key: const Key('capture'), child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (output == null) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(const Key('capture')))
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'inbox and request conversation remain readable at scale $scale',
      (tester) async {
        final item = makeCase('North corn field');
        await mount(
          tester,
          Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Expert review')),
            body: ExpertReviewInbox(
              cases: [
                item,
                makeCase('South corn field', messages: []),
              ],
              userId: 'farmer',
              onOpen: (_) {},
            ),
          ),
          scale,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'review-inbox-${scale == 1 ? 'phone' : 'large-text'}',
        );
        if (scale == 1) {
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('expert_case_North corn field')),
                )
                .height,
            lessThan(100),
          );
        }
        expect(find.byType(ChoiceChip), findsNothing);
        await tester.tap(find.byKey(const ValueKey('expert_case_filter')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<int>, 'Photos needed'),
        );
        await tester.pumpAndSettle();
        expect(find.text('South corn field'), findsNothing);
        await mount(
          tester,
          Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text(
                'Case conversation',
                style: TextStyle(fontSize: 18),
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      ExpertCaseHeader(
                        item: item,
                        onContact: () {},
                        onResults: () {},
                      ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: ExpertConversationMessage(
                          message: request,
                          mine: false,
                          media: media,
                          canReply: true,
                          onReply: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                ExpertCaseMessageComposer(
                  reviewCase: item,
                  owner: 'farmer',
                  service: media,
                  refresh: () async {},
                ),
              ],
            ),
          ),
          scale,
        );
        expect(find.text('Photos for Block 2 · Plant 8'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'review-conversation-${scale == 1 ? 'phone' : 'large-text'}',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'targeted photo edits skip sampling queries; delivered reply is not reported as failed',
    (tester) async {
      media.draft = CaseMessageDraft(
        requestId: 'request',
        targetBlockId: 'block2',
        targetPlant: 8,
        targetBlockSequence: 2,
        photos: [
          CaseMessagePhoto(
            id: 'photo',
            localUri: 'photo.png',
            thumbnailUri: 'photo.png',
            station: 8,
            plant: 1,
            blockRunId: 'block2',
          ),
        ],
      );
      await mount(
        tester,
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              ExpertCaseMessageComposer(
                reviewCase: makeCase('North corn field'),
                owner: 'farmer',
                service: media,
                refresh: () async => throw StateError('Refresh failed'),
              ),
            ],
          ),
        ),
        1,
      );
      await tester.tap(find.text('Add details'));
      await tester.pumpAndSettle();
      expect(media.plans, 0);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Caption (optional)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Send reply',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      expect(media.sent, 1);
      expect(
        find.text('Reply sent. Refresh the conversation to see it.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your draft is kept'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
