import 'package:clinic_mangement/doctor/account_suspended_screen.dart';
import 'package:clinic_mangement/services/auth_models.dart';
import 'package:clinic_mangement/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Real-Time Suspension Logic & Session Enforcement Tests', () {
    test('Suspended status parsing handles both uppercase and lowercase variations', () {
      expect(DoctorAccountStatus.fromString('SUSPENDED'), DoctorAccountStatus.suspended);
      expect(DoctorAccountStatus.fromString('suspended'), DoctorAccountStatus.suspended);
      expect(DoctorAccountStatus.fromString(' Suspended '), DoctorAccountStatus.suspended);
    });

    test('Missing or unknown account status must never evaluate to active', () {
      expect(DoctorAccountStatus.fromString(null), isNot(DoctorAccountStatus.active));
      expect(DoctorAccountStatus.fromString(''), isNot(DoctorAccountStatus.active));
      expect(DoctorAccountStatus.fromString('CLOSED'), isNot(DoctorAccountStatus.active));
      expect(DoctorAccountStatus.fromString('random_value'), isNot(DoctorAccountStatus.active));
    });

    test('DoctorAccount properly identifies suspended state vs active state', () {
      const activeDoctor = DoctorAccount(
        uid: 'doc_1',
        email: 'doc1@example.com',
        displayName: 'Dr. Active',
        accountStatus: DoctorAccountStatus.active,
      );

      const suspendedDoctor = DoctorAccount(
        uid: 'doc_2',
        email: 'doc2@example.com',
        displayName: 'Dr. Suspended',
        accountStatus: DoctorAccountStatus.suspended,
        suspensionReason: 'Administrative review pending',
      );

      const inactiveDoctor = DoctorAccount(
        uid: 'doc_3',
        email: 'doc3@example.com',
        displayName: 'Dr. Inactive',
        accountStatus: DoctorAccountStatus.inactive,
      );

      expect(activeDoctor.isActive, isTrue);
      expect(activeDoctor.isSuspended, isFalse);

      expect(suspendedDoctor.isActive, isFalse);
      expect(suspendedDoctor.isSuspended, isTrue);
      expect(suspendedDoctor.suspensionReason, 'Administrative review pending');

      expect(inactiveDoctor.isActive, isFalse);
      expect(inactiveDoctor.isSuspended, isFalse);
    });

    test('AuthService exposes suspension state via notifier', () {
      expect(AuthService.isSuspendedNotifier.value, isFalse);
      expect(AuthService.isCurrentSessionSuspended, isFalse);
    });

    test('SaaS customer status parsing simulation', () {
      // Simulating the dual-check logic implemented in AuthService
      bool isSaaSCustomerAuthorized(String? customerAccountStatus, DoctorAccountStatus doctorStatus) {
        if (doctorStatus != DoctorAccountStatus.active) return false;
        if (customerAccountStatus == null) return true; // standalone doctor
        final normalized = customerAccountStatus.trim().toUpperCase();
        return normalized == 'ACTIVE';
      }

      // Both active
      expect(isSaaSCustomerAuthorized('ACTIVE', DoctorAccountStatus.active), isTrue);

      // Customer suspended from website while doctor doc was active
      expect(isSaaSCustomerAuthorized('SUSPENDED', DoctorAccountStatus.active), isFalse);

      // Customer closed
      expect(isSaaSCustomerAuthorized('CLOSED', DoctorAccountStatus.active), isFalse);

      // Doctor doc suspended while customer was active
      expect(isSaaSCustomerAuthorized('ACTIVE', DoctorAccountStatus.suspended), isFalse);
    });

    testWidgets('Root-level builder Stack reactively shields active screens upon suspension', (tester) async {
      AuthService.isSuspendedNotifier.value = false;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AuthService.navigatorKey,
          builder: (context, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: AuthService.isSuspendedNotifier,
              builder: (context, isSuspended, _) {
                return Stack(
                  children: [
                    ?child,
                    if (isSuspended)
                      Positioned.fill(
                        child: PopScope(
                          canPop: false,
                          child: AccountSuspendedScreen(
                            reason: AuthService.suspensionReason,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
          home: const Scaffold(
            body: Center(child: Text('Protected Clinical Dashboard')),
          ),
        ),
      );

      // Initially active dashboard is visible, suspended screen is not
      expect(find.text('Protected Clinical Dashboard'), findsOneWidget);
      expect(find.text('Account Suspended'), findsNothing);

      // Trigger suspension in real time
      AuthService.isSuspendedNotifier.value = true;
      await tester.pump();

      // Suspended screen is immediately rendered on top, shielding clinical data
      expect(find.text('Account Suspended'), findsOneWidget);
      expect(find.text('Check Status / Refresh'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);

      // Reactivate account
      AuthService.isSuspendedNotifier.value = false;
      await tester.pump();

      // Suspended screen removed, active dashboard restored
      expect(find.text('Account Suspended'), findsNothing);
      expect(find.text('Protected Clinical Dashboard'), findsOneWidget);
    });
  });
}
