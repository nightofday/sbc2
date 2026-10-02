import '../../domain/repositories/inventory_repository.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_reference.dart';
import '../mock_data.dart';

class MockInventoryRepository implements InventoryRepository {
  final List<InventoryItem> _items = List<InventoryItem>.from(
    MockData.inventory,
  );

  @override
  Future<List<InventoryItem>> getInventoryItems() async {
    return List<InventoryItem>.unmodifiable(_items);
  }

  @override
  Future<InventoryItem?> getInventoryItemById(String id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<List<InventoryCategoryOption>> getCategories() async => const [];

  @override
  Future<List<InventoryUnitOption>> getUnits() async => const [];

  @override
  Future<List<InventoryMovementRecord>> getRecentMovements(
    String inventoryItemId, {
    int limit = 8,
  }) async => const [];

  @override
  Future<List<InventoryMovementRecord>> getAllRecentMovements({
    int limit = 10,
  }) async => const [];

  @override
  Future<List<InventoryLotRecord>> getLots(String inventoryItemId) async =>
      const [];

  @override
  Future<List<StockOutSummary>> getStockOuts({int limit = 20}) async =>
      const [];

  @override
  Future<List<StockCountSummary>> getStockCounts({int limit = 20}) async =>
      const [];

  @override
  Future<void> createStockOut({
    required String purpose,
    required List<StockOutLineInput> items,
    String referenceNumber = '',
    String notes = '',
    DateTime? occurredAt,
    String? clientRequestId,
  }) async {}

  @override
  Future<void> voidStockOut({
    required String stockOutId,
    required String reason,
    String? clientRequestId,
  }) async {}

  @override
  Future<void> voidStockCount({
    required String stockCountId,
    required String reason,
    String? clientRequestId,
  }) async {}

  @override
  Future<void> createAndPostStockCount({
    required List<StockCountLineInput> items,
    String notes = '',
    DateTime? countedAt,
    String? clientRequestId,
  }) async {}

  @override
  Future<void> disposeLot({
    required String inventoryLotId,
    required String movementType,
    required double quantity,
    required String reason,
    String? clientRequestId,
  }) async {}

  @override
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
  }) async {}

  @override
  Future<void> adjustStock({
    required String inventoryItemId,
    required String movementType,
    required double quantity,
    required String reason,
    DateTime? expirationDate,
    double unitCostBase = 0,
    String? clientRequestId,
  }) async {}

  @override
  Future<void> createInventoryItem(InventoryItem item) async {
    _items.add(item);
  }

  @override
  Future<void> updateInventoryItem(InventoryItem item) async {
    final index = _items.indexWhere((entry) => entry.id == item.id);
    if (index == -1) return;
    _items[index] = item;
  }

  @override
  Future<void> deleteInventoryItem(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1 && _items[index].currentQuantity > 0) {
      throw StateError(
        'Stock must be zero before an inventory item can be archived.',
      );
    }
    _items.removeWhere((item) => item.id == id);
  }
}
