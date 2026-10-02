import 'package:sbc_management_system/domain/repositories/order_repository.dart';
import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/pos_discount.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';
import 'package:sbc_management_system/models/pos_modifier.dart';
import 'package:sbc_management_system/models/pos_payment_method.dart';
import 'package:sbc_management_system/models/refund_preview.dart';
import 'package:sbc_management_system/models/shift_cash_snapshot.dart';
import 'package:sbc_management_system/models/shift_report.dart';

/// An in-memory order repository for tests. Tests override what they need.
class FakeOrderRepository implements OrderRepository {
  final List<OrderRecord> _orders = [];

  @override
  Future<List<OrderRecord>> getOrders() async {
    return List<OrderRecord>.unmodifiable(_orders);
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
    String? clientRequestId,
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
    throw UnsupportedError('The fake has no refund preview.');
  }

  @override
  Future<void> refundOrderItems(
    String id, {
    required Map<String, double> quantities,
    required String reason,
    String externalReference = '',
    String? clientRequestId,
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
  Future<String?> getOpenShiftId() async => 'test-shift';

  @override
  Future<String> startShift({
    double? openingCash,
    String? clientRequestId,
  }) async => 'test-shift';

  @override
  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
    String? clientRequestId,
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
  Future<ShiftReport> getShiftReport(String shiftId) async {
    return ShiftReport.fromMap({'shift_id': shiftId, 'status': 'OPEN'});
  }

  @override
  Future<List<ShiftSummary>> getShifts({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<void> recordShiftCashMovement({
    required String shiftId,
    required String movementType,
    required double amount,
    required String reason,
    String? clientRequestId,
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
    required String clientRequestId,
  }) {
    throw UnimplementedError('Override placeOrder in the test.');
  }

  @override
  Future<OrderRecord?> findOrderByRequestId(String clientRequestId) async {
    return null;
  }
}
