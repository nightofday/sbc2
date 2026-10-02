import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/order_item.dart';
import 'package:sbc_management_system/models/order_record.dart';
import 'package:sbc_management_system/models/business_profile.dart';
import 'package:sbc_management_system/models/pos_checkout.dart';
import 'package:sbc_management_system/models/receipt_text.dart';
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

  test('the copied receipt carries the header, lines, discount and refund', () {
    final text = receiptText(
      OrderRecord(
        id: '#12',
        createdAt: DateTime(2026, 10, 3, 9, 5),
        employee: 'Ana',
        type: 'Dine In',
        tableNumber: 'T4',
        amount: 369,
        status: 'Partially Refunded',
        invoiceNumber: 'SI-00000012',
        paymentMethod: 'Cash',
        amountReceived: 400,
        changeAmount: 31,
        subtotal: 410,
        discountAmount: 41,
        discountName: 'Promo 10%',
        refundedAmount: 162,
        items: const [
          OrderItem(
            productId: '1',
            productName: 'Latte (Large)',
            unitPrice: 180,
            quantity: 2,
            options: ['Extra Shot'],
            note: 'Less ice',
          ),
          OrderItem(
            productId: '2',
            productName: 'Cookie',
            unitPrice: 50,
            quantity: 1,
          ),
        ],
      ),
      const BusinessProfile(tradeName: 'Street Bowl Café', tin: '123'),
    );

    expect(text, startsWith('Street Bowl Café\nTIN 123\n'));
    expect(text, contains('#12 · Oct 3, 2026 9:05 AM'));
    expect(text, contains('Dine In · Table T4'));
    expect(text, contains('2 × Latte (Large)   ₱360.00'));
    expect(text, contains('   Extra Shot'));
    expect(text, contains('   Note: Less ice'));
    expect(text, contains('Discount (Promo 10%): -₱41.00'));
    expect(text, contains('Total: ₱369.00'));
    expect(text, contains('Change: ₱31.00'));
    expect(text, contains('Refunded: -₱162.00'));
  });
}
