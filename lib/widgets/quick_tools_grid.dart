import 'package:flutter/material.dart';
import '../screens/fields_screen.dart';
import '../theme/app_colors.dart';

class QuickToolsGrid extends StatelessWidget {
  const QuickToolsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Tools',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _buildToolCard(
              icon: Icons.history,
              label: 'History',
              onTap: () => _showUnavailable(context, 'Assessment history'),
            ),
            _buildToolCard(
              icon: Icons.grid_view,
              label: 'My Fields',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const FieldsScreen()),
              ),
            ),
            _buildToolCard(
              icon: Icons.menu_book,
              label: 'FAW Guide',
              onTap: () => _showUnavailable(context, 'FAW guide'),
            ),
            _buildToolCard(
              icon: Icons.smart_toy_outlined,
              label: 'Assistant',
              onTap: () => _showUnavailable(context, 'Assistant'),
            ),
          ],
        ),
      ],
    );
  }

  void _showUnavailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('$feature is not available in this build yet.')),
      );
  }

  Widget _buildToolCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
