import '../../models/package_memory.dart';
import '../../models/purchasing.dart';

abstract class PurchasingRepository {
  /// Package sizes and costs remembered from earlier receipts.
  Future<PackageMemory> getPackageMemory();

  Future<List<PurchasingSupplierOption>> getSuppliers();

  Future<List<PurchaseInventoryOption>> getInventoryItems();

  Future<List<PurchaseUnitOption>> getUnits();

  Future<List<PurchaseOrderSummary>> getPurchaseOrders();

  Future<List<PurchaseOrderLineRecord>> getPurchaseOrderLines(
    String purchaseOrderId,
  );

  Future<List<GoodsReceiptSummary>> getGoodsReceipts();

  Future<List<GoodsReceiptLineRecord>> getGoodsReceiptLines(
    String goodsReceiptId,
  );

  Future<void> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseLineInput> items,
    DateTime? expectedDate,
    String notes = '',
  });

  Future<void> approvePurchaseOrder(String purchaseOrderId);

  /// Reverses a posted receipt's stock and voids its unpaid supplier bill.
  Future<void> voidGoodsReceipt({
    required String goodsReceiptId,
    required String reason,
    String? clientRequestId,
  });

  Future<void> receiveStock({
    required String supplierId,
    required List<PurchaseLineInput> items,
    required String supplierInvoiceNumber,
    required DateTime supplierInvoiceDate,
    String purchaseOrderId = '',
    String notes = '',
    bool createSupplierBill = true,
    DateTime? dueDate,
    String? clientRequestId,
  });
}
