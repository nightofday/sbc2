import '../../models/order_record.dart';
import '../../models/pos_checkout.dart';
import '../../models/pos_discount.dart';
import '../../models/pos_menu_item.dart';
import '../../models/pos_modifier.dart';
import '../../models/pos_payment_method.dart';
import '../../models/refund_preview.dart';
import '../../models/shift_cash_snapshot.dart';
import '../../models/shift_report.dart';

abstract class OrderRepository {
  Future<List<OrderRecord>> getOrders();

  Future<void> voidOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
  });

  Future<void> refundOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
    String? clientRequestId,
  });

  Future<RefundPreview> getRefundPreview(String id);

  Future<List<RefundRestockCandidate>> getRefundRestockCandidates(String id);

  Future<void> approveRefundItemRestock(
    String refundItemId, {
    String notes = '',
  });

  Future<void> refundOrderItems(
    String id, {
    required Map<String, double> quantities,
    required String reason,
    String externalReference = '',
    String? clientRequestId,
  });

  Future<List<PosMenuItem>> getPosMenu();

  Future<List<PosPaymentMethod>> getPaymentMethods();

  Future<List<PosDiscountType>> getPosDiscountTypes();

  Future<List<PosModifierGroup>> getModifierGroups(String menuItemId);

  Future<String?> getOpenShiftId();

  Future<String> startShift({double? openingCash, String? clientRequestId});

  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
    String? clientRequestId,
  });

  Future<ShiftCashSnapshot> getShiftCashSnapshot(String shiftId);

  /// The end-of-shift report for an open or closed shift.
  Future<ShiftReport> getShiftReport(String shiftId);

  /// Shifts started in the date range, newest first. Staff who do not
  /// manage shifts get their own only.
  Future<List<ShiftSummary>> getShifts({
    required DateTime from,
    required DateTime to,
  });

  Future<void> recordShiftCashMovement({
    required String shiftId,
    required String movementType,
    required double amount,
    required String reason,
    String? clientRequestId,
  });

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
  });

  /// Returns the order saved for [clientRequestId], or null if none was.
  Future<OrderRecord?> findOrderByRequestId(String clientRequestId);
}
