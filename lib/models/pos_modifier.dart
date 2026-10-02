class PosModifierOption {
  final String id;
  final String name;
  final double priceDelta;

  const PosModifierOption({
    required this.id,
    required this.name,
    required this.priceDelta,
  });
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
}
