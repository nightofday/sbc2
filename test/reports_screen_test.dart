import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/reporting_repository.dart';
import 'package:sbc_management_system/models/audit_entry.dart';
import 'package:sbc_management_system/models/reporting.dart';
import 'package:sbc_management_system/screens/reports/reports_screen.dart';

class _FakeReportingRepository implements ReportingRepository {
  final List<String> requests = [];

  @override
  Future<List<AuditEntry>> getAuditLog({
    required DateTime from,
    required DateTime to,
    String search = '',
  }) async => const [];

  @override
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  }) async {
    requests.add('${to.difference(from).inDays + 1} days');

    return BusinessReport.fromJson({
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
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
      },
      'by_item': [
        {
          'item_name': 'Hot Coffee with a Very Long Descriptive Name',
          'variant_name': 'Regular',
          'category_name': 'Coffee',
          'quantity_sold': 5,
          'quantity_refunded': 0,
          'gross_sales': 600,
          'discounts': 0,
          'refunds': 0,
          'net_sales': 600,
        },
      ],
    });
  }

  @override
  Future<List<TransactionTraceRecord>> getTransactionTrace({
    required int days,
  }) async => const [];
}

void main() {
  Future<_FakeReportingRepository> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _FakeReportingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportsScreen(reportingRepository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('the report names each sales figure and can be copied', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final repository = await pump(tester, const Size(1300, 2400));

    expect(repository.requests, ['7 days']);
    expect(find.text('₱1,420.00'), findsOneWidget);
    expect(find.text('At menu prices, before discounts'), findsOneWidget);
    expect(find.text('₱1,217.00'), findsOneWidget);
    expect(find.text('Gross sales less discounts and refunds'), findsOneWidget);
    expect(find.text('No discounts given in this period.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy for Sheets'));
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied!.split('\n').first.split('\t').first, 'Item');
    expect(copied, contains('600.00'));

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 Days'));
    await tester.pumpAndSettle();

    expect(repository.requests, ['7 days', '1 days', '30 days']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report fits a phone', (tester) async {
    await pump(tester, const Size(360, 800));

    expect(find.text('Gross Sales'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
