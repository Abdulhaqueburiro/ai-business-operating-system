import 'package:flutter/material.dart';

/// Fixed brand and meaning colors. Green = good, red = danger or loss,
/// amber = needs attention.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF145C4A);
  static const Color success = Color(0xFF18794E);
  static const Color danger = Color(0xFFB4232F);
  static const Color attention = Color(0xFFA15C08);
  static const Color lightBackground = Color(0xFFF6F7F5);
  static const Color darkBackground = Color(0xFF0E1513);
}

/// Light and dark themes for the whole app.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF6FD1AE) : AppColors.primary,
      onPrimary: isDark ? const Color(0xFF00382A) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF1F4A3E) : const Color(0xFFD7EBE3),
      onPrimaryContainer:
          isDark ? const Color(0xFFD7EBE3) : const Color(0xFF0B3A2F),
      error: isDark ? const Color(0xFFFF8A93) : AppColors.danger,
      onError: isDark ? const Color(0xFF4A0008) : Colors.white,
      surface: isDark ? const Color(0xFF16211D) : Colors.white,
      onSurface: isDark ? const Color(0xFFE6EDEA) : const Color(0xFF17211D),
      onSurfaceVariant:
          isDark ? const Color(0xFFA9B8B2) : const Color(0xFF5B6B65),
      outlineVariant:
          isDark ? const Color(0xFF2A3A34) : const Color(0xFFE1E6E3),
      surfaceContainerHighest:
          isDark ? const Color(0xFF1D2B26) : const Color(0xFFEEF1EF),
    );

    final background =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
