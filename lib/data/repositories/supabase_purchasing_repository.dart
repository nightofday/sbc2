import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/purchasing_repository.dart';
import 'package_memory_query.dart';
import '../../models/package_memory.dart';
import '../../models/purchasing.dart';

class SupabasePurchasingRepository implements PurchasingRepository {
  final SupabaseClient _client;

  SupabasePurchasingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<PackageMemory> getPackageMemory() => loadPackageMemory(_client);

  @override
  Future<List<PurchasingSupplierOption>> getSuppliers() async {
    final rows = await _client
        .from('suppliers')
        .select('id, name')
        .eq('is_active', true)
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) => PurchasingSupplierOption.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<PurchaseInventoryOption>> getInventoryItems() async {
    final rows = await _client
        .from('v_inventory_catalog')
        .select(
          'inventory_item_id, name, base_uom_id, base_uom_code, track_expiry',
        )
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) => PurchaseInventoryOption.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<PurchaseUnitOption>> getUnits() async {
    final rows = await _client
        .from('units_of_measure')
        .select('id, code, name, dimension, factor_to_dimension_base')
        .eq('is_active', true)
        .order('dimension', ascending: true)
        .order('factor_to_dimension_base', ascending: true);

    return (rows as List)
        .map(
          (raw) =>
              PurchaseUnitOption.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<List<PurchaseOrderSummary>> getPurchaseOrders() async {
    final rows = await _client
        .from('v_purchase_order_summary')
        .select()
        .order('created_at', ascending: false);

    return (rows as List)
        .map(
          (raw) => PurchaseOrderSummary.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<PurchaseOrderLineRecord>> getPurchaseOrderLines(
    String purchaseOrderId,
  ) async {
    final rows = await _client
        .from('v_purchase_order_lines_remaining')
        .select()
        .eq('purchase_order_id', purchaseOrderId)
        .order('id', ascending: true);

    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);

      return PurchaseOrderLineRecord(
        id: row['id']?.toString() ?? '',
        inventoryItemId: row['inventory_item_id']?.toString() ?? '',
        inventoryItemName: row['inventory_item_name']?.toString() ?? '',
        purchaseUomId: row['purchase_uom_id']?.toString() ?? '',
        purchaseUomCode: row['purchase_uom_code']?.toString() ?? '',
        orderedQuantity: (row['ordered_quantity'] as num?)?.toDouble() ?? 0,
        receivedQuantity:
            (row['received_purchase_quantity'] as num?)?.toDouble() ?? 0,
        remainingQuantity:
            (row['remaining_purchase_quantity'] as num?)?.toDouble() ?? 0,
        baseQuantityPerPurchaseUnit:
            (row['base_quantity_per_purchase_unit'] as num?)?.toDouble() ?? 1,
        unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  @override
  Future<List<GoodsReceiptSummary>> getGoodsReceipts() async {
    final rows = await _client
        .from('v_goods_receipt_summary')
        .select()
        .order('received_at', ascending: false);

    return (rows as List)
        .map(
          (raw) => GoodsReceiptSummary.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<GoodsReceiptLineRecord>> getGoodsReceiptLines(
    String goodsReceiptId,
  ) async {
    final rows = await _client
        .from('v_goods_receipt_line_details')
        .select()
        .eq('goods_receipt_id', goodsReceiptId)
        .order('inventory_item_name', ascending: true);

    return (rows as List)
        .map(
          (raw) => GoodsReceiptLineRecord.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseLineInput> items,
    DateTime? expectedDate,
    String notes = '',
  }) async {
    await _client.rpc(
      'create_purchase_order',
      params: {
        'p_supplier_id': supplierId,
        'p_items': items.map((item) => item.toPurchaseOrderJson()).toList(),
        'p_expected_date': expectedDate == null
            ? null
            : _dateOnly(expectedDate),
        'p_notes': _nullable(notes),
      },
    );
  }

  @override
  Future<void> approvePurchaseOrder(String purchaseOrderId) async {
    await _client.rpc(
      'approve_purchase_order',
      params: {'p_purchase_order_id': purchaseOrderId},
    );
  }

  @override
  Future<void> voidGoodsReceipt({
    required String goodsReceiptId,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'void_goods_receipt',
      params: {
        'p_goods_receipt_id': goodsReceiptId,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
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
  }) async {
    await _client.rpc(
      'create_and_post_goods_receipt',
      params: {
        'p_supplier_id': supplierId,
        'p_items': items.map((item) => item.toReceiptJson()).toList(),
        'p_purchase_order_id': _nullable(purchaseOrderId),
        'p_supplier_invoice_number': _nullable(supplierInvoiceNumber),
        'p_supplier_invoice_date': _dateOnly(supplierInvoiceDate),
        'p_notes': _nullable(notes),
        'p_create_supplier_bill': createSupplierBill,
        'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  String _dateOnly(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
