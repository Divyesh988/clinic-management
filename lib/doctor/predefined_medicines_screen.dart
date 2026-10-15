import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class PredefinedMedicinesScreen extends StatefulWidget {
  const PredefinedMedicinesScreen({super.key});

  @override
  State<PredefinedMedicinesScreen> createState() => _PredefinedMedicinesScreenState();
}

class _PredefinedMedicinesScreenState extends State<PredefinedMedicinesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTypeFilter = 'All';
  bool _isLoading = false;

  final List<String> _medicineTypes = const [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Ointment',
    'Drops',
    'Inhaler',
    'Powder',
  ];

  static const List<Map<String, dynamic>> _starterMedicines = [
    {'name': 'Paracetamol 500mg', 'type': 'Tablet', 'dosage': '1-0-1', 'duration': '5 Days', 'fee': 40.0, 'genericName': 'Acetaminophen'},
    {'name': 'Amoxicillin 500mg', 'type': 'Capsule', 'dosage': '1-0-1', 'duration': '5 Days', 'fee': 90.0, 'genericName': 'Amoxicillin Trihydrate'},
    {'name': 'Azithromycin 500mg', 'type': 'Tablet', 'dosage': '1-0-0', 'duration': '3 Days', 'fee': 120.0, 'genericName': 'Azithromycin'},
    {'name': 'Cetirizine 10mg', 'type': 'Tablet', 'dosage': '0-0-1', 'duration': '5 Days', 'fee': 35.0, 'genericName': 'Cetirizine HCl'},
    {'name': 'Pantoprazole 40mg', 'type': 'Tablet', 'dosage': '1-0-0', 'duration': '7 Days', 'fee': 75.0, 'genericName': 'Pantoprazole Sodium'},
    {'name': 'Metformin 500mg', 'type': 'Tablet', 'dosage': '1-0-1', 'duration': '30 Days', 'fee': 85.0, 'genericName': 'Metformin HCl'},
    {'name': 'Telmisartan 40mg', 'type': 'Tablet', 'dosage': '1-0-0', 'duration': '30 Days', 'fee': 110.0, 'genericName': 'Telmisartan'},
    {'name': 'Benadryl Cough Syrup', 'type': 'Syrup', 'dosage': '1-1-1 (10ml)', 'duration': '5 Days', 'fee': 130.0, 'genericName': 'Diphenhydramine'},
    {'name': 'ORS Electrolyte Powder', 'type': 'Powder', 'dosage': 'SOS (1 Packet/L)', 'duration': '3 Days', 'fee': 25.0, 'genericName': 'Oral Rehydration Salts'},
    {'name': 'Ciprofloxacin Eye Drops', 'type': 'Drops', 'dosage': '2 drops (4 times)', 'duration': '5 Days', 'fee': 60.0, 'genericName': 'Ciprofloxacin'},
    {'name': 'Diclofenac Gel 30g', 'type': 'Ointment', 'dosage': 'Apply twice daily', 'duration': '7 Days', 'fee': 95.0, 'genericName': 'Diclofenac Diethylamine'},
    {'name': 'Salbutamol Inhaler 100mcg', 'type': 'Inhaler', 'dosage': '2 puffs SOS', 'duration': '30 Days', 'fee': 180.0, 'genericName': 'Salbutamol'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================
  // ADD / EDIT SINGLE MEDICINE
  // ==========================================
  void _showAddEditMedicineDialog([Map<String, dynamic>? existing, String? docId]) {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final genericCtrl = TextEditingController(text: existing?['genericName']?.toString() ?? '');
    final dosageCtrl = TextEditingController(text: existing?['dosage']?.toString() ?? '1-0-1');
    final durationCtrl = TextEditingController(text: existing?['duration']?.toString() ?? '5 Days');
    final feeCtrl = TextEditingController(text: existing?['fee']?.toString() ?? '50');
    String type = existing?['type']?.toString() ?? 'Tablet';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.medication_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    existing == null ? 'Add Predefined Medicine' : 'Edit Medicine',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Medicine Name *',
                          hintText: 'e.g. Paracetamol 650mg',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: genericCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Generic Formula / Composition',
                          hintText: 'e.g. Acetaminophen',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _medicineTypes.contains(type) ? type : 'Tablet',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Formulation Type',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _medicineTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setModalState(() => type = v!),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: dosageCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Dosage',
                                hintText: '1-0-1',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: durationCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Duration',
                                hintText: '5 Days',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: feeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Default Fee / Price (₹)',
                          hintText: '50',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(ctx);
                  final data = {
                    'name': nameCtrl.text.trim(),
                    'genericName': genericCtrl.text.trim(),
                    'type': type,
                    'dosage': dosageCtrl.text.trim().isEmpty ? '1-0-1' : dosageCtrl.text.trim(),
                    'duration': durationCtrl.text.trim().isEmpty ? '5 Days' : durationCtrl.text.trim(),
                    'fee': double.tryParse(feeCtrl.text.trim()) ?? 0.0,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    if (docId != null) {
                      await FirebaseFirestore.instance.collection('predefined_medicines').doc(docId).update(data);
                    } else {
                      data['createdAt'] = FieldValue.serverTimestamp();
                      await FirebaseFirestore.instance.collection('predefined_medicines').add(data);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${nameCtrl.text.trim()} saved to formulary!'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save error: $e'), backgroundColor: AppColors.error),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Save Medicine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // CONFIRM DELETE MEDICINE
  // ==========================================
  Future<void> _confirmDeleteMedicine(String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Medicine?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to remove "$name" from your predefined medicine formulary?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('predefined_medicines').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted $name'), backgroundColor: AppColors.primaryContainer),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  // ==========================================
  // SEED STARTER FORMULARY
  // ==========================================
  Future<void> _seedStarterMedicines() async {
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('predefined_medicines');

      for (final med in _starterMedicines) {
        final docRef = collection.doc();
        batch.set(docRef, {
          ...med,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standard clinical formulary loaded (12 medicines)!'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seed failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ==========================================
  // BULK IMPORT MODAL (EXCEL / CSV / PASTE)
  // ==========================================
  void _showBulkImportModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return BulkImportSheet(
          onMedicinesImported: (imported) async {
            Navigator.pop(ctx);
            await _saveImportedMedicines(imported);
          },
          onSeedDefaults: () {
            Navigator.pop(ctx);
            _seedStarterMedicines();
          },
        );
      },
    );
  }

  Future<void> _saveImportedMedicines(List<Map<String, dynamic>> medicines) async {
    if (medicines.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final collection = FirebaseFirestore.instance.collection('predefined_medicines');
      final batch = FirebaseFirestore.instance.batch();

      for (final m in medicines) {
        final doc = collection.doc();
        batch.set(doc, {
          'name': m['name'] ?? 'Unnamed Medicine',
          'genericName': m['genericName'] ?? '',
          'type': m['type'] ?? 'Tablet',
          'dosage': m['dosage'] ?? '1-0-1',
          'duration': m['duration'] ?? '5 Days',
          'fee': (m['fee'] as num?)?.toDouble() ?? 50.0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Successfully imported ${medicines.length} medicines into Firebase!')),
              ],
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Predefined Medicines',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            tooltip: 'Import Excel / CSV',
            icon: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
            onPressed: _showBulkImportModal,
          ),
          IconButton(
            tooltip: 'Add Single Medicine',
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
            onPressed: () => _showAddEditMedicineDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.primarySurface,
            ),
          _buildSearchAndFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('predefined_medicines').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }

                final docs = snapshot.data?.docs ?? [];
                final List<Map<String, dynamic>> items = [];
                for (final d in docs) {
                  final data = Map<String, dynamic>.from(d.data() as Map);
                  data['docId'] = d.id;
                  items.add(data);
                }

                // Filter items
                final filtered = items.where((med) {
                  final name = (med['name']?.toString() ?? '').toLowerCase();
                  final generic = (med['genericName']?.toString() ?? '').toLowerCase();
                  final type = (med['type']?.toString() ?? '').toLowerCase();
                  final q = _searchQuery.toLowerCase();

                  final matchesQuery = q.isEmpty || name.contains(q) || generic.contains(q);
                  final matchesType = _selectedTypeFilter == 'All' || type == _selectedTypeFilter.toLowerCase();

                  return matchesQuery && matchesType;
                }).toList();

                if (items.isEmpty) {
                  return _buildEmptyState();
                }

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No medicines match your search criteria.', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final med = filtered[i];
                    return _buildMedicineCard(med);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'bulkUpload',
            onPressed: _showBulkImportModal,
            backgroundColor: const Color(0xFF0C1E28),
            icon: const Icon(Icons.table_view_rounded, color: Colors.white, size: 18),
            label: const Text('Excel / CSV Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'addMed',
            onPressed: () => _showAddEditMedicineDialog(),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
            label: const Text('Add Medicine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: const InputDecoration(
                      hintText: 'Search medicine name, formula, or type...',
                      hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: ['All', ..._medicineTypes].map((type) {
                final isSelected = _selectedTypeFilter == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(type),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedTypeFilter = type),
                    selectedColor: AppColors.primarySurface,
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineCard(Map<String, dynamic> med) {
    final type = med['type']?.toString() ?? 'Tablet';
    final name = med['name']?.toString() ?? 'Medicine';
    final generic = med['genericName']?.toString() ?? '';
    final dosage = med['dosage']?.toString() ?? '1-0-1';
    final duration = med['duration']?.toString() ?? '5 Days';
    final fee = (med['fee'] as num?)?.toDouble() ?? 0.0;
    final docId = med['docId']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.medication_rounded, color: AppColors.primary, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (generic.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Formula: $generic',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.borderSubtle),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Dose: $dosage',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          duration,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                        ),
                      ),
                      if (fee > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '₹${fee.toInt()}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                      onPressed: () => _showAddEditMedicineDialog(med, docId),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                      onPressed: () => _confirmDeleteMedicine(docId, name),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFCCFBF1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.medication_liquid_rounded, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Predefined Medicines Stored',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Upload an Excel or CSV file to import your clinic formulary in seconds, or load standard clinic essentials.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _seedStarterMedicines,
                  icon: const Icon(Icons.flash_on_rounded, size: 16),
                  label: const Text('Load 12 Defaults'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showBulkImportModal,
                  icon: const Icon(Icons.file_upload_outlined, size: 16, color: Colors.white),
                  label: const Text('Excel / CSV Import', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// BULK IMPORT BOTTOM SHEET (EXCEL FILE & CSV PASTE)
// ==========================================================
class BulkImportSheet extends StatefulWidget {
  final Future<void> Function(List<Map<String, dynamic>>) onMedicinesImported;
  final VoidCallback onSeedDefaults;

  const BulkImportSheet({
    super.key,
    required this.onMedicinesImported,
    required this.onSeedDefaults,
  });

  @override
  State<BulkImportSheet> createState() => BulkImportSheetState();
}

class BulkImportSheetState extends State<BulkImportSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pasteController = TextEditingController();
  List<Map<String, dynamic>> _previewMedicines = [];
  String? _selectedFileName;
  bool _isParsing = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  // Pick Excel (.xlsx, .xls) or CSV file
  Future<void> _pickAndParseFile() async {
    setState(() {
      _isParsing = true;
      _parseError = null;
    });

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (file == null) {
        setState(() => _isParsing = false);
        return;
      }

      _selectedFileName = file.name;
      final Uint8List bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Could not read file data.');
      }

      final ext = file.extension?.toLowerCase() ?? '';
      List<Map<String, dynamic>> parsed = [];

      if (ext == 'csv') {
        final csvString = utf8.decode(bytes);
        parsed = _parseCsvData(csvString);
      } else {
        // Parse Excel (.xlsx or .xls)
        parsed = _parseExcelBytes(bytes);
      }

      setState(() {
        _previewMedicines = parsed;
        _isParsing = false;
      });
    } catch (e) {
      setState(() {
        _isParsing = false;
        _parseError = 'File processing error: $e\nTip: You can also copy your spreadsheet rows and use the "Paste Data" tab!';
      });
    }
  }

  List<Map<String, dynamic>> _parseExcelBytes(List<int> bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    final List<Map<String, dynamic>> list = [];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      if (sheet.rows.isEmpty) continue;

      // First row as header
      int nameCol = 0;
      int genericCol = -1;
      int typeCol = 1;
      int dosageCol = 2;
      int durationCol = 3;
      int feeCol = 4;

      final headerRow = sheet.rows.first;
      for (int i = 0; i < headerRow.length; i++) {
        final val = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';
        if (val.contains('name') || val.contains('medicine')) nameCol = i;
        if (val.contains('formula') || val.contains('generic')) genericCol = i;
        if (val.contains('type') || val.contains('form')) typeCol = i;
        if (val.contains('dose') || val.contains('dosage')) dosageCol = i;
        if (val.contains('duration') || val.contains('day')) durationCol = i;
        if (val.contains('fee') || val.contains('price') || val.contains('cost') || val.contains('amount')) feeCol = i;
      }

      for (int r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;
        final nameVal = nameCol < row.length ? row[nameCol]?.value?.toString().trim() ?? '' : '';
        if (nameVal.isEmpty) continue;

        final genVal = genericCol >= 0 && genericCol < row.length ? row[genericCol]?.value?.toString().trim() ?? '' : '';
        final typeVal = typeCol < row.length ? row[typeCol]?.value?.toString().trim() ?? 'Tablet' : 'Tablet';
        final doseVal = dosageCol < row.length ? row[dosageCol]?.value?.toString().trim() ?? '1-0-1' : '1-0-1';
        final durVal = durationCol < row.length ? row[durationCol]?.value?.toString().trim() ?? '5 Days' : '5 Days';
        final feeVal = feeCol < row.length ? double.tryParse(row[feeCol]?.value?.toString().replaceAll(RegExp(r'[^\d.]'), '') ?? '') ?? 50.0 : 50.0;

        list.add({
          'name': nameVal,
          'genericName': genVal,
          'type': _normalizeType(typeVal),
          'dosage': doseVal.isEmpty ? '1-0-1' : doseVal,
          'duration': durVal.isEmpty ? '5 Days' : durVal,
          'fee': feeVal,
        });
      }
      break; // Process primary sheet
    }
    return list;
  }

  List<Map<String, dynamic>> _parseCsvData(String csvString) {
    final lines = csvString.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return [];

    final List<List<String>> rows = [];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final cols = line.contains('\t') ? line.split('\t') : line.split(',');
      rows.add(cols.map((c) => c.trim().replaceAll('"', '')).toList());
    }

    if (rows.isEmpty) return [];

    int nameCol = 0;
    int typeCol = 1;
    int dosageCol = 2;
    int durationCol = 3;
    int feeCol = 4;

    final header = rows.first;
    for (int i = 0; i < header.length; i++) {
      final val = header[i].toLowerCase().trim();
      if (val.contains('name') || val.contains('medicine')) nameCol = i;
      if (val.contains('type') || val.contains('form')) typeCol = i;
      if (val.contains('dose') || val.contains('dosage')) dosageCol = i;
      if (val.contains('duration') || val.contains('day')) durationCol = i;
      if (val.contains('fee') || val.contains('price') || val.contains('amount')) feeCol = i;
    }

    final List<Map<String, dynamic>> list = [];
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;
      final nameVal = nameCol < row.length ? row[nameCol] : '';
      if (nameVal.isEmpty) continue;

      final typeVal = typeCol < row.length ? row[typeCol] : 'Tablet';
      final doseVal = dosageCol < row.length ? row[dosageCol] : '1-0-1';
      final durVal = durationCol < row.length ? row[durationCol] : '5 Days';
      final feeVal = feeCol < row.length ? double.tryParse(row[feeCol].replaceAll(RegExp(r'[^\d.]'), '')) ?? 50.0 : 50.0;

      list.add({
        'name': nameVal,
        'genericName': '',
        'type': _normalizeType(typeVal),
        'dosage': doseVal.isEmpty ? '1-0-1' : doseVal,
        'duration': durVal.isEmpty ? '5 Days' : durVal,
        'fee': feeVal,
      });
    }
    return list;
  }

  void _parsePastedData() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste some CSV or spreadsheet rows first.')),
      );
      return;
    }

    final lines = text.split('\n');
    final List<Map<String, dynamic>> list = [];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // Split by tab (Excel copy) or comma
      final parts = line.contains('\t') ? line.split('\t') : line.split(',');
      if (parts.isEmpty) continue;

      final name = parts[0].trim();
      if (name.toLowerCase() == 'name' || name.toLowerCase() == 'medicine name') continue; // header skip

      final type = parts.length > 1 ? parts[1].trim() : 'Tablet';
      final dosage = parts.length > 2 ? parts[2].trim() : '1-0-1';
      final duration = parts.length > 3 ? parts[3].trim() : '5 Days';
      final fee = parts.length > 4 ? double.tryParse(parts[4].replaceAll(RegExp(r'[^\d.]'), '')) ?? 50.0 : 50.0;

      list.add({
        'name': name,
        'genericName': '',
        'type': _normalizeType(type),
        'dosage': dosage.isEmpty ? '1-0-1' : dosage,
        'duration': duration.isEmpty ? '5 Days' : duration,
        'fee': fee,
      });
    }

    setState(() {
      _previewMedicines = list;
    });
  }

  String _normalizeType(String val) {
    final lower = val.toLowerCase();
    if (lower.contains('cap')) return 'Capsule';
    if (lower.contains('syr')) return 'Syrup';
    if (lower.contains('inj')) return 'Injection';
    if (lower.contains('oint') || lower.contains('cream') || lower.contains('gel')) return 'Ointment';
    if (lower.contains('drop')) return 'Drops';
    if (lower.contains('inhal')) return 'Inhaler';
    if (lower.contains('powd')) return 'Powder';
    return 'Tablet';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Bulk Import Medicines',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: widget.onSeedDefaults,
                            icon: const Icon(Icons.flash_on_rounded, size: 15, color: AppColors.primary),
                            label: const Text(
                              'Load 12 Defaults',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Excel spreadsheet (.xlsx) or CSV import into Firebase',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Bulk Import Medicines',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Excel spreadsheet (.xlsx) or CSV import into Firebase',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: widget.onSeedDefaults,
                      icon: const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.primary),
                      label: const Text(
                        'Load 12 Defaults',
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.upload_file_rounded, size: 18), text: 'Upload Excel / CSV'),
              Tab(icon: Icon(Icons.content_paste_rounded, size: 18), text: 'Paste Spreadsheet Data'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFileUploadTab(),
                _buildPasteDataTab(),
              ],
            ),
          ),
          if (_previewMedicines.isNotEmpty) _buildImportConfirmBar(),
        ],
      ),
    );
  }

  Widget _buildFileUploadTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: _pickAndParseFile,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), style: BorderStyle.solid, width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Color(0xFFCCFBF1), shape: BoxShape.circle),
                    child: const Icon(Icons.table_view_rounded, size: 32, color: AppColors.primary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _selectedFileName ?? 'Tap to Browse & Pick Excel / CSV File',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supported: .xlsx, .xls, .csv\nColumns: Medicine Name, Type, Dosage, Duration, Fee',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (_isParsing) ...[
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 8),
            const Text('Parsing spreadsheet rows...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (_parseError != null) ...[
            const SizedBox(height: 10),
            Text(_parseError!, style: const TextStyle(color: AppColors.error, fontSize: 11.5)),
          ],
          if (_previewMedicines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Expanded(child: _buildPreviewTable()),
          ],
        ],
      ),
    );
  }

  Widget _buildPasteDataTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Paste Copied Rows from Excel:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  _pasteController.text =
                      'Paracetamol 650mg\tTablet\t1-0-1\t5 Days\t45\n'
                      'Amoxicillin 250mg\tSyrup\t1-1-1\t5 Days\t120\n'
                      'Ibuprofen 400mg\tTablet\t1-0-1\t3 Days\t35\n'
                      'Rabeprazole 20mg\tCapsule\t1-0-0\t7 Days\t80\n'
                      'Cough Relief Syrup\tSyrup\t0-0-1\t5 Days\t95';
                },
                child: const Text('Insert Sample', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _pasteController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'Paste tab-separated or comma-separated rows here:\nMedicine Name [TAB] Type [TAB] Dosage [TAB] Duration [TAB] Fee',
                hintStyle: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF8FAFC),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _parsePastedData,
              icon: const Icon(Icons.analytics_outlined, size: 16, color: Colors.white),
              label: const Text('Parse Pasted Rows', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer),
            ),
          ),
          if (_previewMedicines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Expanded(flex: 3, child: _buildPreviewTable()),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFF1F5F9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Preview (${_previewMedicines.length} Medicines ready)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _previewMedicines.clear()),
                  child: const Text('Clear', style: TextStyle(fontSize: 11.5, color: AppColors.error)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _previewMedicines.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = _previewMedicines[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 18),
                  title: Text(m['name'] ?? '', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  subtitle: Text('${m['type']} • ${m['dosage']} • ${m['duration']} • ₹${m['fee']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                    onPressed: () => setState(() => _previewMedicines.removeAt(i)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportConfirmBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => widget.onMedicinesImported(_previewMedicines),
          icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 18),
          label: Text(
            'Save ${_previewMedicines.length} Medicines to Firebase',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}
