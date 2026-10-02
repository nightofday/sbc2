import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/finance_management.dart';
import 'package:sbc_management_system/models/inventory_reference.dart';
import 'package:sbc_management_system/models/package_memory.dart';
import 'package:sbc_management_system/models/reporting.dart';

PackageSize _size(String supplier, String unit, double quantity) => PackageSize(
  supplierId: supplier,
  inventoryItemId: 'cups',
  unitId: unit,
  baseQuantity: quantity,
  lastUnitCost: 100,
);

void main() {
  group('package memory', () {
    final memory = PackageMemory([
      _size('supplier-b', 'box', 100),
      _size('supplier-a', 'box', 50),
      _size('supplier-a', 'pack', 0),
    ]);

    test('prefers the size the chosen supplier last delivered', () {
      final size = memory.find(
        itemId: 'cups',
        unitId: 'box',
        supplierId: 'supplier-a',
      );

      expect(size?.baseQuantity, 50);
    });

    test('falls back to the most recent size from any supplier', () {
      expect(memory.find(itemId: 'cups', unitId: 'box')?.baseQuantity, 100);
      expect(
        memory
            .find(itemId: 'cups', unitId: 'box', supplierId: 'supplier-c')
            ?.baseQuantity,
        100,
      );
    });

    test('offers nothing when nothing usable is known', () {
      expect(memory.find(itemId: 'cups', unitId: 'pack'), isNull);
      expect(memory.find(itemId: 'lids', unitId: 'box'), isNull);
      expect(PackageMemory.empty.find(itemId: 'cups', unitId: 'box'), isNull);
    });
  });

  test('only an unreversed write-off can be reversed', () {
    InventoryMovementRecord movement(
      String type, {
      String reference = 'LOT_DISPOSAL',
      bool reversed = false,
    }) => InventoryMovementRecord.fromMap({
      'id': 'movement-1',
      'movement_type': type,
      'reference_type': reference,
      'is_reversed': reversed,
      'quantity_delta': -5,
      'reason': 'Dropped',
      'created_at': '2026-10-02T03:00:00Z',
    });

    expect(movement('DAMAGED').canBeReversed, isTrue);
    expect(movement('EXPIRED').canBeReversed, isTrue);
    expect(movement('DAMAGED', reversed: true).canBeReversed, isFalse);
    expect(movement('SALE_CONSUMPTION', reference: 'ORDER').canBeReversed, isFalse);
    expect(movement('REVERSAL', reference: 'LOT_DISPOSAL_VOID').canBeReversed, isFalse);
  });

  test('a supplier payment can be reversed once, a reversal never', () {
    SupplierPaymentRecord payment({
      bool isReversal = false,
      bool isReversed = false,
    }) => SupplierPaymentRecord.fromMap({
      'id': 'payment-1',
      'paid_at': '2026-10-02T03:00:00Z',
      'amount': isReversal ? -200 : 200,
      'is_reversal': isReversal,
      'is_reversed': isReversed,
    });

    expect(payment().canBeReversed, isTrue);
    expect(payment().statusLabel, 'Paid');
    expect(payment(isReversed: true).canBeReversed, isFalse);
    expect(payment(isReversed: true).statusLabel, 'Reversed');
    expect(payment(isReversal: true).canBeReversed, isFalse);
    expect(payment(isReversal: true).statusLabel, 'Reversal');
  });

  test('a voided document in the trace carries its reason', () {
    final record = TransactionTraceRecord.fromMap(const {
      'event_key': 'GOODS_RECEIPT:1',
      'occurred_at': '2026-10-02T03:00:00Z',
      'event_type': 'STOCK_IN',
      'document_number': 'GR-1',
      'status': 'VOIDED',
      'void_reason': 'Wrong branch',
    });

    expect(record.isVoided, isTrue);
    expect(record.voidReason, 'Wrong branch');
  });
}
