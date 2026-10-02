import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/screens/orders/new_order_screen.dart';

import 'support/fake_order_repository.dart';

class _MenuRepository extends FakeOrderRepository {
  @override
  Future<List<PosMenuItem>> getPosMenu() async => const [
    PosMenuItem(
      variantId: 'latte-large',
      menuItemId: 'latte',
      sku: 'LATTE-L',
      name: 'Latte',
      variantName: 'Large',
      category: 'Coffee',
      price: 150,
      isDefault: false,
      inventoryTrackingMode: 'UNTRACKED',
      availableQuantity: null,
    ),
    PosMenuItem(
      variantId: 'cake',
      menuItemId: 'cake',
      sku: 'CAKE',
      name: 'Chocolate Cake',
      variantName: 'Regular',
      category: 'Baked Goods',
      price: 180,
      isDefault: true,
      inventoryTrackingMode: 'FINISHED_GOOD',
      availableQuantity: 0,
    ),
  ];
}

void main() {
  testWidgets('on a phone products are rows and the tab shows the cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: _MenuRepository())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Latte (Large)'), findsOneWidget);
    expect(find.text('Chocolate Cake'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Current Order'), findsOneWidget);

    // Tapping the row adds the product.
    await tester.tap(find.text('Latte (Large)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Latte (Large)'));
    await tester.pumpAndSettle();

    expect(find.text('Order (2) · ₱300.00'), findsOneWidget);

    // A sold-out product cannot be added.
    await tester.tap(find.text('Chocolate Cake'));
    await tester.pumpAndSettle();

    expect(find.text('Order (2) · ₱300.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
