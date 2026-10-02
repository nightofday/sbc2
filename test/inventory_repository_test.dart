import 'package:flutter_test/flutter_test.dart';

import 'package:sbc_management_system/data/repositories/mock_inventory_repository.dart';
import 'package:sbc_management_system/models/inventory_item.dart';
import 'package:sbc_management_system/models/inventory_reference.dart';

void main() {
  test('mock inventory repository updates stock in memory', () async {
    final repository = MockInventoryRepository();
    final items = await repository.getInventoryItems();

    expect(items.length, 6);

    final water = items.firstWhere((item) => item.id == 'INV-001');
    expect(water.stock, '24 pc');

    await repository.updateInventoryItem(water.copyWith(stock: '26 pc'));

    final updated = await repository.getInventoryItemById('INV-001');
    expect(updated?.stock, '26 pc');

    final bowls = await repository.getInventoryItemById('INV-005');
    expect(bowls?.name, 'Takeout Bowls');
    expect(bowls?.stock, '75 pc');
  });

  test('inventory movement keeps its item reference for activity feeds', () {
    final movement = InventoryMovementRecord.fromMap({
      'inventory_item_id': 'item-123',
      'movement_type': 'MANUAL_IN',
      'quantity_delta': 2.5,
      'reason': 'Opening stock',
      'source_document_number': 'GR-18',
      'external_reference_number': 'OR-2219',
      'created_at': '2026-09-23T08:00:00Z',
    });

    expect(movement.inventoryItemId, 'item-123');
    expect(movement.quantityDelta, 2.5);
    expect(movement.sourceDocumentNumber, 'GR-18');
    expect(movement.externalReferenceNumber, 'OR-2219');
  });

  test('stock-out line serializes package conversion input', () {
    const line = StockOutLineInput(
      inventoryItemId: 'cups',
      issueUomId: 'box',
      issueQuantity: 2,
      baseQuantityPerIssueUnit: 50,
    );

    expect(line.toJson(), {
      'inventory_item_id': 'cups',
      'issue_uom_id': 'box',
      'issue_quantity': 2.0,
      'base_quantity_per_issue_unit': 50.0,
      'notes': null,
    });
  });

  test('stock count summary parses posted count information', () {
    final summary = StockCountSummary.fromMap({
      'id': 'count-1',
      'count_number': 12,
      'status': 'POSTED',
      'counted_at': '2026-09-30T08:30:00Z',
      'posted_at': '2026-09-30T08:35:00Z',
      'notes': 'Month-end count',
      'counted_by_name': 'Test Manager',
      'item_count': 4,
      'variance_item_count': 2,
    });

    expect(summary.number, 12);
    expect(summary.status, 'POSTED');
    expect(summary.itemCount, 4);
    expect(summary.varianceItemCount, 2);
    expect(summary.countedByName, 'Test Manager');
  });

  test('stock count line serializes adjustment details', () {
    final line = StockCountLineInput(
      inventoryItemId: 'cake',
      countedQuantity: 8,
      notes: 'Two pieces found during recount',
      adjustmentExpirationDate: DateTime(2026, 10, 15),
      unitCostBase: 80,
    );

    expect(line.toJson(), {
      'inventory_item_id': 'cake',
      'counted_quantity': 8.0,
      'notes': 'Two pieces found during recount',
      'adjustment_expiration_date': '2026-10-15',
      'unit_cost_base': 80.0,
    });
  });

  test('mock inventory exposes the recent activity contract', () async {
    final repository = MockInventoryRepository();

    expect(await repository.getAllRecentMovements(), isEmpty);
  });

  test('inventory item separates usable, expired, and on-hand stock', () {
    final item = InventoryItem.fromMap({
      'inventory_item_id': 'cake',
      'name': 'Chocolate Cake',
      'category_name': 'Finished Goods',
      'base_uom_code': 'pc',
      'current_quantity': 6,
      'usable_quantity': 3,
      'expired_quantity': 3,
      'reorder_level': 1,
      'next_expiration_date': '2026-10-02',
    });

    expect(item.stock, '6 pc');
    expect(item.usableStock, '3 pc');
    expect(item.expiredStock, '3 pc');
    expect(item.status, 'Expired');
  });

  test('inventory units expose standard conversion factors', () {
    final unit = InventoryUnitOption.fromMap({
      'id': 'kg',
      'code': 'kg',
      'name': 'Kilogram',
      'dimension': 'MASS',
      'factor_to_dimension_base': 1000,
    });

    expect(unit.factorToDimensionBase, 1000);
  });
}
