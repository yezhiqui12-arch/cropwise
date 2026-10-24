# Reproducing this application

The current supported toolchain is Flutter 3.44.1 (stable), Dart 3.12.1.
`.flutter-version` records the SDK version; CI explicitly uses the same version.
Use that installed SDK (or configure your SDK manager to read this file).

## Source checkpoint

Track application code, platform projects, required assets, pubspec.lock, tests,
Supabase functions/migrations, and documentation. Local screenshots, review ZIPs,
logs, dependency folders, build output and work/ scratch files are not release input.
An ignored file is not automatically unused; do not remove runtime dependencies
based on Git status alone. Existing tracked artifact images are retained.

## Local setup

1. Install Flutter 3.44.1 and platform prerequisites.
2. Run flutter pub get using the committed lockfile.
3. For cloud-enabled builds provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY
   using local Dart defines. config/dev.json is private and must remain ignored.
   Never put provider secrets or service-role keys in mobile build configuration.
4. Follow docs/SUPABASE_SETUP.md. Apply committed Supabase migrations in filename
   order, configure server secrets, and deploy matching Edge Functions before
   releasing a client that depends on them. Do not reset a populated database.
5. Run the quality checks in .github/workflows/quality.yml before distribution.

## Distribution prerequisites

Android release signing uses the configured private production keystore. Missing or
invalid release credentials fail validation; debug builds remain available. See
docs/PRODUCTION_SIGNING.md for credential setup and first-distribution guidance.
Before deploying this client, apply the backup manifest migration described in
docs/BACKUP_MANIFESTS.md. Local Drift remains at schema version 8.

No remote repository is configured at the time of this checkpoint. Add the intended
remote and push the checkpoint to obtain an off-device source backup. A local Git
commit alone is not an off-device backup.
