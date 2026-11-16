import 'package:ai_business_os/app/app.dart';
import 'package:ai_business_os/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bottom bar opens More, dark mode switch works', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() => AppTheme.mode.value = ThemeMode.system);

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('Assalam-o-alaikum'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(AppTheme.mode.value, ThemeMode.dark);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Assalam-o-alaikum'), findsOneWidget);
  });
}
