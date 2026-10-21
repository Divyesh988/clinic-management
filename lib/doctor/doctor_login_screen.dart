import 'package:flutter/material.dart';
import '../mainshell.dart';
import '../services/app_update_service.dart';
import '../services/auth_service.dart';
import '../services/clinic_service.dart';
import '../services/setup_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import 'account_suspended_screen.dart';
import 'change_password_screen.dart';
import 'setup_wizard_screen.dart';

/// Professional Healthcare SaaS Doctor Login Screen.
/// Provides responsive desktop/tablet/mobile layouts, Firebase Authentication,
/// account status validation, password visibility toggling, and password reset.
class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    AppUpdateService.updateResultNotifier.addListener(_onUpdateResult);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.showOptionalDialogIfAvailable(context);
      }
    });
  }

  void _onUpdateResult() {
    if (mounted) {
      AppUpdateService.showOptionalDialogIfAvailable(context);
    }
  }

  @override
  void dispose() {
    AppUpdateService.updateResultNotifier.removeListener(_onUpdateResult);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    // Clear previous error
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // 1. Authenticate with Firebase & Verify Account in Firestore
      final doctorAccount = await AuthService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // 2. Mandatory First-Login Password Change Check
      if (doctorAccount.mustChangePassword) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (context, animation, secondaryAnimation) =>
                const ChangePasswordScreen(),
            transitionsBuilder: (context, anim, secondaryAnimation, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
        return;
      }

      // 3. Check if the doctor has registered clinics or requires first-time setup
      Widget destination;
      try {
        final clinics = await ClinicService.getDoctorClinics();
        if (clinics.isEmpty) {
          destination = const SetupWizardScreen();
        } else {
          final setupStatus = await SetupService.checkSetupStatus(reconcileFirestore: false);
          destination = setupStatus.isComplete ? const mainshell() : const SetupWizardScreen();
        }
      } catch (e) {
        debugPrint('Error evaluating clinic setup after login: $e');
        destination = const mainshell();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Welcome back, ${doctorAccount.displayName}!'),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondaryAnimation) => destination,
          transitionsBuilder: (context, anim, secondaryAnimation, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
      if (e.message.toLowerCase().contains('suspended')) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountSuspendedScreen(reason: e.message),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected sign in error occurred: $e';
        _isLoading = false;
      });
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    bool isResetting = false;
    String? resetError;
    String? resetSuccess;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Reset Password',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your registered doctor email address. We will send a secure password reset link to your inbox.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Registered Doctor Email',
                    hintText: 'doctor@clinic.com',
                    prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                if (resetError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    resetError!,
                    style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ],
                if (resetSuccess != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.successText, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            resetSuccess!,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.successText, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isResetting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isResetting
                    ? null
                    : () async {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          setDialogState(() => resetError = 'Please enter a valid email.');
                          return;
                        }

                        setDialogState(() {
                          isResetting = true;
                          resetError = null;
                          resetSuccess = null;
                        });

                        try {
                          await AuthService.sendPasswordResetEmail(email);
                          setDialogState(() {
                            isResetting = false;
                            resetSuccess = 'Password reset email sent! Check your inbox.';
                          });
                        } catch (e) {
                          setDialogState(() {
                            isResetting = false;
                            resetError = e.toString();
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isResetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send Reset Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // DESKTOP TWO-COLUMN LAYOUT
  // ==========================================

  Widget _buildDesktopLayout() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1040),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Left Value-Proposition Panel
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(48),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF062320),
                    Color(0xFF0A3732),
                    Color(0xFF0F5751),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBrandHeader(isLightMode: false),
                  const SizedBox(height: 36),
                  const Text(
                    'Unified Clinical Practice & EHR Intelligence',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Engineered specifically for medical practitioners managing single or multi-clinic practices, longitudinal patient records, and real-time ledgers.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildFeatureBullet(Icons.hub_rounded, 'Multi-Clinic Isolated Practice Workspaces'),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(Icons.timeline_rounded, 'Longitudinal EHR & Consultation Encounters'),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(Icons.medical_information_rounded, 'Predefined Medicine Catalogue & Instant Rx'),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(Icons.security_rounded, '256-Bit Encrypted & Tenant Isolated Data'),
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 6),
                      Text(
                        'NABH & HIPAA Compliant Data Infrastructure',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Right Login Form Card
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 48),
              child: _buildLoginForm(),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MOBILE / TABLET SINGLE-COLUMN LAYOUT
  // ==========================================

  Widget _buildMobileLayout() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBrandHeader(isLightMode: true),
          const SizedBox(height: 28),
          _buildLoginForm(),
        ],
      ),
    );
  }

  // ==========================================
  // REUSABLE LOGIN FORM
  // ==========================================

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Welcome Back, Doctor',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to manage your clinics, patients, and medical records.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),

          // Error Alert Banner
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: AppColors.errorText, fontWeight: FontWeight.w600),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _errorMessage = null),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.errorText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Email Field
          const Text(
            'DOCTOR EMAIL ADDRESS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'doctor@clinic.com',
              prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.primary, size: 19),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter your doctor email.';
              if (!v.contains('@') || !v.contains('.')) return 'Please enter a valid email address.';
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Password Field
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PASSWORD',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: _isLoading ? null : _showForgotPasswordDialog,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '••••••••••••',
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 19),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter your password.';
              if (v.trim().length < 6) return 'Password must be at least 6 characters.';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Remember Me Checkbox
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _rememberMe,
                  activeColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) => setState(() => _rememberMe = val ?? true),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Remember my doctor session',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Primary Sign In Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleSignIn,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.login_rounded, size: 18, color: Colors.white),
              label: Text(
                _isLoading ? 'Verifying Doctor Credentials...' : 'Sign In to Workspace',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Security Subtext
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Text(
                  'End-to-End Encrypted Doctor Session',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BRAND HEADER & VALUE HELPERS
  // ==========================================

  Widget _buildBrandHeader({required bool isLightMode}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 40),
        const SizedBox(width: 10),
        Row(
          children: [
            Text(
              'CLINIQ',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isLightMode ? AppColors.textPrimary : Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryAccent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'CARE',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Color(0xFF062320),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}
