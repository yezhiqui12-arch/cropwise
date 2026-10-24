# Advisor architecture, local guidance, Gemini, and image analysis

The Advisor combines deterministic local guidance, an offline searchable
knowledge layer, saved-record context, on-device image analysis, and optional
Gemini open chat. Advisor output is read-only and does not modify assessment
observations or expert findings.

## Local authoritative routes

Safety-sensitive treatment questions, supported scouting guidance, saved-field
questions, assessment explanations, evidence interpretation, uncertainty, and
expert escalation use local rules and curated content before any online model
request. Missing records remain unknown rather than becoming zero.

## Retrieval layer

`AdvisorRagService` provides deterministic on-device retrieval for both the
Guide UI and online grounding. Curated passages have stable IDs, categories,
evidence grades, source identifiers, jurisdiction, version, and mandatory
warnings. Retrieval does not require a vector database or upload local records.

When open chat is appropriate, the service adds a bounded set of retrieved
passages and permitted saved-record context. Retrieved text cannot override
system safety rules or authorize unsupported treatment claims.

## Gemini proxy

Open chat calls the authenticated `gemini-advisor` Supabase Edge Function. The
function owns model selection, provider authentication, request limits, and
server-side credential access. No Gemini provider credential is entered,
stored, or transmitted by the mobile application.

Requests require a valid WormWise cloud identity. The function validates the
caller and applies request limits before contacting Gemini. Failed requests can
be retried without duplicating the user's message, and clearing a conversation
invalidates late responses.

## Sharing controls

Only the context enabled by the current sharing settings is added to an online
request. Field and assessment records, approximate location, and selected photo
analysis have separate gates. Raw local file paths are never included. Photo
context is derived from explicit attachment or saved structured model findings.

## On-device image analysis

The bundled TFLite pipeline can analyze selected evidence on the phone. Results
are stored and displayed as model suggestions with provenance. They do not
write evaluator observations, establish a diagnosis, or assign expert scores.

## Local history

Advisor messages are saved in the application documents directory with a
bounded history window. Clear removes local conversation history and cancels
pending responses. Provider credentials are absent from the mobile data model
and chat payloads.
