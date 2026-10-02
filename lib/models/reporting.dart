class DailySalesRow {
  final DateTime date;
  final int orders;
  final double grossSales;
  final double refunds;
  final double netSales;

  const DailySalesRow({
    required this.date,
    required this.orders,
    required this.grossSales,
    required this.refunds,
    required this.netSales,
  });

  factory DailySalesRow.fromMap(Map<String, dynamic> map) {
    return DailySalesRow(
      date: DateTime.parse(map['sales_date'].toString()),
      orders: (map['completed_orders'] as num?)?.toInt() ?? 0,
      grossSales: (map['gross_sales'] as num?)?.toDouble() ?? 0,
      refunds: (map['refunds'] as num?)?.toDouble() ?? 0,
      netSales: (map['net_sales'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FinancialReportSummary {
  final double grossSales;
  final double refunds;
  final double netSales;
  final double expenses;
  final double netAfterExpenses;
  final int orders;
  final double averageOrder;

  const FinancialReportSummary({
    required this.grossSales,
    required this.refunds,
    required this.netSales,
    required this.expenses,
    required this.netAfterExpenses,
    required this.orders,
    required this.averageOrder,
  });
}

class InventoryReportSummary {
  final int itemCount;
  final int lowStockCount;
  final int expiringSoonCount;

  const InventoryReportSummary({
    required this.itemCount,
    required this.lowStockCount,
    required this.expiringSoonCount,
  });
}

class ProductSalesRow {
  final String menuItemId;
  final String menuVariantId;
  final String itemName;
  final String variantName;
  final double quantitySold;
  final double quantityRefunded;
  final double netQuantitySold;
  final double sales;

  const ProductSalesRow({
    this.menuItemId = '',
    this.menuVariantId = '',
    required this.itemName,
    required this.variantName,
    required this.quantitySold,
    this.quantityRefunded = 0,
    double? netQuantitySold,
    required this.sales,
  }) : netQuantitySold = netQuantitySold ?? quantitySold;

  factory ProductSalesRow.fromMap(Map<String, dynamic> map) {
    return ProductSalesRow(
      menuItemId: map['menu_item_id']?.toString() ?? '',
      menuVariantId: map['menu_variant_id']?.toString() ?? '',
      itemName: map['item_name_snapshot']?.toString() ?? '',
      variantName: map['variant_name_snapshot']?.toString() ?? '',
      quantitySold: (map['quantity_sold'] as num?)?.toDouble() ?? 0,
      quantityRefunded: (map['quantity_refunded'] as num?)?.toDouble() ?? 0,
      netQuantitySold: (map['net_quantity_sold'] as num?)?.toDouble() ?? 0,
      sales: (map['net_line_sales'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TransactionTraceRecord {
  final String eventKey;
  final DateTime occurredAt;
  final String eventType;
  final String documentNumber;
  final String externalReference;
  final String description;
  final String partyName;
  final double? amount;
  final String actorName;
  final String status;

  const TransactionTraceRecord({
    required this.eventKey,
    required this.occurredAt,
    required this.eventType,
    required this.documentNumber,
    required this.externalReference,
    required this.description,
    required this.partyName,
    required this.amount,
    required this.actorName,
    required this.status,
  });

  factory TransactionTraceRecord.fromMap(Map<String, dynamic> map) {
    return TransactionTraceRecord(
      eventKey: map['event_key']?.toString() ?? '',
      occurredAt: DateTime.parse(map['occurred_at'].toString()).toLocal(),
      eventType: map['event_type']?.toString() ?? '',
      documentNumber: map['document_number']?.toString() ?? '',
      externalReference: map['external_reference']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      partyName: map['party_name']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble(),
      actorName: map['actor_name']?.toString() ?? 'Unknown Employee',
      status: map['status']?.toString() ?? '',
    );
  }
}

class ReportingSnapshot {
  final List<DailySalesRow> dailySales;
  final FinancialReportSummary finance;
  final InventoryReportSummary inventory;
  final List<ProductSalesRow> topProducts;

  const ReportingSnapshot({
    required this.dailySales,
    required this.finance,
    required this.inventory,
    required this.topProducts,
  });
}
