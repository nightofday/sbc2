import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/shift_report.dart';
import 'package:sbc_management_system/screens/orders/shifts_screen.dart';

import 'support/fake_order_repository.dart';

const _reportJson = <String, dynamic>{
  'shift_id': 'shift-1',
  'shift_number': 12,
  'status': 'CLOSED',
  'employee_name': 'Ana',
  'started_at': '2026-10-02T00:00:00Z',
  'ended_at': '2026-10-02T09:00:00Z',
  'closing_notes': 'Counted twice',
  'sales': {
    'order_count': 2,
    'voided_count': 1,
    'gross_sales': 260,
    'discounts': 20,
    'refunds': 0,
    'net_sales': 240,
  },
  'by_payment_method': [
    {
      'payment_method': 'Cash',
      'is_cash': true,
      'payment_count': 1,
      'received': 160,
      'refunded': 0,
      'net': 160,
    },
    {
      'payment_method': 'GCash',
      'is_cash': false,
      'payment_count': 1,
      'received': 80,
      'refunded': 0,
      'net': 80,
    },
  ],
  'cash_movements': [
    {
      'movement_type': 'PAY_OUT',
      'amount': 50,
      'reason': 'Ice',
      'recorded_by': 'Ana',
      'created_at': '2026-10-02T03:00:00Z',
    },
  ],
  'cash': {
    'opening_cash': 500,
    'cash_sales': 160,
    'cash_refunds': 0,
    'cash_in': 0,
    'cash_out': 50,
    'expected_cash': 610,
    'counted_cash': 600,
    'variance': -10,
  },
};

class _ShiftRepository extends FakeOrderRepository {
  @override
  Future<List<ShiftSummary>> getShifts({
    required DateTime from,
    required DateTime to,
  }) async => [
    ShiftSummary.fromMap(const {
      'shift_id': 'shift-1',
      'shift_number': 12,
      'status': 'CLOSED',
      'employee_name': 'Ana',
      'started_at': '2026-10-02T00:00:00Z',
      'ended_at': '2026-10-02T09:00:00Z',
      'opening_cash': 500,
      'expected_cash': 610,
      'counted_cash': 600,
      'variance': -10,
      'order_count': 2,
    }),
  ];

  @override
  Future<ShiftReport> getShiftReport(String shiftId) async =>
      ShiftReport.fromMap(_reportJson);
}

void main() {
  test('a shift report reads its sections and adds up', () {
    final report = ShiftReport.fromMap(_reportJson);

    expect(report.netSales, report.grossSales - report.discounts);
    expect(
      report.payments.fold<double>(0, (sum, payment) => sum + payment.net),
      report.netSales,
    );
    expect(
      report.expectedCash,
      report.openingCash + report.cashSales - report.cashOut,
    );
    expect(report.variance, -10);
    expect(report.cashMovements.single.addsCash, isFalse);
  });

  test('the copied report says the drawer was short', () {
    final text = ShiftReport.fromMap(_reportJson).toText();

    expect(text, contains('Shift #12 — Ana'));
    expect(text, contains('Orders: 2 (1 voided)'));
    expect(text, contains('Net sales: ₱240.00'));
    expect(text, contains('Expected in drawer: ₱610.00'));
    expect(text, contains('Difference: -₱10.00 short'));
  });

  test('an open shift has no count or difference yet', () {
    final report = ShiftReport.fromMap(const {
      'status': 'OPEN',
      'cash': {'expected_cash': 500},
    });

    expect(report.isOpen, isTrue);
    expect(report.countedCash, isNull);
    expect(report.toText(), contains('still open'));
    expect(report.toText(), isNot(contains('Difference')));
  });

  for (final width in [1300.0, 360.0]) {
    testWidgets('the shift list opens a report at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftsScreen(orderRepository: _ShiftRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('#12 · Ana'), findsOneWidget);
      expect(find.text('₱10.00 short'), findsOneWidget);

      await tester.ensureVisible(find.text('Report'));
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Shift report'), findsOneWidget);
      expect(find.text('Expected in drawer'), findsOneWidget);
      expect(find.text('Short'), findsOneWidget);
      expect(find.text('Cash out · Ice'), findsOneWidget);
    });
  }
}
