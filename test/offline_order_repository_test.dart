import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/data/offline/key_value_store.dart';
import 'package:sbc_management_system/data/offline/offline_order_repository.dart';

import 'support/fake_order_repository.dart';

import 'package:sbc_management_system/domain/repositories/offline_sales_queue.dart';
import 'package:sbc_management_system/models/offline_sale.dart';
import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/models/pos_modifier.dart';
import 'package:sbc_management_system/models/pos_payment_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// A server that can be unplugged. It keeps one order per request ID, as
/// the database does.
class _FakeServer extends FakeOrderRepository implements OfflineSaleUploader {
  bool reachable = true;
  String? rejectUploadsWith;
  String? openShiftId = 'shift-1';
  final List<String> placedRequestIds = [];
  final List<OfflineSale> uploads = [];
  final List<String?> shiftStartRequestIds = [];
  final Map<String, OrderRecord> ordersByRequestId = {};
  int modifierCalls = 0;

  void _connect() {
    if (!reachable) throw const SocketException('Network is unreachable');
  }

  @override
  Future<List<PosMenuItem>> getPosMenu() async {
    _connect();
    return const [
      PosMenuItem(
        variantId: 'variant-bowl',
        menuItemId: 'item-bowl',
        sku: 'BOWL',
        name: 'Rice Bowl',
        variantName: 'Regular',
        category: 'Bowls',
        price: 150,
        isDefault: true,
        inventoryTrackingMode: 'FINISHED_GOOD',
        availableQuantity: 3,
      ),
    ];
  }

  @override
  Future<List<PosPaymentMethod>> getPaymentMethods() async {
    _connect();
    return const [
      PosPaymentMethod(
        id: 'cash',
        code: 'CASH',
        name: 'Cash',
        isCash: true,
        requiresReference: false,
      ),
    ];
  }

  @override
  Future<List<PosModifierGroup>> getModifierGroups(String menuItemId) async {
    _connect();
    modifierCalls++;
    return const [
      PosModifierGroup(
        id: 'group-extras',
        name: 'Extras',
        minSelections: 0,
        maxSelections: 2,
        isRequired: false,
        options: [PosModifierOption(id: 'egg', name: 'Egg', priceDelta: 20)],
      ),
    ];
  }

  @override
  Future<String?> getOpenShiftId() async {
    _connect();
    return openShiftId;
  }

  @override
  Future<String> startShift({
    double? openingCash,
    String? clientRequestId,
  }) async {
    _connect();
    shiftStartRequestIds.add(clientRequestId);
    return openShiftId = 'shift-started';
  }

  @override
  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
    String? clientRequestId,
  }) async {
    _connect();
    openShiftId = null;
  }

  @override
  Future<List<OrderRecord>> getOrders() async {
    _connect();
    return ordersByRequestId.values.toList();
  }

  OrderRecord _store(String requestId, DateTime at, double amount) {
    return ordersByRequestId.putIfAbsent(
      requestId,
      () => OrderRecord(
        id: '#${ordersByRequestId.length + 1}',
        createdAt: at,
        employee: 'Cashier',
        type: 'Takeout',
        amount: amount,
        status: 'Completed',
      ),
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
    _connect();
    placedRequestIds.add(clientRequestId);
    return _store(
      clientRequestId,
      DateTime(2026, 10, 2),
      payments.first.amount,
    );
  }

  @override
  Future<void> uploadOfflineSale(OfflineSale sale) async {
    _connect();
    final rejection = rejectUploadsWith;
    if (rejection != null) {
      throw PostgrestException(message: rejection, code: 'P0001');
    }
    uploads.add(sale);
    _store(sale.requestId, sale.soldAt, sale.total);
  }
}

const _cashier = OfflineIdentity(userId: 'user-1', displayName: 'Ana');

Future<OrderRecord> _sell(
  OfflineOrderRepository till,
  String requestId, {
  List<String> modifierIds = const [],
  double amount = 150,
}) {
  return till.placeOrder(
    clientRequestId: requestId,
    orderType: 'Takeout',
    items: [
      PosCheckoutItem(
        menuVariantId: 'variant-bowl',
        quantity: 1,
        modifierIds: modifierIds,
      ),
    ],
    payments: [
      PosPaymentInput(
        paymentMethodId: 'cash',
        amount: amount,
        amountTendered: 200,
        changeAmount: 200 - amount,
      ),
    ],
  );
}

