import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum WormWiseIdentityState {
  localOnly,
  connecting,
  anonymous,
  registered,
  unavailable,
}

/// Maintains an optional Supabase identity behind the guest experience.
///
/// Failure never blocks local field or assessment work. An anonymous Supabase
/// user is created only when the backend is configured and reachable.
class WormWiseIdentityService extends ChangeNotifier {
  static const emailConfirmationRedirect = 'com.wormwise.app://login-callback/';
  WormWiseIdentityService(this._client, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  WormWiseIdentityService.localOnly({FlutterSecureStorage? secureStorage})
    : _client = null,
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _guestAccessKey = 'wormwise_guest_access_granted';
  static const _guestDisplayNameKey = 'wormwise_guest_display_name';
  static const _pendingSignInMethodKey = 'wormwise_pending_sign_in_method';
  static const _pendingUpgradeUserKey = 'wormwise_pending_upgrade_user';
  static const _pendingUpgradePasswordKey = 'wormwise_pending_upgrade_password';
  static const _pendingGuestHandoffKey = 'wormwise_pending_guest_handoff';
  static const _pendingGuestTransferKey = 'wormwise_pending_guest_transfer';
  static const _replaceLocalDataOnSignInKey =
      'wormwise_replace_local_data_on_account_sign_in';

  final SupabaseClient? _client;
  final FlutterSecureStorage _secureStorage;
  StreamSubscription<AuthState>? _authSubscription;
  WormWiseIdentityState _state = WormWiseIdentityState.localOnly;
  bool _guestAccessGranted = false;
  bool _finishingGuestUpgrade = false;
  Future<bool>? _finishingGuestHandoff;
  String? _lastError;
  String? _guestDisplayName;
  String? _lastSignInMethod;
  String? _methodUserId;
  String? _activeUserId;
  String? _pendingDisplayName;
  String? _profilePhone;
  String? _phoneOwner;
  int _phoneRevision = 0;
  bool _syncingPendingName = false;

  WormWiseIdentityState get state => _state;
  bool get hasAppAccess =>
      _guestAccessGranted || _state == WormWiseIdentityState.registered;
  String? get lastError => _lastError;
  User? get user => _client?.auth.currentUser;
  String? get userId => user?.id;
  SupabaseClient? get client => _client;
  bool get hasCloudIdentity => user != null;
  bool get isAnonymous => user?.isAnonymous ?? false;
  bool get canSubmitForExpertReview => hasCloudIdentity;
  String? get email => user?.email;
  String? get phone =>
      _phoneOwner == (userId ?? 'guest') ? _profilePhone : null;

  /// Contact information is separate from Auth's SMS sign-in phone.
  Future<void> loadProfilePhone() async {
    final owner = userId ?? 'guest';
    final revision = ++_phoneRevision;
    String? value;
    try {
      value = await _secureStorage.read(key: 'wormwise_profile_phone_$owner');
      final client = _client;
      if (client != null && userId != null) {
        final profile = await client
            .from('profiles')
            .select('phone')
            .eq('user_id', owner)
            .maybeSingle();
        value = profile?['phone'] as String?;
      }
    } catch (_) {
      // Keep the account-scoped cached contact when offline.
    }
    if (revision != _phoneRevision || (userId ?? 'guest') != owner) return;
    _phoneOwner = owner;
    _profilePhone = value;
    notifyListeners();
  }

  Future<void> updateProfilePhone(String value) async {
    final phone = value.trim();
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isNotEmpty &&
        (phone.length > 40 ||
            !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) ||
            digits.length < 7 ||
            digits.length > 15)) {
      throw ArgumentError('Enter a valid phone number.');
    }
    final owner = userId ?? 'guest';
    _phoneRevision++;
    if (userId != null) {
      await _requireClient().rpc(
        'set_own_profile_phone',
        params: {'p_phone': phone},
      );
    }
    if ((userId ?? 'guest') != owner) return;
    _phoneRevision++;
    try {
      await _secureStorage.write(
        key: 'wormwise_profile_phone_$owner',
        value: phone,
      );
    } catch (_) {
      if (owner == 'guest') rethrow;
    }
    if ((userId ?? 'guest') != owner) return;
    _phoneOwner = owner;
    _profilePhone = phone.isEmpty ? null : phone;
    notifyListeners();
  }

  bool get usesGoogleSignIn => signInMethod == 'google';
  bool get usesEmailSignIn => signInMethod == 'email';
  String get signInMethod {
    if (_lastSignInMethod != null) return _lastSignInMethod!;
    final identities = user?.identities;
    if (identities != null && identities.isNotEmpty) {
      final ordered = [
        ...identities,
      ]..sort((a, b) => (b.lastSignInAt ?? '').compareTo(a.lastSignInAt ?? ''));
      if (ordered.first.provider == 'google') return 'google';
      if (ordered.first.provider == 'email') return 'email';
    }
    final provider = user?.appMetadata['provider'];
    return provider == 'google' || provider == 'email'
        ? provider as String
        : 'unknown';
  }

  String? get displayName {
    if (_state != WormWiseIdentityState.registered) return _guestDisplayName;
    if (_pendingDisplayName != null) return _pendingDisplayName;
    final metadata = user?.userMetadata;
    for (final key in ['display_name', 'full_name', 'name']) {
      final value = metadata?[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// Returns whether the registered name reached the account immediately.
  Future<bool> updateDisplayName(String value) async {
    final name = value.trim();
    if (name.isEmpty) throw ArgumentError('Enter a display name.');
    if (_state != WormWiseIdentityState.registered) {
      _guestDisplayName = name;
      notifyListeners();
      try {
        await _secureStorage.write(key: _guestDisplayNameKey, value: name);
      } catch (_) {
        // Keep the edit for this session if secure storage is unavailable.
      }
      return true;
    }
    final client = _requireClient();
    final ownerId = user!.id;
    try {
      await client.auth.updateUser(
        UserAttributes(data: {'display_name': name}),
      );
      _pendingDisplayName = null;
      notifyListeners();
      try {
        await _secureStorage.delete(key: 'wormwise_pending_name_$ownerId');
      } catch (_) {}
      return true;
    } catch (_) {
      _pendingDisplayName = name;
      notifyListeners();
      try {
        await _secureStorage.write(
          key: 'wormwise_pending_name_$ownerId',
          value: name,
        );
      } catch (_) {}
      return false;
    }
  }

  Future<void> updateEmail(String value) async {
    if (_state != WormWiseIdentityState.registered || !usesEmailSignIn) {
      throw StateError('Email changes are unavailable for this account.');
    }
    await _requireClient().auth.updateUser(
      UserAttributes(email: value.trim()),
      emailRedirectTo: emailConfirmationRedirect,
    );
    notifyListeners();
  }

  Future<void> updatePassword(String value) async {
    if (_state != WormWiseIdentityState.registered || !usesEmailSignIn) {
      throw StateError('Password changes are unavailable for this account.');
    }
    await _requireClient().auth.updateUser(UserAttributes(password: value));
  }

  /// Opens Google sign-in. Guest data is copied only for the explicit save flow.
  Future<void> continueWithGoogle({required bool linkGuest}) async {
    final client = _requireClient();
    try {
      await _markUnrelatedLocalDataForReplacement(keepGuestTransfer: linkGuest);
      await _secureStorage.write(key: _pendingSignInMethodKey, value: 'google');
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: emailConfirmationRedirect,
      );
      if (!launched) {
        await _secureStorage.delete(key: _pendingSignInMethodKey);
        throw const AuthException('Google sign-in could not be opened.');
      }
      _lastError = null;
    } on AuthException catch (error) {
      try {
        await _secureStorage.delete(key: _pendingSignInMethodKey);
      } catch (_) {}
      _lastError = error.message;
      rethrow;
    } catch (error) {
      try {
        await _secureStorage.delete(key: _pendingSignInMethodKey);
      } catch (_) {}
      _lastError = error.toString();
      rethrow;
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
    bool transferGuest = false,
  }) async {
    final client = _requireClient();
    _setState(WormWiseIdentityState.connecting);
    try {
      await _markUnrelatedLocalDataForReplacement(
        keepGuestTransfer: transferGuest,
      );
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final signedInUser = response.user;
      if (signedInUser == null) {
        throw const AuthException('The account could not be opened.');
      }
      _lastError = null;
      await _rememberSignInMethod(signedInUser.id, 'email');
      _applyUser(signedInUser);
      await finishPendingGuestHandoff();
    } on AuthException catch (error) {
      _lastError = error.message;
      _applyUser(client.auth.currentUser);
      rethrow;
    } catch (error) {
      _lastError = error.toString();
      _applyUser(client.auth.currentUser);
      rethrow;
    }
  }

  /// Creates a separate account. Guest records remain in the guest local view.
  /// Supabase's Confirm Email setting must be disabled for this flow.
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    bool transferGuest = false,
  }) async {
    final client = _requireClient();
    final cleanName = displayName.trim();
    final cleanEmail = email.trim();
    _setState(WormWiseIdentityState.connecting);
    try {
      await _markUnrelatedLocalDataForReplacement(
        keepGuestTransfer: transferGuest,
      );
      if (client.auth.currentUser?.isAnonymous ?? false) {
        await client.auth.signOut();
      }
      final response = await client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'display_name': cleanName},
      );
      final registeredUser = response.user;
      if (registeredUser == null) {
        throw const AuthException('The account could not be created.');
      }
      if (response.session == null ||
          client.auth.currentUser?.id != registeredUser.id) {
        throw const AuthException(
          'Account creation needs Confirm Email turned off in Supabase: Authentication > Sign In / Providers > Email.',
        );
      }
      await _rememberSignInMethod(registeredUser.id, 'email');
      if (client.auth.currentUser != null) {
        try {
          await client
              .from('profiles')
              .update({'display_name': cleanName})
              .eq('user_id', registeredUser.id);
        } catch (_) {
          // Auth metadata already holds the name; profile sync can retry.
        }
      }
      _lastError = null;
      _applyUser(client.auth.currentUser);
      return;
    } on AuthException catch (error) {
      _lastError = error.message;
      _applyUser(client.auth.currentUser);
      rethrow;
    } catch (error) {
      _lastError = error.toString();
      _applyUser(client.auth.currentUser);
      rethrow;
    }
  }

  /// Requests another confirmation for a registration already started above.
  /// Supabase accepts resend requests without guaranteeing inbox delivery.
  Future<void> resendRegistrationConfirmation({
    required String email,
    required bool guestUpgrade,
  }) async {
    await _requireClient().auth.resend(
      type: guestUpgrade ? OtpType.emailChange : OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailConfirmationRedirect,
    );
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AuthException(
        'Online accounts are unavailable because Supabase is not configured.',
      );
    }
    return client;
  }

  Future<void> _markUnrelatedLocalDataForReplacement({
    bool keepGuestTransfer = false,
  }) async {
    await _secureStorage.write(
      key: _replaceLocalDataOnSignInKey,
      value: 'true',
    );
    // A previous cancelled connect attempt must not be completed by an
    // ordinary sign-in.
    await _secureStorage.delete(key: _pendingGuestHandoffKey);
    if (!keepGuestTransfer) {
      await _secureStorage.delete(key: _pendingGuestTransferKey);
    }
  }

  Future<bool> finishPendingGuestHandoff() =>
      _finishingGuestHandoff ??= _finishPendingGuestHandoff().whenComplete(() {
        _finishingGuestHandoff = null;
      });

  Future<bool> _finishPendingGuestHandoff() async {
    final client = _client;
    if (client?.auth.currentUser?.isAnonymous != false) return false;
    final token = await _secureStorage.read(key: _pendingGuestHandoffKey);
    if (token == null) return false;
    final linked = await client!.rpc(
      'finish_guest_account_handoff',
      params: {'token': token},
    );
    if (linked != true) {
      throw const AuthException(
        'Guest data transfer could not be completed. The guest records have not been erased.',
      );
    }
    await _secureStorage.delete(key: _pendingGuestHandoffKey);
    return true;
  }

  /// Ends the cloud session without touching WormWise's on-device database.
  Future<void> signOut() async {
    _guestAccessGranted = false;
    await _deleteGuestAccessChoice();
    final client = _client;
    if (client == null) {
      _lastError = null;
      _setState(WormWiseIdentityState.localOnly);
      return;
    }

    try {
      await client.auth.signOut();
      _lastError = null;
      _setState(WormWiseIdentityState.localOnly);
    } on AuthException catch (error) {
      _lastError = error.message;
      rethrow;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    }
  }

  /// Starts a fresh optional cloud identity while continuing to use the same
  /// local Drift database supplied by [WormWiseDataScope].
  Future<void> continueAsGuest() async {
    final client = _client;
    // Guest access must not silently reuse a registered account's persisted
    // session. Signing out does not delete any on-device field or assessment.
    if (client?.auth.currentUser != null &&
        client!.auth.currentUser!.isAnonymous != true) {
      await client.auth.signOut();
      _applyUser(client.auth.currentUser);
    }
    _guestAccessGranted = true;
    notifyListeners();
    try {
      await _secureStorage.write(key: _guestAccessKey, value: 'true');
    } catch (_) {
      // Guest access still works for this session if device storage is
      // temporarily unavailable.
    }
    // Local access must never wait on connectivity. Identity initialization
    // continues in the background solely to restore optional cloud features.
    unawaited(initialize());
  }

  /// Restores the previous account or guest choice before the first app screen
  /// is built, preventing the account page from flashing on every launch.
  Future<void> restoreAccessState() async {
    try {
      _guestAccessGranted =
          await _secureStorage.read(key: _guestAccessKey) == 'true';
      _guestDisplayName = await _secureStorage.read(key: _guestDisplayNameKey);
    } catch (_) {
      _guestAccessGranted = false;
    }

    final existing = _client?.auth.currentUser;
    if (existing != null) {
      _applyUser(existing);
      if (!existing.isAnonymous) await _restoreSignInMethod(existing);
      if (!existing.isAnonymous) await _restorePendingDisplayName(existing);
    }
  }

  Future<void> initialize() async {
    if (_client == null) {
      _setState(WormWiseIdentityState.localOnly);
      return;
    }

    _authSubscription ??= _client.auth.onAuthStateChange.listen((event) {
      _applyUser(event.session?.user);
      if (event.session?.user != null) {
        unawaited(_restoreSignInMethod(event.session!.user));
        unawaited(_restorePendingDisplayName(event.session!.user));
        unawaited(_finishPendingGuestUpgrade(event.session!.user));
        unawaited(
          finishPendingGuestHandoff().catchError((Object error) {
            _lastError = error.toString();
            notifyListeners();
            return false;
          }),
        );
      }
    });

    final existing = _client.auth.currentUser;
    if (existing != null) {
      _applyUser(existing);
      unawaited(_finishPendingGuestUpgrade(existing));
      return;
    }

    _setState(WormWiseIdentityState.connecting);
    try {
      final response = await _client.auth.signInAnonymously();
      final created = response.user;
      if (created == null) {
        _lastError = 'Anonymous identity was not returned.';
        _setState(WormWiseIdentityState.unavailable);
        return;
      }
      _lastError = null;
      _applyUser(created);
    } on AuthException catch (error) {
      _lastError = error.message;
      _setState(WormWiseIdentityState.unavailable);
    } catch (error) {
      _lastError = error.toString();
      _setState(WormWiseIdentityState.unavailable);
    }
  }

  /// Retries identity creation when connectivity returns.
  Future<void> retry() => initialize();

  Future<void> _finishPendingGuestUpgrade(User user) async {
    if (user.isAnonymous || _client == null || _finishingGuestUpgrade) return;
    _finishingGuestUpgrade = true;
    try {
      final pendingId = await _secureStorage.read(key: _pendingUpgradeUserKey);
      if (pendingId != user.id) return;
      final pendingPassword = await _secureStorage.read(
        key: _pendingUpgradePasswordKey,
      );
      if (pendingPassword == null) return;
      await _client.auth.updateUser(UserAttributes(password: pendingPassword));
      await _clearPendingGuestUpgrade();
      _lastError = null;
    } catch (error) {
      _lastError = 'Email confirmed, but password setup failed: $error';
      notifyListeners();
    } finally {
      _finishingGuestUpgrade = false;
    }
  }

  Future<void> _clearPendingGuestUpgrade() async {
    await _secureStorage.delete(key: _pendingUpgradePasswordKey);
    await _secureStorage.delete(key: _pendingUpgradeUserKey);
  }

  Future<void> _deleteGuestAccessChoice() async {
    try {
      await _secureStorage.delete(key: _guestAccessKey);
    } catch (_) {
      // An explicit sign-out still applies to the current process.
    }
  }

  void _applyUser(User? value) {
    if (value?.id != _activeUserId) {
      _lastSignInMethod = null;
      _methodUserId = null;
      _pendingDisplayName = null;
      _activeUserId = value?.id;
    }
    if (value == null) {
      _lastSignInMethod = null;
      _methodUserId = null;
      _setState(WormWiseIdentityState.localOnly);
    } else {
      _setState(
        value.isAnonymous
            ? WormWiseIdentityState.anonymous
            : WormWiseIdentityState.registered,
      );
    }
  }

  Future<void> _rememberSignInMethod(String userId, String method) async {
    _lastSignInMethod = method;
    _methodUserId = userId;
    notifyListeners();
    try {
      await _secureStorage.write(
        key: 'wormwise_sign_in_method_$userId',
        value: method,
      );
      await _secureStorage.delete(key: _pendingSignInMethodKey);
    } catch (_) {
      // The current session still knows how the user signed in.
    }
  }

  Future<void> _restoreSignInMethod(User currentUser) async {
    if (currentUser.isAnonymous) return;
    if (_methodUserId == currentUser.id && _lastSignInMethod != null) return;
    try {
      final pending = await _secureStorage.read(key: _pendingSignInMethodKey);
      if (pending == 'google') {
        await _rememberSignInMethod(currentUser.id, 'google');
        return;
      }
      final stored = await _secureStorage.read(
        key: 'wormwise_sign_in_method_${currentUser.id}',
      );
      if (_methodUserId == currentUser.id && _lastSignInMethod != null) return;
      if (stored != null && _lastSignInMethod != stored) {
        _lastSignInMethod = stored;
        _methodUserId = currentUser.id;
        notifyListeners();
      }
    } catch (_) {
      // User identity data remains available as a fallback.
    }
  }

  Future<void> _restorePendingDisplayName(User currentUser) async {
    if (currentUser.isAnonymous || _syncingPendingName) return;
    _syncingPendingName = true;
    try {
      final pending = await _secureStorage.read(
        key: 'wormwise_pending_name_${currentUser.id}',
      );
      if (pending == null || user?.id != currentUser.id) return;
      _pendingDisplayName = pending;
      notifyListeners();
      try {
        await _requireClient().auth.updateUser(
          UserAttributes(data: {'display_name': pending}),
        );
        await _secureStorage.delete(
          key: 'wormwise_pending_name_${currentUser.id}',
        );
        _pendingDisplayName = null;
        notifyListeners();
      } catch (_) {
        // Retry the pending account edit on a later session.
      }
    } catch (_) {
    } finally {
      _syncingPendingName = false;
    }
  }

  void _setState(WormWiseIdentityState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
