class DashboardSummary {
  final double grossSales;
  final double refunds;
  final double netSales;
  final int completedOrders;
  final int openOrders;
  final double averageOrder;
  final double? expenses;
  final double? netAfterExpenses;
  final bool businessScope;

  const DashboardSummary({
    required this.grossSales,
    required this.refunds,
    required this.netSales,
    required this.completedOrders,
    required this.openOrders,
    required this.averageOrder,
    required this.expenses,
    required this.netAfterExpenses,
    required this.businessScope,
  });

  factory DashboardSummary.fromMap(Map<String, dynamic> map) {
    return DashboardSummary(
      grossSales: (map['gross_sales'] as num?)?.toDouble() ?? 0,
      refunds: (map['refunds'] as num?)?.toDouble() ?? 0,
      netSales: (map['net_sales'] as num?)?.toDouble() ?? 0,
      completedOrders: (map['completed_orders'] as num?)?.toInt() ?? 0,
      openOrders: (map['open_orders'] as num?)?.toInt() ?? 0,
      averageOrder: (map['average_order'] as num?)?.toDouble() ?? 0,
      expenses: (map['expenses'] as num?)?.toDouble(),
      netAfterExpenses: (map['net_after_expenses'] as num?)?.toDouble(),
      businessScope: map['business_scope'] == true,
    );
  }
}
