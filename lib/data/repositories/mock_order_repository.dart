import '../../domain/repositories/order_repository.dart';
import '../../models/order_record.dart';
import '../../models/pos_checkout.dart';
import '../../models/pos_discount.dart';
import '../../models/pos_menu_item.dart';
import '../../models/pos_modifier.dart';
import '../../models/pos_payment_method.dart';
import '../../models/refund_preview.dart';
import '../../models/shift_cash_snapshot.dart';
import '../mock_data.dart';

class MockOrderRepository implements OrderRepository {
  final List<OrderRecord> _orders = List<OrderRecord>.from(MockData.orders);

  @override
  Future<List<OrderRecord>> getOrders() async {
    return List<OrderRecord>.unmodifiable(_orders);
  }

  @override
  Future<OrderRecord?> getOrderById(String id) async {
    for (final order in _orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  @override
  Future<void> createOrder(OrderRecord order) async {
    _orders.insert(0, order);
  }

  @override
  Future<void> updateOrder(OrderRecord order) async {
    final index = _orders.indexWhere((entry) => entry.id == order.id);
    if (index == -1) return;
    _orders[index] = order;
  }

  @override
  Future<void> voidOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
  }) async {
    final index = _orders.indexWhere((entry) => entry.id == id);
    if (index == -1) return;

    _orders[index] = _orders[index].copyWith(
      status: 'Void',
      lastActionReason: reason,
      authorizedBy: authorizedBy,
    );
  }

  @override
  Future<void> refundOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
  }) async {
    final index = _orders.indexWhere((entry) => entry.id == id);
    if (index == -1) return;

    _orders[index] = _orders[index].copyWith(
      status: 'Refunded',
      lastActionReason: reason,
      authorizedBy: authorizedBy,
    );
  }

  @override
  Future<RefundPreview> getRefundPreview(String id) async {
    throw UnsupportedError('Mock refund preview is not implemented.');
  }

  @override
  Future<void> refundOrderItems(
    String id, {
    required Map<String, double> quantities,
    required String reason,
    String externalReference = '',
  }) async {
    await refundOrder(id, reason: reason);
  }

  @override
  Future<List<RefundRestockCandidate>> getRefundRestockCandidates(
    String id,
  ) async => const [];

  @override
  Future<void> approveRefundItemRestock(
    String refundItemId, {
    String notes = '',
  }) async {}

  @override
  Future<List<PosMenuItem>> getPosMenu() async => const [];

  @override
  Future<List<PosPaymentMethod>> getPaymentMethods() async => const [];

  @override
  Future<List<PosDiscountType>> getPosDiscountTypes() async => const [];

  @override
  Future<List<PosModifierGroup>> getModifierGroups(String menuItemId) async =>
      const [];

  @override
  Future<String?> getOpenShiftId() async => 'mock-shift';

  @override
  Future<String> startShift({double? openingCash}) async => 'mock-shift';

  @override
  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
  }) async {}

  @override
  Future<ShiftCashSnapshot> getShiftCashSnapshot(String shiftId) async {
    return ShiftCashSnapshot(
      shiftId: shiftId,
      openingCash: 0,
      cashSales: 0,
      cashRefunds: 0,
      cashIn: 0,
      cashOut: 0,
      expectedCash: 0,
      status: 'OPEN',
    );
  }

  @override
  Future<void> recordShiftCashMovement({
    required String shiftId,
    required String movementType,
    required double amount,
    required String reason,
  }) async {}

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
  }) {
    throw UnimplementedError('Mock POS placement is not used by the live app.');
  }
}
