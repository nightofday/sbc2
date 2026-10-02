import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/common/summary_card.dart';
import '../../widgets/layout/app_page.dart';

class ReportsScreen extends StatefulWidget {
  final ReportingRepository reportingRepository;
  final Listenable? refreshListenable;

  const ReportsScreen({
    super.key,
    required this.reportingRepository,
    this.refreshListenable,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 7;
  late Future<ReportingSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
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

  void _reload() {
    _snapshotFuture = widget.reportingRepository.getSnapshot(days: _days);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Reports',
      action: OutlinedButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
      ),
      child: FutureBuilder<ReportingSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load reports.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!;
          final finance = data.finance;
          final inventory = data.inventory;
          final daily = data.dailySales;
          final maxSales = daily.fold<double>(
            0,
            (current, row) => row.netSales > current ? row.netSales : current,
          );

          return SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<int>(
                        initialValue: _days,
                        decoration: const InputDecoration(
                          labelText: 'Report Period',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 7,
                            child: Text('Last 7 Days'),
                          ),
                          DropdownMenuItem(
                            value: 30,
                            child: Text('Last 30 Days'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _days = value;
                            _reload();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SummaryCardGrid(
                  children: [
                    SummaryCard(
                      label: 'Net Sales',
                      value: _money(finance.netSales),
                      subtitle: 'Current report period',
                      accentColor: AppColors.primary,
                    ),
                    SummaryCard(
                      label: 'Orders',
                      value: '${finance.orders}',
                      subtitle: 'Completed transactions',
                      accentColor: AppColors.orange,
                    ),
                    SummaryCard(
                      label: 'Average Order',
                      value: _money(finance.averageOrder),
                      subtitle: 'Net sales per completed order',
                      accentColor: AppColors.black,
                    ),
                    SummaryCard(
                      label: 'Expenses',
                      value: _money(finance.expenses),
                      subtitle: 'Posted operating expenses',
                      accentColor: AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ResponsiveSplit(
                  primary: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sales by Day', style: AppTextStyles.h3),
                        const SizedBox(height: 20),
                        if (daily.isEmpty)
                          Text(
                            'No completed sales in this period.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.gray500,
                            ),
                          )
                        else
                          for (final row in daily)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _BarRow(
                                label: _date(row.date),
                                widthFactor: maxSales <= 0
                                    ? 0
                                    : row.netSales / maxSales,
                                value: _money(row.netSales),
                              ),
                            ),
                      ],
                    ),
                  ),
                  secondary: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Inventory Summary',
                          style: AppTextStyles.h3,
                        ),
                        const SizedBox(height: 24),
                        _ReportStat(
                          'Tracked Items',
                          '${inventory.itemCount}',
                          AppColors.success,
                        ),
                        const SizedBox(height: 16),
                        _ReportStat(
                          'Low Stock',
                          '${inventory.lowStockCount}',
                          AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        _ReportStat(
                          'Expiring Soon',
                          '${inventory.expiringSoonCount}',
                          AppColors.warning,
                        ),
                        const Divider(height: 32),
                        _ReportStat(
                          'Net After Expenses',
                          _money(finance.netAfterExpenses),
                          finance.netAfterExpenses >= 0
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Top Products — Last $_days Days',
                    style: AppTextStyles.h3,
                  ),
                ),
                const SizedBox(height: 12),
                if (data.topProducts.isEmpty)
                  const SectionCard(
                    child: Text('No product sales recorded yet.'),
                  )
                else
                  DataTableCard(
                    headers: const [
                      'Product',
                      'Variant',
                      'Sold',
                      'Refunded',
                      'Net Quantity',
                      'Net Sales',
                    ],
                    flexes: const [3, 2, 1, 1, 2, 2],
                    rows: data.topProducts
                        .map(
                          (row) => [
                            Text(row.itemName, style: AppTextStyles.bodyMedium),
                            Text(row.variantName, style: AppTextStyles.body),
                            Text(
                              _qty(row.quantitySold),
                              style: AppTextStyles.body,
                            ),
                            Text(
                              _qty(row.quantityRefunded),
                              style: AppTextStyles.body,
                            ),
                            Text(
                              _qty(row.netQuantitySold),
                              style: AppTextStyles.bodyMedium,
                            ),
                            Text(
                              _money(row.sales),
                              style: AppTextStyles.bodyMedium,
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

  String _money(double value) => '₱${value.toStringAsFixed(2)}';

  String _qty(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double widthFactor;
  final String value;

  const _BarRow({
    required this.label,
    required this.widthFactor,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final safeWidth = widthFactor.clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: AppTextStyles.caption)),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: constraints.maxWidth * safeWidth,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ReportStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(value, style: AppTextStyles.h3.copyWith(color: color)),
        ],
      ),
    );
  }
}
