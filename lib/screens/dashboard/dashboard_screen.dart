import 'package:flutter/material.dart';

import '../../models/reporting.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/dashboard_summary.dart';
import '../../models/order_record.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/summary_card.dart';
import '../../widgets/layout/app_page.dart';
import '../orders/new_order_screen.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

class DashboardScreen extends StatefulWidget {
  final OrderRepository orderRepository;
  final DashboardRepository dashboardRepository;
  final Listenable? refreshListenable;
  final VoidCallback? onDataChanged;

  /// Shown above the sales summary, such as stock alerts.
  final Widget? notice;

  const DashboardScreen({
    super.key,
    required this.orderRepository,
    required this.dashboardRepository,
    this.refreshListenable,
    this.onDataChanged,
    this.notice,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_refresh);
      widget.refreshListenable?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    // A block body: an arrow would return the Future, which setState rejects
    // in debug builds before it marks the screen for rebuild.
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Dashboard',
      action: ElevatedButton.icon(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  NewOrderScreen(orderRepository: widget.orderRepository),
            ),
          );
          if (changed == true) {
            widget.onDataChanged?.call();
            if (widget.onDataChanged == null) _refresh();
          }
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New Order'),
      ),
      child: FutureBuilder<_DashboardData>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load dashboard.\n${errorText(snapshot.error)}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!;
          final summary = data.summary;
          final recentOrders = data.orders.take(5).toList();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?widget.notice,
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 116),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: AppRadius.all,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: .12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final sales = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "TODAY'S NET SALES",
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _money(summary.netSales),
                                maxLines: 1,
                                style: AppTextStyles.display.copyWith(
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                      final contextLabel = Text(
                        '${summary.completedOrders} completed orders'
                        '  •  ${_money(summary.averageOrder)} average',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white,
                        ),
                      );

                      if (constraints.maxWidth < 700) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            sales,
                            const SizedBox(height: AppSpacing.md),
                            contextLabel,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: sales),
                          contextLabel,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SummaryCardGrid(
                  children: [
                    SummaryCard(
                      label: 'Orders',
                      value: '${summary.completedOrders}',
                      subtitle: '${summary.openOrders} currently open',
                      accentColor: AppColors.primary,
                    ),
                    SummaryCard(
                      label: 'Refunds',
                      value: _money(summary.refunds),
                      subtitle: 'Completed refunds today',
                      accentColor: AppColors.orange,
                    ),
                    SummaryCard(
                      label: summary.businessScope ? 'Expenses' : 'Your Sales',
                      value: summary.businessScope
                          ? _money(summary.expenses ?? 0)
                          : _money(summary.netSales),
                      subtitle: summary.businessScope
                          ? 'Posted expenses today'
                          : 'Your completed sales today',
                      accentColor: AppColors.black,
                    ),
                    if (summary.businessScope)
                      SummaryCard(
                        label: 'Net After Expenses',
                        value: _money(summary.netAfterExpenses ?? 0),
                        subtitle: 'Sales less refunds and expenses',
                        accentColor: AppColors.success,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Recent Orders', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.md),
                if (recentOrders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No orders recorded yet.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  )
                else
                  DataTableCard(
                    headers: const [
                      'Order',
                      'Time',
                      'Employee',
                      'Type',
                      'Amount',
                      'Status',
                    ],
                    flexes: const [2, 3, 3, 2, 2, 3],
                    rows: recentOrders
                        .map(
                          (order) => [
                            Text(order.id, style: AppTextStyles.bodyMedium),
                            Text(
                              order.timeLabelAt(DateTime.now()),
                              style: AppTextStyles.body,
                            ),
                            Text(order.employee, style: AppTextStyles.body),
                            Text(order.type, style: AppTextStyles.body),
                            Text(
                              _money(order.amount),
                              style: AppTextStyles.body,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(order.status),
                            ),
                          ],
                        )
                        .toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<_DashboardData> _loadDashboard() async {
    final results = await Future.wait([
      widget.dashboardRepository.getTodaySummary(),
      widget.orderRepository.getOrders(),
    ]);

    return _DashboardData(
      summary: results[0] as DashboardSummary,
      orders: results[1] as List<OrderRecord>,
    );
  }

  static String _money(double value) => formatReportMoney(value);
}

class _DashboardData {
  final DashboardSummary summary;
  final List<OrderRecord> orders;

  const _DashboardData({required this.summary, required this.orders});
}
