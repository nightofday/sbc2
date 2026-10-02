import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/reporting.dart';

void main() {
  test('product sales row reads gross, refunded and net values', () {
    final row = ProductSalesRow.fromMap({
      'menu_item_id': 'item-1',
      'menu_variant_id': 'variant-1',
      'item_name_snapshot': 'Street Bowl',
      'variant_name_snapshot': 'Regular',
      'quantity_sold': 3,
      'quantity_refunded': 0.5,
      'net_quantity_sold': 2.5,
      'net_line_sales': 250,
    });

    expect(row.menuItemId, 'item-1');
    expect(row.menuVariantId, 'variant-1');
    expect(row.quantitySold, 3);
    expect(row.quantityRefunded, 0.5);
    expect(row.netQuantitySold, 2.5);
    expect(row.sales, 250);
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
