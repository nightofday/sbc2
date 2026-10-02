class OrderItem {
  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });

  double get lineTotal => unitPrice * quantity;

  OrderItem copyWith({
    String? productId,
    String? productName,
    double? unitPrice,
    int? quantity,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }
}
