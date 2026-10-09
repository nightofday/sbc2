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
    expect(find.text('Current order'), findsOneWidget);

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

  testWidgets('on a tablet tapping anywhere on a card adds the product', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: _MenuRepository())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // There is no separate Add button to aim for.
    expect(find.text('Add'), findsNothing);

    final latte = find.byKey(const ValueKey('pos-product-latte-large'));
    final cake = find.byKey(const ValueKey('pos-product-cake'));
    Finder badgeOn(Finder card, String quantity) =>
        find.descendant(of: card, matching: find.text(quantity));

    // Tap the card's bottom-left corner, away from its text.
    final corner = tester.getBottomLeft(latte) + const Offset(6, -6);
    await tester.tapAt(corner);
    await tester.pumpAndSettle();
    await tester.tapAt(corner);
    await tester.pumpAndSettle();

    // The card shows how many are already in the order.
    expect(badgeOn(latte, '2'), findsOneWidget);

    // A sold-out card cannot be added.
    await tester.tap(cake);
    await tester.pumpAndSettle();
    expect(badgeOn(cake, '1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the order panel has large quantity and charge buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: NewOrderScreen(orderRepository: _MenuRepository())),
    );
    await tester.pumpAndSettle();

    final latte = find.byKey(const ValueKey('pos-product-latte-large'));
    await tester.tap(latte);
    await tester.pumpAndSettle();

    // The charge button names the amount.
    expect(find.text('Charge ₱150.00'), findsOneWidget);
    // Buttons are at least 48 px, so a finger can hit them.
    final more = find.byTooltip('One more Latte');
    expect(tester.getSize(more).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.byKey(const ValueKey('pos-charge'))).height,
      greaterThanOrEqualTo(56),
    );

    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Charge ₱300.00'), findsOneWidget);

    await tester.tap(find.byTooltip('One less Latte'));
    await tester.pumpAndSettle();

    // At one, the same button takes the line off the order.
    expect(find.byTooltip('One less Latte'), findsNothing);
    await tester.tap(find.byTooltip('Remove Latte from the order'));
    await tester.pumpAndSettle();

    expect(find.text('Charge'), findsOneWidget);
    expect(find.text('No items added yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
