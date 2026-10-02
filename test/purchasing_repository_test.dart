import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/purchasing.dart';

void main() {
  test('receipt summary keeps its external reference date', () {
    final receipt = GoodsReceiptSummary.fromMap({
      'id': 'receipt-1',
      'receipt_number': 18,
      'supplier_name': 'Davao Grocery',
      'purchase_order_number': null,
      'supplier_invoice_number': 'OR-1045',
      'supplier_invoice_date': '2026-09-30',
      'received_at': '2026-09-30T08:00:00Z',
      'received_by_name': 'Test Manager',
      'status': 'POSTED',
      'line_count': 2,
      'receipt_total': 850,
    });

    expect(receipt.number, 18);
    expect(receipt.supplierInvoiceNumber, 'OR-1045');
    expect(receipt.supplierInvoiceDate, DateTime(2026, 9, 30));
    expect(receipt.receivedByName, 'Test Manager');
    expect(receipt.lineCount, 2);
  });

  test('receipt line stores practical package conversion', () {
    const line = PurchaseLineInput(
      inventoryItemId: 'cups',
      purchaseUomId: 'box',
      quantity: 2,
      baseQuantityPerPurchaseUnit: 50,
      unitCost: 125,
      lotCode: 'CUPS-0930',
    );

    expect(line.toReceiptJson(), {
      'inventory_item_id': 'cups',
      'purchase_uom_id': 'box',
      'purchase_order_item_id': null,
      'purchase_quantity': 2.0,
      'base_quantity_per_purchase_unit': 50.0,
      'unit_cost_purchase_uom': 125.0,
      'expiration_date': null,
      'lot_code': 'CUPS-0930',
    });
  });

  test('receipt detail parses received lot balances', () {
    final line = GoodsReceiptLineRecord.fromMap({
      'id': 'line-1',
      'inventory_item_name': 'Paper Cups',
      'purchase_uom_code': 'box',
      'purchase_quantity': 2,
      'base_quantity_per_purchase_unit': 50,
      'base_quantity': 100,
      'base_uom_code': 'pc',
      'unit_cost_purchase_uom': 125,
      'line_total': 250,
      'lot_code': 'CUPS-0930',
      'expiration_date': null,
      'remaining_quantity': 75,
      'lot_status': 'AVAILABLE',
    });

    expect(line.inventoryItemName, 'Paper Cups');
    expect(line.baseQuantityPerPurchaseUnit, 50);
    expect(line.baseQuantity, 100);
    expect(line.remainingQuantity, 75);
  });
}
