class PurchasingSupplierOption {
  final String id;
  final String name;

  const PurchasingSupplierOption({required this.id, required this.name});

  factory PurchasingSupplierOption.fromMap(Map<String, dynamic> map) {
    return PurchasingSupplierOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class PurchaseUnitOption {
  final String id;
  final String code;
  final String name;
  final String dimension;
  final double factorToBase;

  const PurchaseUnitOption({
    required this.id,
    required this.code,
    required this.name,
    required this.dimension,
    required this.factorToBase,
  });

  factory PurchaseUnitOption.fromMap(Map<String, dynamic> map) {
    return PurchaseUnitOption(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      dimension: map['dimension']?.toString() ?? 'OTHER',
      factorToBase: (map['factor_to_dimension_base'] as num?)?.toDouble() ?? 1,
    );
  }
}

class PurchaseInventoryOption {
  final String id;
  final String name;
  final String baseUomId;
  final String baseUomCode;
  final bool trackExpiry;

  const PurchaseInventoryOption({
    required this.id,
    required this.name,
    required this.baseUomId,
    required this.baseUomCode,
    required this.trackExpiry,
  });

  factory PurchaseInventoryOption.fromMap(Map<String, dynamic> map) {
    return PurchaseInventoryOption(
      id: map['inventory_item_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      baseUomId: map['base_uom_id']?.toString() ?? '',
      baseUomCode: map['base_uom_code']?.toString() ?? '',
      trackExpiry: map['track_expiry'] == true,
    );
  }
}

class PurchaseOrderSummary {
  final String id;
  final int number;
  final String supplierId;
  final String supplierName;
  final String status;
  final DateTime createdAt;
  final DateTime? expectedDate;
  final double totalAmount;
  final int lineCount;

  const PurchaseOrderSummary({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.createdAt,
    required this.expectedDate,
    required this.totalAmount,
    required this.lineCount,
  });

  factory PurchaseOrderSummary.fromMap(Map<String, dynamic> map) {
    final expected = map['expected_date']?.toString();
    return PurchaseOrderSummary(
      id: map['id']?.toString() ?? '',
      number: (map['purchase_order_number'] as num?)?.toInt() ?? 0,
      supplierId: map['supplier_id']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? '',
      status: map['status']?.toString() ?? 'DRAFT',
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
      expectedDate: expected == null || expected.isEmpty
          ? null
          : DateTime.tryParse(expected),
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      lineCount: (map['line_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class PurchaseOrderLineRecord {
  final String id;
  final String inventoryItemId;
  final String inventoryItemName;
  final String purchaseUomId;
  final String purchaseUomCode;
  final double orderedQuantity;
  final double receivedQuantity;
  final double remainingQuantity;
  final double baseQuantityPerPurchaseUnit;
  final double unitCost;

  const PurchaseOrderLineRecord({
    required this.id,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.purchaseUomId,
    required this.purchaseUomCode,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.baseQuantityPerPurchaseUnit,
    required this.unitCost,
  });
}

class GoodsReceiptSummary {
  final String id;
  final int number;
  final String supplierName;
  final int? purchaseOrderNumber;
  final String supplierInvoiceNumber;
  final DateTime? supplierInvoiceDate;
  final DateTime receivedAt;
  final String receivedByName;
  final String status;
  final int lineCount;
  final double total;

  const GoodsReceiptSummary({
    required this.id,
    required this.number,
    required this.supplierName,
    required this.purchaseOrderNumber,
    required this.supplierInvoiceNumber,
    required this.supplierInvoiceDate,
    required this.receivedAt,
    required this.receivedByName,
    required this.status,
    required this.lineCount,
    required this.total,
  });

  factory GoodsReceiptSummary.fromMap(Map<String, dynamic> map) {
    final invoiceDate = map['supplier_invoice_date']?.toString();
    return GoodsReceiptSummary(
      id: map['id']?.toString() ?? '',
      number: (map['receipt_number'] as num?)?.toInt() ?? 0,
      supplierName: map['supplier_name']?.toString() ?? '',
      purchaseOrderNumber: (map['purchase_order_number'] as num?)?.toInt(),
      supplierInvoiceNumber: map['supplier_invoice_number']?.toString() ?? '',
      supplierInvoiceDate: invoiceDate == null || invoiceDate.isEmpty
          ? null
          : DateTime.tryParse(invoiceDate),
      receivedAt: DateTime.parse(map['received_at'].toString()).toLocal(),
      receivedByName: map['received_by_name']?.toString() ?? '',
      status: map['status']?.toString() ?? '',
      lineCount: (map['line_count'] as num?)?.toInt() ?? 0,
      total: (map['receipt_total'] as num?)?.toDouble() ?? 0,
    );
  }
}

class GoodsReceiptLineRecord {
  final String id;
  final String inventoryItemName;
  final String purchaseUomCode;
  final double purchaseQuantity;
  final double baseQuantityPerPurchaseUnit;
  final double baseQuantity;
  final String baseUomCode;
  final double unitCost;
  final double lineTotal;
  final String lotCode;
  final DateTime? expirationDate;
  final double remainingQuantity;
  final String lotStatus;

  const GoodsReceiptLineRecord({
    required this.id,
    required this.inventoryItemName,
    required this.purchaseUomCode,
    required this.purchaseQuantity,
    required this.baseQuantityPerPurchaseUnit,
    required this.baseQuantity,
    required this.baseUomCode,
    required this.unitCost,
    required this.lineTotal,
    required this.lotCode,
    required this.expirationDate,
    required this.remainingQuantity,
    required this.lotStatus,
  });

  factory GoodsReceiptLineRecord.fromMap(Map<String, dynamic> map) {
    final expiration = map['expiration_date']?.toString();
    return GoodsReceiptLineRecord(
      id: map['id']?.toString() ?? '',
      inventoryItemName: map['inventory_item_name']?.toString() ?? '',
      purchaseUomCode: map['purchase_uom_code']?.toString() ?? '',
      purchaseQuantity: (map['purchase_quantity'] as num?)?.toDouble() ?? 0,
      baseQuantityPerPurchaseUnit:
          (map['base_quantity_per_purchase_unit'] as num?)?.toDouble() ?? 1,
      baseQuantity: (map['base_quantity'] as num?)?.toDouble() ?? 0,
      baseUomCode: map['base_uom_code']?.toString() ?? '',
      unitCost: (map['unit_cost_purchase_uom'] as num?)?.toDouble() ?? 0,
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
      lotCode: map['lot_code']?.toString() ?? '',
      expirationDate: expiration == null || expiration.isEmpty
          ? null
          : DateTime.tryParse(expiration),
      remainingQuantity: (map['remaining_quantity'] as num?)?.toDouble() ?? 0,
      lotStatus: map['lot_status']?.toString() ?? '',
    );
  }
}

class PurchaseLineInput {
  final String inventoryItemId;
  final String purchaseUomId;
  final double quantity;
  final double baseQuantityPerPurchaseUnit;
  final double unitCost;
  final String purchaseOrderItemId;
  final DateTime? expirationDate;
  final String lotCode;

  const PurchaseLineInput({
    required this.inventoryItemId,
    required this.purchaseUomId,
    required this.quantity,
    required this.baseQuantityPerPurchaseUnit,
    required this.unitCost,
    this.purchaseOrderItemId = '',
    this.expirationDate,
    this.lotCode = '',
  });

  Map<String, dynamic> toPurchaseOrderJson() => {
    'inventory_item_id': inventoryItemId,
    'purchase_uom_id': purchaseUomId,
    'ordered_quantity': quantity,
    'base_quantity_per_purchase_unit': baseQuantityPerPurchaseUnit,
    'unit_cost': unitCost,
  };

  Map<String, dynamic> toReceiptJson() => {
    'inventory_item_id': inventoryItemId,
    'purchase_uom_id': purchaseUomId,
    'purchase_order_item_id': purchaseOrderItemId.isEmpty
        ? null
        : purchaseOrderItemId,
    'purchase_quantity': quantity,
    'base_quantity_per_purchase_unit': baseQuantityPerPurchaseUnit,
    'unit_cost_purchase_uom': unitCost,
    'expiration_date': expirationDate == null
        ? null
        : '${expirationDate!.year}-'
              '${expirationDate!.month.toString().padLeft(2, '0')}-'
              '${expirationDate!.day.toString().padLeft(2, '0')}',
    'lot_code': lotCode.trim().isEmpty ? null : lotCode.trim(),
  };
}
