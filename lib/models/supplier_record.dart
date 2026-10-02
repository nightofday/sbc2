class SupplierRecord {
  final String id;
  final String name;

  /// One-line summary of the contact details, for lists.
  final String contact;
  final String itemsSupplied;
  final String status;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final int paymentTermsDays;
  final String notes;

  const SupplierRecord({
    this.id = '',
    required this.name,
    required this.contact,
    required this.itemsSupplied,
    required this.status,
    this.contactPerson = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.paymentTermsDays = 0,
    this.notes = '',
  });

  SupplierRecord copyWith({
    String? id,
    String? name,
    String? contact,
    String? itemsSupplied,
    String? status,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    int? paymentTermsDays,
    String? notes,
  }) {
    return SupplierRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      contact: contact ?? this.contact,
      itemsSupplied: itemsSupplied ?? this.itemsSupplied,
      status: status ?? this.status,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      paymentTermsDays: paymentTermsDays ?? this.paymentTermsDays,
      notes: notes ?? this.notes,
    );
  }
}
