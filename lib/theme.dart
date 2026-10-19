import 'package:flutter/material.dart';

/// Dark palette shared by every screen.
class AppColors {
  static const bg = Color(0xFF07080C);
  static const bgCard = Color(0xFF14161E);
  static const bgCard2 = Color(0xFF1D2029);
  static const accent = Color(0xFFFF4D6D);
  static const accent2 = Color(0xFF9B51E0);
  static const text = Color(0xFFF3F5F9);
  static const text2 = Color(0xFF9AA1AE);
  static const text3 = Color(0xFF5A616D);
  static const border = Color(0xFF1F232D);
}

const LinearGradient kAccentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.accent, AppColors.accent2],
);

/// Vertical fade used on top of artwork so text stays readable.
const LinearGradient kCoverFade = LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [Color(0xF2000000), Color(0x40000000), Colors.transparent],
  stops: [0.0, 0.45, 1.0],
);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.bgCard,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.bgCard2,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      elevation: 6,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
