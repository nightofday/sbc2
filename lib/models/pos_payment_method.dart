class PosPaymentMethod {
  final String id;
  final String code;
  final String name;
  final bool isCash;
  final bool requiresReference;

  const PosPaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    required this.isCash,
    required this.requiresReference,
  });

  factory PosPaymentMethod.fromMap(Map<String, dynamic> map) {
    return PosPaymentMethod(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      isCash: map['is_cash'] == true,
      requiresReference: map['requires_reference'] == true,
    );
  }
}
