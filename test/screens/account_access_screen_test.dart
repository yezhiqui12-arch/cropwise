import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';
import 'package:wormwise/data/local/app_database.dart';
import 'package:wormwise/screens/signed_out_screen.dart';
import 'package:wormwise/screens/animated_app_entry_screen.dart';
import 'package:wormwise/screens/account_access_screen.dart';
import 'package:wormwise/services/cloud/wormwise_identity_service.dart';
import 'package:wormwise/services/cloud/wormwise_cloud_sync_service.dart';

void main() {
  testWidgets('explicit guest save selects the transfer flow for Google', (
    tester,
  ) async {
    final identity = _RecordingIdentityService();
    final database = AppDatabase(NativeDatabase.memory());
    final sync = _RecordingCloudSyncService(database);
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WormWiseIdentityService>.value(
              value: identity,
            ),
            ChangeNotifierProvider<WormWiseCloudSyncService>.value(value: sync),
          ],
          child: const MaterialApp(
            home: AccountAccessScreen(transferGuestProfile: true),
          ),
        ),
      );
      expect(find.text('Save your guest profile'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('google_account_button')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('google_account_button')));
      await tester.pump();
      expect(sync.transferStarted, isTrue);
      expect(identity.linkGuestArguments, [true]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });

  testWidgets('creating an account with Google leaves guest data separate', (
    tester,
  ) async {
    final identity = _RecordingIdentityService();
    await tester.pumpWidget(
      ChangeNotifierProvider<WormWiseIdentityService>.value(
        value: identity,
        child: const MaterialApp(home: AccountAccessScreen()),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('google_account_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('google_account_button')));
    await tester.pump();

    expect(identity.linkGuestArguments, [false]);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('registered state does not show a confirmation modal', (
    tester,
  ) async {
    final identity = _RecordingIdentityService();
    await tester.pumpWidget(
      ChangeNotifierProvider<WormWiseIdentityService>.value(
        value: identity,
        child: const MaterialApp(home: AccountAccessScreen()),
      ),
    );

    identity.completeGoogleSignIn();
    await tester.pump();
    expect(find.text('Good to go!'), findsNothing);
    expect(
      find.byKey(const Key('registered_account_continue_button')),
      findsNothing,
    );
  });

  testWidgets('signed-out users can sign in, register, or continue as guest', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<WormWiseIdentityService>(
        create: (_) => WormWiseIdentityService.localOnly(),
        child: const MaterialApp(home: SignedOutScreen()),
      ),
    );

    expect(find.byKey(const Key('sign_in_button')), findsOneWidget);
    expect(find.byKey(const Key('continue_as_guest_button')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3300));
    await tester.pump(const Duration(milliseconds: 3300));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.byKey(const Key('account_name_field')), findsOneWidget);
    expect(
      find.byKey(const Key('account_confirm_password_field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('create_account_button')), findsOneWidget);
    expect(
      find.textContaining('reuses the existing local database'),
      findsNothing,
    );
  });

  testWidgets('launch animation reveals branding then opens guest account UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<WormWiseIdentityService>(
        create: (_) => WormWiseIdentityService.localOnly(),
        child: const MaterialApp(home: AnimatedAppEntryScreen()),
      ),
    );

    expect(find.byKey(const Key('login_brand_logo')), findsOneWidget);
    expect(find.byKey(const Key('login_brand_wordmark')), findsOneWidget);
    expect(find.byKey(const Key('login_field_art')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3300));

    expect(find.byKey(const Key('login_brand_logo')), findsOneWidget);
    expect(find.byKey(const Key('login_brand_wordmark')), findsOneWidget);
    expect(find.byKey(const Key('login_field_art')), findsOneWidget);
    expect(find.byKey(const Key('continue_as_guest_button')), findsOneWidget);
  });
}

class _RecordingIdentityService extends WormWiseIdentityService {
  _RecordingIdentityService() : super.localOnly();

  final List<bool> linkGuestArguments = [];
  bool _registered = false;

  @override
  WormWiseIdentityState get state => _registered
      ? WormWiseIdentityState.registered
      : WormWiseIdentityState.localOnly;

  void completeGoogleSignIn() {
    _registered = true;
    notifyListeners();
  }

  @override
  Future<void> continueWithGoogle({required bool linkGuest}) async {
    linkGuestArguments.add(linkGuest);
  }
}

class _RecordingCloudSyncService extends WormWiseCloudSyncService {
  _RecordingCloudSyncService(AppDatabase database) : super(database, null);

  bool transferStarted = false;

  @override
  Future<void> beginGuestTransfer() async {
    transferStarted = true;
  }
}
