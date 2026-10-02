class SupplierRecord {
  final String id;
  final String name;
  final String contact;
  final String itemsSupplied;
  final String status;

  const SupplierRecord({
    this.id = '',
    required this.name,
    required this.contact,
    required this.itemsSupplied,
    required this.status,
  });

  SupplierRecord copyWith({
    String? id,
    String? name,
    String? contact,
    String? itemsSupplied,
    String? status,
  }) {
    return SupplierRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      contact: contact ?? this.contact,
      itemsSupplied: itemsSupplied ?? this.itemsSupplied,
      status: status ?? this.status,
    );
  }
}
