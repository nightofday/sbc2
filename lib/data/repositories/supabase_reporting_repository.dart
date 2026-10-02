import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';

class SupabaseReportingRepository implements ReportingRepository {
  final SupabaseClient _client;

  SupabaseReportingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<ReportingSnapshot> getSnapshot({required int days}) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final startDate = _dateOnly(start);
    final endDate = _dateOnly(DateTime(now.year, now.month, now.day));

    final results = await Future.wait([
      _client
          .from('v_daily_sales')
          .select()
          .gte('sales_date', startDate)
          .lte('sales_date', endDate)
          .order('sales_date'),
      _client
          .from('expenses')
          .select('expense_date, amount')
          .eq('status', 'POSTED')
          .gte('expense_date', startDate)
          .lte('expense_date', endDate),
      _client
          .from('v_inventory_catalog')
          .select(
            'inventory_item_id, usable_quantity, reorder_level, next_expiration_date',
          ),
      _client
          .from('v_product_sales_daily')
          .select(
            'menu_item_id, menu_variant_id, item_name_snapshot, '
            'variant_name_snapshot, quantity_sold, quantity_refunded, '
            'net_quantity_sold, net_line_sales',
          )
          .gte('sales_date', startDate)
          .lte('sales_date', endDate),
    ]);

    final dailySales = (results[0] as List)
        .map(
          (raw) => DailySalesRow.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();

    double expenses = 0;
    for (final raw in results[1] as List) {
      expenses += ((raw as Map)['amount'] as num?)?.toDouble() ?? 0;
    }

    double grossSales = 0;
    double refunds = 0;
    double netSales = 0;
    int orders = 0;

    for (final row in dailySales) {
      grossSales += row.grossSales;
      refunds += row.refunds;
      netSales += row.netSales;
      orders += row.orders;
    }

    int itemCount = 0;
    int lowStock = 0;
    int expiringSoon = 0;
    final today = DateTime(now.year, now.month, now.day);

    for (final raw in results[2] as List) {
      final row = raw as Map;
      itemCount += 1;

      final quantity = (row['usable_quantity'] as num?)?.toDouble() ?? 0;
      final reorder = (row['reorder_level'] as num?)?.toDouble() ?? 0;

      if (quantity <= reorder) {
        lowStock += 1;
      }

      final expiryText = row['next_expiration_date']?.toString();
      if (expiryText != null && expiryText.isNotEmpty && quantity > 0) {
        final expiry = DateTime.tryParse(expiryText);
        if (expiry != null) {
          final daysUntil = expiry.difference(today).inDays;
          if (daysUntil >= 0 && daysUntil <= 7) {
            expiringSoon += 1;
          }
        }
      }
    }

    final productTotals = <String, _ProductSalesAccumulator>{};
    for (final raw in results[3] as List) {
      final row = ProductSalesRow.fromMap(
        Map<String, dynamic>.from(raw as Map),
      );
      final key = [
        row.menuItemId,
        row.menuVariantId,
        row.itemName,
        row.variantName,
      ].join(':');
      productTotals
          .putIfAbsent(
            key,
            () => _ProductSalesAccumulator(
              menuItemId: row.menuItemId,
              menuVariantId: row.menuVariantId,
              itemName: row.itemName,
              variantName: row.variantName,
            ),
          )
          .add(row);
    }

    final topProducts =
        productTotals.values.map((item) => item.toRecord()).toList()
          ..sort((a, b) => b.netQuantitySold.compareTo(a.netQuantitySold));

    return ReportingSnapshot(
      dailySales: dailySales,
      finance: FinancialReportSummary(
        grossSales: grossSales,
        refunds: refunds,
        netSales: netSales,
        expenses: expenses,
        netAfterExpenses: netSales - expenses,
        orders: orders,
        averageOrder: orders == 0 ? 0 : netSales / orders,
      ),
      inventory: InventoryReportSummary(
        itemCount: itemCount,
        lowStockCount: lowStock,
        expiringSoonCount: expiringSoon,
      ),
      topProducts: topProducts.take(10).toList(),
    );
  }

  @override
  Future<List<TransactionTraceRecord>> getTransactionTrace({
    required int days,
  }) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final endExclusive = DateTime(now.year, now.month, now.day + 1);

    final rows = await _client
        .from('v_business_transaction_trace')
        .select()
        .gte('occurred_at', start.toUtc().toIso8601String())
        .lt('occurred_at', endExclusive.toUtc().toIso8601String())
        .order('occurred_at', ascending: false)
        .limit(500);

    return (rows as List)
        .map(
          (raw) => TransactionTraceRecord.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  String _dateOnly(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _ProductSalesAccumulator {
  final String menuItemId;
  final String menuVariantId;
  final String itemName;
  final String variantName;
  double quantitySold = 0;
  double quantityRefunded = 0;
  double netQuantitySold = 0;
  double netSales = 0;

  _ProductSalesAccumulator({
    required this.menuItemId,
    required this.menuVariantId,
    required this.itemName,
    required this.variantName,
  });

  void add(ProductSalesRow row) {
    quantitySold += row.quantitySold;
    quantityRefunded += row.quantityRefunded;
    netQuantitySold += row.netQuantitySold;
    netSales += row.sales;
  }

  ProductSalesRow toRecord() {
    return ProductSalesRow(
      menuItemId: menuItemId,
      menuVariantId: menuVariantId,
      itemName: itemName,
      variantName: variantName,
      quantitySold: quantitySold,
      quantityRefunded: quantityRefunded,
      netQuantitySold: netQuantitySold,
      sales: netSales,
    );
  }
}
