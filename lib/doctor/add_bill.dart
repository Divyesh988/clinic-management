import 'package:flutter/material.dart';

class AddBill extends StatefulWidget {
  const AddBill({super.key});

  @override
  State<AddBill> createState() => _AddBillState();
}

class _AddBillState extends State<AddBill> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Add Bill')),
    );
  }
}

// Backwards compatibility alias
// ignore: camel_case_types
typedef addbill = AddBill;
