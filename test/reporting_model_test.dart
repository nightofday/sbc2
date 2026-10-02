import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/reporting.dart';

void main() {
  Map<String, dynamic> sampleReport() => {
    'from': '2026-10-01',
    'to': '2026-10-02',
    'summary': {
      'gross_sales': 1420,
      'discounts': 41,
      'refunds': 162,
      'net_sales': 1217,
      'orders': 3,
      'refund_count': 1,
      'average_order': 459.67,
      'expenses': 350,
      'net_sales_less_expenses': 867,
      'purchases': 200,
      'supplier_payments': 0,
      'stock_loss_cost': 28,
    },
    'by_day': [
      {
        'date': '2026-10-02',
        'orders': 3,
        'gross_sales': 1420,
        'discounts': 41,
        'refunds': 162,
        'net_sales': 1217,
        'expenses': 350,
      },
    ],
    'refunds': [
      {
        'refund_number': 1,
        'order_number': 1,
        'refunded_at': '2026-10-02T13:20:00Z',
        'sold_on': '2026-10-02',
        'amount': 162,
        'reason': '=cmd|calc\tsecond line\nthird',
      },
    ],
    'stock_movement': [
      {
        'item_name': 'Paper Cups',
        'unit': 'pc',
        'opening': 0,
        'received': 100,
        'sold': 0,
        'released': 12.5,
        'lost': 0,
        'other': 0,
        'closing': 87.5,
      },
    ],
  };

  test('a business report reads its summary and sections', () {
    final report = BusinessReport.fromJson(sampleReport());

    expect(report.summary.grossSales, 1420);
    expect(report.summary.netSales, 1217);
    expect(
      report.summary.grossSales -
          report.summary.discounts -
          report.summary.refunds,
      report.summary.netSales,
    );
    expect(report.section('by_day').rows, hasLength(1));
    // Sections the server sent nothing for are present and empty.
    expect(report.section('by_item').rows, isEmpty);
    expect(report.section('low_stock').rows, isEmpty);
  });

  test('values are formatted for people on screen', () {
    final report = BusinessReport.fromJson(sampleReport());
    final days = report.section('by_day');
    final stock = report.section('stock_movement');

    expect(days.display(days.rows.first, days.columns[0]), 'Oct 2, 2026');
    expect(days.display(days.rows.first, days.columns[2]), '₱1,420.00');
    expect(stock.display(stock.rows.first, stock.columns[5]), '12.5');
    expect(stock.display(stock.rows.first, stock.columns[3]), '100');
    expect(formatReportMoney(-143), '-₱143.00');
    expect(formatReportMoney(1234567.5), '₱1,234,567.50');
  });

  test('an export is plain numbers, one value per cell, and formula-safe', () {
    final report = BusinessReport.fromJson(sampleReport());
    final days = report.section('by_day').toTsv().split('\n');
    final refunds = report.section('refunds').toTsv().split('\n');

    expect(
      days.first,
      'Date\tOrders\tGross Sales\tDiscounts\tRefunds\tNet Sales\tExpenses',
    );
    expect(days.last, '2026-10-02\t3\t1420.00\t41.00\t162.00\t1217.00\t350.00');

    // Tabs and line breaks inside a value cannot spill into other cells,
    // and text that begins like a formula is quoted.
    expect(refunds, hasLength(2));
    expect(refunds.last.split('\t'), hasLength(6));
    expect(refunds.last.split('\t').last, "'=cmd|calc second line third");

    final whole = report.toTsv();
    expect(whole, contains('Gross sales (before discounts)\t1420.00'));
    expect(whole, contains('Sales by Day'));
  });

  test('transaction trace row reads nullable amount and local time', () {
    final row = TransactionTraceRecord.fromMap({
      'event_key': 'EXPENSE:1',
      'occurred_at': '2026-09-30T04:30:00Z',
      'event_type': 'EXPENSE',
      'document_number': 'EX-1001',
      'external_reference': 'OR-5566',
      'description': 'Grocery purchase',
      'party_name': 'Local Grocery',
      'amount': -75,
      'actor_name': 'Manager',
      'status': 'POSTED',
    });

    expect(row.eventKey, 'EXPENSE:1');
    expect(row.occurredAt.isUtc, isFalse);
    expect(row.documentNumber, 'EX-1001');
    expect(row.externalReference, 'OR-5566');
    expect(row.amount, -75);
    expect(row.actorName, 'Manager');
  });
}
