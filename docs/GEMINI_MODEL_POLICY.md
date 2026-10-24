# Gemini model policy

The `gemini-advisor` Supabase Edge Function chooses the model and tries the
next approved model on model retirement, access errors, quota limits, or a
temporary provider failure. Existing app versions may send a model name; the
function uses it only to preserve a request for the faster Flash-Lite class.
The response includes `wormwiseModel`, so updated app versions record the model
that actually answered.

The default order is 3.6 Flash, 3.5 Flash-Lite, 3.1 Flash-Lite, then 3 Flash
Preview. The function reads the optional `GEMINI_ADVISOR_MODELS` Supabase secret
for a comma-separated ordered list of up to four approved Flash or Flash-Lite
models. For example:

`gemini-3.8-flash,gemini-3.5-flash-lite,gemini-3.6-flash`

Changing that secret updates the policy without an app update or function
redeploy. Leave at least one known working fallback. The function rejects
malformed lists and Pro/image model IDs. Before adding a new model, confirm
that it has free-tier access for this Gemini API project and that it accepts
WormWise's structured JSON requests and produces suitable agricultural advice.
The Gemini model listing API cannot establish all three conditions by itself.

This change must be deployed once to Supabase for existing installed apps to
benefit. The new app code is needed only to show the actual responding model
in answer provenance. The Gemini API key remains in the function secret.

## Authentication and request budgets (protection v1)

The function verifies the caller through Supabase Auth `/auth/v1/user`; a
project public key or service key is not accepted as a user session. Existing
Supabase-authenticated anonymous guest accounts are supported. The legacy JWT
platform check remains enabled as an additional layer; never rely on it alone.

`202610110003_advisor_request_limits.sql` adds an atomic, service-only RPC and
RLS-protected counters. Apply this migration before deploying the function.
Each provider attempt, including model fallbacks, reserves one unit:

| Scope | Per fixed minute | Per UTC calendar day |
| --- | ---: | ---: |
| Verified account (including guests) | 18 | 180 |
| Shared project | 120 | 1500 |

A chat reply may use planning, record retrieval, answer generation and mandatory
review. These are separate requests, so these are attempt budgets, not message
quotas. Failed/time-out provider calls remain counted because billing may have
occurred. The shared budget bounds account churn; guest accounts can still be
created, so this is not a complete bot-defense solution. The thresholds are
initial operational caps, not guarantees about provider free-tier availability
or monetary spending. Change limits in the migration/RPC after reviewing usage.
Counters store user UUID and counts only, never prompts. Window timestamps are
read after locking the shared row so concurrent requests cannot reset stale
windows. The RPC is inaccessible to anon/authenticated clients.

Input is limited to 128 KiB, 80,000 text characters and 32 conversation turns.
Only text contents, system instructions and supported JSON generation settings
are forwarded. Image/file uploads, tools, cached content, thinking overrides and
extra candidates are rejected. Output is capped at 2,500 tokens and one candidate;
smaller existing app limits are retained. Response schemas are bounded in size
and nesting. Model names remain server-owned; clients supply only a recognized
Flash class preference. Model availability is not established by mock checks.

Auth, malformed input, quota and provider errors return `terminal: true` with a
machine-readable code. The updated Flutter transport respects that flag, including
optional planning/record steps, so it does not start a second server fallback chain.
Existing installed apps receive the backend protection immediately but need a
rebuild for this client retry behavior. Old clients may repeat rejected requests;
those requests never reach Gemini and do not consume attempt budgets.

Verification: `node --test supabase/functions/gemini-advisor/index.test.mjs`
uses fake Auth/quota/provider transports (25 tests). `verify-limits.sql` checks
live database permissions and window limits in a rolled-back transaction (8
checks). The focused Flutter answer-gate file covers terminal quota propagation.
No successful live Gemini generation is needed for these checks.

Official references:
- https://supabase.com/docs/guides/functions/auth-legacy-jwt
- https://supabase.com/docs/guides/auth/auth-anonymous
- https://ai.google.dev/gemini-api/docs/generate-content/thinking
