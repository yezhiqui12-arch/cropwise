# Mandatory answer checks and optional sources

Generated substantive replies, including FAW, record, photo and app explanations,
go through a separate semantic review request before display. It uses the same
configured model service in a separate review context. Only a bare courtesy
exchange with no other generated content avoids that additional request.
Verification adds latency and
one model request to applicable turns; it is always enabled independently of
the display preference.

The reviewer checks factual support, completion/review status, metric units and
denominators, uncertainty, and pesticide/diagnosis/food/feed boundaries.
Deterministic checks then require exact retrieved article IDs and contiguous
supporting quotes, exact claim text in the answer, and scalar values at existing
record paths. Numeric claims must agree with the recorded value. Invalid or
unsupported drafts are withheld; verifier failures surface a retryable error
instead of displaying unchecked output. Local sensitive-pattern checks add a
second guard. The reviewer must return both supported=true and safe=true, with
an empty safety-issues list. Rejected, malformed, or failed checks do not return
the original draft. Neither regex nor a model judge guarantees perfect detection.
Natural-language entailment and claim completeness still depend on the reviewer.

Only passages explicitly used and accepted by the review become supporting
sources. Source summaries use those articles, rather than every retrieval hit.
Quotes and article versions are persisted with conversation answers. Older
conversations without evidence retain no invented supporting sources.

More > Preferences > Artificial Intelligence > Show supporting sources is off
by default. When enabled, an expandable section shows exact supporting excerpts
and opens their Guidelines articles. It does not affect validation. The preference
is included in the existing private account preference snapshot. Sources can be
shown for stored verified answers after changing the preference.

The 11 October 2026 correction enforces these checks even while supporting
sources are hidden. It applies to newly generated replies; existing chat history
is preserved and is not retroactively certified by this change.

Focused verification for this correction: 20 Flutter checks passed using mock
transport responses, including source display on/off, valid supporting passages,
rejected/negative-safety verdicts, malformed and timed-out checks, saved-record
mismatches, photo follow-ups and retry without a duplicate question. Static
analysis of the changed validation code and these tests completed without issues.
The deterministic grounding evaluation also passed 17 retrieval questions and
18 validation checks. No live AI requests or full app coverage suite were run.

AI reference context contains whole articles within 12,000 characters. Articles
with unverified dependencies, overdue review, or expert-validation requirements
are excluded from AI grounding; offline Guidelines retain them with review status.
The focused evaluation is `dart tool/evaluate_advisor_grounding.dart`; results
are recorded in `ADVISOR_GROUNDING_EVALUATION.md`. No live model or expert-reviewed
benchmark has been run, so those results measure deterministic retrieval and
evidence integrity, not production answer accuracy.
