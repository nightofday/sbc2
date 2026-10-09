import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/state/app_navigation_controller.dart';
import 'package:sbc_management_system/core/state/inventory_refresh_controller.dart';
import 'package:sbc_management_system/core/state/stock_alerts_controller.dart';
import 'package:sbc_management_system/domain/repositories/inventory_repository.dart';
import 'package:sbc_management_system/models/inventory_item.dart';
import 'package:sbc_management_system/models/stock_alerts.dart';
import 'package:sbc_management_system/widgets/common/stock_alerts_view.dart';

final _today = DateTime(2026, 10, 9);

InventoryItem _item(
  String name, {
  double usable = 10,
  double expired = 0,
  double reorder = 0,
  DateTime? nextExpiry,
}) => InventoryItem(
  id: name,
  name: name,
  category: 'Supplies',
  stock: '$usable pc',
  currentQuantity: usable + expired,
  usableQuantity: usable,
  expiredQuantity: expired,
  reorderLevel: reorder,
  baseUomCode: 'pc',
  nextExpirationDate: nextExpiry,
  status: '',
  supplier: '',
  expiration: nextExpiry == null ? '—' : 'soon',
);

class _Inventory implements InventoryRepository {
  List<InventoryItem> items;
  Object? failure;
  int loads = 0;

  _Inventory(this.items);

  @override
  Future<List<InventoryItem>> getInventoryItems() async {
    loads++;
    if (failure != null) throw failure!;
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StockAlerts', () {
    test('groups expired, expiring and low stock separately', () {
      final alerts = StockAlerts.fromItems([
        _item('Milk', expired: 4),
        _item('Water', nextExpiry: DateTime(2026, 10, 12)),
        _item('Bowls', usable: 18, reorder: 50),
        _item('Lids', usable: 200, reorder: 50),
        _item('Cheese', nextExpiry: DateTime(2026, 11, 30)),
      ], today: _today);

      expect(alerts.expired.map((i) => i.name), ['Milk']);
      expect(alerts.expiringSoon.map((i) => i.name), ['Water']);
      expect(alerts.belowReorder.map((i) => i.name), ['Bowls']);
      expect(alerts.itemCount, 3);
      expect(
        alerts.summary,
        '1 expired, 1 expiring within 7 days, 1 below reorder level',
      );
    });

    test('an item in two groups is counted once', () {
      final alerts = StockAlerts.fromItems([
        _item('Milk', usable: 2, expired: 4, reorder: 6),
      ], today: _today);

      expect(alerts.expired, hasLength(1));
      expect(alerts.belowReorder, hasLength(1));
      expect(alerts.itemCount, 1);
    });

    test('expiry counts the seventh day but not the eighth', () {
      final alerts = StockAlerts.fromItems([
        _item('Day 7', nextExpiry: DateTime(2026, 10, 16)),
        _item('Day 8', nextExpiry: DateTime(2026, 10, 17)),
      ], today: _today);

      expect(alerts.expiringSoon.map((i) => i.name), ['Day 7']);
    });

    test('nothing usable left means no expiring alert, only low stock', () {
      final alerts = StockAlerts.fromItems([
        _item('Empty', usable: 0, nextExpiry: DateTime(2026, 10, 10)),
      ], today: _today);

      expect(alerts.expiringSoon, isEmpty);
      expect(alerts.belowReorder.map((i) => i.name), ['Empty']);
    });

    test('expiring items are listed soonest first', () {
      final alerts = StockAlerts.fromItems([
        _item('Later', nextExpiry: DateTime(2026, 10, 15)),
        _item('Sooner', nextExpiry: DateTime(2026, 10, 10)),
      ], today: _today);

      expect(alerts.expiringSoon.map((i) => i.name), ['Sooner', 'Later']);
    });

    test('Manila date is used whatever the device timezone', () {
      // 18:30 UTC on 9 Oct is already 10 Oct in Manila.
      expect(
        manilaToday(DateTime.utc(2026, 10, 9, 18, 30)),
        DateTime(2026, 10, 10),
      );
      expect(
        manilaToday(DateTime.utc(2026, 10, 9, 15, 59)),
        DateTime(2026, 10, 9),
      );
    });
  });

  group('StockAlertsController', () {
    test(
      'reloads when inventory changes and keeps alerts on failure',
      () async {
        final inventory = _Inventory([_item('Milk', expired: 1)]);
        final refresh = InventoryRefreshController();
        final controller = StockAlertsController(
          inventory,
          refreshListenable: refresh,
          today: () => _today,
        );
        addTearDown(controller.dispose);

        await controller.load();
        expect(controller.alerts.itemCount, 1);

        inventory.items = [
          _item('Milk', expired: 1),
          _item('Bowls', usable: 1, reorder: 5),
        ];
        refresh.refresh();
        await pumpEventQueue();
        expect(inventory.loads, 2);
        expect(controller.alerts.itemCount, 2);

        inventory.failure = StateError('offline');
        await controller.load();
        expect(controller.error, isNotNull);
        expect(controller.alerts.itemCount, 2);
      },
    );
  });

  group('alerts widgets', () {
    Future<StockAlertsController> pumpAlerts(
      WidgetTester tester,
      List<InventoryItem> items, {
      VoidCallback? onOpenStockOverview,
    }) async {
      final controller = StockAlertsController(
        _Inventory(items),
        today: () => _today,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StockAlertsBanner(
                  controller: controller,
                  onOpenStockOverview: onOpenStockOverview,
                ),
                SizedBox(
                  width: 220,
                  child: StockAlertsButton(
                    controller: controller,
                    onOpenStockOverview: onOpenStockOverview,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('nothing to report hides the banner', (tester) async {
      await pumpAlerts(tester, [_item('Lids', usable: 200, reorder: 50)]);

      expect(find.textContaining('need attention'), findsNothing);
      expect(find.textContaining('needs attention'), findsNothing);
      expect(find.text('Stock alerts'), findsOneWidget);
    });

    testWidgets('the bell counts items and opens the grouped list', (
      tester,
    ) async {
      var opened = false;
      await pumpAlerts(tester, [
        _item('Fresh milk', expired: 4),
        _item('Bottled water', nextExpiry: DateTime(2026, 10, 12)),
        _item('Kraft bowls', usable: 18, reorder: 50),
      ], onOpenStockOverview: () => opened = true);

      expect(find.text('3'), findsOneWidget);
      expect(
        find.textContaining('3 stock items need attention'),
        findsOneWidget,
      );

      await tester.tap(find.text('Stock alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Expired · dispose to clear'), findsOneWidget);
      expect(find.text('Fresh milk'), findsOneWidget);
      expect(find.text('In 3 days'), findsOneWidget);
      expect(find.text('18 pc usable · reorder at 50 pc'), findsOneWidget);

      await tester.tap(find.text('Open stock overview'));
      await tester.pumpAndSettle();

      expect(find.text('Fresh milk'), findsNothing);
      expect(opened, isTrue);
    });
  });

  test('navigation requests reach listeners', () {
    final navigation = AppNavigationController();
    int? shown;
    navigation.addListener(() => shown = navigation.requested);
    navigation.show(4);
    expect(shown, 4);
    navigation.dispose();
  });
}
