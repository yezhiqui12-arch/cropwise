import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Main Navigation Bar Shell
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
            border: Border(
              top: BorderSide(
                color: Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: _buildNavItem(
                      0,
                      Icons.home_outlined,
                      Icons.home,
                      'Home',
                      key: const Key('bottom_nav_home'),
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      1,
                      Icons.assignment_outlined,
                      Icons.assignment,
                      'Assess',
                    ),
                  ),
                  // Middle Empty Spacer for the elevated center button
                  const Expanded(child: SizedBox()),
                  Expanded(
                    child: _buildNavItem(
                      3,
                      Icons.map_outlined,
                      Icons.map,
                      'Map',
                      key: const Key('bottom_nav_map'),
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      4,
                      Icons.smart_toy_outlined,
                      Icons.smart_toy,
                      'Bot',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Elevated center destination for active fieldwork.
        Positioned(
          top: -16,
          child: Semantics(
            button: true,
            selected: currentIndex == 2,
            label: 'Scan',
            child: InkWell(
              key: const Key('bottom_nav_scan'),
              onTap: () => onTap(2),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 72,
                height: 80,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.highContrastGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.highContrastGreen.withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.center_focus_strong,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 2),
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Text(
                        'Scan',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: currentIndex == 2
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: currentIndex == 2
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(
    int index,
    IconData unselectedIcon,
    IconData selectedIcon,
    String label, {
    Key? key,
  }) {
    final isSelected = currentIndex == index;
    return InkWell(
      key: key,
      onTap: () => onTap(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? selectedIcon : unselectedIcon,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
            size: 24,
          ),
          const SizedBox(height: 2),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
