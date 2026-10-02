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
