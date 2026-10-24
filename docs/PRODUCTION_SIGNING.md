# Production Android signing

WormWise has not yet been distributed. Release builds now use an explicit release
signing configuration; debug/profile builds keep their normal development setup.
Release tasks fail if credentials are absent or the keystore/alias/password cannot
be opened. They no longer fall back to the debug key.

## Local configuration

Copy android/key.properties.example to android/key.properties on a new build
machine, or set WORMWISE_SIGNING_PROPERTIES to an absolute properties-file path.
The file must provide storeFile, storePassword, keyAlias and keyPassword. Use an
absolute keystore path. Both the properties file and keystore must stay out of Git.
The current machine has an owner-restricted keystore and recovery properties copy
in C:/src/wormwise-private/signing/. The local ignored android/key.properties points
there. Passwords are not included in documentation, test logs or chat outputs.

Generated key: RSA 4096, PKCS12, alias wormwise-upload, validity 10,000 days.
Public certificate SHA-256:
70:CA:E3:5A:37:32:C3:F7:2E:16:26:B1:C8:03:1C:85:04:BC:69:36:D2:B3:53:8C:B3:4E:91:B7:03:CD:A4:AC

## Verification

From android/, run:

gradlew.bat :app:verifyWormWiseReleaseSigning

This opens the keystore and checks that the selected alias has an accessible
private key. Verification was successful locally. The same task fails when the
properties file is absent. No signed APK/AAB was built or distributed in this change.

## First distribution

Choose the distribution channel before giving production installs to users. For
Google Play App Signing, this key can be the upload key; the Play-managed app signing
certificate can differ from locally signed APKs. Keep that distinction explicit when
planning updates or distributing APKs outside Play. The application ID remains
com.wormwise.app.wormwise.

Keep an encrypted off-device copy of the keystore and its credentials. The existing
external folder and Git source bundle are on the same computer; the source bundle
intentionally excludes private signing material. No off-device signing backup was
created automatically.

Existing development installations signed with the debug key cannot be updated in place with this new release key. Before replacing such an installation, verify recovery/export of any field records. No installation was removed or replaced during this work.
