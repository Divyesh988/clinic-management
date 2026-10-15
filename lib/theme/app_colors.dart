import 'package:flutter/material.dart';

/// Centralized color grading and palette definition for the Clinic Management application.
/// Based on the PRD Stitch Medical design system specifications.
class AppColors {
  AppColors._();

  // Primary & Healthcare Brand Colors
  static const Color primary = Color(0xFF0F766E); // Medical Teal
  static const Color primaryDark = Color(0xFF0B3B36); // Deep Forest Teal
  static const Color primaryContainer = Color(0xFF0C3833); // Dark Pill Teal
  static const Color primaryAccent = Color(0xFF14B8A6); // Mint Accent
  static const Color primarySurface = Color(0xFFE8F6F5); // Light mint wash
  static const Color primaryBorder = Color(0xFFCCEBE7); // Light teal border

  // Secondary Healthcare Accent
  static const Color secondary = Color(0xFF2563EB); // Healthcare Blue
  static const Color secondaryLight = Color(0xFFEFF6FF); // Soft blue tint
  static const Color secondaryPurple = Color(0xFF4F46E5); // Indigo/Purple for patient pulse

  // Backgrounds & Surfaces
  static const Color background = Color(0xFFF7FAFA); // Soft clinical off-white
  static const Color surface = Color(0xFFFFFFFF); // Card white
  static const Color surfaceVariant = Color(0xFFF1F5F9); // Light slate/pill background
  static const Color surfaceHover = Color(0xFFF8FAFC); // Subtle card hover

  // Text Hierarchy
  static const Color textPrimary = Color(0xFF172033); // Deep slate charcoal
  static const Color textSecondary = Color(0xFF64748B); // Slate grey
  static const Color textMuted = Color(0xFF94A3B8); // Light grey text
  static const Color textWhite = Color(0xFFFFFFFF); // Pure white

  // Status & Badges
  static const Color success = Color(0xFF16A34A); // Positive / Done / Confirmed
  static const Color successLight = Color(0xFFDCFCE7); // Light green pill
  static const Color successText = Color(0xFF15803D);

  static const Color warning = Color(0xFFD97706); // Warning / Expiring
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningText = Color(0xFFB45309);

  static const Color error = Color(0xFFDC2626); // Critical / Red
  static const Color errorLight = Color(0xFFFEE2E2); // Light red pill
  static const Color errorText = Color(0xFFB91C1C);

  static const Color info = Color(0xFF0284C7); // Waiting / Info
  static const Color infoLight = Color(0xFFE0F2FE); // Light info pill
  static const Color infoText = Color(0xFF0369A1);

  static const Color mintBadgeBg = Color(0xFFCCFBF1);
  static const Color mintBadgeText = Color(0xFF0F766E);

  // Borders & Dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFF1F5F9);

  // Shadows
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: const Color(0xFF0C3833).withValues(alpha: 0.25),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];
}
