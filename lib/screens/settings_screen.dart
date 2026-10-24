import '../localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_text.dart';
import '../services/cloud/wormwise_identity_service.dart';
import '../theme/app_colors.dart';
import 'language_screen.dart';
import 'my_profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final identity = context.watch<WormWiseIdentityService>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const AppText('Settings')),
      body: ListView(
        key: const PageStorageKey('settings_screen'),
        padding: const EdgeInsets.all(16),
        children: [
          const _Heading('Account'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const AppText('My Profile'),
              subtitle: Text(
                identity.email ??
                    AppWords.of(context).translate('Guest account'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const MyProfileScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Heading('Preferences'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const AppText('Language'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const LanguageScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Heading('About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: AppText('WormWise'),
              subtitle: AppText('Version 1.0.0+1 · Structured field scouting'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: AppText(
      text,
      style: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
