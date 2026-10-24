import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_language.dart';
import '../screens/notifications_screen.dart';
import '../services/wormwise_notification_service.dart';
import '../theme/app_colors.dart';

class TopHeader extends StatelessWidget implements PreferredSizeWidget {
  const TopHeader({super.key, required this.onOpenAssess});
  final VoidCallback onOpenAssess;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      titleSpacing: 20,
      title: Text(
        AppWords.of(context).home,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        Consumer<WormWiseNotificationService>(
          builder: (context, notifications, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('home_notifications_button'),
                tooltip: AppWords.of(context).notifications,
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        NotificationsScreen(onOpenAssess: onOpenAssess),
                  ),
                ),
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.textPrimary,
                  size: 27,
                ),
              ),
              if (notifications.unreadCount > 0)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC62828),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      notifications.unreadCount > 9
                          ? '9+'
                          : '${notifications.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}
