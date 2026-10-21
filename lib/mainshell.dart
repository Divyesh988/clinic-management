import 'package:clinic_mangement/doctor/analytics.dart';
import 'package:clinic_mangement/doctor/dashboard.dart';
import 'package:clinic_mangement/doctor/doctor_profile.dart';
import 'package:clinic_mangement/doctor/patients.dart';
import 'package:clinic_mangement/services/app_update_service.dart';
import 'package:flutter/material.dart';

import 'navigationbar.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;
  @override
  State<MainShell> createState() => _MainShellState();
}

// Backwards compatibility alias
// ignore: camel_case_types
typedef mainshell = MainShell;

class _MainShellState extends State<MainShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4);
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
    super.dispose();
  }

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _index,
        children: [
          Dashboard(onNavigateTab: (i) => setState(() => _index = i)),
          const Patients(),
          const Analytics(),
          const DoctorProfile(),
        ],
      ),
      bottomNavigationBar: AppNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
