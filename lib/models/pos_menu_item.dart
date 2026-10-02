class PosMenuItem {
  final String variantId;
  final String menuItemId;
  final String sku;
  final String name;
  final String variantName;
  final String category;
  final double price;
  final bool isDefault;
  final String inventoryTrackingMode;
  final double? availableQuantity;

  const PosMenuItem({
    required this.variantId,
    required this.menuItemId,
    required this.sku,
    required this.name,
    required this.variantName,
    required this.category,
    required this.price,
    required this.isDefault,
    required this.inventoryTrackingMode,
    required this.availableQuantity,
  });

  bool get tracksInventory => inventoryTrackingMode == 'FINISHED_GOOD';

  bool get isOutOfStock => tracksInventory && (availableQuantity ?? 0) <= 0;

  factory PosMenuItem.fromMap(Map<String, dynamic> map) {
    return PosMenuItem(
      variantId: map['variant_id']?.toString() ?? '',
      menuItemId: map['menu_item_id']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      name: map['item_name']?.toString() ?? '',
      variantName: map['variant_name']?.toString() ?? '',
      category: map['category_name']?.toString() ?? 'Other',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      isDefault: map['is_default'] == true,
      inventoryTrackingMode:
          map['inventory_tracking_mode']?.toString() ?? 'UNTRACKED',
      availableQuantity: (map['available_quantity'] as num?)?.toDouble(),
    );
  }
}
