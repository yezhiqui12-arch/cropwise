# Advisor backend protection deployment — 2026-10-11

Project: rbzjqjfzphbrhkmonoqg
Function: gemini-advisor

Applied `202610110003_advisor_request_limits.sql` through the authorized Supabase
SQL Editor. Verified 8 rolled-back database checks: RPC execution restricted to
service_role, counter-table RLS/grants, invalid users, account minute/day limits,
project minute/day limits and expired window reset. No test counters retained.

Deployed the matching local index.ts through the function Code editor. The
editor text was compared with the local file after normalizing CRLF/LF. The
function deployment timestamp changed to a few seconds ago. Existing legacy
JWT verification remained enabled; no secrets or JWT settings were changed.

Focused verification:
- 25 Node mock tests passed (fake Auth, quota RPC and Gemini).
- 17 Flutter answer-gate tests passed, including a server quota rejection that
  stops all further requests from optional conversation planning.
- Changed Dart service, translation map and test file: analyzer found no issues.
- Live deliberately invalid token: 401 UNAUTHORIZED_INVALID_JWT_FORMAT from
  Supabase gateway. This proves the gateway still rejects malformed JWTs; user
  verification inside the handler was exercised with mock Auth, not a live
  signed-in farmer token.
- No Gemini generation or full app/dashboard coverage run was performed.

Limits: 18 provider attempts/fixed minute and 180/UTC day per verified account;
120/fixed minute and 1500/UTC day shared across the project. Each fallback is a
separate reservation. Request <=128 KiB, prompt <=80,000 text characters,
conversation <=32 turns, output <=2500 tokens, candidate count 1. Text-only
requests preserve existing current app prompts and structured JSON schemas.
Existing authenticated anonymous guests remain supported. Public project keys
alone do not identify a user. Quota/Auth outages fail closed before Gemini.

App source needs rebuilding/reinstallation for `terminal` server errors to stop
client retries immediately. Backend protection already applies to old installs.
No live paid/provider success was exercised, so current Gemini availability and
full prompt/rendering behavior are not verified by this deployment check.

Recovery: prior deployed source is archived in the Codex workspace
`work/gemini-advisor-deployed-before.ts`. Supabase does not provide automatic
rollback of this UI deployment; redeploy that source manually if necessary.
Removing/reverting server protections is not part of the requested work.

Proof images in the Codex workspace outputs directory:
- advisor-quota-verification.png
- advisor-function-deployed.png
