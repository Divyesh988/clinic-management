import 'package:clinic_mangement/doctor/account_suspended_screen.dart';
import 'package:clinic_mangement/firebase_options.dart';
import 'package:clinic_mangement/services/auth_service.dart';
import 'package:clinic_mangement/splash_screen.dart';
import 'package:clinic_mangement/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize global real-time auth and suspension listener immediately
  AuthService.initializeAuthListener();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the application resumes from background or becomes active,
    // authoritatively re-verify account authorization and suspension status.
    if (state == AppLifecycleState.resumed) {
      if (AuthService.isAuthenticated) {
        AuthService.revalidateActiveSession(forceServer: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AuthService.navigatorKey,
      title: 'CliniqCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: AuthService.isSuspendedNotifier,
          builder: (context, isSuspended, _) {
            if (kDebugMode) {
              debugPrint('[RootBuilder] Live state update: isSuspended=$isSuspended, childExists=${child != null}');
            }
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
      home: const SplashScreen(),
    );
  }
}

