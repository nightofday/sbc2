class RefundableOrderItem {
  final String orderItemId;
  final String itemName;
  final String variantName;
  final double soldQuantity;
  final double refundedQuantity;
  final double remainingQuantity;
  final double unitRefundable;
  final double remainingRefundableAmount;

  const RefundableOrderItem({
    required this.orderItemId,
    required this.itemName,
    required this.variantName,
    required this.soldQuantity,
    required this.refundedQuantity,
    required this.remainingQuantity,
    required this.unitRefundable,
    required this.remainingRefundableAmount,
  });

  factory RefundableOrderItem.fromMap(Map<String, dynamic> map) {
    return RefundableOrderItem(
      orderItemId: map['order_item_id']?.toString() ?? '',
      itemName: map['item_name']?.toString() ?? '',
      variantName: map['variant_name']?.toString() ?? '',
      soldQuantity: (map['sold_quantity'] as num?)?.toDouble() ?? 0,
      refundedQuantity: (map['refunded_quantity'] as num?)?.toDouble() ?? 0,
      remainingQuantity: (map['remaining_quantity'] as num?)?.toDouble() ?? 0,
      unitRefundable: (map['unit_refundable'] as num?)?.toDouble() ?? 0,
      remainingRefundableAmount:
          (map['remaining_refundable_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RefundPreview {
  final String orderId;
  final String orderNumber;
  final String status;
  final double totalAmount;
  final String paymentMethodId;
  final String paymentMethodName;
  final String paymentMethodCode;
  final bool requiresReference;
  final List<RefundableOrderItem> items;

  const RefundPreview({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.totalAmount,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.paymentMethodCode,
    required this.requiresReference,
    required this.items,
  });

  factory RefundPreview.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List? ?? const [];

    return RefundPreview(
      orderId: map['order_id']?.toString() ?? '',
      orderNumber: map['order_number']?.toString() ?? '',
      status: map['status']?.toString() ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethodId: map['payment_method_id']?.toString() ?? '',
      paymentMethodName: map['payment_method_name']?.toString() ?? '',
      paymentMethodCode: map['payment_method_code']?.toString() ?? '',
      requiresReference: map['requires_reference'] == true,
      items: rawItems
          .map(
            (raw) => RefundableOrderItem.fromMap(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(),
    );
  }
}

class RefundRestockCandidate {
  final String refundItemId;
  final String itemName;
  final String variantName;
  final double refundedQuantity;
  final bool restockApproved;
  final bool eligibleForRestock;
  final String inventoryItemName;

  const RefundRestockCandidate({
    required this.refundItemId,
    required this.itemName,
    required this.variantName,
    required this.refundedQuantity,
    required this.restockApproved,
    required this.eligibleForRestock,
    required this.inventoryItemName,
  });

  factory RefundRestockCandidate.fromMap(Map<String, dynamic> map) {
    return RefundRestockCandidate(
      refundItemId: map['refund_item_id']?.toString() ?? '',
      itemName: map['item_name_snapshot']?.toString() ?? '',
      variantName: map['variant_name_snapshot']?.toString() ?? '',
      refundedQuantity: (map['refunded_quantity'] as num?)?.toDouble() ?? 0,
      restockApproved: map['restock_approved'] == true,
      eligibleForRestock: map['eligible_for_restock'] == true,
      inventoryItemName: map['inventory_item_name']?.toString() ?? '',
    );
  }
}
