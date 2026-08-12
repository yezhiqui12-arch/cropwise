import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/field_workspace_provider.dart';
import '../screens/fields_screen.dart';
import '../theme/app_colors.dart';

class AppSideMenuDrawer extends StatelessWidget {
  const AppSideMenuDrawer({super.key});

  void _openFields(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const FieldsScreen()));
  }

  @override
  Widget build(BuildContext context) {
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
                    // Item 1: My Profile (Standard inactive)
                    _buildMenuItem(
                      icon: Icons.person_outline,
                      label: 'My Profile',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 6),

                    // Item 2: My Fields
                    _buildMenuItem(
                      icon: Icons.landscape_outlined,
                      label: 'My Fields',
                      onTap: () => _openFields(context),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 12),

                    // Item 4: Language
                    _buildMenuItem(
                      icon: Icons.language,
                      label: 'Language',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 6),

                    // Item 5: Settings
                    _buildMenuItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 12),

                    // Item 6: Help & Support
                    _buildMenuItem(
                      icon: Icons.help_outline,
                      label: 'Help & Support',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 6),

                    // Item 7: About WormWise
                    _buildMenuItem(
                      icon: Icons.info_outline,
                      label: 'About WormWise',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),

                    // Item 8: Sign Out (Red accent)
                    _buildMenuItem(
                      icon: Icons.logout,
                      label: 'Sign Out',
                      isDestructive: true,
                      onTap: () => Navigator.pop(context),
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
    final activeFieldName =
        context.watch<FieldWorkspaceProvider>().activeWorkspace?.field.name ??
        'No field selected';
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.eco,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'WormWise',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local user',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Profile not set up',
                      style: TextStyle(
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
          const SizedBox(height: 16),

          // Field Selector Dropdown Pill
          InkWell(
            onTap: () => _openFields(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeFieldName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Status Pill Badge: Offline Ready
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC8E6C9)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  color: AppColors.primary,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Offline Ready',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
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
