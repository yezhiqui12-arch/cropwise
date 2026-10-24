import 'models_screen.dart';
import 'artificial_intelligence_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_text.dart';
import '../services/cloud/wormwise_identity_service.dart';
import '../theme/app_colors.dart';
import 'advisor/guidelines_redesign.dart';
import 'fields_screen.dart';
import 'field_trends_screen.dart';
import 'help_support_screen.dart';
import 'language_screen.dart';
import 'my_profile_screen.dart';
import 'signed_out_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _signOut(BuildContext context) async {
    final identity = context.read<WormWiseIdentityService>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppText('Sign out?'),
        content: const AppText('Your saved records remain on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_sign_out_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const AppText('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await identity.signOut();
    } catch (_) {
      // Local access must remain possible if network sign-out fails.
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SignedOutScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<WormWiseIdentityService>();
    final accountName =
        identity.displayName ??
        (identity.state == WormWiseIdentityState.registered
            ? 'WormWise account'
            : 'Guest');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const AppText('More')),
      body: ListView(
        key: const Key('more_screen'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Material(
            color: const Color(0xFFEAF2EC),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context, const MyProfileScreen()),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9E8DD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF2D5940),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            accountName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF233D2E),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            identity.email ?? 'Guest account',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF647B6B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFF647B6B),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _section('Workspace'),
          _group([
            _item(
              context,
              Icons.landscape_outlined,
              'My Fields',
              const FieldsScreen(),
            ),
            _item(
              context,
              Icons.insights_outlined,
              'Field trends',
              const FieldTrendsScreen(),
              key: const Key('open_field_trends'),
            ),
            _item(
              context,
              Icons.menu_book_outlined,
              'Guidelines',
              const AdvisorOfflineGuidesScreen(),
            ),
          ]),
          _section('Preferences'),
          _group([
            _item(
              context,
              Icons.auto_awesome_outlined,
              'Artificial Intelligence',
              const ArtificialIntelligenceScreen(),
              key: const Key('open_artificial_intelligence'),
            ),
            _item(
              context,
              Icons.memory_outlined,
              'Models',
              const ModelsScreen(),
              key: const Key('open_models'),
            ),
            _item(
              context,
              Icons.language_rounded,
              'Language',
              const LanguageScreen(),
            ),
          ]),
          _section('Information'),
          _group([
            _item(
              context,
              Icons.help_outline_rounded,
              'Help & Support',
              const HelpSupportScreen(),
            ),
          ]),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('more_sign_out'),
              onPressed: () => _signOut(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF98504C),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const AppText(
                'Sign out',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
    child: AppText(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 1.3,
        color: Color(0xFF78877D),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _group(List<Widget> items) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFDDE7E0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              indent: 58,
              endIndent: 16,
              color: Color(0xFFEDF1EE),
            ),
          items[i],
        ],
      ],
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    Widget destination, {
    Key? key,
  }) => InkWell(
    key: key,
    onTap: () => _open(context, destination),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xFF50735C)),
          const SizedBox(width: 16),
          Expanded(
            child: AppText(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF293D31),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: Color(0xFF92A096),
          ),
        ],
      ),
    ),
  );
}
