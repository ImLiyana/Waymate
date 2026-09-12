import 'package:flutter/material.dart';

/// WayMate's professional design tokens — deep navy + gold accent.
/// Accessible by design (large touch targets, high contrast) without
/// looking like an "accessibility mode" — SOS red is reserved
/// exclusively for danger, never used decoratively elsewhere.
class AppColors {
  static const navyDark = Color(0xFF050D1A);
  static const navy = Color(0xFF0B1F3A);
  static const navyCard = Color(0xFF12294D);
  static const navyBorder = Color(0xFF1F3A5F);

  static const gold = Color(0xFFD4AF37);
  static const goldDark = Color(0xFFB8952E);

  static const sos = Color(0xFFC0392B);
  static const sosPressed = Color(0xFF922017);
  static const medical = Color(0xFFE08E1E);

  static const success = Color(0xFF4ADE80);
  static const inactive = Color(0xFF9FB3D1);

  static const textOnNavy = Color(0xFFFFFFFF);
  static const textOnNavySecondary = Color(0xFF9FB3D1);
  static const textOnNavyMuted = Color(0xFF5C7A9E);

  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF4A4A4A);
}

class AppTextStyles {
  static const heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnNavy,
  );

  static const subheading = TextStyle(
    fontSize: 14,
    color: AppColors.textOnNavySecondary,
  );

  static const body = TextStyle(
    fontSize: 16,
    color: AppColors.textOnNavy,
    height: 1.4,
  );

  static const label = TextStyle(
    fontSize: 12,
    color: AppColors.textOnNavySecondary,
    letterSpacing: 0.4,
  );

  static const buttonLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

class AppSpacing {
  static const xs = 6.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const minTouchTarget = 52.0;
}

final ThemeData wayMateTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.navy,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
    primary: AppColors.gold,
    surface: AppColors.navyCard,
  ),
  fontFamily: 'Roboto',
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.navy,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
    iconTheme: IconThemeData(color: Colors.white),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.gold,
      foregroundColor: AppColors.navyDark,
      minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
      textStyle: AppTextStyles.buttonLabel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
      side: const BorderSide(color: AppColors.navyBorder, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.navyCard,
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    labelStyle: const TextStyle(color: AppColors.textOnNavySecondary, fontSize: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.navyBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.gold, width: 2),
    ),
  ),
);