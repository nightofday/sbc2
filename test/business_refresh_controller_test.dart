import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/state/business_refresh_controller.dart';

void main() {
  test('business refresh controller notifies registered listeners', () {
    final controller = BusinessRefreshController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.refresh();

    expect(notifications, 1);
    controller.dispose();
  });
}
