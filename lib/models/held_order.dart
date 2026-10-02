import 'pos_menu_item.dart';
import 'pos_modifier.dart';

/// One line of an order that was set aside.
class HeldOrderLine {
  final PosMenuItem product;
  final int quantity;
  final List<PosModifierOption> modifiers;
  final String note;

  const HeldOrderLine({
    required this.product,
    required this.quantity,
    this.modifiers = const [],
    this.note = '',
  });

  double get lineTotal =>
      (product.price +
          modifiers.fold<double>(0, (sum, option) => sum + option.priceDelta)) *
      quantity;

  Map<String, dynamic> toMap() => {
    'product': product.toMap(),
    'quantity': quantity,
    'modifiers': modifiers.map((option) => option.toMap()).toList(),
    'note': note,
  };

  factory HeldOrderLine.fromMap(Map<String, dynamic> map) {
    return HeldOrderLine(
      product: PosMenuItem.fromMap(
        Map<String, dynamic>.from(map['product'] as Map),
      ),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      modifiers: ((map['modifiers'] as List?) ?? const [])
          .map(
            (raw) => PosModifierOption.fromMap(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(),
      note: map['note']?.toString() ?? '',
    );
  }
}

/// An order set aside on this device to be finished and paid later, such as
/// a table that is still ordering. Nothing is posted until it is paid: no
/// stock moves and it is in no report.
class HeldOrder {
  final String id;
  final String userId;
  final DateTime heldAt;
  final String orderType;
  final String tableNumber;
  final String customerName;
  final String deliveryReference;
  final List<HeldOrderLine> lines;

  const HeldOrder({
    required this.id,
    required this.userId,
    required this.heldAt,
    required this.orderType,
    required this.lines,
    this.tableNumber = '',
    this.customerName = '',
    this.deliveryReference = '',
  });

  /// What staff look for when picking the order up again.
  String get label {
    if (tableNumber.trim().isNotEmpty) return 'Table ${tableNumber.trim()}';
    if (customerName.trim().isNotEmpty) return customerName.trim();
    return orderType;
  }

  int get itemCount => lines.fold<int>(0, (sum, line) => sum + line.quantity);

  double get total =>
      lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'held_at': heldAt.toUtc().toIso8601String(),
    'order_type': orderType,
    'table_number': tableNumber,
    'customer_name': customerName,
    'delivery_reference': deliveryReference,
    'lines': lines.map((line) => line.toMap()).toList(),
  };

  factory HeldOrder.fromMap(Map<String, dynamic> map) {
    String text(String key) => map[key]?.toString() ?? '';

    return HeldOrder(
      id: text('id'),
      userId: text('user_id'),
      heldAt: DateTime.parse(text('held_at')).toLocal(),
      orderType: text('order_type'),
      tableNumber: text('table_number'),
      customerName: text('customer_name'),
      deliveryReference: text('delivery_reference'),
      lines: ((map['lines'] as List?) ?? const [])
          .map(
            (raw) =>
                HeldOrderLine.fromMap(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(),
    );
  }
}
