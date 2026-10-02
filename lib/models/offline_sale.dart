import 'order_item.dart';
import 'order_record.dart';
import 'pos_checkout.dart';

/// A sale taken while the till could not reach the server. It is kept on the
/// device with the request ID it will be sent under, so sending it twice
/// cannot create two orders.
class OfflineSale {
  /// Shown on the order while it has not been sent yet.
  static const waitingStatus = 'Waiting to Sync';

  /// Shown when the server refused it and a manager has to look at it.
  static const rejectedStatus = 'Needs Attention';

  final String requestId;
  final String userId;
  final DateTime soldAt;
  final String orderType;
  final List<PosCheckoutItem> items;
  final PosPaymentInput payment;
  final String tableNumber;
  final String customerName;
  final String deliveryReference;
  final String notes;
  final String discountTypeId;
  final double? discountValue;
  final String discountNotes;

  /// What the till showed and the customer paid.
  final double subtotal;
  final double total;
  final String employeeName;
  final String paymentMethodName;
  final String discountName;
  final List<OrderItem> lines;

  /// Why the server refused it, or empty while it is simply waiting.
  final String rejection;

  const OfflineSale({
    required this.requestId,
    required this.userId,
    required this.soldAt,
    required this.orderType,
    required this.items,
    required this.payment,
    required this.subtotal,
    required this.total,
    required this.lines,
    this.tableNumber = '',
    this.customerName = '',
    this.deliveryReference = '',
    this.notes = '',
    this.discountTypeId = '',
    this.discountValue,
    this.discountNotes = '',
    this.employeeName = '',
    this.paymentMethodName = '',
    this.discountName = '',
    this.rejection = '',
  });

  bool get isRejected => rejection.isNotEmpty;

  /// A short reference staff can read out, since there is no order number
  /// until the sale reaches the server.
  String get reference {
    final compact = requestId.replaceAll('-', '').toUpperCase();
    return 'OFFLINE-${compact.substring(0, compact.length < 6 ? compact.length : 6)}';
  }

  OfflineSale withRejection(String message) {
    return OfflineSale(
      requestId: requestId,
      userId: userId,
      soldAt: soldAt,
      orderType: orderType,
      items: items,
      payment: payment,
      subtotal: subtotal,
      total: total,
      lines: lines,
      tableNumber: tableNumber,
      customerName: customerName,
      deliveryReference: deliveryReference,
      notes: notes,
      discountTypeId: discountTypeId,
      discountValue: discountValue,
      discountNotes: discountNotes,
      employeeName: employeeName,
      paymentMethodName: paymentMethodName,
      discountName: discountName,
      rejection: message,
    );
  }

  /// How the sale appears in order lists and on its receipt until it syncs.
  OrderRecord toOrderRecord() {
    return OrderRecord(
      id: reference,
      createdAt: soldAt,
      employee: employeeName.isEmpty ? 'This device' : employeeName,
      type: orderType,
      amount: total,
      status: isRejected ? rejectedStatus : waitingStatus,
      customerName: customerName,
      tableNumber: tableNumber,
      deliveryReference: deliveryReference,
      items: lines,
      paymentMethod: paymentMethodName,
      amountReceived: payment.amountTendered ?? payment.amount,
      changeAmount: payment.changeAmount,
      lastActionReason: rejection,
      subtotal: subtotal,
      discountAmount: subtotal > total ? subtotal - total : 0,
      discountName: discountName,
    );
  }

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'user_id': userId,
    'sold_at': soldAt.toUtc().toIso8601String(),
    'order_type': orderType,
    'items': items.map((item) => item.toJson()).toList(),
    'payment': payment.toJson(),
    'table_number': tableNumber,
    'customer_name': customerName,
    'delivery_reference': deliveryReference,
    'notes': notes,
    'discount_type_id': discountTypeId,
    'discount_value': discountValue,
    'discount_notes': discountNotes,
    'subtotal': subtotal,
    'total': total,
    'employee_name': employeeName,
    'payment_method_name': paymentMethodName,
    'discount_name': discountName,
    'lines': lines
        .map(
          (line) => {
            'product_id': line.productId,
            'product_name': line.productName,
            'unit_price': line.unitPrice,
            'quantity': line.quantity,
          },
        )
        .toList(),
    'rejection': rejection,
  };

  factory OfflineSale.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key]?.toString() ?? '';

    return OfflineSale(
      requestId: text('request_id'),
      userId: text('user_id'),
      soldAt: DateTime.parse(text('sold_at')).toLocal(),
      orderType: text('order_type'),
      items: ((json['items'] as List?) ?? const [])
          .map(
            (raw) =>
                PosCheckoutItem.fromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(),
      payment: PosPaymentInput.fromJson(
        Map<String, dynamic>.from((json['payment'] as Map?) ?? const {}),
      ),
      tableNumber: text('table_number'),
      customerName: text('customer_name'),
      deliveryReference: text('delivery_reference'),
      notes: text('notes'),
      discountTypeId: text('discount_type_id'),
      discountValue: (json['discount_value'] as num?)?.toDouble(),
      discountNotes: text('discount_notes'),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      employeeName: text('employee_name'),
      paymentMethodName: text('payment_method_name'),
      discountName: text('discount_name'),
      lines: ((json['lines'] as List?) ?? const []).map((raw) {
        final line = Map<String, dynamic>.from(raw as Map);
        return OrderItem(
          productId: line['product_id']?.toString() ?? '',
          productName: line['product_name']?.toString() ?? '',
          unitPrice: (line['unit_price'] as num?)?.toDouble() ?? 0,
          quantity: (line['quantity'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
      rejection: text('rejection'),
    );
  }
}
