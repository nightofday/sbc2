import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/state/inventory_refresh_controller.dart';

void main() {
  test('inventory refresh controller notifies registered listeners', () {
    final controller = InventoryRefreshController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.refresh();

    expect(notifications, 1);
    controller.dispose();
  });

  test('inventory refresh also broadcasts dependent business changes', () {
    var businessNotifications = 0;
    final controller = InventoryRefreshController(
      onRefresh: () => businessNotifications++,
    );

    controller.refresh();

    expect(businessNotifications, 1);
    controller.dispose();
  });
}
