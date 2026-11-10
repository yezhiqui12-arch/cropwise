import 'package:flutter/material.dart';
import '../localization/app_text.dart';
import 'package:provider/provider.dart';
import '../localization/app_language.dart';
import '../providers/field_workspace_provider.dart';
import '../screens/fields_screen.dart';
import '../screens/my_profile_screen.dart';
import '../screens/language_screen.dart';
import '../screens/help_support_screen.dart';
import '../screens/advisor/guidelines_redesign.dart';
import '../screens/signed_out_screen.dart';
import '../services/cloud/wormwise_identity_service.dart';
import '../services/recent_weather_service.dart';
import '../theme/app_colors.dart';

class AppSideMenuDrawer extends StatelessWidget {
  const AppSideMenuDrawer({super.key});

  void _openLanguage(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const LanguageScreen()));
  }

  void _openFields(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const FieldsScreen()));
  }

  void _openGuides(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => const AdvisorOfflineGuidesScreen()),
    );
  }

  void _openAccount(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const MyProfileScreen()));
  }

  void _openHelp(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final identity = context.read<WormWiseIdentityService>();
    final words = AppWords.of(context);
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(words.signOutQuestion),
        content: Text(words.signOutRetention),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(words.cancel),
          ),
          FilledButton(
            key: const Key('confirm_sign_out_button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            child: Text(words.signOut),
          ),
        ],
      ),
    );
    if (shouldSignOut != true) return;

    // Close the drawer only after confirmation. Closing it before awaiting the
    // dialog disposed this widget's context and previously aborted sign-out.
    navigator.pop();

    try {
      await identity.signOut();
    } catch (_) {
      // A failed network sign-out must not block local access or risk local
      // records. The signed-out gate remains usable in offline mode.
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignedOutScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    // Width set to 78% of total screen width as requested (70-80% bounds)
    final drawerWidth = MediaQuery.of(context).size.width * 0.78;

    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              // 1. Top Header & User Profile Card Section
              _buildProfileHeader(context),

              // 2. Scrollable Navigation Menu Items List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  children: [
                    const _SidebarFieldConditions(),
                    const SizedBox(height: 12),
                    // Item 1: My Profile (Standard inactive)
                    _buildMenuItem(
                      icon: Icons.person_outline,
                      label: words.myProfile,
                      onTap: () => _openAccount(context),
                    ),
                    const SizedBox(height: 6),

                    // Item 2: My Fields
                    _buildMenuItem(
                      icon: Icons.landscape_outlined,
                      label: words.myFields,
                      onTap: () => _openFields(context),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 12),

                    _buildMenuItem(
                      icon: Icons.menu_book_outlined,
                      label: words.guidelines,
                      onTap: () => _openGuides(context),
                    ),
                    const SizedBox(height: 6),

                    // Language
                    _buildMenuItem(
                      icon: Icons.language,
                      label: words.languageLabel,
                      onTap: () => _openLanguage(context),
                    ),
                    const SizedBox(height: 6),

                    // Item 5: Settings
                    _buildMenuItem(
                      icon: Icons.settings_outlined,
                      label: words.settings,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 12),

                    // Item 6: Help & Support
                    _buildMenuItem(
                      icon: Icons.help_outline,
                      label: words.helpAndSupport,
                      onTap: () => _openHelp(context),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),

                    // Item 8: Sign Out (Red accent)
                    _buildMenuItem(
                      icon: Icons.logout,
                      label: words.signOut,
                      isDestructive: true,
                      onTap: () => _signOut(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    final words = AppWords.of(context);
    final identity = context.watch<WormWiseIdentityService>();
    final registered = identity.state == WormWiseIdentityState.registered;
    final profileName = registered
        ? identity.displayName ?? words.wormwiseUser
        : words.guestUser;
    final profileSubtitle = registered
        ? identity.email ?? words.registeredAccount
        : words.dataSavedOnDevice;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F8F2),
        borderRadius: BorderRadius.only(topRight: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & App Name Header
          Image.asset(
            'assets/images/cropwise_brand_logo.png',
            height: 48,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
          const SizedBox(height: 20),

          // User Avatar & Details Row
          Row(
            children: [
              // Local placeholder until a real user profile is created.
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),

              // Profile state
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profileName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      profileSubtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isDestructive = false,
    String? badgeCount,
    Color? badgeColor,
  }) {
    final textColor = isDestructive
        ? const Color(0xFFD32F2F)
        : (isActive ? AppColors.primary : AppColors.textPrimary);
    final iconColor = isDestructive
        ? const Color(0xFFD32F2F)
        : (isActive ? AppColors.primary : AppColors.primary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8F5E9) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            if (badgeCount != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeCount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (!isDestructive)
              Icon(
                Icons.chevron_right,
                color: isActive ? AppColors.primary : const Color(0xFF9E9E9E),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFieldConditions extends StatefulWidget {
  const _SidebarFieldConditions();

  @override
  State<_SidebarFieldConditions> createState() =>
      _SidebarFieldConditionsState();
}

class _SidebarFieldConditionsState extends State<_SidebarFieldConditions> {
  String? _coordinatesKey;
  Future<CurrentFieldWeather>? _weather;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspace = context.watch<FieldWorkspaceProvider>().activeWorkspace;
    final coordinates = workspace == null
        ? null
        : resolveRecentWeatherCoordinates(
            storedLatitude: workspace.boundary?.centroidLatitude,
            storedLongitude: workspace.boundary?.centroidLongitude,
            boundaryGeoJson: workspace.boundary?.geometryGeojson ?? '',
          );
    final key = coordinates == null
        ? null
        : '${coordinates.latitude}:${coordinates.longitude}';
    if (key == _coordinatesKey) return;
    _coordinatesKey = key;
    _weather = coordinates == null
        ? null
        : const OpenMeteoCurrentWeatherService().current(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sidebar_field_conditions'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              AppWords.of(context).fieldConditions,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (_weather != null)
            FutureBuilder<CurrentFieldWeather>(
              future: _weather,
              builder: (context, snapshot) => Text(
                snapshot.hasData
                    ? '${snapshot.data!.temperatureC.round()}°C'
                    : '—',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            const AppText(
              '—',
              style: TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
