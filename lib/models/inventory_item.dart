class InventoryItem {
  final String id;
  final String sku;
  final String name;
  final String category;
  final String categoryId;
  final String stock;
  final double currentQuantity;
  final double usableQuantity;
  final double expiredQuantity;
  final double reorderLevel;
  final String baseUomCode;
  final String baseUomId;
  final bool trackExpiry;
  final DateTime? nextExpirationDate;
  final String status;
  final String supplier;
  final String supplierId;
  final String expiration;

  const InventoryItem({
    this.id = '',
    this.sku = '',
    required this.name,
    required this.category,
    this.categoryId = '',
    required this.stock,
    double currentQuantity = 0,
    double? usableQuantity,
    this.expiredQuantity = 0,
    this.reorderLevel = 0,
    this.baseUomCode = '',
    this.baseUomId = '',
    this.trackExpiry = false,
    this.nextExpirationDate,
    required this.status,
    required this.supplier,
    this.supplierId = '',
    required this.expiration,
  }) : currentQuantity = currentQuantity,
       usableQuantity = usableQuantity ?? currentQuantity;

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    final quantity = (map['current_quantity'] as num?)?.toDouble() ?? 0;
    final usableQuantity =
        (map['usable_quantity'] as num?)?.toDouble() ?? quantity;
    final expiredQuantity = (map['expired_quantity'] as num?)?.toDouble() ?? 0;
    final reorder = (map['reorder_level'] as num?)?.toDouble() ?? 0;
    final uom = map['base_uom_code']?.toString() ?? '';
    final expiryRaw = map['next_expiration_date']?.toString();
    final expiry = expiryRaw == null || expiryRaw.isEmpty
        ? null
        : DateTime.tryParse(expiryRaw);

    return InventoryItem(
      id: map['inventory_item_id']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      category: map['category_name']?.toString() ?? 'Uncategorized',
      categoryId: map['category_id']?.toString() ?? '',
      stock: _formatStock(quantity, uom),
      currentQuantity: quantity,
      usableQuantity: usableQuantity,
      expiredQuantity: expiredQuantity,
      reorderLevel: reorder,
      baseUomCode: uom,
      baseUomId: map['base_uom_id']?.toString() ?? '',
      trackExpiry: map['track_expiry'] == true,
      nextExpirationDate: expiry,
      status: _deriveStatus(
        usableQuantity: usableQuantity,
        expiredQuantity: expiredQuantity,
        reorderLevel: reorder,
        expiry: expiry,
      ),
      supplier: '—',
      expiration: expiry == null ? '—' : _formatDate(expiry),
    );
  }

  static String _deriveStatus({
    required double usableQuantity,
    required double expiredQuantity,
    required double reorderLevel,
    required DateTime? expiry,
  }) {
    if (expiredQuantity > 0) return 'Expired';

    if (expiry != null) {
      final today = DateTime.now();
      final dateOnly = DateTime(today.year, today.month, today.day);
      final expiryOnly = DateTime(expiry.year, expiry.month, expiry.day);
      final days = expiryOnly.difference(dateOnly).inDays;

      if (days <= 7 && usableQuantity > 0) return 'Expiring Soon';
    }

    if (usableQuantity <= reorderLevel) return 'Low Stock';
    return 'In Stock';
  }

  String get usableStock => _formatStock(usableQuantity, baseUomCode);

  String get expiredStock => _formatStock(expiredQuantity, baseUomCode);

  static String _formatStock(double quantity, String unit) {
    final value = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');

    return unit.isEmpty ? value : '$value $unit';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
