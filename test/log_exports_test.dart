import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/export/xlsx.dart';
import 'package:sbc_management_system/domain/repositories/reporting_repository.dart';
import 'package:sbc_management_system/models/audit_entry.dart';
import 'package:sbc_management_system/models/reporting.dart';
import 'package:sbc_management_system/screens/reports/audit_log_screen.dart';
import 'package:sbc_management_system/screens/reports/transaction_traceability_screen.dart';

class _Repository implements ReportingRepository {
  @override
  Future<List<AuditEntry>> getAuditLog({
    required DateTime from,
    required DateTime to,
    String search = '',
  }) async => [
    AuditEntry.fromMap(const {
      'id': '1',
      'created_at': '2026-10-02T03:00:00Z',
      'actor_name': 'Ana',
      'action_code': 'MENU_VARIANTS_UPDATED',
      'entity_type': 'menu_variants',
      'label': 'Large',
      'old_data': {'price': 100.0},
      'new_data': {'price': 120.0},
    }),
  ];

  @override
  Future<List<TransactionTraceRecord>> getTransactionTrace({
    required int days,
  }) async => [
    TransactionTraceRecord.fromMap(const {
      'event_key': 'sale-1',
      'occurred_at': '2026-10-02T03:00:00Z',
      'event_type': 'SALE',
      'document_number': 'ORD-12',
      'description': 'Dine in',
      'amount': 485.5,
      'actor_name': 'Ben',
      'status': 'COMPLETED',
    }),
    TransactionTraceRecord.fromMap(const {
      'event_key': 'payment-1',
      'occurred_at': '2026-10-02T04:00:00Z',
      'event_type': 'SUPPLIER_PAYMENT',
      'document_number': 'PAY-3',
      'party_name': 'Davao Packaging Supply',
      'amount': -1200,
      'actor_name': 'Ana',
      'status': 'POSTED',
    }),
  ];

  @override
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  }) => throw UnimplementedError();
}

/// Taps [button] on [screen] and returns the workbook handed to the share
/// sheet, as text: its parts are stored uncompressed.
Future<String> _sharedWorkbook(
  WidgetTester tester,
  Widget screen,
  String button,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<Object?, Object?>? shared;
  messenger.setMockMethodCallHandler(channel, (call) async {
    shared = call.arguments as Map<Object?, Object?>;
    return 'dev.fluttercommunity.plus/share/success';
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pumpAndSettle();

  // The file is written with real disk access, so the tap runs on the
  // real clock.
  await tester.runAsync(() async {
    await tester.tap(find.text(button));
    for (var i = 0; i < 100 && shared == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pumpAndSettle();

  expect(shared, isNotNull);
  final path = (shared!['paths'] as List).cast<String>().single;
  expect(path, endsWith('.xlsx'));
  expect((shared!['mimeTypes'] as List).single, XlsxWorkbook.mimeType);
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(2), [0x50, 0x4B]);
  return utf8.decode(bytes, allowMalformed: true);
}

void main() {
  testWidgets('the audit log is shared as an Excel workbook', (tester) async {
    final workbook = await _sharedWorkbook(
      tester,
      AuditLogScreen(reportingRepository: _Repository()),
      'Share Excel',
    );

    expect(workbook, contains('<sheet name="Audit Log"'));
    expect(workbook, contains('Street Bowl Café — Audit Log'));
    expect(workbook, contains('Product size changed'));
    expect(workbook, contains('Price: 100.0 → 120.0'));
  });

  testWidgets('the transaction trace is shared without adding up amounts', (
    tester,
  ) async {
    final workbook = await _sharedWorkbook(
      tester,
      TransactionTraceabilityScreen(reportingRepository: _Repository()),
      'Share Excel',
    );

    expect(workbook, contains('<sheet name="Transactions"'));
    expect(workbook, contains('Last 30 days, up to 500 recent records'));
    expect(workbook, contains('ORD-12'));
    expect(workbook, contains('Davao Packaging Supply'));
    // Amounts are numbers, a sale and a supplier payment kept apart.
    expect(workbook, contains('<v>485.5</v>'));
    expect(workbook, contains('<v>-1200</v>'));
    expect(workbook, isNot(contains('<f>SUM')));
  });
}
