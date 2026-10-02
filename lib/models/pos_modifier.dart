class PosModifierOption {
  final String id;
  final String name;
  final double priceDelta;

  const PosModifierOption({
    required this.id,
    required this.name,
    required this.priceDelta,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price_delta': priceDelta,
  };

  factory PosModifierOption.fromMap(Map<String, dynamic> map) {
    return PosModifierOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PosModifierGroup {
  final String id;
  final String name;
  final int minSelections;
  final int? maxSelections;
  final bool isRequired;
  final List<PosModifierOption> options;

  const PosModifierGroup({
    required this.id,
    required this.name,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
    required this.options,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'min_selections': minSelections,
    'max_selections': maxSelections,
    'is_required': isRequired,
    'options': options.map((option) => option.toMap()).toList(),
  };

  factory PosModifierGroup.fromMap(Map<String, dynamic> map) {
    return PosModifierGroup(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      minSelections: (map['min_selections'] as num?)?.toInt() ?? 0,
      maxSelections: (map['max_selections'] as num?)?.toInt(),
      isRequired: map['is_required'] == true,
      options: ((map['options'] as List?) ?? const [])
          .map(
            (raw) =>
                PosModifierOption.fromMap(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(),
    );
  }
}
