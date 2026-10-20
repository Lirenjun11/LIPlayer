import 'package:flutter/material.dart';

/// Runtime palette. Values are mutable because the app supports a light theme:
/// [AppColors.apply] swaps every colour before the widget tree rebuilds.
class AppColors {
  static Color bg = const Color(0xFF07080C);
  static Color bgCard = const Color(0xFF14161E);
  static Color bgCard2 = const Color(0xFF1D2029);
  static Color accent = const Color(0xFFFF4D6D);
  static Color accent2 = const Color(0xFF9B51E0);
  static Color text = const Color(0xFFF3F5F9);
  static Color text2 = const Color(0xFF9AA1AE);
  static Color text3 = const Color(0xFF5A616D);
  static Color border = const Color(0xFF1F232D);

  static bool isDark = true;

  static void apply(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    isDark = dark;
    if (dark) {
      bg = const Color(0xFF07080C);
      bgCard = const Color(0xFF14161E);
      bgCard2 = const Color(0xFF1D2029);
      text = const Color(0xFFF3F5F9);
      text2 = const Color(0xFF9AA1AE);
      text3 = const Color(0xFF5A616D);
      border = const Color(0xFF1F232D);
    } else {
      bg = const Color(0xFFF5F6FA);
      bgCard = const Color(0xFFFFFFFF);
      bgCard2 = const Color(0xFFEDEFF5);
      text = const Color(0xFF15171C);
      text2 = const Color(0xFF6B7280);
      text3 = const Color(0xFF9AA1AE);
      border = const Color(0xFFE3E6EC);
    }
  }
}

/// Accent gradient (depends on the live palette, so it cannot be `const`).
LinearGradient get kAccentGradient => LinearGradient(
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

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      surface: AppColors.bgCard,
      onSurface: AppColors.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: AppColors.text),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgCard2,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      elevation: 6,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    // Dialogs and sheets follow the active palette instead of the platform
    // default, which looked wrong in light mode.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      contentTextStyle: TextStyle(fontSize: 13, color: AppColors.text2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.bgCard,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
