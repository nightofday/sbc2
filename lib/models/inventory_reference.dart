class InventoryCategoryOption {
  final String id;
  final String name;

  const InventoryCategoryOption({required this.id, required this.name});

  factory InventoryCategoryOption.fromMap(Map<String, dynamic> map) {
    return InventoryCategoryOption(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class InventoryUnitOption {
  final String id;
  final String code;
  final String name;
  final String dimension;
  final double factorToDimensionBase;

  const InventoryUnitOption({
    required this.id,
    required this.code,
    required this.name,
    required this.dimension,
    this.factorToDimensionBase = 1,
  });

  factory InventoryUnitOption.fromMap(Map<String, dynamic> map) {
    return InventoryUnitOption(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      dimension: map['dimension']?.toString() ?? '',
      factorToDimensionBase:
          (map['factor_to_dimension_base'] as num?)?.toDouble() ?? 1,
    );
  }
}

class InventoryMovementRecord {
  final String id;
  final String inventoryItemId;
  final String movementType;
  final double quantityDelta;
  final String reason;
  final String sourceDocumentNumber;
  final String externalReferenceNumber;
  final DateTime createdAt;
  final String referenceType;

  /// True for a write-off that has since been reversed.
  final bool isReversed;

  /// A waste, damaged or expired write-off that has not been undone.
  bool get canBeReversed =>
      id.isNotEmpty &&
      !isReversed &&
      referenceType == 'LOT_DISPOSAL' &&
      const {'WASTE', 'DAMAGED', 'EXPIRED'}.contains(movementType);

  const InventoryMovementRecord({
    this.id = '',
    this.referenceType = '',
    this.isReversed = false,
    this.inventoryItemId = '',
    required this.movementType,
    required this.quantityDelta,
    required this.reason,
    this.sourceDocumentNumber = '',
    this.externalReferenceNumber = '',
    required this.createdAt,
  });

  factory InventoryMovementRecord.fromMap(Map<String, dynamic> map) {
    return InventoryMovementRecord(
      id: map['id']?.toString() ?? '',
      referenceType: map['reference_type']?.toString() ?? '',
      isReversed: map['is_reversed'] == true,
      inventoryItemId: map['inventory_item_id']?.toString() ?? '',
      movementType: map['movement_type']?.toString() ?? '',
      quantityDelta: (map['quantity_delta'] as num?)?.toDouble() ?? 0,
      reason: map['reason']?.toString() ?? '',
      sourceDocumentNumber: map['source_document_number']?.toString() ?? '',
      externalReferenceNumber:
          map['external_reference_number']?.toString() ?? '',
      createdAt: DateTime.parse(map['created_at'].toString()).toLocal(),
    );
  }
}

class InventoryLotRecord {
  final String id;
  final String inventoryItemId;
  final String lotCode;
  final DateTime receivedAt;
  final DateTime? expirationDate;
  final double receivedQuantity;
  final double remainingQuantity;
  final double unitCostBase;
  final String status;
  final String unitCode;

  const InventoryLotRecord({
    required this.id,
    required this.inventoryItemId,
    required this.lotCode,
    required this.receivedAt,
    required this.expirationDate,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.unitCostBase,
    required this.status,
    required this.unitCode,
  });

  factory InventoryLotRecord.fromMap(Map<String, dynamic> map) {
    final expirationRaw = map['expiration_date']?.toString();

    return InventoryLotRecord(
      id: map['lot_id']?.toString() ?? '',
      inventoryItemId: map['inventory_item_id']?.toString() ?? '',
      lotCode: map['lot_code']?.toString() ?? '',
      receivedAt: DateTime.parse(map['received_at'].toString()).toLocal(),
      expirationDate: expirationRaw == null || expirationRaw.isEmpty
          ? null
          : DateTime.tryParse(expirationRaw),
      receivedQuantity: (map['received_quantity'] as num?)?.toDouble() ?? 0,
      remainingQuantity: (map['remaining_quantity'] as num?)?.toDouble() ?? 0,
      unitCostBase: (map['unit_cost_base'] as num?)?.toDouble() ?? 0,
      status: map['status']?.toString() ?? '',
      unitCode: map['uom_code']?.toString() ?? '',
    );
  }
}

class StockOutSummary {
  final String id;
  final int number;
  final DateTime occurredAt;
  final String purpose;
  final String referenceNumber;
  final String recordedByName;
  final int lineCount;
  final String status;

  const StockOutSummary({
    required this.id,
    required this.number,
    required this.occurredAt,
    required this.purpose,
    required this.referenceNumber,
    required this.recordedByName,
    required this.lineCount,
    required this.status,
  });

  factory StockOutSummary.fromMap(Map<String, dynamic> map) {
    return StockOutSummary(
      id: map['id']?.toString() ?? '',
      number: (map['stock_out_number'] as num?)?.toInt() ?? 0,
      occurredAt: DateTime.parse(map['occurred_at'].toString()).toLocal(),
      purpose: map['purpose']?.toString() ?? '',
      referenceNumber: map['reference_number']?.toString() ?? '',
      recordedByName: map['recorded_by_name']?.toString() ?? '',
      lineCount: (map['line_count'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? '',
    );
  }
}

class StockOutLineInput {
  final String inventoryItemId;
  final String issueUomId;
  final double issueQuantity;
  final double baseQuantityPerIssueUnit;
  final String notes;

  const StockOutLineInput({
    required this.inventoryItemId,
    required this.issueUomId,
    required this.issueQuantity,
    required this.baseQuantityPerIssueUnit,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'inventory_item_id': inventoryItemId,
    'issue_uom_id': issueUomId,
    'issue_quantity': issueQuantity,
    'base_quantity_per_issue_unit': baseQuantityPerIssueUnit,
    'notes': notes.trim().isEmpty ? null : notes.trim(),
  };
}

class StockCountSummary {
  final String id;
  final int number;
  final String status;
  final DateTime countedAt;
  final DateTime? postedAt;
  final String notes;
  final String countedByName;
  final int itemCount;
  final int varianceItemCount;

  const StockCountSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.countedAt,
    required this.postedAt,
    required this.notes,
    required this.countedByName,
    required this.itemCount,
    required this.varianceItemCount,
  });

  factory StockCountSummary.fromMap(Map<String, dynamic> map) {
    final postedAtRaw = map['posted_at']?.toString();
    return StockCountSummary(
      id: map['id']?.toString() ?? '',
      number: (map['count_number'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? '',
      countedAt: DateTime.parse(map['counted_at'].toString()).toLocal(),
      postedAt: postedAtRaw == null || postedAtRaw.isEmpty
          ? null
          : DateTime.parse(postedAtRaw).toLocal(),
      notes: map['notes']?.toString() ?? '',
      countedByName: map['counted_by_name']?.toString() ?? '',
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      varianceItemCount: (map['variance_item_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class StockCountLineInput {
  final String inventoryItemId;
  final double countedQuantity;
  final String notes;
  final DateTime? adjustmentExpirationDate;
  final double unitCostBase;

  const StockCountLineInput({
    required this.inventoryItemId,
    required this.countedQuantity,
    this.notes = '',
    this.adjustmentExpirationDate,
    this.unitCostBase = 0,
  });

  Map<String, dynamic> toJson() => {
    'inventory_item_id': inventoryItemId,
    'counted_quantity': countedQuantity,
    'notes': notes.trim().isEmpty ? null : notes.trim(),
    'adjustment_expiration_date': adjustmentExpirationDate == null
        ? null
        : _dateOnly(adjustmentExpirationDate!),
    'unit_cost_base': unitCostBase,
  };

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
