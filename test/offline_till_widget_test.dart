import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/data/offline/key_value_store.dart';
import 'package:sbc_management_system/data/offline/offline_order_repository.dart';

import 'support/fake_order_repository.dart';

import 'package:sbc_management_system/domain/repositories/offline_sales_queue.dart';
import 'package:sbc_management_system/models/offline_sale.dart';
import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/models/pos_payment_method.dart';
import 'package:sbc_management_system/screens/orders/new_order_screen.dart';
import 'package:sbc_management_system/widgets/common/offline_status_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _Server extends FakeOrderRepository implements OfflineSaleUploader {
  bool reachable = true;
  String? rejectUploadsWith;
  final List<OfflineSale> uploads = [];

  void _connect() {
    if (!reachable) throw Exception('Failed to fetch');
  }

  @override
  Future<List<PosMenuItem>> getPosMenu() async {
    _connect();
    return const [
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
  Future<String?> getOpenShiftId() async {
    _connect();
    return 'shift-1';
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
    throw StateError('The test only sells offline.');
  }

  @override
  Future<void> uploadOfflineSale(OfflineSale sale) async {
    _connect();
    final rejection = rejectUploadsWith;
    if (rejection != null) {
      throw PostgrestException(message: rejection, code: 'P0001');
    }
    uploads.add(sale);
  }
}

void main() {
  testWidgets('a sale taken offline gets a receipt and is sent later', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = _Server();
    final till = OfflineOrderRepository(
      remote: server,
      uploader: server,
      store: MemoryKeyValueStore(),
      identity: () =>
          const OfflineIdentity(userId: 'user-1', displayName: 'Ana'),
      retryInterval: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OfflineStatusBanner(queue: till),
              Expanded(child: NewOrderScreen(orderRepository: till)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline'), findsNothing);

    // The connection drops after the till has loaded.
    server.reachable = false;

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

    expect(find.text('Receipt'), findsOneWidget);
    expect(find.textContaining('Saved on this device'), findsOneWidget);
    expect(find.textContaining('OFFLINE-'), findsOneWidget);
    expect(till.waitingSales, hasLength(1));
    expect(find.textContaining('1 sale saved on this device'), findsOneWidget);

    // Back online: the server refuses it, and the banner says so.
    server
      ..reachable = true
      ..rejectUploadsWith = 'No open shift';
    await tester.runAsync(till.syncPending);
    await tester.pumpAndSettle();

    expect(find.textContaining('needs attention'), findsOneWidget);

    // Once the cause is fixed, sending again clears it.
    server.rejectUploadsWith = null;
    await tester.runAsync(
      () => till.retrySale(till.rejectedSales.single.requestId),
    );
    await tester.pumpAndSettle();

    expect(server.uploads.single.total, 100);
    expect(find.textContaining('needs attention'), findsNothing);
    expect(find.textContaining('saved on this device'), findsNothing);

    till.dispose();
  });
}
