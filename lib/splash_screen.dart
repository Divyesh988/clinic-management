import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'doctor/account_suspended_screen.dart';
import 'doctor/change_password_screen.dart';
import 'doctor/doctor_login_screen.dart';
import 'doctor/setup_wizard_screen.dart';
import 'mainshell.dart';
import 'models/app_version.dart';
import 'services/app_update_service.dart';
import 'services/auth_service.dart';
import 'services/clinic_service.dart';
import 'services/setup_service.dart';
import 'services/shorebird_update_service.dart';
import 'theme/app_colors.dart';

/// Doctor Practice Management Splash Screen
/// Displays clinical branding, initialization sequence, and navigates to the main shell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _progressController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _pulseAnimation;

  Timer? _statusTimer;
  int _currentStepIndex = 0;
  bool _hasNavigated = false;

  final List<String> _loadingSteps = [
    'Initializing clinical workspace...',
    'Connecting to multi-clinic network...',
    'Syncing centralized patient records...',
    'Preparing schedule & billing ledger...',
    'Ready. Welcome to your workspace',
  ];

  @override
  void initState() {
    super.initState();

    // 1. Entrance animation (Logo + Title fade & slight scale)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );

    // 2. Pulse heartbeat ring around the emblem
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // 3. Progress bar animation (0% -> 100% over 2.6 seconds)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _entranceController.forward();
    _progressController.forward();

    // Asynchronously check for application updates and OTA patches in background
    AppUpdateService.checkForUpdates().catchError((e) {
      debugPrint('[SplashScreen] Update check error: $e');
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.networkError,
        currentVersion: AppVersion(major: 1, minor: 0, patch: 0, buildNumber: 1, rawVersion: '1.0.0+1'),
      );
    });
    ShorebirdUpdateService.checkForPatch().then((hasPatch) {
      if (hasPatch) {
        ShorebirdUpdateService.downloadPatch();
      }
    }).catchError((e) {
      debugPrint('[SplashScreen] Shorebird patch check error: $e');
    });

    // Rotate status messages smoothly
    _statusTimer = Timer.periodic(const Duration(milliseconds: 550), (timer) {
      if (!mounted) return;
      if (_currentStepIndex < _loadingSteps.length - 1) {
        setState(() {
          _currentStepIndex++;
        });
      } else {
        timer.cancel();
      }
    });

    // Auto navigate after progress completes
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToHome();
      }
    });
  }

  Future<void> _navigateToHome() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Widget destination;
    try {
      // 1. Observe Authentication State & Restore Doctor Account
      final doctorAccount = await AuthService.restoreSession();

      if (AuthService.isCurrentSessionSuspended) {
        // Authoritatively suspended -> Route immediately to dedicated AccountSuspendedScreen
        destination = AccountSuspendedScreen(reason: AuthService.suspensionReason);
      } else if (doctorAccount == null || !doctorAccount.isActive) {
        // Not authenticated -> Route to SaaS Doctor Login Screen
        destination = const DoctorLoginScreen();
      } else if (doctorAccount.mustChangePassword) {
        // First login detected -> Require password change before unlocking EHR/clinic data
        destination = const ChangePasswordScreen();
      } else {
        // Authenticated & password set -> Verify clinic status strictly for the logged-in doctor
        final clinics = await ClinicService.getDoctorClinics();
        if (clinics.isEmpty) {
          destination = const SetupWizardScreen();
        } else {
          final status = await SetupService.checkSetupStatus(reconcileFirestore: false);
          destination = status.isComplete ? const mainshell() : const SetupWizardScreen();
        }
      }
    } catch (e) {
      debugPrint('Startup routing error in splash: $e');
      destination = const DoctorLoginScreen();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _entranceController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.height < 700;
    final horizontalPadding = (size.width * 0.06).clamp(16.0, 36.0);
    final verticalPadding = isCompact ? 12.0 : 20.0;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: GestureDetector(
        onTap: _navigateToHome, // Tap anywhere to fast-forward
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Gradient & Ambient Glow Orbs
            Positioned.fill(
              child: _buildBackground(),
            ),

            // Background subtle ECG Pulse Line watermark
            Positioned.fill(
              child: Opacity(
                opacity: 0.045,
                child: CustomPaint(
                  painter: _EcgLineBackgroundPainter(),
                ),
              ),
            ),

            // Main Foreground Content (Centered & Responsive)
            Positioned.fill(
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top Multi-Clinic Indicator
                        Center(child: _buildTopClinicBadge()),

                        Spacer(flex: isCompact ? 1 : 2),

                        // Centered Animated Emblem & Title
                        Center(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: ScaleTransition(
                              scale: _scaleAnimation,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildEmblem(isCompact: isCompact),
                                  SizedBox(height: isCompact ? 20 : 28),
                                  _buildAppTitle(),
                                  const SizedBox(height: 10),
                                  _buildSubtitle(),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Spacer(flex: isCompact ? 2 : 3),

                        // Progress Indicator & Status Message
                        Center(child: _buildProgressSection(size.width)),

                        SizedBox(height: isCompact ? 24 : 36),

                        // Bottom Compliance & Clinic Network Tag
                        Center(child: _buildFooter()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // BACKGROUND
  // ==========================================
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF062320), // Deepest forest teal
            Color(0xFF0A3732), // Medical deep teal
            Color(0xFF0F5751), // Mid teal
            Color(0xFF082E2A), // Shadow teal
          ],
          stops: [0.0, 0.45, 0.8, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Ambient Glow Orb - Top Right
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryAccent.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Ambient Glow Orb - Bottom Left
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TOP BADGE
  // ==========================================
  Widget _buildTopClinicBadge() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.primaryAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'DOCTOR PRACTICE SUITE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // EMBLEM WITH PULSING GLOW
  // ==========================================
  Widget _buildEmblem({bool isCompact = false}) {
    final cardSize = isCompact ? 76.0 : 88.0;
    final outerRing = isCompact ? 104.0 : 120.0;
    final innerRing = isCompact ? 94.0 : 108.0;
    final crossSize = isCompact ? 38.0 : 44.0;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outermost glowing pulse ring
            Container(
              width: outerRing * _pulseAnimation.value,
              height: outerRing * _pulseAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryAccent.withValues(
                  alpha: (0.16 * (1.25 - _pulseAnimation.value)).clamp(0.0, 1.0),
                ),
              ),
            ),

            // Inner subtle ring
            Container(
              width: innerRing,
              height: innerRing,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryAccent.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
            ),

            // Core Emblem Card
            Container(
              width: cardSize,
              height: cardSize,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF14B8A6), // Mint accent
                    Color(0xFF0F766E), // Medical teal
                    Color(0xFF0B4641), // Deep teal
                  ],
                ),
                borderRadius: BorderRadius.circular(isCompact ? 20 : 24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryAccent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: CustomPaint(
                  size: Size(crossSize, crossSize),
                  painter: _MedicalCrossPulsePainter(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // APP TITLE & SUBTITLE
  // ==========================================
  Widget _buildAppTitle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'CLINIQ',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryAccent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'CARE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFF062320),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Multi-Clinic Practice & Patient Intelligence',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Secure  •  Integrated  •  Cloud-Enabled',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppColors.primaryAccent.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PROGRESS & STATUS SECTION
  // ==========================================
  Widget _buildProgressSection(double screenWidth) {
    final barWidth = math.min(screenWidth * 0.55, 220.0).clamp(160.0, 240.0);

    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, child) {
        final progress = _progressController.value;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Smooth Progress Bar
            Container(
              width: barWidth,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: barWidth * progress,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primaryAccent,
                        Color(0xFF5EEAD4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryAccent.withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Live Cycling Loading Message
            SizedBox(
              width: math.min(screenWidth * 0.85, 340.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: child,
                ),
                child: Text(
                  _loadingSteps[_currentStepIndex],
                  key: ValueKey<int>(_currentStepIndex),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Tap to Skip hint
            Text(
              'Tap to skip',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.35),
                letterSpacing: 0.3,
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // FOOTER (SECURITY & VERSION)
  // ==========================================
  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 5),
            Text(
              'HIPAA & NABH Ready • 256-Bit Encrypted',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'v1.0.0',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CUSTOM PAINTER: MEDICAL CROSS WITH ECG PULSE LINE
// ============================================================================
class _MedicalCrossPulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Draw Cross
    final crossPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const double barWidth = 10.0;
    const double barLength = 34.0;
    final double radius = 3.5;

    // Vertical Bar
    final vRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, h / 2),
        width: barWidth,
        height: barLength,
      ),
      Radius.circular(radius),
    );
    canvas.drawRRect(vRect, crossPaint);

    // Horizontal Bar
    final hRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, h / 2),
        width: barLength,
        height: barWidth,
      ),
      Radius.circular(radius),
    );
    canvas.drawRRect(hRect, crossPaint);

    // ECG Heartbeat Overlay Line
    final ecgPaint = Paint()
      ..color = const Color(0xFF0F766E)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final ecgPath = Path();
    final double cy = h / 2;

    ecgPath.moveTo(w * 0.18, cy);
    ecgPath.lineTo(w * 0.36, cy);
    ecgPath.lineTo(w * 0.42, cy - 7);
    ecgPath.lineTo(w * 0.50, cy + 8);
    ecgPath.lineTo(w * 0.58, cy - 9);
    ecgPath.lineTo(w * 0.64, cy);
    ecgPath.lineTo(w * 0.82, cy);

    canvas.drawPath(ecgPath, ecgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// BACKGROUND ECG WATERMARK
// ============================================================================
class _EcgLineBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final path = Path();
    final y = size.height * 0.55;
    final w = size.width;

    path.moveTo(0, y);
    path.lineTo(w * 0.20, y);
    path.lineTo(w * 0.24, y - 25);
    path.lineTo(w * 0.28, y + 35);
    path.lineTo(w * 0.32, y - 55);
    path.lineTo(w * 0.36, y + 20);
    path.lineTo(w * 0.40, y);
    path.lineTo(w * 0.65, y);
    path.lineTo(w * 0.69, y - 30);
    path.lineTo(w * 0.73, y + 45);
    path.lineTo(w * 0.77, y - 60);
    path.lineTo(w * 0.81, y + 15);
    path.lineTo(w * 0.85, y);
    path.lineTo(w, y);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
