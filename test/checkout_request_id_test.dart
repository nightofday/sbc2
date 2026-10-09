import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_order_repository.dart';

import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/models/pos_payment_method.dart';
import 'package:sbc_management_system/models/request_id.dart';
import 'package:sbc_management_system/screens/orders/new_order_screen.dart';

/// Saves the sale on the first call but loses the response, as a dropped
/// connection would, then answers normally.
class _LostResponseOrderRepository extends FakeOrderRepository {
  final List<String> requestIds = [];
  final Map<String, OrderRecord> savedByRequestId = {};
  bool loseNextResponse = true;

  @override
  Future<List<PosMenuItem>> getPosMenu() async => const [
    PosMenuItem(
      variantId: 'variant-latte',
      menuItemId: 'item-latte',
      sku: 'TEST-LATTE',
      name: 'Test Latte',
      variantName: 'Regular',
      category: 'Coffee',
      price: 100,
      isDefault: true,
      inventoryTrackingMode: 'UNTRACKED',
      availableQuantity: null,
    ),
  ];

  @override
  Future<List<PosPaymentMethod>> getPaymentMethods() async => const [
    PosPaymentMethod(
      id: 'cash',
      code: 'CASH',
      name: 'Cash',
      isCash: true,
      requiresReference: false,
    ),
  ];

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
    requestIds.add(clientRequestId);

    // The server keeps one order per request ID.
    final order = savedByRequestId.putIfAbsent(
      clientRequestId,
      () => OrderRecord(
        id: '#${savedByRequestId.length + 1}',
        createdAt: DateTime(2026, 10, 2, 21),
        employee: 'Test Cashier',
        type: orderType,
        amount: 100,
        status: 'Completed',
        tableNumber: tableNumber,
        paymentMethod: 'Cash',
        amountReceived: 100,
      ),
    );

    if (loseNextResponse) {
      loseNextResponse = false;
      throw Exception('connection closed before a response was received');
    }

    return order;
  }

  @override
  Future<OrderRecord?> findOrderByRequestId(String clientRequestId) async {
    return savedByRequestId[clientRequestId];
  }
}

void main() {
  test('request IDs are version 4 UUIDs and differ', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final first = newRequestId(Random(1));
    final second = newRequestId(Random(2));

    expect(pattern.hasMatch(first), isTrue);
    expect(pattern.hasMatch(newRequestId()), isTrue);
    expect(first, isNot(second));
  });

  test('only a server answer counts as a definite rejection', () {
    expect(isServerRejectionCode('P0001'), isTrue);
    expect(isServerRejectionCode('23505'), isTrue);
    expect(isServerRejectionCode('PGRST301'), isTrue);
    expect(isServerRejectionCode('504'), isFalse);
    expect(isServerRejectionCode(''), isFalse);
    expect(isServerRejectionCode(null), isFalse);
  });

  test('an attempt keeps its ID until the outcome is known', () {
    var created = 0;
    final attempt = CheckoutAttempt(createId: () => 'id-${++created}');

    expect(attempt.hasUnresolved, isFalse);
    expect(attempt.requestIdFor('sale A'), 'id-1');
    expect(attempt.requestIdFor('sale A'), 'id-1');
    expect(attempt.conflictsWith('sale A'), isFalse);
    expect(attempt.conflictsWith('sale B'), isTrue);

    attempt.resolve();

    expect(attempt.hasUnresolved, isFalse);
    expect(attempt.conflictsWith('sale B'), isFalse);
    expect(attempt.requestIdFor('sale B'), 'id-2');
  });

  testWidgets('a lost response followed by a retry saves one order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _LostResponseOrderRepository();

    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pos-product-variant-latte')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Table Number *'),
      'T1',
    );
    await tester.tap(find.byKey(const ValueKey('pos-charge')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete Payment'));
    await tester.pumpAndSettle();

    expect(find.textContaining('may already be saved'), findsOneWidget);
    expect(find.text('Receipt'), findsNothing);

    await tester.tap(find.text('Complete Payment'));
    await tester.pumpAndSettle();

    expect(find.text('Receipt'), findsOneWidget);
    expect(repository.requestIds, hasLength(2));
    expect(repository.requestIds.first, repository.requestIds.last);
    expect(repository.savedByRequestId, hasLength(1));
  });
}
