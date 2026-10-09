import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/data/offline/key_value_store.dart';
import 'package:sbc_management_system/data/offline/offline_order_repository.dart';
import 'package:sbc_management_system/domain/repositories/offline_sales_queue.dart';
import 'package:sbc_management_system/models/held_order.dart';
import 'package:sbc_management_system/models/offline_sale.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/models/pos_modifier.dart';
import 'package:sbc_management_system/screens/orders/new_order_screen.dart';

import 'support/fake_order_repository.dart';

const _latte = PosMenuItem(
  variantId: 'latte',
  menuItemId: 'latte',
  sku: 'LATTE',
  name: 'Latte',
  variantName: 'Regular',
  category: 'Coffee',
  price: 120,
  isDefault: true,
  inventoryTrackingMode: 'UNTRACKED',
  availableQuantity: null,
);

class _Server extends FakeOrderRepository implements OfflineSaleUploader {
  double lattePrice = 120;
  bool latteOnMenu = true;

  @override
  Future<List<PosMenuItem>> getPosMenu() async => [
    if (latteOnMenu)
      PosMenuItem(
        variantId: 'latte',
        menuItemId: 'latte',
        sku: 'LATTE',
        name: 'Latte',
        variantName: 'Regular',
        category: 'Coffee',
        price: lattePrice,
        isDefault: true,
        inventoryTrackingMode: 'UNTRACKED',
        availableQuantity: null,
      ),
  ];

  @override
  Future<void> uploadOfflineSale(OfflineSale sale) async {}
}

OfflineOrderRepository _till(
  _Server server,
  KeyValueStore store, {
  String userId = 'user-1',
}) {
  return OfflineOrderRepository(
    remote: server,
    uploader: server,
    store: store,
    identity: () => OfflineIdentity(userId: userId, displayName: 'Ana'),
    retryInterval: const Duration(hours: 1),
  );
}

HeldOrder _held(String id, {String userId = 'user-1', DateTime? at}) =>
    HeldOrder(
      id: id,
      userId: userId,
      heldAt: at ?? DateTime(2026, 10, 3, 9),
      orderType: 'Dine In',
      tableNumber: 'T4',
      lines: const [
        HeldOrderLine(
          product: _latte,
          quantity: 2,
          modifiers: [
            PosModifierOption(id: 'shot', name: 'Shot', priceDelta: 30),
          ],
          note: 'Less ice',
        ),
      ],
    );

void main() {
  test('a held order keeps its lines, options and notes', () {
    final restored = HeldOrder.fromMap(_held('order-1').toMap());

    expect(restored.label, 'Table T4');
    expect(restored.itemCount, 2);
    expect(restored.total, 300);
    expect(restored.lines.single.modifiers.single.name, 'Shot');
    expect(restored.lines.single.note, 'Less ice');
  });

  test('held orders stay on the device and belong to who held them', () async {
    final server = _Server();
    final store = MemoryKeyValueStore();
    final ana = _till(server, store);
    addTearDown(ana.dispose);

    await ana.holdOrder(_held('order-2', at: DateTime(2026, 10, 3, 10)));
    await ana.holdOrder(_held('order-1', at: DateTime(2026, 10, 3, 9)));

    // Oldest first, and still there after the app is reopened.
    final reopened = _till(server, store);
    addTearDown(reopened.dispose);
    expect(reopened.heldOrders.map((order) => order.id), [
      'order-1',
      'order-2',
    ]);

    final ben = _till(server, store, userId: 'user-2');
    addTearDown(ben.dispose);
    expect(ben.heldOrders, isEmpty);

    await ana.removeHeldOrder('order-1');
    expect(ana.heldOrders.single.id, 'order-2');
  });

  testWidgets('an order can be held and continued at the current price', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = _Server();
    final till = _till(server, MemoryKeyValueStore());

    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: till)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Held (0)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pos-product-latte')));
    await tester.pumpAndSettle();

    // Without a table or a name the order could not be found again.
    await tester.tap(find.text('Hold'));
    await tester.pumpAndSettle();
    expect(find.textContaining('so the order can be found'), findsOneWidget);
    expect(till.heldOrders, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Table Number *'),
      'T7',
    );
    await tester.tap(find.text('Hold'));
    await tester.pumpAndSettle();

    expect(find.text('Held (1)'), findsOneWidget);
    expect(find.text('No items added yet.'), findsOneWidget);
    expect(till.heldOrders.single.tableNumber, 'T7');

    // The price changes while the order waits.
    server.lattePrice = 130;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: till)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Held (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Table T7'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Held (0)'), findsOneWidget);
    expect(find.text('No items added yet.'), findsNothing);
    expect(find.widgetWithText(TextField, 'T7'), findsOneWidget);
    // Charged at today's price, not the price when it was held.
    expect(find.text('₱130.00'), findsWidgets);

    till.dispose();
  });
}
