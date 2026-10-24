import 'package:flutter/material.dart';
import '../localization/app_language.dart';
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
    final words = AppWords.of(context);
    return Container(
      key: const Key('bottom_nav_bar'),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -1),
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
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  0,
                  Icons.home_outlined,
                  Icons.home,
                  words.home,
                  key: const Key('bottom_nav_home'),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  1,
                  Icons.assignment_outlined,
                  Icons.assignment,
                  words.assess,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  2,
                  Icons.map_outlined,
                  Icons.map,
                  words.map,
                  key: const Key('bottom_nav_map'),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  3,
                  Icons.menu_book_outlined,
                  Icons.menu_book,
                  words.advisor,
                  key: const Key('bottom_nav_guide'),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  4,
                  Icons.more_horiz,
                  Icons.more,
                  words.translate('More'),
                  key: const Key('bottom_nav_more'),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final icon = Icon(
      isSelected ? selectedIcon : unselectedIcon,
      color: isSelected ? AppColors.highContrastGreen : AppColors.textMuted,
      size: 24,
    );
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        key: key,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 36, child: Center(child: icon)),
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
      ),
    );
  }
}
