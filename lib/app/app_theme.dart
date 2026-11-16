import 'package:flutter/material.dart';

/// Fixed brand and meaning colors. Green = good, red = danger or loss,
/// amber = needs attention.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF145C4A);
  static const Color primaryLight = Color(0xFF1B7A62);
  static const Color primaryDark = Color(0xFF0E4034);
  static const Color success = Color(0xFF18794E);
  static const Color danger = Color(0xFFB4232F);
  static const Color attention = Color(0xFFA15C08);
  static const Color lightBackground = Color(0xFFF6F7F5);
  static const Color lightText = Color(0xFF14201C);

  static const Color darkBackground = Color(0xFF0D1311);
  static const Color darkCard = Color(0xFF151D1A);
  static const Color darkBorder = Color(0xFF26322D);
  static const Color darkText = Color(0xFFEAF2EE);
  static const Color darkPrimary = Color(0xFF4FD1A5);
  static const Color darkWarning = Color(0xFFF0B25A);
  static const Color darkDanger = Color(0xFFFF8F96);
}

/// Light and dark themes for the whole app.
class AppTheme {
  const AppTheme._();

  /// The person's choice of light or dark. Starts by following the device.
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.darkPrimary : AppColors.primary,
      onPrimary: isDark ? const Color(0xFF00382A) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF1F4A3E) : const Color(0xFFDDEEE8),
      onPrimaryContainer:
          isDark ? const Color(0xFFD7EBE3) : const Color(0xFF0B3A2F),
      error: isDark ? AppColors.darkDanger : AppColors.danger,
      onError: isDark ? const Color(0xFF4A0008) : Colors.white,
      surface: isDark ? AppColors.darkCard : Colors.white,
      onSurface: isDark ? AppColors.darkText : AppColors.lightText,
      onSurfaceVariant:
          isDark ? const Color(0xFFA9B8B2) : const Color(0xFF5B6B65),
      outlineVariant: isDark ? AppColors.darkBorder : const Color(0xFFE3E8E5),
      surfaceContainerHighest:
          isDark ? const Color(0xFF1D2925) : const Color(0xFFF0F3F1),
    );

    final background =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
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
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
