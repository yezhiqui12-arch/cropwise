# WormWise Supabase setup

## Implemented foundation

- Local Drift remains the source used by the current app screens.
- When configured and online, startup silently restores or creates a Supabase anonymous user.
- When configuration or networking is unavailable, startup continues in local-only mode.
- The cloud schema separates owners, immutable submitted assessments, private evidence, and expert-review cases.
- Row Level Security is enabled on every exposed table. The Flutter app uses only the publishable key.

## Create and configure a project

1. Create a Supabase project.
2. Enable **Anonymous Sign-Ins** under Authentication settings.
   Under Authentication > Sign In / Providers > Email,
   disable **Confirm Email** so email/password signup can finish immediately.
   This accepts the address without proving that the user owns its inbox.
   Under Authentication > URL Configuration, set the Site URL and add a
   Redirect URL of `com.wormwise.app://login-callback/`. The Android and iOS
   apps register this URL scheme for Google sign-in and other email actions.
   Do not leave Site URL at the default `http://localhost:3000`:
   other authentication links without an explicit redirect would open localhost.
   Custom SMTP is not required for signup while Confirm Email is disabled.
   Password recovery and email changes still depend on working email delivery.
3. Configure CAPTCHA/Turnstile and appropriate anonymous-auth rate limits before public release.
4. Apply `supabase/migrations/202609140001_initial_wormwise_cloud.sql`.
5. Apply `supabase/migrations/202609150001_expert_case_submission.sql`.
6. Apply `supabase/migrations/202609150002_fix_rls_recursion.sql`.
7. Confirm that the migration created the private `assessment-evidence` bucket with its file restrictions.
8. Run the app with public configuration only:

```text
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Never use `service_role` or secret keys in Flutter. Without both defines, WormWise intentionally remains local-only.

## Identity behavior

### Google sign-in

Google sign-in requires a Google Cloud OAuth **Web application** client and
the Supabase Google provider. In Google Auth Platform, configure the consent
screen and create a client with the authorized redirect URI
`https://rbzjqjfzphbrhkmonoqg.supabase.co/auth/v1/callback`. Put the client
ID and secret in Supabase Authentication > Sign In / Providers > Google, then
enable the provider. Keep the client secret out of the Flutter app and source
files. The mobile app redirects back through
`com.wormwise.app://login-callback/`, which is already in the Supabase redirect
allow list and registered by Android and iOS.

Google sign-in opens the chosen account directly. A newly created account
starts with its own empty local view; guest records stay in a separate local
view on this device. Signing back in restores that account's own view and
cloud backup, when available.

From the guest My Profile screen, **Save guest profile to an account** is an
explicit transfer path. Creating an email account or connecting Google from
that path copies the guest's local fields, assessments, and related records
into the account view while retaining the guest view on this device. Ordinary
account creation and sign-in do not copy guest records.

An anonymous user is a real Supabase Auth user and receives a persisted session. It is not the same as the public `anon` database role. The app exposes `WormWiseIdentityService` through Provider with these states:

- `localOnly`
- `connecting`
- `anonymous`
- `registered`
- `unavailable`

Anonymous identity failure does not block local fields or assessments. Account-linking UI remains separate follow-up work.

Anonymous sign-in is started after the first app frame instead of delaying the local guest experience while the network responds.

## Background cloud synchronization

After an identity is available, WormWise automatically uploads local fields,
field boundaries, and assessment metadata/results in dependency order. Drift
remains the offline source of truth and synchronization retries after later
local changes or authentication recovery.

For registered accounts, apply
`supabase/migrations/202609210001_account_snapshots.sql` in the SQL Editor.
This creates a private `wormwise-account-backups` bucket with owner-only
policies. Without it, cross-device restore will not work. Account backup
includes local records and evidence photos, but does not share them with an
expert. Expert submission uses its separate consent-based flow. The backup
currently restores missing records; edits made on two phones to the same
record are not merged automatically. Keep the original phone's data until
you have verified the records on the second phone.

## Security notes

- User-supplied profile rows cannot assign themselves `expert` or `admin`.
- Expert/admin status must be assigned through a trusted server/admin process.
- Submitted assessment rows cannot be edited or deleted by the farmer.
- Experts can read an assessment only when an expert case exists for it.
- Evidence files use private Storage and owner-prefixed paths.
- The migration revokes table access from unauthenticated `anon` requests.
- Review the generated policies in a staging Supabase project before production.
## Expert submission access diagnostics (2026-10-01)

Read-only inspection confirmed Julen and test 2 belong to the intended account.
The failing ID instead identified an unrelated local field owned by another
account. Device-wide relational synchronization could fail on that row before
reaching the assessment selected for submission.

Send to Expert now uses serialized, assessment-scoped synchronization: only the
selected completed assessment, its field, boundaries, and stations are published.
It does not wait for unrelated device recovery/media backups or change the cloud
current-field selection. Account changes still abort the upload, and server RLS
and submitted-record immutability remain enforced. Device-wide background backup
continues separately and can still report errors for unrelated records.

Submission now checks the cloud assessment's visibility, owner, completion date
and result snapshot before uploading evidence. Local synced flags or successful
account backup are not proof of relational assessment availability. Only an
explicitly returned owner mismatch is described as a different owning account.

Server policy rejections report the failing step: initial cloud synchronization,
existing-case lookup, assessment lookup, photo upload, photo retry lookup,
evidence metadata or case submission. Generic 42501/RLS failures no longer tell
the user to sign in with another account. Account changes during uploads and
submission are checked. Server policies remain intact. These diagnostics were
statically checked; the affected device session and deployed server policies
were not available for inspection, so its actual rejection remains unconfirmed.

An on-device error subsequently confirmed a 42501 rejection on the assessments
table during relational sync, before submission. Sync now reads the cloud
assessment status before upserting and skips submitted rows even when the local
submission receipt is absent (for example after an interrupted successful RPC).
Submitted station snapshots are also preserved. Before other assessment writes,
the parent cloud field must be visible and owned by the current account. A write
rejection includes the assessment/field IDs and existing/requested status for
diagnosis. This fixes the known submitted-row retry path without weakening RLS;
the screenshot alone does not establish that this was the affected row's status.
