import 'dart:convert';
import 'advisor_open_chat_service.dart';

/// Deterministic discovery, before the AI plans any optional detailed reads.
/// A selected/current record cannot stand in for the user's saved history.
Future<Map<String, dynamic>> loadAdvisorRecordCatalog(
  AdvisorDataTools tools, {
  int maxCharacters = 120000,
}) async {
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  var offset = 0;
  Map<String, dynamic>? first;
  var complete = false;
  while (true) {
    final page = await tools.read('get_assessment_catalog', {
      'offset': offset,
      'limit': 25,
    });
    if (page['assessments'] is! List || page['total_assessments'] is! int) {
      throw StateError('Assessment catalogue could not be retrieved.');
    }
    first ??= page;
    for (final value in (page['assessments'] as List).whereType<Map>()) {
      final row = Map<String, dynamic>.from(value);
      final id = row['id'];
      if (id is! String || !seen.add(id)) continue;
      if (jsonEncode([...rows, row]).length > maxCharacters) {
        return _catalog(first, rows, complete: false, reason: 'context_budget');
      }
      rows.add(row);
    }
    final next = page['next_offset'];
    if (next == null) {
      complete = rows.length == first['total_assessments'];
      break;
    }
    if (next is! int ||
        next <= offset ||
        (page['assessments'] as List).isEmpty) {
      return _catalog(
        first,
        rows,
        complete: false,
        reason: 'incomplete_pagination',
      );
    }
    offset = next;
  }
  return _catalog(
    first,
    rows,
    complete: complete,
    reason: complete ? null : 'catalog_changed_or_incomplete',
  );
}

Map<String, dynamic> _catalog(
  Map<String, dynamic> first,
  List<Map<String, dynamic>> rows, {
  required bool complete,
  String? reason,
}) => {
  'scope': first['scope'],
  'total_assessments': first['total_assessments'],
  'total_fields': first['total_fields'],
  'status_counts': first['status_counts'],
  'fields': first['fields'],
  'assessments': rows,
  'retrieved_assessments': rows.length,
  'coverage_complete': complete,
  'next_offset': complete ? null : rows.length,
  'omitted_assessments': ((first['total_assessments'] as int) - rows.length)
      .clamp(0, first['total_assessments'] as int),
  'limitation': reason,
  'meaning': first['meaning'],
};
