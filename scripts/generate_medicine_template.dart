import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  final sheet = excel[defaultSheet];

  // Define headers
  final headers = [
    'Medicine Name',
    'Generic Formula',
    'Formulation Type',
    'Dosage',
    'Duration',
    'Price (₹)',
  ];

  // Append header row
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

  // Sample medicine records matching the clinic clinical formulary
  final sampleMedicines = [
    ['Paracetamol 650mg', 'Acetaminophen', 'Tablet', '1-0-1', '5 Days', 40.0],
    ['Amoxicillin 500mg', 'Amoxicillin Trihydrate', 'Capsule', '1-0-1', '5 Days', 90.0],
    ['Azithromycin 500mg', 'Azithromycin', 'Tablet', '1-0-0', '3 Days', 120.0],
    ['Cetirizine 10mg', 'Cetirizine HCl', 'Tablet', '0-0-1', '5 Days', 35.0],
    ['Pantoprazole 40mg', 'Pantoprazole Sodium', 'Tablet', '1-0-0', '7 Days', 75.0],
    ['Metformin 500mg', 'Metformin HCl', 'Tablet', '1-0-1', '30 Days', 85.0],
    ['Telmisartan 40mg', 'Telmisartan', 'Tablet', '1-0-0', '30 Days', 110.0],
    ['Benadryl Cough Syrup', 'Diphenhydramine', 'Syrup', '1-1-1 (10ml)', '5 Days', 130.0],
    ['ORS Electrolyte Powder', 'Oral Rehydration Salts', 'Powder', 'SOS (1 Packet/L)', '3 Days', 25.0],
    ['Ciprofloxacin Eye Drops', 'Ciprofloxacin 0.3%', 'Drops', '2 drops (4 times)', '5 Days', 60.0],
    ['Diclofenac Gel 30g', 'Diclofenac Diethylamine', 'Ointment', 'Apply twice daily', '7 Days', 95.0],
    ['Salbutamol Inhaler 100mcg', 'Salbutamol', 'Inhaler', '2 puffs SOS', '30 Days', 180.0],
    ['Augmentin 625mg', 'Amoxicillin + Potassium Clavulanate', 'Tablet', '1-0-1', '5 Days', 210.0],
    ['Ibuprofen 400mg', 'Ibuprofen', 'Tablet', '1-0-1', '3 Days', 30.0],
    ['Ondansetron 4mg', 'Ondansetron HCl', 'Tablet', '1-0-1 (Before Food)', '3 Days', 45.0],
    ['Dolo 650', 'Paracetamol', 'Tablet', '1-0-1 (After Food)', '5 Days', 35.0],
  ];

  for (final row in sampleMedicines) {
    sheet.appendRow([
      TextCellValue(row[0] as String),
      TextCellValue(row[1] as String),
      TextCellValue(row[2] as String),
      TextCellValue(row[3] as String),
      TextCellValue(row[4] as String),
      DoubleCellValue(row[5] as double),
    ]);
  }

  // Save the .xlsx file
  final bytes = excel.encode();
  if (bytes != null) {
    final file = File('medicines_template.xlsx');
    file.writeAsBytesSync(bytes);
    print('Generated medicines_template.xlsx successfully (${bytes.length} bytes)');
  }

  // Also create a CSV version
  final csvContent = StringBuffer();
  csvContent.writeln(headers.map((h) => '"$h"').join(','));
  for (final row in sampleMedicines) {
    csvContent.writeln([
      '"${row[0]}"',
      '"${row[1]}"',
      '"${row[2]}"',
      '"${row[3]}"',
      '"${row[4]}"',
      row[5],
    ].join(','));
  }
  File('medicines_template.csv').writeAsStringSync(csvContent.toString());
  print('Generated medicines_template.csv successfully');
}
