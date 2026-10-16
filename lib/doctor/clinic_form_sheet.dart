import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/clinic_service.dart';
import '../theme/app_colors.dart';

/// Reusable modal sheet for adding or editing a Clinic location.
/// Persists directly to Firestore 'clinics' collection and ensures primary clinic state consistency.
Future<Map<String, dynamic>?> showAddEditClinicSheet(
  BuildContext context, {
  DocumentSnapshot? existing,
  Map<String, dynamic>? initialData,
}) async {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ClinicFormSheet(existing: existing, initialData: initialData),
  );
}

class _ClinicFormSheet extends StatefulWidget {
  final DocumentSnapshot? existing;
  final Map<String, dynamic>? initialData;

  const _ClinicFormSheet({this.existing, this.initialData});

  @override
  State<_ClinicFormSheet> createState() => _ClinicFormSheetState();
}

class _ClinicFormSheetState extends State<_ClinicFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _hoursCtrl;
  late bool _isPrimary;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? (widget.existing?.data() as Map<String, dynamic>?);
    _nameCtrl = TextEditingController(text: data?['name']?.toString() ?? '');
    _addressCtrl = TextEditingController(text: data?['address']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone']?.toString() ?? '');
    _feeCtrl = TextEditingController(text: (data?['consultationFee'] ?? 500).toString());
    _emailCtrl = TextEditingController(text: data?['email']?.toString() ?? '');
    _hoursCtrl = TextEditingController(
      text: data?['workingHours']?.toString() ?? 'Mon - Sat: 09:00 AM - 01:00 PM, 05:00 PM - 08:30 PM',
    );
    _isPrimary = data?['isPrimary'] == true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _feeCtrl.dispose();
    _emailCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveClinic() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final savedClinic = await ClinicService.saveClinic(
        docId: widget.existing?.id ?? widget.initialData?['docId']?.toString(),
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        consultationFee: double.tryParse(_feeCtrl.text.trim()) ?? 500.0,
        workingHours: _hoursCtrl.text.trim(),
        isPrimary: _isPrimary,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context, savedClinic);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error saving clinic. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isRequired = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: isRequired ? (v) => v == null || v.trim().isEmpty ? 'Required field' : null : null,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null && widget.initialData == null;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 14,
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNew ? 'Add New Clinic' : 'Edit Clinic Details',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const Text(
                        'Configure practice location details',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField('Clinic / Hospital Name *', _nameCtrl, Icons.apartment_rounded,
                        isRequired: true, hint: 'e.g. City Health Clinic'),
                    const SizedBox(height: 12),
                    _buildField('Full Address *', _addressCtrl, Icons.location_on_outlined,
                        isRequired: true, maxLines: 2, hint: 'e.g. Medical Arts Building, Suite 201'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField('Phone Number', _phoneCtrl, Icons.phone_outlined,
                              keyboardType: TextInputType.phone, hint: '+91 98765 43210'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildField('Consultation Fee (₹)', _feeCtrl, Icons.currency_rupee_rounded,
                              keyboardType: TextInputType.number, hint: '500'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildField('Official Email', _emailCtrl, Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress, hint: 'contact@clinic.com'),
                    const SizedBox(height: 12),
                    _buildField('OPD Working Hours', _hoursCtrl, Icons.access_time_rounded,
                        hint: 'e.g. Mon-Sat: 09:00 AM - 01:00 PM, 05:00 PM - 08:30 PM'),
                    const SizedBox(height: 14),

                    // Set as Primary switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Set as Primary Active Clinic',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                Text('New patients will default to this clinic',
                                    style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrimary,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _isPrimary = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveClinic,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isSaving
                              ? 'Saving Clinic...'
                              : (isNew ? 'Save Clinic' : 'Update Clinic'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
