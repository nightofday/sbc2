class PosDiscountType {
  final String id;
  final String code;
  final String name;
  final String calculationMethod;
  final double? defaultValue;
  final bool requiresAuthorization;

  /// False when management fixed the value; the till cannot change it.
  final bool allowCustomValue;
  final double? maxValue;

  const PosDiscountType({
    required this.id,
    required this.code,
    required this.name,
    required this.calculationMethod,
    required this.defaultValue,
    required this.requiresAuthorization,
    this.allowCustomValue = true,
    this.maxValue,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'calculation_method': calculationMethod,
    'default_value': defaultValue,
    'requires_authorization': requiresAuthorization,
    'allow_custom_value': allowCustomValue,
    'max_value': maxValue,
  };

  factory PosDiscountType.fromMap(Map<String, dynamic> map) {
    return PosDiscountType(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      calculationMethod:
          map['calculation_method']?.toString() ?? 'MANUAL_AMOUNT',
      defaultValue: (map['default_value'] as num?)?.toDouble(),
      requiresAuthorization: map['requires_authorization'] == true,
      allowCustomValue: map['allow_custom_value'] != false,
      maxValue: (map['max_value'] as num?)?.toDouble(),
    );
  }

  double calculateDiscount(double subtotal, double manualValue) {
    if (subtotal <= 0) return 0;

    final value = allowCustomValue && manualValue > 0
        ? manualValue
        : (defaultValue ?? 0);

    switch (calculationMethod) {
      case 'PERCENTAGE':
        if (value <= 0) return 0;
        final safePercent = value.clamp(0, 100).toDouble();
        return subtotal * safePercent / 100;
      case 'FIXED_AMOUNT':
      case 'MANUAL_AMOUNT':
        return value.clamp(0, subtotal).toDouble();
      default:
        return 0;
    }
  }
}
