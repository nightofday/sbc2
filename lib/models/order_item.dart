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

}
