import 'package:clinic_mangement/doctor/analytics.dart';
import 'package:clinic_mangement/doctor/dashboard.dart';
import 'package:clinic_mangement/doctor/doctor_profile.dart';
import 'package:clinic_mangement/doctor/patients.dart';
import 'package:flutter/material.dart';

import 'navigationbar.dart';

class mainshell extends StatefulWidget {
  const mainshell({super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;
  @override
  State<mainshell> createState() => _mainshellState();
}

class _mainshellState extends State<mainshell> {

  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4);
  }

  @override
  void didUpdateWidget(mainshell oldWidget) {
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
          dashboard(onNavigateTab: (i) => setState(() => _index = i)),
          const patients(),
          const analytics(),
          const doctor_profile(),
        ],
      ),
      bottomNavigationBar: navigationbar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
