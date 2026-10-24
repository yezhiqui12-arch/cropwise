# Contextual actions and suggested follow-ups

The code-owned action catalog supplies the model action enum and navigation
descriptions. Coverage includes Home, Assess, Map, More, profile, fields, field
details, boundaries, assessment setup/history/results/resume, Guidelines,
photo attachment, field conditions on Home, expert messages, account access,
field trends, models, Artificial Intelligence preferences, language, and notifications. Help/About are reached via
More. Actions navigate only after a tap; no destructive operation is exposed.

Action payloads can retain field, assessment, and guideline IDs in chat history.
Generated targets must come from retrieved app records or guideline passages.
Assessment buttons re-read the selected record and validate completion/resume
status when tapped. Missing or stale records lead to assessment history.
Dedicated field details and trends can open another field without changing the
active field. Map/boundary/setup remain active-field workflows; generated
cross-field targets for them are suppressed rather than silently changing scope.

Suggestions use an explicit purpose: clarification, assessment follow-up,
uncertainty, or requested next steps. The default is none. There is no answer
length gate or minimum number of photo suggestions. Up to two unique questions
are shown on the latest reply only, hidden after a new message or while sending.
Earlier suggestions and the current question are excluded. Field-choice text
must contain a real field name from the current catalog. The existing bubble
appearance is preserved; follow-up bubbles send text and action buttons navigate.

Focused checks: run `dart tool/check_advisor_qol.dart`. These checks do not load
Flutter assets or call an AI API. Live model selection and rendered navigation
still require manual app verification. Suggestion purpose is model-proposed and
validated structurally; this is not a guarantee of semantic answer correctness.

## Shared conversation interpretation

Before text-answer retrieval, a structured intent pass reads the privacy-filtered
conversation and current message. It produces a self-contained question, intent,
reference query, registered navigation destination and data requirements. The
same interpretation is passed to guideline retrieval, app-data planning, final
answer generation and action selection. History resolves references but never
proves saved facts. Explicit topic changes and corrections take precedence.
Unresolved ambiguity asks for clarification. General menu navigation skips agricultural
retrieval and general menus skip private record reads. Record targets are still
verified against retrieved records before navigation. The current active field
is only the default when the user has not specified another field.

This adds one bounded AI interpretation request per ordinary text reply, but
avoids irrelevant record-planning rounds for menus and general education. If
interpretation fails, the original message and privacy-filtered history remain
available to reply generation. Record-retrieval failures are reported as missing
access, never as proof that the user's records are empty. No blocking answer
validation was restored. Whole-word action matching supports plural screen names
and selects a concrete destination ahead of its parent More menu.

The local QoL checks exercise interpretation contracts and downstream policies;
they do not prove that a live model always resolves intent correctly. Verify the
conversation sequence Models -> give me the route, scouting -> route, switching
to a new topic, field clarification, photo follow-ups and station comparisons
in the rebuilt app.
## Assessment PDF export awareness (2026-10-01)

General Advisor and assessment-specific Ask WormWise share code-owned reporting
capabilities through GeminiAdvisorOpenChatService's system instructions. These
product facts do not depend on agricultural RAG retrieval or field-data sharing.
They take precedence over earlier chat claims that PDF export was unavailable.

The implemented route is Assess > completed assessment > Results > Export >
Save or Share Assessment PDF > choose map/photos/coordinates > Create PDF >
device share sheet. The report can be shared with a crop expert while awaiting
Expert Review; sharing does not submit or update an in-app expert case. Local
report creation is offline; available photos must exist locally and sending
depends on the chosen sharing app. Model screening remains distinct from expert
confirmation and severity review.

The Export menu now offers PDF only. Copy Field Summary and Copy CSV Data
were removed at the user's request; Advisor capability descriptions match.

The existing view_results action now describes the export options. Explicit PDF
navigation can resolve to Results; it does not automatically create or send a
report. General questions about whether sharing would help need no action card.
Assessment chat allows questions about these workflows as well as recorded facts.

Verification: changed Dart files passed static analysis and two focused fake-
transport/navigation checks passed. No paid AI calls or full test suite were run.
