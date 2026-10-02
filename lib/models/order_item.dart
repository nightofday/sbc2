class OrderItem {
  final String productId;
  final String productName;

  /// Price of one unit including its chosen options.
  final double unitPrice;
  final int quantity;

  /// Names of the options chosen for this line, such as "Extra Shot".
  final List<String> options;

  /// What the customer asked for on this line, if anything.
  final String note;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.options = const [],
    this.note = '',
  });

  double get lineTotal => unitPrice * quantity;
}

/// How a sold line is named: the product, with its size in brackets unless
/// the size is the product's ordinary one.
String orderLineName(String itemName, String variantName) {
  final variant = variantName.trim();
  const ordinary = {'', 'regular', 'default', 'standard'};

  if (ordinary.contains(variant.toLowerCase()) || variant == itemName.trim()) {
    return itemName;
  }
  return '$itemName ($variant)';
}
