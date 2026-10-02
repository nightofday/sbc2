import 'order_item.dart';

class OrderRecord {
  final String id;
  final DateTime createdAt;
  final String employee;
  final String employeeId;
  final String type;
  final double amount;
  final String status;
  final String customerName;
  final String tableNumber;
  final String deliveryReference;
  final List<OrderItem> items;
  final String paymentMethod;
  final double amountReceived;
  final double changeAmount;
  final String lastActionReason;
  final String authorizedBy;
  final String invoiceNumber;

  /// Sales value before any discount. Zero when it was not loaded.
  final double subtotal;
  final double discountAmount;
  final String discountName;

  /// What has been given back to the customer on this order so far.
  final double refundedAmount;

  const OrderRecord({
    required this.id,
    required this.createdAt,
    required this.employee,
    this.employeeId = '',
    required this.type,
    required this.amount,
    required this.status,
    this.customerName = '',
    this.tableNumber = '',
    this.deliveryReference = '',
    this.items = const [],
    this.paymentMethod = '',
    this.amountReceived = 0,
    this.changeAmount = 0,
    this.lastActionReason = '',
    this.authorizedBy = '',
    this.invoiceNumber = '',
    this.subtotal = 0,
    this.discountAmount = 0,
    this.discountName = '',
    this.refundedAmount = 0,
  });

  /// Date and time as printed on a receipt, such as "Oct 3, 2026 9:05 AM".
  String get dateTimeLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}, '
        '${createdAt.year} $time';
  }

  /// The time alone for today's orders, with the date for older ones.
  String timeLabelAt(DateTime now) {
    final sameDay =
        createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
    return sameDay ? time : dateTimeLabel;
  }

  String get time {
    int hour = createdAt.hour;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour %= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  String get customerOrTable {
    if (type == 'Dine In' && tableNumber.trim().isNotEmpty) {
      return 'Table ${tableNumber.trim()}';
    }
    if (customerName.trim().isNotEmpty) {
      return customerName.trim();
    }
    return 'Walk-in';
  }

  OrderRecord copyWith({
    String? id,
    DateTime? createdAt,
    String? employee,
    String? employeeId,
    String? type,
    double? amount,
    String? status,
    String? customerName,
    String? tableNumber,
    String? deliveryReference,
    List<OrderItem>? items,
    String? paymentMethod,
    double? amountReceived,
    double? changeAmount,
    String? lastActionReason,
    String? authorizedBy,
    String? invoiceNumber,
  }) {
    return OrderRecord(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      employee: employee ?? this.employee,
      employeeId: employeeId ?? this.employeeId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      customerName: customerName ?? this.customerName,
      tableNumber: tableNumber ?? this.tableNumber,
      deliveryReference: deliveryReference ?? this.deliveryReference,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountReceived: amountReceived ?? this.amountReceived,
      changeAmount: changeAmount ?? this.changeAmount,
      lastActionReason: lastActionReason ?? this.lastActionReason,
      authorizedBy: authorizedBy ?? this.authorizedBy,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      subtotal: subtotal,
      discountAmount: discountAmount,
      discountName: discountName,
      refundedAmount: refundedAmount,
    );
  }
}
