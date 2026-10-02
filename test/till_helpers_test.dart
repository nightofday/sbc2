import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/order_item.dart';
import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/reporting.dart';

void main() {
  test('quick cash offers the exact amount and the next notes above it', () {
    expect(quickCashAmounts(120), [120, 150, 200, 500, 1000]);
    expect(quickCashAmounts(369), [369, 400, 500, 1000]);
    // An amount that is already a note is not offered twice.
    expect(quickCashAmounts(500), [500, 1000]);
    expect(quickCashAmounts(0), isEmpty);
  });

  test(
    'a line is named without its size when the size is the ordinary one',
    () {
      expect(orderLineName('Cookie', 'Regular'), 'Cookie');
      expect(orderLineName('Cookie', ''), 'Cookie');
      expect(orderLineName('Cookie', 'Cookie'), 'Cookie');
      expect(orderLineName('Latte', 'Large'), 'Latte (Large)');
      expect(
        orderLineName('Coca-Cola', '330 ml Can'),
        'Coca-Cola (330 ml Can)',
      );
    },
  );

  test('money always shows two decimals, separators and a leading minus', () {
    expect(formatReportMoney(120), '₱120.00');
    expect(formatReportMoney(1540.5), '₱1,540.50');
    expect(formatReportMoney(-200), '-₱200.00');
    expect(formatReportMoney(0), '₱0.00');
  });

  test('an order shows its date once it is no longer today', () {
    final order = OrderRecord(
      id: '#1',
      createdAt: DateTime(2026, 10, 2, 21, 9),
      employee: 'Ana',
      type: 'Dine In',
      amount: 369,
      status: 'Completed',
      refundedAmount: 162,
    );

    expect(order.timeLabelAt(DateTime(2026, 10, 2, 23)), '9:09 PM');
    expect(order.timeLabelAt(DateTime(2026, 10, 3, 8)), 'Oct 2, 2026 9:09 PM');
    expect(order.dateTimeLabel, 'Oct 2, 2026 9:09 PM');
    // Changing the status keeps what was refunded.
    expect(order.copyWith(status: 'Refunded').refundedAmount, 162);
  });
}
