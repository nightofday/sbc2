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
  });

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
    );
  }
}
