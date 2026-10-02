class ExpenseRecord {
  final String id;
  final int expenseNumber;
  final String expenseType;
  final String date;
  final String description;
  final String category;
  final double amount;
  final DateTime? expenseDate;
  final String supplierId;
  final String supplierName;
  final String referenceNumber;
  final String notes;

  const ExpenseRecord({
    this.id = '',
    this.expenseNumber = 0,
    this.expenseType = 'OPERATING',
    required this.date,
    required this.description,
    required this.category,
    required this.amount,
    this.expenseDate,
    this.supplierId = '',
    this.supplierName = '',
    this.referenceNumber = '',
    this.notes = '',
  });

}

class ExpenseSupplierOption {
  final String id;
  final String name;

  const ExpenseSupplierOption({required this.id, required this.name});

  factory ExpenseSupplierOption.fromMap(Map<String, dynamic> map) {
    return ExpenseSupplierOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class ExpenseCategoryOption {
  final String id;
  final String name;

  const ExpenseCategoryOption({required this.id, required this.name});

  factory ExpenseCategoryOption.fromMap(Map<String, dynamic> map) {
    return ExpenseCategoryOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}
