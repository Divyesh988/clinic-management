import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../mainshell.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'doctor_login_screen.dart';

/// Dedicated Account Suspended Screen.
/// Rendered immediately when a doctor's account is suspended by Master Admin.
/// Blocks all protected clinical routes, disables back navigation, and provides
/// real-time status revalidation and controlled sign out.
class AccountSuspendedScreen extends StatefulWidget {
  final String? reason;

  const AccountSuspendedScreen({
    super.key,
    this.reason,
  });

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  bool _isCheckingStatus = false;
  bool _isSigningOut = false;

  Future<void> _checkAccountStatus() async {
    if (_isCheckingStatus) return;
    setState(() => _isCheckingStatus = true);

    try {
      final account = await AuthService.revalidateActiveSession(forceServer: true);
      if (!mounted) return;

      if (account != null && account.isActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account has been reactivated! Welcome back.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        final nav = AuthService.navigatorKey.currentState ?? Navigator.of(context);
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const mainshell()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account is still suspended by administrator.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to verify account status. Please check your internet connection.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingStatus = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);

    try {
      await AuthService.signOut();
      if (!mounted) return;

      final nav = AuthService.navigatorKey.currentState ?? Navigator.of(context);
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DoctorLoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error signing out. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  void _copySupportEmail() {
    Clipboard.setData(const ClipboardData(text: 'support@cliniqcare.com'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied: support@cliniqcare.com'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAccount = AuthService.currentAccount;
    final displayReason = widget.reason ??
        currentAccount?.suspensionReason ??
        AuthService.suspensionReason;

    debugPrint('[AccountSuspendedScreen] Rendering AccountSuspendedScreen with reason: "$displayReason"');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Alert Icon Badge
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFECACA), width: 2),
                        ),
                        child: const Icon(
                          Icons.lock_person_rounded,
                          size: 38,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      const Text(
                        'Account Suspended',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Main Mandatory Explanatory Message
                      const Text(
                        'Your CliniqCare account has been suspended by the platform administrator. Access to clinical features is currently unavailable. Please contact CliniqCare support or your administrator for assistance.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Account detail chip
                      if (currentAccount != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_circle_outlined, size: 20, color: AppColors.textSecondary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentAccount.displayName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      currentAccount.email,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Suspended',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB91C1C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Optional Suspension Reason Banner
                      if (displayReason != null && displayReason.trim().isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notice: $displayReason',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Support Contact Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Administrator Support Contact',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _copySupportEmail,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mail_outline_rounded, size: 18, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'support@cliniqcare.com',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Action Buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isCheckingStatus ? null : _checkAccountStatus,
                          icon: _isCheckingStatus
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                          label: Text(
                            _isCheckingStatus ? 'Checking Status...' : 'Check Status / Refresh',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSigningOut ? null : _handleSignOut,
                          icon: _isSigningOut
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                                )
                              : const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC2626)),
                          label: Text(
                            _isSigningOut ? 'Signing Out...' : 'Sign Out',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
