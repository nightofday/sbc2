class SupplierBalanceRecord {
  final String billId;
  final String supplierName;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final double amount;
  final double amountPaid;
  final double balance;

  const SupplierBalanceRecord({
    required this.billId,
    required this.supplierName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.amount,
    required this.amountPaid,
    required this.balance,
  });

  factory SupplierBalanceRecord.fromMap(Map<String, dynamic> map) {
    final due = map['due_date']?.toString();

    return SupplierBalanceRecord(
      billId: map['supplier_bill_id']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? '',
      invoiceNumber: map['supplier_invoice_number']?.toString() ?? '',
      invoiceDate: DateTime.parse(map['invoice_date'].toString()),
      dueDate: due == null || due.isEmpty ? null : DateTime.tryParse(due),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FinancePaymentMethod {
  final String id;
  final String code;
  final String name;
  final bool requiresReference;

  const FinancePaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    required this.requiresReference,
  });

  factory FinancePaymentMethod.fromMap(Map<String, dynamic> map) {
    return FinancePaymentMethod(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      requiresReference: map['requires_reference'] == true,
    );
  }
}