void main() {
  late _FakeServer server;
  late MemoryKeyValueStore store;
  late DateTime clock;

  OfflineOrderRepository openTill({OfflineIdentity? identity = _cashier}) {
    final till = OfflineOrderRepository(
      remote: server,
      uploader: server,
      store: store,
      identity: () => identity,
      now: () => clock,
      // Long enough that the retry timer never fires inside a test.
      retryInterval: const Duration(hours: 1),
    );
    addTearDown(till.dispose);
    return till;
  }

  /// Loads everything a till loads when it opens, which fills the cache.
  Future<void> warmUp(OfflineOrderRepository till) async {
    await till.getPosMenu();
    await till.getPaymentMethods();
    await till.getModifierGroups('item-bowl');
    await till.getOpenShiftId();
  }

  setUp(() {
    server = _FakeServer();
    store = MemoryKeyValueStore();
    clock = DateTime(2026, 10, 2, 12, 30);
  });

  test('an online sale goes straight to the server', () async {
    final till = openTill();

    final order = await _sell(till, 'request-1');

    expect(order.id, '#1');
    expect(server.placedRequestIds, ['request-1']);
    expect(till.waitingSales, isEmpty);
    expect(till.isOffline, isFalse);
  });

  test(
    'a sale taken with no connection is kept and shown as waiting',
    () async {
      final till = openTill();
      await warmUp(till);
      server.reachable = false;

      final order = await _sell(
        till,
        'aaaaaaaa-1111',
        modifierIds: ['egg'],
        amount: 170,
      );

      expect(order.status, OfflineSale.waitingStatus);
      expect(order.id, 'OFFLINE-AAAAAA');
      expect(order.amount, 170);
      expect(order.employee, 'Ana');
      expect(order.paymentMethod, 'Cash');
      expect(order.items.single.productName, 'Rice Bowl + Egg');
      expect(order.items.single.unitPrice, 170);
      expect(till.isOffline, isTrue);
      expect(till.waitingSales.single.soldAt, clock);
    },
  );

  test('waiting sales survive closing the app', () async {
    final till = openTill();
    await warmUp(till);
    server.reachable = false;
    await _sell(till, 'request-1');

    final reopened = openTill();

    expect(reopened.waitingSales.single.requestId, 'request-1');
    expect(reopened.waitingSales.single.total, 150);
  });

  test(
    'syncing sends each sale once, oldest first, at its sale time',
    () async {
      final till = openTill();
      await warmUp(till);
      server.reachable = false;

      await _sell(till, 'request-1');
      clock = clock.add(const Duration(minutes: 5));
      await _sell(till, 'request-2');

      server.reachable = true;
      await till.syncPending();
      await till.syncPending();

      expect(server.uploads.map((sale) => sale.requestId), [
        'request-1',
        'request-2',
      ]);
      expect(server.uploads.first.soldAt, DateTime(2026, 10, 2, 12, 30));
      expect(server.uploads.last.soldAt, DateTime(2026, 10, 2, 12, 35));
      expect(till.waitingSales, isEmpty);
      expect(till.isOffline, isFalse);
    },
  );

  test('a sale whose answer was lost is not saved twice', () async {
    final till = openTill();
    await warmUp(till);

    // The server stores the order, then the connection drops.
    server._store('request-1', clock, 150);
    server.reachable = false;
    await _sell(till, 'request-1');

    // Tapping pay again offline does not queue a second copy.
    await _sell(till, 'request-1');
    expect(till.waitingSales, hasLength(1));

    server.reachable = true;
    await till.syncPending();

    expect(server.ordersByRequestId, hasLength(1));
    expect(till.waitingSales, isEmpty);
  });

  test('a sale made while others wait joins the queue behind them', () async {
    final till = openTill();
    await warmUp(till);
    server.reachable = false;
    await _sell(till, 'request-1');

    // Still unreachable: the second sale must not jump ahead.
    await _sell(till, 'request-2');
    expect(server.placedRequestIds, isEmpty);
    expect(till.waitingSales, hasLength(2));

    // Back online: the queue drains first, then the new sale posts live.
    server.reachable = true;
    final live = await _sell(till, 'request-3');

    expect(server.uploads.map((sale) => sale.requestId), [
      'request-1',
      'request-2',
    ]);
    expect(server.placedRequestIds, ['request-3']);
    expect(live.status, 'Completed');
  });

  test('a sale the server refuses is kept for a manager', () async {
    final till = openTill();
    await warmUp(till);
    server.reachable = false;
    await _sell(till, 'request-1');
    await _sell(till, 'request-2');

    server.reachable = true;
    server.rejectUploadsWith = 'No open shift';
    await till.syncPending();

    expect(till.waitingSales, isEmpty);
    expect(till.rejectedSales, hasLength(2));
    expect(till.rejectedSales.first.rejection, 'No open shift');
    expect((await till.getOrders()).first.status, OfflineSale.rejectedStatus);

    // Once the cause is fixed it can be sent again.
    server.rejectUploadsWith = null;
    await till.retrySale('request-1');

    expect(server.uploads.single.requestId, 'request-1');
    expect(till.rejectedSales.single.requestId, 'request-2');

    await till.discardSale('request-2');
    expect(till.rejectedSales, isEmpty);
  });

  test('a waiting sale cannot be discarded', () async {
    final till = openTill();
    await warmUp(till);
    server.reachable = false;
    await _sell(till, 'request-1');

    await till.discardSale('request-1');

    expect(till.waitingSales, hasLength(1));
  });

  test('a server refusal at the till is not queued', () async {
    final till = openTill();
    final refusing = _RefusingServer();
    final strictTill = OfflineOrderRepository(
      remote: refusing,
      uploader: refusing,
      store: store,
      identity: () => _cashier,
      retryInterval: const Duration(hours: 1),
    );
    addTearDown(strictTill.dispose);

    await expectLater(
      _sell(strictTill, 'request-1'),
      throwsA(isA<PostgrestException>()),
    );
    expect(strictTill.waitingSales, isEmpty);
    expect(till.waitingSales, isEmpty);
  });

  test('the till opens from the device cache when offline', () async {
    await warmUp(openTill());
    server.reachable = false;
    final till = openTill();

    final menu = await till.getPosMenu();
    final methods = await till.getPaymentMethods();
    final groups = await till.getModifierGroups('item-bowl');

    expect(menu.single.name, 'Rice Bowl');
    // Kept stock levels are stale, so the cached menu does not block sales.
    expect(menu.single.availableQuantity, isNull);
    expect(menu.single.isOutOfStock, isFalse);
    expect(methods.single.name, 'Cash');
    expect(groups.single.options.single.priceDelta, 20);
    expect(await till.getOpenShiftId(), 'shift-1');
    expect(till.isOffline, isTrue);
  });

  test('loading the menu also keeps the options of every product', () async {
    final till = openTill();
    await till.getPosMenu();
    await pumpEventQueue();
    expect(server.modifierCalls, 1);

    server.reachable = false;

    expect(
      (await openTill().getModifierGroups('item-bowl')).single.name,
      'Extras',
    );
  });

  test('with nothing cached an offline till reports the failure', () async {
    server.reachable = false;

    await expectLater(openTill().getPosMenu(), throwsA(isA<SocketException>()));
  });

  test(
    'a shift opened offline is opened on the server before its sales',
    () async {
      final till = openTill();
      await till.getPosMenu();
      await till.getPaymentMethods();
      server
        ..openShiftId = null
        ..reachable = false;

      final localShift = await till.startShift(
        openingCash: 500,
        clientRequestId: 'shift-request',
      );
      expect(localShift, startsWith('offline-shift-'));
      expect(await till.getOpenShiftId(), localShift);

      await _sell(till, 'request-1');

      server.reachable = true;
      await till.syncPending();

      expect(server.shiftStartRequestIds, ['shift-request']);
      expect(server.uploads.single.requestId, 'request-1');
      expect(await till.getOpenShiftId(), 'shift-started');
    },
  );

  test('a shift cannot close while sales are still on the device', () async {
    final till = openTill();
    await warmUp(till);
    server.reachable = false;
    await _sell(till, 'request-1');

    await expectLater(
      till.endShift(shiftId: 'shift-1'),
      throwsA(isA<OfflineSalesPendingException>()),
    );

    server.reachable = true;
    await till.endShift(shiftId: 'shift-1');

    expect(server.uploads, hasLength(1));
    expect(server.openShiftId, isNull);
  });

  test('offline sales are listed first and cannot be refunded yet', () async {
    final till = openTill();
    await warmUp(till);
    await _sell(till, 'request-0');
    server.reachable = false;
    final offline = await _sell(till, 'request-1');

    // Offline, only this device's sales can be shown.
    expect((await till.getOrders()).single.id, offline.id);
    expect(
      () => till.refundOrder(offline.id, reason: 'Wrong item'),
      throwsA(isA<OfflineUnavailableException>()),
    );

    server.reachable = true;
    final orders = await till.getOrders();
    expect(orders.map((order) => order.id), [offline.id, '#1']);
  });

  test('one cashier never sees or sends another cashier\'s sales', () async {
    final ana = openTill();
    await warmUp(ana);
    server.reachable = false;
    await _sell(ana, 'request-1');

    final ben = openTill(
      identity: const OfflineIdentity(userId: 'user-2', displayName: 'Ben'),
    );
    server.reachable = true;
    await ben.syncPending();

    expect(ben.waitingSales, isEmpty);
    expect(server.uploads, isEmpty);
    expect(openTill().waitingSales, hasLength(1));
  });

  test('listeners hear about queue and connection changes', () async {
    final till = openTill();
    await warmUp(till);
    var notifications = 0;
    till.addListener(() => notifications++);

    server.reachable = false;
    await _sell(till, 'request-1');
    final afterSale = notifications;
    server.reachable = true;
    await till.syncPending();

    expect(afterSale, greaterThan(0));
    expect(notifications, greaterThan(afterSale));
  });

  test('connection failures are told apart from server refusals', () {
    expect(isConnectionFailure(const SocketException('down')), isTrue);
    expect(
      isConnectionFailure(
        const PostgrestException(message: 'Gateway', code: '504'),
      ),
      isTrue,
    );
    expect(
      isConnectionFailure(
        const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
      ),
      isTrue,
    );
    expect(
      isConnectionFailure(
        const PostgrestException(message: 'timeout', code: '57014'),
      ),
      isTrue,
    );
    expect(
      isConnectionFailure(
        const PostgrestException(message: 'Insufficient stock', code: 'P0001'),
      ),
      isFalse,
    );
    expect(isConnectionFailure(const CheckoutSavedException('12')), isFalse);
  });
}

class _RefusingServer extends _FakeServer {
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
    throw const PostgrestException(
      message: 'Insufficient stock',
      code: 'P0001',
    );
  }
}
