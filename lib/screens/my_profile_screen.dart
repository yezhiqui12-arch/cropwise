import 'dart:io';
import '../localization/app_language.dart';
import '../localization/app_text.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud/wormwise_identity_service.dart';
import '../services/profile_avatar_store.dart';
import 'account_access_screen.dart';
import 'signed_out_screen.dart';
import 'profile_visual_layout.dart';

enum _AvatarAction { gallery, camera, remove }

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  static const _avatars = ProfileAvatarStore();
  String? _avatarOwner;
  File? _avatar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.watch<WormWiseIdentityService>().userId ?? 'guest';
    if (owner == _avatarOwner) return;
    _avatarOwner = owner;
    _avatar = null;
    _loadAvatar(owner);
    context.read<WormWiseIdentityService>().loadProfilePhone();
  }

  Future<void> _loadAvatar(String owner) async {
    final file = await _avatars.fileFor(owner == 'guest' ? null : owner);
    if (!mounted || _avatarOwner != owner) return;
    if (await file.exists()) {
      setState(() => _avatar = file);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: AppText(value)));
    }
  }

  Future<void> _editAvatar(WormWiseIdentityService identity) async {
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const AppText('Choose from photos'),
              onTap: () => Navigator.pop(sheetContext, _AvatarAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const AppText('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, _AvatarAction.camera),
            ),
            if (_avatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const AppText('Remove photo'),
                onTap: () => Navigator.pop(sheetContext, _AvatarAction.remove),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == null) return;
    if (action == _AvatarAction.remove) {
      await _avatars.remove(identity.userId);
      setState(() {
        _avatar = null;
      });
      return;
    }
    try {
      final source = action == _AvatarAction.camera
          ? ImageSource.camera
          : ImageSource.gallery;
      final file = await _avatars.pickAndSave(identity.userId, source);
      if (!mounted || file == null) return;
      await FileImage(file).evict();
      setState(() {
        _avatar = file;
      });
    } catch (_) {
      _message('Could not save the profile photo.');
    }
  }

  Future<String?> _askText({
    required String title,
    required String initial,
    required String label,
    bool email = false,
    bool phone = false,
  }) async {
    var draft = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(title),
        content: TextFormField(
          initialValue: initial,
          onChanged: (value) => draft = value,
          autofocus: true,
          maxLength: email
              ? 254
              : phone
              ? 40
              : 80,
          keyboardType: phone
              ? TextInputType.phone
              : email
              ? TextInputType.emailAddress
              : TextInputType.name,
          textCapitalization: email || phone
              ? TextCapitalization.none
              : TextCapitalization.words,
          decoration: InputDecoration(
            labelText: AppWords.of(dialogContext).translate(label),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const AppText('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _editName(WormWiseIdentityService identity) async {
    final value = await _askText(
      title: 'Edit display name',
      initial: identity.displayName ?? '',
      label: 'Display name',
    );
    if (value == null || !mounted) return;
    if (value.isEmpty) {
      _message('Enter a display name.');
      return;
    }
    try {
      final synced = await identity.updateDisplayName(value);
      _message(
        synced
            ? 'Display name updated.'
            : 'Name saved on this phone. Account update will retry later.',
      );
    } catch (error) {
      _message(_editError(error, 'Could not update your name.'));
    }
  }

  Future<void> _editEmail(WormWiseIdentityService identity) async {
    final value = await _askText(
      title: 'Change email',
      initial: identity.email ?? '',
      label: 'Email address',
      email: true,
    );
    if (value == null || !mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      _message('Enter a valid email address.');
      return;
    }
    try {
      await identity.updateEmail(value);
      _message('Check your email to confirm this change.');
    } catch (error) {
      _message(_editError(error, 'Could not change your email.'));
    }
  }

  Future<void> _editPhone(WormWiseIdentityService identity) async {
    final value = await _askText(
      title: 'Edit phone number',
      initial: identity.phone ?? '',
      label: 'Phone number',
      phone: true,
    );
    if (value == null || !mounted) return;
    try {
      await identity.updateProfilePhone(value);
      _message('Phone number updated.');
    } on ArgumentError {
      _message('Enter a valid phone number.');
    } catch (_) {
      _message(
        'Could not save your phone number. Check your connection and try again.',
      );
    }
  }

  Future<void> _changePassword(WormWiseIdentityService identity) async {
    var password = '';
    var confirmation = '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) => password = value,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppWords.of(context).translate('New password'),
              ),
            ),
            TextField(
              onChanged: (value) => confirmation = value,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppWords.of(context).translate('Confirm password'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, password),
            child: const AppText('Update'),
          ),
        ],
      ),
    );
    final matches = password == confirmation;
    if (value == null || !mounted) return;
    if (value.length < 8 || !matches) {
      _message('Use at least 8 characters and matching passwords.');
      return;
    }
    try {
      await identity.updatePassword(value);
      _message('Password updated.');
    } catch (error) {
      _message(_editError(error, 'Could not update your password.'));
    }
  }

  String _editError(Object error, String fallback) =>
      error is AuthException && error.message.isNotEmpty
      ? error.message
      : fallback;

  Future<void> _signOut(WormWiseIdentityService identity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('Sign out of Cropwise?'),
        content: const AppText(
          'Your fields, assessments, and photos will stay saved on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const AppText('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await identity.signOut();
    } catch (_) {
      _message('Could not sign out. Try again.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignedOutScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<WormWiseIdentityService>();
    final registered = identity.state == WormWiseIdentityState.registered;
    final name =
        identity.displayName ?? (registered ? 'Cropwise user' : 'Guest user');
    final email = registered
        ? identity.email ?? 'No email available'
        : 'No email linked';
    final google = registered && identity.usesGoogleSignIn;
    final emailSignIn = registered && identity.usesEmailSignIn;

    return ProfileVisualLayout(
      name: name,
      email: email,
      phone: identity.phone,
      registered: registered,
      googleSignIn: google,
      emailSignIn: emailSignIn,
      avatar: _avatar,
      onAvatar: () => _editAvatar(identity),
      onEditName: () => _editName(identity),
      onEditEmail: () => _editEmail(identity),
      onEditPhone: () => _editPhone(identity),
      onChangePassword: () => _changePassword(identity),
      onSignOut: () => _signOut(identity),
      onSaveGuestProfile: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AccountAccessScreen(transferGuestProfile: true),
        ),
      ),
    );
  }
}
