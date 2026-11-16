import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_business_os/app/app.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> openMore(WidgetTester tester) async {
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone: home shows greeting, shortcuts and bottom bar', (
    WidgetTester tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('Assalam-o-alaikum'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('New order'), findsOneWidget);
    expect(find.text('Shortcuts'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.textContaining('only visible to the owner'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    expect(find.text('Flutter Demo Home Page'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('wide screen: top bar replaces the bottom bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('AI Business OS'), findsOneWidget);
    expect(find.text('Assalam-o-alaikum'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('system status shows the backend message in More', (
    WidgetTester tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(const App());
    await openMore(tester);

    await tester.ensureVisible(find.text('System status'));
    expect(find.text('System status'), findsOneWidget);
    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
  });

  testWidgets('application displays a safe initialization failure status', (
    WidgetTester tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
      const App(
        backendStatusMessage:
            'Supabase client initialization failed. Check the launch '
            'configuration and restart. The backend connection is unverified.',
      ),
    );
    await openMore(tester);

    expect(
      find.textContaining('Supabase client initialization failed'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-value'), findsNothing);
  });

  testWidgets(
    'connection check moves from not tested to testing to connected',
    (WidgetTester tester) async {
      usePhoneScreen(tester);
      final response = Completer<SupabaseConnectionResult>();
      await tester.pumpWidget(
        App(testSupabaseConnection: () => response.future),
      );
      await openMore(tester);

      expect(
        find.text('Auth service availability: Not tested'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Check Auth Service Availability'));
      await tester.tap(find.text('Check Auth Service Availability'));
      await tester.pump();

      expect(find.text('Auth service availability: Testing'), findsOneWidget);

      response.complete(
        const SupabaseConnectionResult(
          status: SupabaseConnectionStatus.connected,
          message:
              'Auth service responded with HTTP 200. This confirms Auth '
              'service availability only; it does not verify publishable API '
              'key validity, database connectivity, or RLS access.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Auth service availability: Connected'), findsOneWidget);
      expect(
        find.textContaining('Auth service availability only'),
        findsOneWidget,
      );
    },
  );

  testWidgets('connection failure status displays safe error text', (
    WidgetTester tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
      App(
        testSupabaseConnection: () async => const SupabaseConnectionResult(
          status: SupabaseConnectionStatus.failed,
          message: 'Connection timed out. Check your network and try again.',
        ),
      ),
    );
    await openMore(tester);

    await tester.ensureVisible(find.text('Check Auth Service Availability'));
    await tester.tap(find.text('Check Auth Service Availability'));
    await tester.pumpAndSettle();

    expect(
      find.text('Auth service availability: Connection failed'),
      findsOneWidget,
    );
    expect(find.textContaining('Connection timed out'), findsOneWidget);
    expect(find.textContaining('publishable-key'), findsNothing);
  });

  testWidgets('Products screen shows database-backed UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Products'));
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Saved products'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.textContaining('Saved products'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Could not load products.'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.text('Could not load products.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('Unit label'), findsOneWidget);
    expect(find.text('Save product'), findsOneWidget);
  });
}
