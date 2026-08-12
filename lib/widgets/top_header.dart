import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TopHeader extends StatelessWidget implements PreferredSizeWidget {
  const TopHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      leading: IconButton(
        key: const Key('home_menu_button'),
        icon: const Icon(Icons.menu, color: AppColors.textPrimary, size: 28),
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          // Logo Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 8),
          const Text(
            'Home',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        // WormWise currently stores its core field records locally.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF005312),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.primary),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_android, color: Colors.white, size: 14),
              SizedBox(width: 4),
              Text(
                'LOCAL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // User Avatar Button
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}
