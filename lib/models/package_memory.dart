/// How a supplier packs an item: how many base units are in one purchase
/// unit, and what it last cost. Learned from stock already received.
class PackageSize {
  final String supplierId;
  final String inventoryItemId;
  final String unitId;
  final double baseQuantity;
  final double? lastUnitCost;

  const PackageSize({
    required this.supplierId,
    required this.inventoryItemId,
    required this.unitId,
    required this.baseQuantity,
    required this.lastUnitCost,
  });

  factory PackageSize.fromMap(Map<String, dynamic> map) {
    return PackageSize(
      supplierId: map['supplier_id']?.toString() ?? '',
      inventoryItemId: map['inventory_item_id']?.toString() ?? '',
      unitId: map['purchase_uom_id']?.toString() ?? '',
      baseQuantity:
          (map['base_quantity_per_purchase_unit'] as num?)?.toDouble() ?? 0,
      lastUnitCost: (map['last_unit_cost'] as num?)?.toDouble(),
    );
  }
}

/// The package sizes known so far, most recently used first.
class PackageMemory {
  final List<PackageSize> sizes;

  const PackageMemory(this.sizes);

  static const empty = PackageMemory([]);

  /// The size last used for [itemId] in [unitId], preferring [supplierId]
  /// when that supplier has delivered it before.
  PackageSize? find({
    required String itemId,
    required String unitId,
    String supplierId = '',
  }) {
    PackageSize? fallback;

    for (final size in sizes) {
      if (size.inventoryItemId != itemId || size.unitId != unitId) continue;
      if (size.baseQuantity <= 0) continue;
      if (supplierId.isNotEmpty && size.supplierId == supplierId) return size;
      fallback ??= size;
    }

    return fallback;
  }
}
