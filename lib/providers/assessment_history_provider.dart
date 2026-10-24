import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/assessment_history_models.dart';
import '../data/repositories/assessment_history_repository.dart';

class AssessmentHistoryProvider extends ChangeNotifier {
  AssessmentHistoryProvider(this.repository, {this.fieldId}) {
    reload();
  }
  final AssessmentHistoryRepository repository;
  String? fieldId, status;
  int limit = 30;
  bool loading = true;
  bool _hasMore = false;
  Object? error;
  List<AssessmentHistoryEntry> entries = const [];
  StreamSubscription<List<AssessmentHistoryEntry>>? _subscription;
  int _generation = 0;
  bool _disposed = false;
  bool get canLoadMore => _hasMore;
  void filter({required String? field, required String? state}) {
    fieldId = field;
    status = state;
    limit = 30;
    reload();
  }

  void loadMore() {
    if (canLoadMore) {
      limit += 30;
      reload();
    }
  }

  void reload() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    loading = true;
    error = null;
    notifyListeners();
    _subscription = repository
        .watchPage(fieldId: fieldId, status: status, limit: limit + 1)
        .listen(
          (value) {
            if (_disposed || generation != _generation) return;
            _hasMore = value.length > limit;
            entries = List.unmodifiable(value.take(limit));
            loading = false;
            error = null;
            notifyListeners();
          },
          onError: (Object value) {
            if (_disposed || generation != _generation) return;
            error = value;
            loading = false;
            _hasMore = false;
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
