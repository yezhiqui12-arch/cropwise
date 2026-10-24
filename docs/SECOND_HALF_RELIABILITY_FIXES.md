# Second-half implementation and verification — 2026-10-24

Scope completed in source:
1. Startup loading/retry UI with account preparation before app access, cleanup of
   partial resources, and a notice for unresolved photo repairs.
2. Private prepared-capture journal, restart replay with session/actor/path/checksum
   checks, account isolation, idempotence, interrupted promotion recovery, thumbnail
   regeneration and explicit-deletion cleanup. No local schema migration.
3. Verified per-device snapshot manifests, complete fallbacks, safe retention and
   legacy recovery; serialized same-device publishers, unique snapshot names,
   account/manifest checks before cleanup, and validation of restored typed maps.
4. Focused extraction of results calculations/evidence/map widgets, photo checkpoint
   persistence, startup resources, reconciliation and snapshot management.
5. Production signing configuration and a generated owner-protected RSA-4096 PKCS12
   keystore outside the repository. Debug builds retain development signing; release
   credentials are validated and missing/invalid credentials fail closed.

Validator consolidation remains excluded. Fieldwork, assessment rules, navigation
and existing Guide behavior were not redesigned. Local Drift remains version 8;
app_database.dart and generated schema code are unchanged.

Verification:
- 75 focused tests passed in the final combined run, including results-screen
  presentation at normal and enlarged text scale.
- Two final journal tests passed after adding canonical path binding and corruption
  checks. These are additional runs of the recovery cases, not extra unique tests.
- Application library and new tests analyzed without errors. 29 existing warnings
  remain, along with informational diagnostics; the project is not warning-clean.
- Gradle verifyWormWiseReleaseSigning and validateSigningRelease succeeded offline.
  An explicit missing-credentials check failed with the intended actionable message.
- keytool created and opened the production keystore successfully; its public PEM
  certificate was exported to this chat's outputs.
- Private signing files are ignored, and a targeted scan found no generated signing
  password in changed/new source. No private keystore/password is in the outputs.
- Formatting and git diff --check passed for this increment.

Broader validation limits:
A separate Advisor UI run hit eight failing assertions (including older Guide text
expectations) and later stalled. It was stopped; Guide behavior was not changed to
satisfy that suite. Full project tests are not certified passing. Native inference
and camera behavior on a physical device remain unverified; the prior Windows DLL
limitation still applies. No signed APK/AAB was built or distributed.

Required deployment step:
Apply supabase/migrations/202610240001_backup_manifests_retention.sql to the intended
Supabase project BEFORE using this client's manifest backup path. It permits JSON
manifests and restricts deletion to owner snapshot objects. The migration is prepared
but was NOT deployed; no live account snapshot/evidence was uploaded or deleted.
See docs/BACKUP_MANIFESTS.md for retention and recovery details.

Signing material is at C:/src/wormwise-private/signing/, with a local ignored
android/key.properties pointer. Preserve an encrypted OFF-DEVICE copy before first
production distribution. The source bundle intentionally contains no signing secret.
See docs/PRODUCTION_SIGNING.md and docs/STARTUP_RECOVERY.md for operational details.
