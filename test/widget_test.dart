// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_business_os/app/app.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';

void main() {
  testWidgets('application shell shows placeholder workspace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());

    expect(find.text('AI Business OS'), findsOneWidget);
    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
    expect(find.text('Your business workspace'), findsOneWidget);
    expect(find.text('Workspace areas'), findsOneWidget);
    expect(
      find.textContaining('not connected to business data'),
      findsOneWidget,
    );
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Orders and fulfillment'), findsOneWidget);
    expect(find.text('Payments and reports'), findsOneWidget);

    expect(find.text('Flutter Demo Home Page'), findsNothing);
    expect(
      find.text('You have pushed the button this many times:'),
      findsNothing,
    );
    expect(find.text('0'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('application displays a safe initialization failure status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const App(
        backendStatusMessage:
            'Supabase client initialization failed. Check the launch '
            'configuration and restart. The backend connection is unverified.',
      ),
    );

    expect(
      find.textContaining('Supabase client initialization failed'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-value'), findsNothing);
  });

  testWidgets(
    'connection check moves from not tested to testing to connected',
    (WidgetTester tester) async {
      final response = Completer<SupabaseConnectionResult>();
      await tester.pumpWidget(
        App(testSupabaseConnection: () => response.future),
      );

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
    await tester.pumpWidget(
      App(
        testSupabaseConnection: () async => const SupabaseConnectionResult(
          status: SupabaseConnectionStatus.failed,
          message: 'Connection timed out. Check your network and try again.',
        ),
      ),
    );

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

    await tester.ensureVisible(find.text('Products'));
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Business products'), findsOneWidget);
    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('Unit label'), findsOneWidget);
    expect(find.text('Save product'), findsOneWidget);
    expect(find.textContaining('Saved products'), findsOneWidget);
    expect(find.text('Could not load products.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
