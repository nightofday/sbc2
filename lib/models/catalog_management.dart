/// The three kinds of category the business maintains. They are separate
/// lists; a menu category is never an inventory or expense category.
enum CategoryDomain {
  menu('MENU', 'Menu', 'products'),
  inventory('INVENTORY', 'Inventory', 'stock items'),
  expense('EXPENSE', 'Expenses', 'expenses');

  /// The code the database functions expect.
  final String code;
  final String label;

  /// What a category of this kind is used by, for "used by 3 products".
  final String usageNoun;

  const CategoryDomain(this.code, this.label, this.usageNoun);
}

class CategoryRecord {
  final String id;
  final String name;
  final String description;
  final int sortOrder;
  final bool isActive;
  final int usageCount;

  const CategoryRecord({
    required this.id,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
    this.isActive = true,
    this.usageCount = 0,
  });

  factory CategoryRecord.fromMap(Map<String, dynamic> map) {
    return CategoryRecord(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isActive: map['is_active'] == true,
      usageCount: (map['usage_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DiscountDefinition {
  final String id;
  final String name;

  /// `PERCENTAGE`, `FIXED_AMOUNT` or `MANUAL_AMOUNT`.
  final String calculationMethod;
  final double? value;
  final bool allowCustomValue;
  final double? maxValue;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool isActive;
  final bool isPosEnabled;

  /// Senior, PWD and similar discounts whose rules are not confirmed yet.
  final bool isStatutory;
  final String notes;

  const DiscountDefinition({
    this.id = '',
    required this.name,
    required this.calculationMethod,
    this.value,
    this.allowCustomValue = false,
    this.maxValue,
    this.validFrom,
    this.validUntil,
    this.isActive = true,
    this.isPosEnabled = true,
    this.isStatutory = false,
    this.notes = '',
  });

  factory DiscountDefinition.fromMap(Map<String, dynamic> map) {
    DateTime? date(String key) {
      final raw = map[key]?.toString();
      return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    return DiscountDefinition(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      calculationMethod:
          map['calculation_method']?.toString() ?? 'MANUAL_AMOUNT',
      value: (map['default_value'] as num?)?.toDouble(),
      allowCustomValue: map['allow_custom_value'] == true,
      maxValue: (map['max_value'] as num?)?.toDouble(),
      validFrom: date('valid_from'),
      validUntil: date('valid_until'),
      isActive: map['is_active'] == true,
      isPosEnabled: map['is_pos_enabled'] == true,
      isStatutory:
          map['requires_id'] == true || map['is_tax_exempt_related'] == true,
      notes: map['notes']?.toString() ?? '',
    );
  }

  bool get isPercentage => calculationMethod == 'PERCENTAGE';

  /// "10% off", "₱20 off", or how the value is decided at the till.
  String get valueLabel {
    String amount(double number) {
      final text = number == number.roundToDouble()
          ? number.toStringAsFixed(0)
          : number.toStringAsFixed(2);
      return isPercentage ? '$text%' : '₱$text';
    }

    final fixed = value == null ? null : '${amount(value!)} off';
    if (!allowCustomValue) return fixed ?? 'No value set';

    final limit = maxValue == null ? '' : ', up to ${amount(maxValue!)}';
    return fixed == null
        ? 'Entered at the till$limit'
        : '$fixed, changeable at the till$limit';
  }
}
