import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/reporting_repository.dart';
import 'package:sbc_management_system/models/audit_entry.dart';
import 'package:sbc_management_system/models/reporting.dart';
import 'package:sbc_management_system/screens/reports/audit_log_screen.dart';

class _AuditRepository implements ReportingRepository {
  final List<String> searches = [];

  @override
  Future<List<AuditEntry>> getAuditLog({
    required DateTime from,
    required DateTime to,
    String search = '',
  }) async {
    searches.add(search);
    return [
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
      AuditEntry.fromMap(const {
        'id': '2',
        'created_at': '2026-10-02T02:00:00Z',
        'actor_name': 'Ben',
        'action_code': 'SHIFT_STARTED',
        'entity_type': 'shift',
        'label': null,
        'old_data': null,
        'new_data': {'shift_id': 'abc', 'opening_cash': 500},
      }),
    ];
  }

  @override
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  }) => throw UnimplementedError();

  @override
  Future<List<TransactionTraceRecord>> getTransactionTrace({
    required int days,
  }) => throw UnimplementedError();
}

void main() {
  test('a change is described in plain words with before and after', () {
    final entry = AuditEntry.fromMap(const {
      'action_code': 'PROFILES_UPDATED',
      'entity_type': 'profiles',
      'old_data': {'status': 'ACTIVE', 'role_id': 'a'},
      'new_data': {'status': 'INACTIVE', 'role_id': 'b'},
    });

    expect(entry.title, 'Staff account changed');
    // Internal identifiers are left out.
    expect(entry.changes.map((change) => change.field), ['Status']);
    expect(entry.changes.single.before, 'ACTIVE');
    expect(entry.changes.single.after, 'INACTIVE');
  });

  test('an unknown action still reads as words', () {
    final entry = AuditEntry.fromMap(const {
      'action_code': 'SOMETHING_NEW_HAPPENED',
      'entity_type': 'thing',
    });

    expect(entry.title, 'Something new happened');
    expect(entry.changes, isEmpty);
  });

  for (final width in [1300.0, 360.0]) {
    testWidgets('the audit log lists and searches at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _AuditRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditLogScreen(reportingRepository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Product size changed: Large'), findsOneWidget);
      expect(find.text('Price: 100.0 → 120.0'), findsOneWidget);
      expect(find.text('Shift opened'), findsOneWidget);
      expect(find.text('Opening cash: 500'), findsOneWidget);
      expect(find.textContaining('Shift id'), findsNothing);

      await tester.enterText(find.byType(TextField), 'latte');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(repository.searches.last, 'latte');
    });
  }
}
