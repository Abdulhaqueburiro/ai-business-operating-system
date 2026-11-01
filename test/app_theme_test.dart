import 'package:ai_business_os/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Light theme uses the brand colors', () {
    final theme = AppTheme.light();
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.error, AppColors.danger);
    expect(theme.scaffoldBackgroundColor, AppColors.lightBackground);
    expect(theme.colorScheme.brightness, Brightness.light);
  });

  test('Dark theme is dark and uses the dark background', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.darkBackground);
  });
}
