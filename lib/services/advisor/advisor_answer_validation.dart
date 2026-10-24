import 'dart:convert';
import 'advisor_knowledge_service.dart';
import 'advisor_rag_service.dart';

class AdvisorValidationResult {
  const AdvisorValidationResult(this.accepted, this.passages);
  final bool accepted;
  final List<AdvisorSupportingPassage> passages;
}

/// Deterministic evidence checks supplement the separate semantic review.
abstract final class AdvisorAnswerValidation {
  static const prohibitedDecisions = {
    'pesticide_prescription',
    'definitive_model_diagnosis',
    'food_feed_clearance',
  };
  static bool hasProhibitedDecision(Map<String, dynamic> review) =>
      review['safety_issues'] is List &&
      (review['safety_issues'] as List).any(prohibitedDecisions.contains);
  static String normalizeEvidence(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
  static bool hasUnsafeInstruction(String answer) {
    final patterns = [
      RegExp(
        r'\b(apply|spray|mix|use|mag-spray|isprey|ihalo|ilagay)\b.{0,65}\b\d+(?:\.\d+)?\s*(ml|millilit|liters?|litres?|grams?|kg|g/|mL/)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(grain|corn|mais|feed)\b.{0,45}\b(safe to (eat|feed)|ligtas kainin|ligtas ipakain)\b',
        caseSensitive: false,
      ),
    ];
    // Keep decimal doses together and evaluate separate instruction clauses.
    // A warning in one clause must not conceal a prescription in the next.
    for (final sentence in answer.split(
      RegExp(
        r'[\n;!?]|\.(?!\d)|\b(?:but|however|then|pero|ngunit)\b',
        caseSensitive: false,
      ),
    )) {
      if (RegExp(
        r"\b(do not|don't|never|cannot|can't|not confirmed|huwag|hindi)\b",
        caseSensitive: false,
      ).hasMatch(sentence)) {
        continue;
      }
      if (patterns.any((p) => p.hasMatch(sentence))) return true;
    }
    return false;
  }

  static AdvisorValidationResult check({
    required String answer,
    required Map<String, dynamic> review,
    required AdvisorRagContext rag,
    Map<String, dynamic>? records,
  }) {
    const failed = AdvisorValidationResult(false, []);
    if (![
      'supported',
      'safe',
      'needs_reference',
      'has_record_facts',
    ].every((key) => review[key] is bool)) {
      return failed;
    }
    if (answer.trim().isEmpty ||
        review['supported'] != true ||
        review['safe'] != true ||
        review['safety_issues'] is! List ||
        (review['safety_issues'] as List).isNotEmpty ||
        hasProhibitedDecision(review) ||
        hasUnsafeInstruction(answer)) {
      return failed;
    }
    if (review['passages'] is! List || review['record_claims'] is! List) {
      return failed;
    }
    if (review['needs_reference'] == true &&
        (review['passages'] as List).isEmpty) {
      return failed;
    }
    if (review['has_record_facts'] == true &&
        (review['record_claims'] as List).isEmpty) {
      return failed;
    }
    final passages = <AdvisorSupportingPassage>[];
    for (final raw in review['passages'] as List) {
      if (raw is! Map ||
          raw['article_id'] is! String ||
          raw['quote'] is! String ||
          raw['claim'] is! String) {
        return failed;
      }
      final matches = rag.results.where((r) => r.chunk.id == raw['article_id']);
      if (matches.isEmpty) return failed;
      final chunk = matches.first.chunk;
      final quote = (raw['quote'] as String).trim();
      final claim = (raw['claim'] as String).trim();
      final content = [
        chunk.summary,
        chunk.body,
        ...chunk.steps,
        ...chunk.lookFor,
        ...chunk.doNotAssume,
        ...chunk.safetyWarnings,
        ...chunk.escalateWhen,
        if (chunk.warning != null) chunk.warning!,
      ].join('\n');
      if (quote.length < 12 ||
          !normalizeEvidence(content).contains(normalizeEvidence(quote)) ||
          claim.isEmpty ||
          !normalizeEvidence(answer).contains(normalizeEvidence(claim))) {
        return failed;
      }
      passages.add(
        AdvisorSupportingPassage(
          articleId: chunk.id,
          title: chunk.title,
          quote: quote,
          claim: claim,
          version: chunk.contentVersion,
        ),
      );
    }
    for (final raw in review['record_claims'] as List) {
      if (records == null ||
          raw is! Map ||
          raw['path'] is! String ||
          raw['value_json'] is! String ||
          raw['claim'] is! String ||
          (raw['path'] as String).trim().isEmpty ||
          (raw['claim'] as String).trim().isEmpty ||
          !normalizeEvidence(
            answer,
          ).contains(normalizeEvidence(raw['claim'] as String))) {
        return failed;
      }
      Object? value = records;
      for (final key in (raw['path'] as String).split('.')) {
        if (value is Map && value.containsKey(key)) {
          value = value[key];
        } else if (value is List &&
            int.tryParse(key) != null &&
            int.parse(key) >= 0 &&
            int.parse(key) < value.length) {
          value = value[int.parse(key)];
        } else {
          return failed;
        }
      }
      Object? claimed;
      try {
        claimed = jsonDecode(raw['value_json'] as String);
      } on FormatException {
        return failed;
      }
      if (jsonEncode(value) != jsonEncode(claimed) && value != claimed) {
        return failed;
      }
      if (value is num) {
        final numbers = RegExp(r'\d+(?:\.\d+)?')
            .allMatches(raw['claim'] as String)
            .map((m) => num.parse(m.group(0)!))
            .toList();
        if (numbers.isNotEmpty && !numbers.contains(value)) return failed;
      }
    }
    return AdvisorValidationResult(true, passages);
  }
}
