import 'dart:io';

import 'package:flutter/material.dart';

import '../localization/app_language.dart';
import '../localization/app_text.dart';
import '../widgets/account_backup_status_card.dart';

/// Visual shell for guest and registered profiles.
class ProfileVisualLayout extends StatelessWidget {
  const ProfileVisualLayout({
    super.key,
    required this.name,
    required this.email,
    this.phone,
    this.onEditPhone,
    required this.registered,
    required this.googleSignIn,
    required this.emailSignIn,
    required this.avatar,
    required this.onAvatar,
    required this.onEditName,
    required this.onEditEmail,
    required this.onChangePassword,
    required this.onSignOut,
    required this.onSaveGuestProfile,
  });

  final String name;
  final String email;
  final String? phone;
  final VoidCallback? onEditPhone;
  final bool registered;
  final bool googleSignIn;
  final bool emailSignIn;
  final File? avatar;
  final VoidCallback onAvatar;
  final VoidCallback onEditName;
  final VoidCallback onEditEmail;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;
  final VoidCallback onSaveGuestProfile;

  static const _green = Color(0xFF205A36);
  static const _deep = Color(0xFF143D29);
  static const _canvas = Color(0xFFF7F9F6);
  static const _border = Color(0xFFE1E9E1);
  static const _muted = Color(0xFF667268);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 18, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: AppWords.of(context).translate('Back'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _deep),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: AppText(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF17251B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  _identityCard(context),
                  const SizedBox(height: 26),
                  _sectionTitle(context, 'PERSONAL INFORMATION'),
                  const SizedBox(height: 10),
                  _surface([
                    _row(
                      context,
                      icon: Icons.badge_outlined,
                      title: 'Display name',
                      detail: name,
                      action: 'Edit',
                      onTap: onEditName,
                    ),
                    const Divider(height: 1, indent: 62, color: _border),
                    _row(
                      context,
                      icon: Icons.alternate_email_rounded,
                      title: 'Email address',
                      detail: email,
                      note: googleSignIn ? 'Managed by Google' : null,
                      action: emailSignIn ? 'Change' : null,
                      onTap: emailSignIn ? onEditEmail : null,
                    ),
                    const Divider(height: 1, indent: 62, color: _border),
                    _row(
                      context,
                      icon: Icons.phone_outlined,
                      title: 'Phone number',
                      detail: phone?.isNotEmpty == true
                          ? phone
                          : AppWords.of(context).translate('Not provided'),
                      action: 'Edit',
                      onTap: onEditPhone,
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _sectionTitle(
                    context,
                    registered ? 'ACCOUNT' : 'SAVE YOUR PROFILE',
                  ),
                  const SizedBox(height: 10),
                  if (registered) _registeredCard(context) else _guestCard(),
                  if (registered) const AccountBackupStatusCard(),
                  if (registered) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: onSignOut,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFAE3E36),
                        side: const BorderSide(color: Color(0xFFE7C9C5)),
                        backgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 19),
                      label: const AppText('Sign out'),
                    ),
                    const SizedBox(height: 10),
                    const AppText(
                      'Your field data will remain on this phone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityCard(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_green, _deep],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F1A4B2C),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -48,
          top: -54,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .09),
                width: 24,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            registered
                                ? Icons.verified_user_outlined
                                : Icons.person_outline,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            registered ? 'Registered account' : 'Guest profile',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _avatar() => Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        onTap: onAvatar,
        customBorder: const CircleBorder(),
        child: Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFDCEADD),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            image: avatar == null
                ? null
                : DecorationImage(image: FileImage(avatar!), fit: BoxFit.cover),
          ),
          child: avatar == null
              ? Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.w700,
                    color: _deep,
                  ),
                )
              : null,
        ),
      ),
      Positioned(
        right: -4,
        bottom: -3,
        child: Material(
          color: Colors.white,
          elevation: 2,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onAvatar,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 31,
              height: 31,
              child: Icon(Icons.camera_alt_rounded, size: 17, color: _deep),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Text(
      AppWords.of(context).translate(title),
      style: const TextStyle(
        color: _muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.15,
      ),
    ),
  );

  Widget _surface(List<Widget> children) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _border),
    ),
    child: Column(children: children),
  );

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? detail,
    String? note,
    String? action,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EE),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: _green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppWords.of(context).translate(title),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B2B1E),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: _muted,
                    ),
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppWords.of(context).translate(note),
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 7),
            if (action != null)
              Text(
                AppWords.of(context).translate(action),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _green,
                ),
              ),
            const Icon(Icons.chevron_right_rounded, size: 19, color: _muted),
          ],
        ],
      ),
    ),
  );

  Widget _registeredCard(BuildContext context) => _surface([
    _row(
      context,
      icon: Icons.lock_outline_rounded,
      title: 'Sign-in method',
      detail: googleSignIn
          ? 'Google account'
          : emailSignIn
          ? 'Email and password'
          : 'Sign-in method unavailable',
    ),
    if (emailSignIn) ...[
      const Divider(height: 1, indent: 62, color: _border),
      _row(
        context,
        icon: Icons.key_outlined,
        title: 'Change password',
        onTap: onChangePassword,
      ),
    ],
  ]);

  Widget _guestCard() => _surface([
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppText(
            'Keep your fields and assessments when you create an account.',
            style: TextStyle(fontSize: 13, height: 1.35, color: _muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onSaveGuestProfile,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
            label: const AppText('Save guest profile to an account'),
          ),
        ],
      ),
    ),
  ]);
}
