import '../../models/inventory_item.dart';
import '../../models/inventory_reference.dart';

abstract class InventoryRepository {
  Future<List<InventoryItem>> getInventoryItems();

  Future<InventoryItem?> getInventoryItemById(String id);

  Future<List<InventoryCategoryOption>> getCategories();

  Future<List<InventoryUnitOption>> getUnits();

  Future<List<InventoryMovementRecord>> getRecentMovements(
    String inventoryItemId, {
    int limit = 8,
  });

  Future<List<InventoryMovementRecord>> getAllRecentMovements({int limit = 10});

  Future<List<InventoryLotRecord>> getLots(String inventoryItemId);

  Future<List<StockOutSummary>> getStockOuts({int limit = 20});

  Future<List<StockCountSummary>> getStockCounts({int limit = 20});

  Future<void> createStockOut({
    required String purpose,
    required List<StockOutLineInput> items,
    String referenceNumber = '',
    String notes = '',
    DateTime? occurredAt,
    String? clientRequestId,
  });

  /// Reverses a posted release and marks it voided.
  Future<void> voidStockOut({
    required String stockOutId,
    required String reason,
    String? clientRequestId,
  });

  /// Reverses a posted count's variances and marks it cancelled.
  Future<void> voidStockCount({
    required String stockCountId,
    required String reason,
    String? clientRequestId,
  });

  Future<void> createAndPostStockCount({
    required List<StockCountLineInput> items,
    String notes = '',
    DateTime? countedAt,
    String? clientRequestId,
  });

  Future<void> disposeLot({
    required String inventoryLotId,
    required String movementType,
    required double quantity,
    required String reason,
    String? clientRequestId,
  });

  Future<void> createInventoryItemWithInitialStock({
    required String name,
    required String categoryId,
    required String baseUomId,
    String sku = '',
    bool trackExpiry = false,
    double reorderLevel = 0,
    double initialQuantity = 0,
    DateTime? expirationDate,
    double unitCostBase = 0,
  });

  Future<void> adjustStock({
    required String inventoryItemId,
    required String movementType,
    required double quantity,
    required String reason,
    DateTime? expirationDate,
    double unitCostBase = 0,
    String? clientRequestId,
  });

  Future<void> createInventoryItem(InventoryItem item);

  Future<void> updateInventoryItem(InventoryItem item);

  Future<void> deleteInventoryItem(String id);
}
