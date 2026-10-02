import '../../models/held_order.dart';

/// Orders set aside on this device to be paid later.
abstract class HeldOrdersStore {
  /// The signed-in user's held orders, oldest first.
  List<HeldOrder> get heldOrders;

  /// The user the next held order belongs to, or empty when signed out.
  String get heldOrdersOwnerId;

  Future<void> holdOrder(HeldOrder order);

  Future<void> removeHeldOrder(String id);
}
