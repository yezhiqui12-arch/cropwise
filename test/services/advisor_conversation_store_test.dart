import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/services/advisor/advisor_conversation_store.dart';
import 'package:wormwise/services/advisor/advisor_knowledge_service.dart';
import 'package:wormwise/services/computer_vision/faw_computer_vision_service.dart';

void main() {
  test('file store saves, restores, and clears Guide history', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wormwise-guide-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileAdvisorConversationStore(
      directoryProvider: () async => directory,
    );
    const messages = [
      AdvisorStoredMessage(id: '1', role: 'farmer', text: 'Question'),
      AdvisorStoredMessage(
        id: '2',
        role: 'guide',
        text: 'Answer',
        imagePath: 'guide-photo.jpg',
        modelFindings: 'Larval damage: 87%',
        detectionBoxes: [
          ModelDetectionBox(
            sourcePath: 'guide-photo.jpg',
            classId: 2,
            label: 'Larva',
            confidence: 0.87,
            left: 0.1,
            top: 0.2,
            right: 0.6,
            bottom: 0.8,
            imageWidth: 1200,
            imageHeight: 900,
          ),
        ],
        answer: AdvisorAnswer(
          topicId: 'test',
          title: 'Saved answer',
          summary: 'Answer',
          details: ['Detail'],
          suggestedActions: ['Explain the detected damage'],
          source: AdvisorKnowledgeSource(
            label: 'Source',
            reference: 'Reference',
            version: 'v1',
          ),
        ),
      ),
    ];

    await store.save(messages);
    final restored = await store.load();

    expect(restored, hasLength(2));
    expect(restored.last.answer!.title, 'Saved answer');
    expect(restored.last.answer!.source.version, 'v1');
    expect(restored.last.imagePath, 'guide-photo.jpg');
    expect(restored.last.detectionBoxes, hasLength(1));
    expect(restored.last.detectionBoxes.single.label, 'Larva');
    expect(restored.last.detectionBoxes.single.left, 0.1);
    expect(restored.last.modelFindings, 'Larval damage: 87%');
    expect(restored.last.answer!.suggestedActions, [
      'Explain the detected damage',
    ]);

    await store.clear();
    expect(await store.load(), isEmpty);
  });
}
