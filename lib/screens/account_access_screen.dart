import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud/wormwise_identity_service.dart';
import '../services/cloud/wormwise_cloud_sync_service.dart';
import '../theme/app_colors.dart';
import 'main_navigation_screen.dart';
import '../widgets/account_recovery_view.dart';

enum _AccountMode { signIn, register }

class AccountAccessScreen extends StatefulWidget {
  const AccountAccessScreen({
    super.key,
    this.allowContinueAsGuest = false,
    this.replaceWithHomeOnSuccess = false,
    this.brandedLanding = false,
    this.transferGuestProfile = false,
  });

  final bool allowContinueAsGuest;
  final bool replaceWithHomeOnSuccess;
  // Nullable for hot-reload compatibility with AccountAccessScreen instances
  // created before the branded landing property existed.
  final bool? brandedLanding;
  final bool transferGuestProfile;

  @override
  State<AccountAccessScreen> createState() => _AccountAccessScreenState();
}

class _AccountAccessScreenState extends State<AccountAccessScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _accountScrollController = ScrollController();
  _AccountMode _mode = _AccountMode.signIn;
  bool _busy = false;
  bool _googleAuthPending = false;
  bool _googleCompletionScheduled = false;
  bool _obscurePassword = true;
  bool _guestTransferCompleted = false;
  bool _registrationPendingCompletion = false;
  bool get _registering => _mode == _AccountMode.register;
  bool get _transferRequested =>
      widget.transferGuestProfile && !_guestTransferCompleted;
  String? _error;
  String? _notice;
  late final AnimationController _entryController;
  late final Animation<double> _centerLogoReveal;
  late final Animation<double> _topBrandReveal;
  late final Animation<double> _fieldReveal;
  late final Animation<double> _accountReveal;

  @override
  void initState() {
    super.initState();
    if (!widget.allowContinueAsGuest) _mode = _AccountMode.register;
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    );
    _centerLogoReveal = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 13),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 13,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 56),
    ]).animate(_entryController);
    _topBrandReveal = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(.43, .60, curve: Curves.easeOutCubic),
    );
    _fieldReveal = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(.48, .67, curve: Curves.easeOutCubic),
    );
    _accountReveal = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(.67, .88, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.brandedLanding != true) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entryController.value = 1;
      } else {
        _entryController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _accountScrollController.dispose();
    super.dispose();
  }

  void _setMode(_AccountMode mode) {
    if (_busy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _accountScrollController.hasClients) {
        _accountScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final identity = context.read<WormWiseIdentityService>();
    final cloudSync = context.read<WormWiseCloudSyncService>();
    final transferGuest = _transferRequested;
    try {
      if (transferGuest) await cloudSync.beginGuestTransfer();
      if (!_registering) {
        await identity.signIn(
          email: _emailController.text,
          password: _passwordController.text,
          transferGuest: transferGuest,
        );
        await cloudSync.prepareAccountView(identity.userId!);
        _guestTransferCompleted = transferGuest;
        if (!mounted) return;
        _openHome();
      } else {
        await identity.register(
          displayName: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          transferGuest: transferGuest,
        );
        _registrationPendingCompletion = true;
        await cloudSync.prepareAccountView(identity.userId!);
        _guestTransferCompleted = transferGuest;
        if (transferGuest) {
          if (mounted) _openHome();
          return;
        }
        await identity.signOut();
        _registrationPendingCompletion = false;
        if (!mounted) return;
        _passwordController.clear();
        _confirmController.clear();
        setState(() {
          _mode = _AccountMode.signIn;
          _notice = transferGuest
              ? 'Guest profile added on this phone. Verify your account backup.'
              : 'Account created. Sign in to continue.';
        });
      }
    } on AuthException catch (error) {
      if (identity.state != WormWiseIdentityState.registered) {
        await cloudSync.cancelGuestTransfer();
      }
      if (mounted) setState(() => _error = _authErrorMessage(error));
    } catch (_) {
      if (identity.state != WormWiseIdentityState.registered) {
        await cloudSync.cancelGuestTransfer();
      }
      if (mounted) {
        setState(
          () => _error = identity.state == WormWiseIdentityState.registered
              ? 'Account connected, but its data could not be prepared. Retry to finish.'
              : 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryAccountPreparation() async {
    final identity = context.read<WormWiseIdentityService>();
    final cloudSync = context.read<WormWiseCloudSyncService>();
    if (identity.userId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await cloudSync.prepareAccountView(identity.userId!);
      final transferred = _transferRequested;
      _guestTransferCompleted = transferred;
      if (_registrationPendingCompletion) {
        if (transferred) {
          _registrationPendingCompletion = false;
          if (mounted) _openHome();
          return;
        }
        await identity.signOut();
        _registrationPendingCompletion = false;
        if (!mounted) return;
        _passwordController.clear();
        _confirmController.clear();
        setState(() {
          _mode = _AccountMode.signIn;
          _notice = transferred
              ? 'Guest profile added on this phone. Verify your account backup.'
              : 'Account created. Sign in to continue.';
        });
      } else if (mounted) {
        _openHome();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not prepare account data. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(AuthException error) {
    if (error.code == 'email_address_not_authorized' ||
        error.message.toLowerCase().contains('email address not authorized')) {
      return 'This address cannot receive mail from the current email sender. Ask the app administrator to configure email delivery.';
    }
    return error.message;
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cloudSync = context.read<WormWiseCloudSyncService>();
      await context.read<WormWiseIdentityService>().continueAsGuest();
      await cloudSync.prepareGuestView();
      if (!mounted) return;
      _finishAuthentication();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not switch to guest. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _googleAuthPending = true;
    });
    final cloudSync = context.read<WormWiseCloudSyncService>();
    final identity = context.read<WormWiseIdentityService>();
    final transferGuest = _transferRequested;
    try {
      if (transferGuest) await cloudSync.beginGuestTransfer();
      await identity.continueWithGoogle(linkGuest: transferGuest);
    } on AuthException catch (error) {
      await cloudSync.cancelGuestTransfer();
      if (mounted) {
        setState(() {
          _googleAuthPending = false;
          _error = error.message;
        });
      }
    } catch (_) {
      await cloudSync.cancelGuestTransfer();
      if (mounted) {
        setState(() {
          _googleAuthPending = false;
          _error = 'Google sign-in could not be started. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finishAuthentication() {
    if (widget.replaceWithHomeOnSuccess) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (_) => false,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _openHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<WormWiseIdentityService>();
    final cloudSync = context.watch<WormWiseCloudSyncService?>();
    final registered = identity.state == WormWiseIdentityState.registered;
    if (registered && _googleAuthPending && !_googleCompletionScheduled) {
      _googleCompletionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await context.read<WormWiseCloudSyncService>().prepareAccountView(
            identity.userId!,
          );
          _guestTransferCompleted = _transferRequested;
          if (mounted) _openHome();
        } catch (_) {
          if (mounted) {
            setState(() {
              _googleCompletionScheduled = false;
              _googleAuthPending = false;
              _error = 'Could not open account data. Please try signing in.';
            });
          }
        }
      });
    }
    if (registered &&
        cloudSync != null &&
        (_busy ||
            _googleAuthPending ||
            _error != null ||
            cloudSync.recoveryState == AccountRecoveryState.restoring)) {
      return Scaffold(
        body: AccountRecoveryView(
          state: _error != null
              ? AccountRecoveryState.error
              : cloudSync.recoveryState,
          detail: _error ?? cloudSync.recoveryDetail,
          onRetry: _busy ? null : _retryAccountPreparation,
          onContinueWithLocalData: _busy || !cloudSync.canContinueWithLocalData
              ? null
              : () {
                  cloudSync.continueWithLocalData();
                  _openHome();
                },
        ),
      );
    }
    final content = _accessCard(hideIntro: widget.brandedLanding == true);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F4),
      appBar: widget.allowContinueAsGuest
          ? null
          : AppBar(title: const AppText('My account')),
      body: widget.brandedLanding == true
          ? _brandedBody(content)
          : SafeArea(
              child: Align(
                alignment: _transferRequested
                    ? Alignment.topCenter
                    : Alignment.center,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: content,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _brandedBody(Widget content) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 640;
        const fieldAspectRatio = 2172 / 724;
        final fieldHeight = (constraints.maxWidth / fieldAspectRatio)
            .clamp(0.0, constraints.maxHeight * .38)
            .toDouble();
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: fieldHeight * .34,
              child: FadeTransition(
                opacity: _fieldReveal,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF3F8F10), Color(0xFF174D0A)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: fieldHeight,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _fieldReveal,
                  child: Transform.translate(
                    offset: Offset(0, fieldHeight * .225),
                    child: Image.asset(
                      key: const Key('login_field_art'),
                      'assets/images/wormwise_login_field.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFF8F7F1),
                    const Color(0xFFF8F7F1),
                    const Color(0xFFF8F7F1).withValues(alpha: .94),
                    const Color(0xFFF8F7F1).withValues(alpha: .35),
                    Colors.transparent,
                  ],
                  stops: const [0, .55, .70, .84, 1],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  compact ? 4 : 10,
                  18,
                  compact ? 8 : 18,
                ),
                child: Column(
                  children: [
                    FadeTransition(
                      opacity: _topBrandReveal,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            key: const Key('login_brand_logo'),
                            'assets/images/wormwise_brand_logo.png',
                            width: compact ? 112 : 156,
                            height: compact ? 78 : 112,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.agriculture_outlined,
                              size: compact ? 54 : 76,
                              color: AppColors.primary,
                            ),
                          ),
                          Image.asset(
                            key: const Key('login_brand_wordmark'),
                            'assets/images/wormwise_brand_wordmark.png',
                            width: compact ? 180 : 228,
                            height: compact ? 48 : 64,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => AppText(
                              'WormWise',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: compact ? 27 : 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 8),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AnimatedBuilder(
                            animation: _accountReveal,
                            child: FadeTransition(
                              opacity: _accountReveal,
                              child: _brandedAccountContent(content),
                            ),
                            builder: (context, child) => IgnorePointer(
                              ignoring: _accountReveal.value < .95,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: FadeTransition(
                  opacity: _centerLogoReveal,
                  child: Image.asset(
                    key: const Key('login_center_logo'),
                    'assets/images/wormwise_brand_logo.png',
                    width: compact ? 190 : 238,
                    height: compact ? 136 : 170,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.agriculture_outlined,
                      size: compact ? 112 : 140,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _brandedAccountContent(Widget content) {
    return SizedBox(
      width: double.infinity,
      child: Scrollbar(
        controller: _accountScrollController,
        child: SingleChildScrollView(
          controller: _accountScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _accessCard({bool hideIntro = false}) {
    final registering = _registering;
    return Column(
      children: [
        if (!hideIntro && _transferRequested) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE5F0E8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: AppText(
              'Create account',
              style: TextStyle(
                color: Color(0xFF172C20),
                fontSize: 29,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: AppText(
              'Keep your guest fields and assessments with your account.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: AppText(
              'ACCOUNT DETAILS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (!hideIntro && widget.allowContinueAsGuest) ...[
          Container(
            width: 82,
            height: 82,
            decoration: const BoxDecoration(
              color: Color(0xFFE3F3E5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.agriculture_outlined,
              color: AppColors.primary,
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (!hideIntro && !_transferRequested) ...[
          Text(
            widget.allowContinueAsGuest
                ? 'Welcome to WormWise'
                : _transferRequested
                ? 'Save your guest profile'
                : registering
                ? 'Create your account'
                : 'Sign in to your account',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 29,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.allowContinueAsGuest
                ? 'An account is optional. Your field records stay stored on this phone whether you sign in or continue as guest.'
                : _transferRequested
                ? 'Create an account or sign in to one you own. Your guest fields and assessments will be copied to it.'
                : registering
                ? 'Create a new account with its own empty profile.'
                : 'Sign in to your existing account. Your field records remain on this phone.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (!_transferRequested)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(child: _modeButton('Sign in', _AccountMode.signIn)),
                Expanded(
                  child: _modeButton('Create account', _AccountMode.register),
                ),
              ],
            ),
          ),
        if (!_transferRequested) const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            children: [
              if (registering) ...[
                TextFormField(
                  key: const Key('account_name_field'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: _decoration('Name', Icons.person_outline),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name.'
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('account_email_field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: _decoration('Email address', Icons.mail_outline),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('account_password_field'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: registering
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: [
                  registering
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onFieldSubmitted: registering ? null : (_) => _submit(),
                decoration: _decoration('Password', Icons.lock_outline)
                    .copyWith(
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters.'
                    : null,
              ),
              if (registering) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('account_confirm_password_field'),
                  controller: _confirmController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration(
                    'Confirm password',
                    Icons.lock_reset_outlined,
                  ),
                  validator: (value) => value != _passwordController.text
                      ? 'Passwords do not match.'
                      : null,
                ),
              ],
              if (_error != null) _message(_error!, error: true),
              if (_error != null &&
                  context.watch<WormWiseIdentityService>().state ==
                      WormWiseIdentityState.registered)
                TextButton.icon(
                  onPressed: _busy ? null : _retryAccountPreparation,
                  icon: const Icon(Icons.refresh),
                  label: const AppText('Retry opening account'),
                ),
              if (_notice != null) _message(_notice!),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: Key(
                    registering ? 'create_account_button' : 'sign_in_button',
                  ),
                  onPressed:
                      _busy ||
                          context.watch<WormWiseIdentityService>().state ==
                              WormWiseIdentityState.registered
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _transferRequested
                              ? registering
                                    ? 'Create account'
                                    : 'Sign in'
                              : registering
                              ? 'Create account'
                              : 'Sign in',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (!_transferRequested &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: AppText('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('google_account_button'),
              onPressed: _busy ? null : _continueWithGoogle,
              icon: const AppText(
                'G',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              label: Text(
                _transferRequested
                    ? 'Save with Google'
                    : widget.allowContinueAsGuest
                    ? 'Continue with Google'
                    : 'Sign in with Google',
              ),
            ),
          ),
        ],
        if (widget.allowContinueAsGuest) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 17),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: AppText(
                    'or',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('continue_as_guest_button'),
              onPressed: _busy ? null : _continueAsGuest,
              icon: const Icon(Icons.phone_android_rounded),
              label: const AppText(
                'Continue as guest',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          if (!hideIntro) ...[
            const SizedBox(height: 10),
            const AppText(
              'Continuing as guest reuses the existing local database on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ],
    );
  }

  Widget _modeButton(String label, _AccountMode mode) {
    final selected = _mode == mode;
    return TextButton(
      onPressed: () => _setMode(mode),
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.primary : AppColors.textSecondary,
        backgroundColor: selected ? Colors.white : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE4DC)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE4DC)),
    ),
  );

  Widget _message(String text, {bool error = false}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: error ? const Color(0xFFB3261E) : AppColors.primary,
        height: 1.35,
      ),
    ),
  );
}
