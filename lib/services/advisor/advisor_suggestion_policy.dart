/// Suggestions are optional continuations, not a quota attached to each answer.
abstract final class AdvisorSuggestionPolicy {
  static String _userMessage(String raw) {
    var text = raw.trim();
    final invitation = RegExp(
      r'^(?:would you like (?:me )?to|do you want (?:me )?to|would you want to)\s+',
      caseSensitive: false,
    );
    if (invitation.hasMatch(text)) {
      text = text.replaceFirst(invitation, '').replaceFirst(RegExp(r'\?$'), '');
      text = text.replaceAll(RegExp(r'\byour\b', caseSensitive: false), 'my');
      if (text.isNotEmpty) {
        text = '${text[0].toUpperCase()}${text.substring(1)}';
      }
    }
    return text;
  }

  static List<String> validate({
    required String reason,
    required Iterable<String> proposed,
    required String question,
    Iterable<String> previous = const [],
    Iterable<String>? fieldChoices,
  }) {
    if (RegExp(
      r'^(hi|hello|hey|thanks|thank you|salamat|kumusta)[!. ]*$',
      caseSensitive: false,
    ).hasMatch(question.trim())) {
      return const [];
    }
    if (!const [
      'clarification',
      'assessment_follow_up',
      'uncertainty',
      'next_steps',
    ].contains(reason)) {
      return const [];
    }
    final seen = previous.map((s) => s.trim().toLowerCase()).toSet();
    seen.add(question.trim().toLowerCase());
    final result = <String>[];
    for (final raw in proposed) {
      final text = _userMessage(raw);
      if (fieldChoices != null &&
          !fieldChoices.any(
            (name) => text.toLowerCase().contains(name.toLowerCase()),
          )) {
        continue;
      }
      if (text.isEmpty || text.length > 80 || !seen.add(text.toLowerCase())) {
        continue;
      }
      result.add(text);
      if (result.length == 2) break;
    }
    return result;
  }
}
