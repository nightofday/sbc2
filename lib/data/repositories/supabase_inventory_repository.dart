import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/inventory_repository.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_reference.dart';

class SupabaseInventoryRepository implements InventoryRepository {
  final SupabaseClient _client;

  SupabaseInventoryRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<InventoryItem>> getInventoryItems() async {
    final rows = await _client
        .from('v_inventory_catalog')
        .select()
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (row) => InventoryItem.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<InventoryItem?> getInventoryItemById(String id) async {
    final rows = await _client
        .from('v_inventory_catalog')
        .select()
        .eq('inventory_item_id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    return InventoryItem.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<List<InventoryCategoryOption>> getCategories() async {
    final rows = await _client
        .from('inventory_categories')
        .select('id, name')
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (row) => InventoryCategoryOption.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<InventoryUnitOption>> getUnits() async {
    final rows = await _client
        .from('units_of_measure')
        .select('id, code, name, dimension, factor_to_dimension_base')
        .eq('is_active', true)
        .order('dimension', ascending: true)
        .order('factor_to_dimension_base', ascending: true);

    return (rows as List)
        .map(
          (row) => InventoryUnitOption.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<InventoryMovementRecord>> getRecentMovements(
    String inventoryItemId, {
    int limit = 8,
  }) async {
    final rows = await _client
        .from('v_inventory_movement_history')
        .select()
        .eq('inventory_item_id', inventoryItemId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (row) => InventoryMovementRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<InventoryMovementRecord>> getAllRecentMovements({
    int limit = 10,
  }) async {
    final rows = await _client
        .from('v_inventory_movement_history')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (row) => InventoryMovementRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<InventoryLotRecord>> getLots(String inventoryItemId) async {
    final rows = await _client
        .from('v_inventory_lots')
        .select()
        .eq('inventory_item_id', inventoryItemId)
        .order('expiration_date', ascending: true)
        .order('received_at', ascending: true);

    return (rows as List)
        .map(
          (row) =>
              InventoryLotRecord.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<StockOutSummary>> getStockOuts({int limit = 20}) async {
    final rows = await _client
        .from('v_stock_out_summary')
        .select()
        .order('occurred_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (row) =>
              StockOutSummary.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<StockCountSummary>> getStockCounts({int limit = 20}) async {
    final rows = await _client
        .from('v_stock_count_summary')
        .select()
        .order('counted_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (row) =>
              StockCountSummary.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<void> createStockOut({
    required String purpose,
    required List<StockOutLineInput> items,
    String referenceNumber = '',
    String notes = '',
    DateTime? occurredAt,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'create_and_post_stock_out',
      params: {
        'p_purpose': purpose.trim(),
        'p_items': items.map((item) => item.toJson()).toList(),
        'p_reference_number': _nullableText(referenceNumber),
        'p_notes': _nullableText(notes),
        'p_occurred_at': (occurredAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> voidStockOut({
    required String stockOutId,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'void_stock_out',
      params: {
        'p_stock_out_id': stockOutId,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> voidStockCount({
    required String stockCountId,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'void_stock_count',
      params: {
        'p_stock_count_id': stockCountId,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> createAndPostStockCount({
    required List<StockCountLineInput> items,
    String notes = '',
    DateTime? countedAt,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'create_and_post_stock_count',
      params: {
        'p_items': items.map((item) => item.toJson()).toList(),
        'p_notes': _nullableText(notes),
        'p_counted_at': (countedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> disposeLot({
    required String inventoryLotId,
    required String movementType,
    required double quantity,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'dispose_inventory_lot',
      params: {
        'p_inventory_lot_id': inventoryLotId,
        'p_movement_type': movementType,
        'p_quantity': quantity,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

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
  }) async {
    await _client.rpc(
      'create_inventory_item_with_initial_stock',
      params: {
        'p_name': name.trim(),
        'p_category_id': _nullableId(categoryId),
        'p_base_uom_id': baseUomId,
        'p_sku': _nullableText(sku),
        'p_track_expiry': trackExpiry,
        'p_reorder_level': reorderLevel,
        'p_initial_quantity': initialQuantity,
        'p_expiration_date': expirationDate == null
            ? null
            : _dateOnly(expirationDate),
        'p_unit_cost_base': unitCostBase,
      },
    );
  }

  @override
  Future<void> adjustStock({
    required String inventoryItemId,
    required String movementType,
    required double quantity,
    required String reason,
    DateTime? expirationDate,
    double unitCostBase = 0,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'adjust_inventory_stock',
      params: {
        'p_inventory_item_id': inventoryItemId,
        'p_movement_type': movementType,
        'p_quantity': quantity,
        'p_reason': reason.trim(),
        'p_expiration_date': expirationDate == null
            ? null
            : _dateOnly(expirationDate),
        'p_unit_cost_base': unitCostBase,
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> deleteInventoryItem(String id) async {
    final rows = await _client
        .from('v_inventory_catalog')
        .select('current_quantity')
        .eq('inventory_item_id', id)
        .limit(1);
    final currentQuantity = (rows as List).isEmpty
        ? 0.0
        : ((rows.first as Map)['current_quantity'] as num?)?.toDouble() ?? 0;

    if (currentQuantity > 0) {
      throw StateError(
        'Stock must be zero before an inventory item can be archived.',
      );
    }

    await _client
        .from('inventory_items')
        .update({
          'is_active': false,
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _nullableId(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
