import 'package:flutter/material.dart';

class AppColors {
  // Brand & Primary Colors
  static const Color primary = Color(0xFF0D631B);
  static const Color primaryContainer = Color(0xFF2E7D32);
  static const Color highContrastGreen = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFFE8F5E9);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Surfaces & Backgrounds
  static const Color background = Color(0xFFF9F9F6);
  static const Color surface = Color(0xFFF4F4F1);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFEEEEEB);
  static const Color surfaceVariant = Color(0xFFE2E3E0);

  // Text & Icons
  static const Color textPrimary = Color(0xFF1A1C1B);
  static const Color textSecondary = Color(0xFF5D5F5F);
  static const Color textMuted = Color(0xFF707A6C);
  static const Color outline = Color(0xFF707A6C);
  static const Color outlineVariant = Color(0xFFBFCABA);

  // FAW Severity & Status Badges
  static const Color lowSeverityRing = Color(0xFF2E7D32);
  static const Color lowSeverityBg = Color(0xFFE8F5E9);
  static const Color moderateSeverityRing = Color(0xFFEF6C00);
  static const Color moderateSeverityBg = Color(0xFFFFF3E0);
  static const Color severeSeverityRing = Color(0xFFBA1A1A);
  static const Color severeSeverityBg = Color(0xFFFFDAD6);

  // Card Borders & Shadows
  static const Color cardBorder = Color(0xFFE2E8F0);
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];
}
