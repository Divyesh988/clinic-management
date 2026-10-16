import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clinic_mangement/doctor/account_suspended_screen.dart';

void main() {
  testWidgets('AccountSuspendedScreen displays critical suspension UI elements', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountSuspendedScreen(
          reason: 'Subscription non-payment',
        ),
      ),
    );

    // Verify Title
    expect(find.text('Account Suspended'), findsOneWidget);

    // Verify Mandatory Explanatory Message
    expect(
      find.text(
        'Your CliniqCare account has been suspended by the platform administrator. Access to clinical features is currently unavailable. Please contact CliniqCare support or your administrator for assistance.',
      ),
      findsOneWidget,
    );

    // Verify Notice Reason
    expect(find.text('Notice: Subscription non-payment'), findsOneWidget);

    // Verify Support Contact
    expect(find.text('support@cliniqcare.com'), findsOneWidget);

    // Verify Action Buttons
    expect(find.text('Check Status / Refresh'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.byIcon(Icons.lock_person_rounded), findsOneWidget);
  });
}
