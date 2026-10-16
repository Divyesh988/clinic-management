import 'package:flutter/material.dart';

/// Official CliniqCare App Logo widget matching the splash screen branding.
/// Consists of a teal gradient rounded card, white medical cross, and
/// teal ECG heartbeat pulse line.
class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showShadow;

  const AppLogo({
    super.key,
    this.size = 40.0,
    double? borderRadius,
    this.showShadow = true,
  }) : borderRadius = borderRadius ?? (size * 0.25);

  @override
  Widget build(BuildContext context) {
    final crossSize = size * 0.5;

    return Container(
      width: size,
      height: size,
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
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
                  blurRadius: size * 0.25,
                  offset: Offset(0, size * 0.08),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: size * 0.12,
                  offset: Offset(0, size * 0.04),
                ),
              ]
            : null,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: (size * 0.02).clamp(1.0, 2.0),
        ),
      ),
      child: Center(
        child: CustomPaint(
          size: Size(crossSize, crossSize),
          painter: const AppLogoCrossPainter(),
        ),
      ),
    );
  }
}

/// Custom painter for the CliniqCare medical cross with ECG pulse overlay.
class AppLogoCrossPainter extends CustomPainter {
  const AppLogoCrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Proportional dimensions based on splash screen ratio (10 / 34 / 44)
    final double barWidth = w * (10.0 / 44.0);
    final double barLength = w * (34.0 / 44.0);
    final double radius = barWidth * 0.35;

    final crossPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

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
      ..strokeWidth = (w * 0.06).clamp(1.5, 3.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final ecgPath = Path();
    final double cy = h / 2;

    ecgPath.moveTo(w * 0.18, cy);
    ecgPath.lineTo(w * 0.36, cy);
    ecgPath.lineTo(w * 0.42, cy - (h * 0.16));
    ecgPath.lineTo(w * 0.50, cy + (h * 0.18));
    ecgPath.lineTo(w * 0.58, cy - (h * 0.20));
    ecgPath.lineTo(w * 0.64, cy);
    ecgPath.lineTo(w * 0.82, cy);

    canvas.drawPath(ecgPath, ecgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
