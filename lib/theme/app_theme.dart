import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          surface: AppColors.surfaceCard,
          error: AppColors.severeSeverityRing,
        ).copyWith(
          primaryContainer: AppColors.primaryLight,
          onPrimaryContainer: AppColors.highContrastGreen,
          surfaceContainerLowest: AppColors.surfaceCard,
          surfaceContainerLow: AppColors.background,
          surfaceContainer: AppColors.surface,
          surfaceContainerHigh: AppColors.surfaceContainer,
          surfaceContainerHighest: AppColors.surfaceVariant,
          outline: AppColors.outline,
          outlineVariant: AppColors.outlineVariant,
        );

    final baseText = GoogleFonts.interTextTheme();
    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.45,
        color: AppColors.textPrimary,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.42,
        color: AppColors.textPrimary,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    );

    final border = OutlineInputBorder(
      borderRadius: AppRadii.controlBorder,
      borderSide: const BorderSide(color: AppColors.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: const CardThemeData(
        elevation: AppElevation.card,
        margin: EdgeInsets.zero,
        color: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardBorder,
          side: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.severeSeverityRing),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        helperStyle: const TextStyle(color: AppColors.textMuted, height: 1.35),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, AppSizes.primaryActionHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.controlBorder,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, AppSizes.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          side: const BorderSide(color: AppColors.outlineVariant),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.controlBorder,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, AppSizes.minimumTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.controlBorder,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.controlBorder,
        ),
        side: const BorderSide(color: AppColors.outlineVariant),
        selectedColor: AppColors.primaryLight,
        backgroundColor: AppColors.surfaceCard,
        labelStyle: textTheme.bodyMedium,
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.highContrastGreen,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
        space: AppSpacing.md,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.prominentBorder),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.prominent),
          ),
        ),
      ),
    );
  }
}
