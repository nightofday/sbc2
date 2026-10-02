import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/offline_sales_queue.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/offline_sale.dart';
import '../../models/order_item.dart';
import '../../models/order_record.dart';
import '../../models/pos_checkout.dart';
import '../../models/pos_discount.dart';
import '../../models/pos_menu_item.dart';
import '../../models/pos_modifier.dart';
import '../../models/pos_payment_method.dart';
import '../../models/refund_preview.dart';
import '../../models/shift_cash_snapshot.dart';

class SupabaseOrderRepository
    implements OrderRepository, OfflineSaleUploader {
  final SupabaseClient _client;

  SupabaseOrderRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<OrderRecord>> getOrders() async {
    final rows = await _client
        .from('orders')
        .select(
          'id, order_number, created_at, employee_name_snapshot, order_type, '
          'total_amount, subtotal, discount_amount, status, customer_name, '
          'table_number, delivery_reference, '
          'order_discounts(discount_name_snapshot), '
          'order_items(id, item_name_snapshot, quantity, unit_price), '
          'payments(amount, amount_tendered, change_amount, transaction_type, status, '
          'payment_methods(name, code)), sales_invoices(invoice_number)',
        )
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => _orderFromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<OrderRecord?> getOrderById(String id) async {
    final row = await _findOrderRow(id);
    if (row == null) return null;
    return _orderFromMap(row);
  }

  @override
  Future<void> createOrder(OrderRecord order) async {
    throw UnsupportedError(
      'Live orders must be created through placeOrder() so pricing and payment '
      'are validated by PostgreSQL.',
    );
  }

  @override
  Future<void> updateOrder(OrderRecord order) async {
    throw UnsupportedError(
      'Live order changes must use the protected order RPCs.',
    );
  }

  @override
  Future<RefundPreview> getRefundPreview(String id) async {
    final orderUuid = await _resolveOrderUuid(id);
    final result = await _client.rpc(
      'get_refund_preview',
      params: {'p_order_id': orderUuid},
    );

    return RefundPreview.fromMap(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> refundOrderItems(
    String id, {
    required Map<String, double> quantities,
    required String reason,
    String externalReference = '',
    String? clientRequestId,
  }) async {
    final orderUuid = await _resolveOrderUuid(id);

    final items = quantities.entries
        .where((entry) => entry.value > 0)
        .map((entry) => {'order_item_id': entry.key, 'quantity': entry.value})
        .toList();

    await _client.rpc(
      'process_refund_items',
      params: {
        'p_order_id': orderUuid,
        'p_items': items,
        'p_reason': reason.trim(),
        'p_external_reference': _nullable(externalReference),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<List<PosMenuItem>> getPosMenu() async {
    final rows = await _client
        .from('v_pos_menu')
        .select()
        .order('category_sort_order', ascending: true)
        .order('variant_sort_order', ascending: true)
        .order('item_name', ascending: true);

    return (rows as List)
        .map(
          (row) => PosMenuItem.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<PosDiscountType>> getPosDiscountTypes() async {
    final result = await _client.rpc('get_pos_discount_types');

    return (result as List)
        .map(
          (raw) =>
              PosDiscountType.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<List<PosPaymentMethod>> getPaymentMethods() async {
    final rows = await _client
        .from('payment_methods')
        .select('id, code, name, is_cash, requires_reference')
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (rows as List)
        .map(
          (row) =>
              PosPaymentMethod.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<PosModifierGroup>> getModifierGroups(String menuItemId) async {
    final rows = await _client
        .from('v_pos_modifiers')
        .select()
        .eq('menu_item_id', menuItemId)
        .order('group_sort_order', ascending: true)
        .order('modifier_sort_order', ascending: true)
        .order('modifier_name', ascending: true);

    final groups = <String, _MutableModifierGroup>{};

    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final groupId = row['modifier_group_id']?.toString() ?? '';

      final group = groups.putIfAbsent(
        groupId,
        () => _MutableModifierGroup(
          id: groupId,
          name: row['group_name']?.toString() ?? '',
          minSelections: (row['min_selections'] as num?)?.toInt() ?? 0,
          maxSelections: (row['max_selections'] as num?)?.toInt(),
          isRequired: row['is_required'] == true,
        ),
      );

      group.options.add(
        PosModifierOption(
          id: row['modifier_id']?.toString() ?? '',
          name: row['modifier_name']?.toString() ?? '',
          priceDelta: (row['price_delta'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    return groups.values
        .map(
          (group) => PosModifierGroup(
            id: group.id,
            name: group.name,
            minSelections: group.minSelections,
            maxSelections: group.maxSelections,
            isRequired: group.isRequired,
            options: List<PosModifierOption>.unmodifiable(group.options),
          ),
        )
        .toList();
  }

  @override
  Future<String?> getOpenShiftId() async {
    final result = await _client.rpc('current_open_shift_id');
    return result?.toString();
  }

  @override
  Future<String> startShift({
    double? openingCash,
    String? clientRequestId,
  }) async {
    final result = await _client.rpc(
      'start_shift',
      params: {
        'p_device_id': null,
        'p_opening_cash': openingCash,
        'p_client_request_id': clientRequestId,
      },
    );

    final row = Map<String, dynamic>.from(result as Map);
    return row['id'].toString();
  }

  @override
  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'end_shift',
      params: {
        'p_shift_id': shiftId,
        'p_closing_cash_counted': closingCashCounted,
        'p_notes': _nullable(notes),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<ShiftCashSnapshot> getShiftCashSnapshot(String shiftId) async {
    final result = await _client.rpc(
      'get_shift_cash_snapshot',
      params: {'p_shift_id': shiftId},
    );

    return ShiftCashSnapshot.fromMap(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> recordShiftCashMovement({
    required String shiftId,
    required String movementType,
    required double amount,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'record_shift_cash_movement',
      params: {
        'p_shift_id': shiftId,
        'p_movement_type': movementType,
        'p_amount': amount,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<OrderRecord> placeOrder({
    required String orderType,
    required List<PosCheckoutItem> items,
    required List<PosPaymentInput> payments,
    String tableNumber = '',
    String customerName = '',
    String deliveryReference = '',
    String notes = '',
    String discountTypeId = '',
    double? discountValue,
    String discountNotes = '',
    required String clientRequestId,
  }) async {
    if (payments.length != 1) {
      throw const FormatException(
        'The current POS flow requires exactly one payment method.',
      );
    }

    final payment = payments.first;

    final result = await _client.rpc(
      'place_order_v2',
      params: {
        'p_order_type': _dbOrderType(orderType),
        'p_items': items.map((item) => item.toJson()).toList(),
        'p_payment': {
          'payment_method_id': payment.paymentMethodId,
          'amount_tendered': payment.amountTendered,
          'external_reference': payment.externalReference,
        },
        'p_discount': discountTypeId.trim().isEmpty
            ? null
            : {
                'discount_type_id': discountTypeId,
                'manual_value': discountValue,
                'notes': _nullable(discountNotes),
              },
        'p_table_number': _nullable(tableNumber),
        'p_customer_name': _nullable(customerName),
        'p_delivery_reference': _nullable(deliveryReference),
        'p_notes': _nullable(notes),
        'p_client_request_id': clientRequestId,
      },
    );

    final resultMap = Map<String, dynamic>.from(result as Map);
    final orderNumber = resultMap['order_number']?.toString();

    if (orderNumber == null) {
      throw const FormatException(
        'The completed order number was not returned.',
      );
    }

    // The sale is committed at this point. A failure to read it back must not
    // be reported as a failed sale.
    try {
      final row = await _findOrderRow('#$orderNumber');
      if (row != null) return _orderFromMap(row);
    } catch (_) {
      throw CheckoutSavedException(orderNumber);
    }

    throw CheckoutSavedException(orderNumber);
  }

  @override
  Future<void> uploadOfflineSale(OfflineSale sale) async {
    await _client.rpc(
      'sync_offline_order',
      params: {
        'p_order_type': _dbOrderType(sale.orderType),
        'p_items': sale.items.map((item) => item.toJson()).toList(),
        'p_payment': {
          'payment_method_id': sale.payment.paymentMethodId,
          'amount_tendered': sale.payment.amountTendered,
          'external_reference': sale.payment.externalReference,
        },
        'p_client_request_id': sale.requestId,
        'p_sold_at': sale.soldAt.toUtc().toIso8601String(),
        'p_client_total': sale.total,
        'p_discount': sale.discountTypeId.trim().isEmpty
            ? null
            : {
                'discount_type_id': sale.discountTypeId,
                'manual_value': sale.discountValue,
                'notes': _nullable(sale.discountNotes),
              },
        'p_table_number': _nullable(sale.tableNumber),
        'p_customer_name': _nullable(sale.customerName),
        'p_delivery_reference': _nullable(sale.deliveryReference),
        'p_notes': _nullable(sale.notes),
      },
    );
  }

  @override
  Future<OrderRecord?> findOrderByRequestId(String clientRequestId) async {
    final row = await _findOrderRow('', clientRequestId: clientRequestId);

    return row == null ? null : _orderFromMap(row);
  }

  @override
  Future<void> voidOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
  }) async {
    final orderUuid = await _resolveOrderUuid(id);
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw const AuthException('You must be signed in.');
    }

    await _client.rpc(
      'void_order',
      params: {
        'p_order_id': orderUuid,
        'p_reason': reason,
        'p_authorized_by': userId,
      },
    );
  }

  @override
  Future<void> refundOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
    String? clientRequestId,
  }) async {
    final orderUuid = await _resolveOrderUuid(id);
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      throw const AuthException('You must be signed in.');
    }

    final orderRows = await _client
        .from('orders')
        .select(
          'id, total_amount, order_items(id, quantity), '
          'payments(payment_method_id, amount, transaction_type, status)',
        )
        .eq('id', orderUuid)
        .limit(1);

    if ((orderRows as List).isEmpty) {
      throw const FormatException('Order not found.');
    }

    final order = Map<String, dynamic>.from(orderRows.first as Map);
    final itemRows = (order['order_items'] as List? ?? const []);
    final paymentRows = (order['payments'] as List? ?? const []);

    final items = itemRows.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return {
        'order_item_id': item['id'],
        'quantity': (item['quantity'] as num).toDouble(),
      };
    }).toList();

    Map<String, dynamic>? originalPayment;
    for (final raw in paymentRows) {
      final payment = Map<String, dynamic>.from(raw as Map);
      if (payment['transaction_type'] == 'PAYMENT' &&
          payment['status'] == 'COMPLETED') {
        originalPayment = payment;
        break;
      }
    }

    if (originalPayment == null) {
      throw const FormatException('Original payment method was not found.');
    }

    await _client.rpc(
      'process_refund',
      params: {
        'p_order_id': orderUuid,
        'p_items': items,
        'p_payment_returns': [
          {
            'payment_method_id': originalPayment['payment_method_id'],
            'amount': (order['total_amount'] as num).toDouble(),
          },
        ],
        'p_reason': reason,
        'p_authorized_by': userId,
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<List<RefundRestockCandidate>> getRefundRestockCandidates(
    String id,
  ) async {
    final orderUuid = await _resolveOrderUuid(id);

    final rows = await _client
        .from('v_refund_restock_candidates')
        .select()
        .eq('order_id', orderUuid)
        .order('refund_number', ascending: true)
        .order('item_name_snapshot', ascending: true);

    return (rows as List)
        .map(
          (raw) => RefundRestockCandidate.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> approveRefundItemRestock(
    String refundItemId, {
    String notes = '',
  }) async {
    await _client.rpc(
      'approve_refund_item_restock',
      params: {'p_refund_item_id': refundItemId, 'p_notes': _nullable(notes)},
    );
  }

  Future<Map<String, dynamic>?> _findOrderRow(
    String id, {
    String? clientRequestId,
  }) async {
    dynamic query = _client
        .from('orders')
        .select(
          'id, order_number, created_at, employee_name_snapshot, order_type, '
          'total_amount, subtotal, discount_amount, status, customer_name, '
          'table_number, delivery_reference, '
          'order_discounts(discount_name_snapshot), '
          'order_items(id, item_name_snapshot, quantity, unit_price), '
          'payments(amount, amount_tendered, change_amount, transaction_type, status, '
          'payment_methods(name, code)), sales_invoices(invoice_number)',
        );

    if (clientRequestId != null) {
      query = query.eq('client_request_id', clientRequestId);
    } else if (id.startsWith('#')) {
      final number = int.tryParse(id.substring(1));
      if (number == null) return null;
      query = query.eq('order_number', number);
    } else {
      query = query.eq('id', id);
    }

    final rows = await query.limit(1);
    if ((rows as List).isEmpty) return null;

    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<String> _resolveOrderUuid(String id) async {
    if (!id.startsWith('#')) return id;

    final number = int.tryParse(id.substring(1));
    if (number == null) {
      throw const FormatException('Invalid order number.');
    }

    final rows = await _client
        .from('orders')
        .select('id')
        .eq('order_number', number)
        .limit(1);

    if ((rows as List).isEmpty) {
      throw const FormatException('Order not found.');
    }

    return (rows.first as Map)['id'].toString();
  }

  OrderRecord _orderFromMap(Map<String, dynamic> row) {
    final itemRows = row['order_items'] as List? ?? const [];
    final paymentRows = row['payments'] as List? ?? const [];

    final items = itemRows.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      return OrderItem(
        productId: item['id']?.toString() ?? '',
        productName: item['item_name_snapshot']?.toString() ?? '',
        unitPrice: ((item['unit_price'] as num?) ?? 0).toDouble(),
        quantity: ((item['quantity'] as num?) ?? 0).round(),
      );
    }).toList();

    Map<String, dynamic>? payment;
    for (final raw in paymentRows) {
      final candidate = Map<String, dynamic>.from(raw as Map);
      if (candidate['transaction_type'] == 'PAYMENT' &&
          candidate['status'] == 'COMPLETED') {
        payment = candidate;
        break;
      }
    }

    final methodRaw = payment?['payment_methods'];
    final method = methodRaw is Map
        ? Map<String, dynamic>.from(methodRaw)
        : <String, dynamic>{};

    final invoiceRaw = row['sales_invoices'];
    String invoiceNumber = '';
    if (invoiceRaw is Map) {
      invoiceNumber = invoiceRaw['invoice_number']?.toString() ?? '';
    } else if (invoiceRaw is List && invoiceRaw.isNotEmpty) {
      final first = invoiceRaw.first;
      if (first is Map) {
        invoiceNumber = first['invoice_number']?.toString() ?? '';
      }
    }

    final amountTendered = payment?['amount_tendered'] as num?;
    final paymentAmount = payment?['amount'] as num?;

    return OrderRecord(
      id: '#${row['order_number']}',
      createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
      employee: row['employee_name_snapshot']?.toString() ?? 'Employee',
      employeeId: '',
      type: _uiOrderType(row['order_type']?.toString() ?? ''),
      amount: ((row['total_amount'] as num?) ?? 0).toDouble(),
      status: _uiStatus(row['status']?.toString() ?? ''),
      customerName: row['customer_name']?.toString() ?? '',
      tableNumber: row['table_number']?.toString() ?? '',
      deliveryReference: row['delivery_reference']?.toString() ?? '',
      items: items,
      paymentMethod: method['name']?.toString() ?? '',
      amountReceived: (amountTendered ?? paymentAmount ?? 0).toDouble(),
      changeAmount: ((payment?['change_amount'] as num?) ?? 0).toDouble(),
      invoiceNumber: invoiceNumber,
      subtotal: ((row['subtotal'] as num?) ?? 0).toDouble(),
      discountAmount: ((row['discount_amount'] as num?) ?? 0).toDouble(),
      discountName: ((row['order_discounts'] as List?) ?? const [])
          .map((raw) => (raw as Map)['discount_name_snapshot']?.toString())
          .whereType<String>()
          .join(', '),
    );
  }

  String _dbOrderType(String type) {
    switch (type) {
      case 'Dine In':
        return 'DINE_IN';
      case 'Delivery':
        return 'DELIVERY';
      default:
        return 'TAKE_OUT';
    }
  }

  String _uiOrderType(String type) {
    switch (type) {
      case 'DINE_IN':
        return 'Dine In';
      case 'DELIVERY':
        return 'Delivery';
      default:
        return 'Take Out';
    }
  }

  String _uiStatus(String status) {
    switch (status) {
      case 'COMPLETED':
        return 'Completed';
      case 'VOIDED':
        return 'Void';
      case 'REFUNDED':
        return 'Refunded';
      case 'PARTIALLY_REFUNDED':
        return 'Partially Refunded';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return 'Open';
    }
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MutableModifierGroup {
  final String id;
  final String name;
  final int minSelections;
  final int? maxSelections;
  final bool isRequired;
  final List<PosModifierOption> options = [];

  _MutableModifierGroup({
    required this.id,
    required this.name,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
  });
}
