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

  /// A null quantity means the stock level is unknown, which is the case for
  /// a menu served from the device cache while offline. It is not treated as
  /// sold out: the server accepts offline sales and reports any shortfall.
  bool get isOutOfStock =>
      tracksInventory && availableQuantity != null && availableQuantity! <= 0;

  bool get hasUnknownStock => tracksInventory && availableQuantity == null;

  /// The same keys [PosMenuItem.fromMap] reads, for the device cache.
  Map<String, dynamic> toMap() => {
    'variant_id': variantId,
    'menu_item_id': menuItemId,
    'sku': sku,
    'item_name': name,
    'variant_name': variantName,
    'category_name': category,
    'price': price,
    'is_default': isDefault,
    'inventory_tracking_mode': inventoryTrackingMode,
    'available_quantity': availableQuantity,
  };

  PosMenuItem withAvailableQuantity(double? quantity) {
    return PosMenuItem(
      variantId: variantId,
      menuItemId: menuItemId,
      sku: sku,
      name: name,
      variantName: variantName,
      category: category,
      price: price,
      isDefault: isDefault,
      inventoryTrackingMode: inventoryTrackingMode,
      availableQuantity: quantity,
    );
  }

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
