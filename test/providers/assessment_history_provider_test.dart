import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/data/repositories/assessment_history_repository.dart';
import 'package:wormwise/providers/assessment_history_provider.dart';

import '../support/assessment_history_fixture.dart';

void main() {
  test(
    'pagination fetches one look-ahead row and reports has-more exactly',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (var index = 0; index < 31; index++) {
        await historyFixture(
          database,
          name: 'Pagination field $index',
          daysAgo: index,
        );
      }

      final provider = AssessmentHistoryProvider(
        AssessmentHistoryRepository(database),
      );
      addTearDown(provider.dispose);
      await _waitUntil(provider, () => !provider.loading);

      expect(provider.entries, hasLength(30));
      expect(provider.canLoadMore, isTrue);

      provider.loadMore();
      await _waitUntil(
        provider,
        () => !provider.loading && provider.entries.length == 31,
      );
      expect(provider.entries, hasLength(31));
      expect(provider.canLoadMore, isFalse);
    },
  );
}

Future<void> _waitUntil(
  AssessmentHistoryProvider provider,
  bool Function() condition,
) async {
  if (condition()) return;
  final completer = Completer<void>();
  void listener() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  provider.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    provider.removeListener(listener);
  }
}
