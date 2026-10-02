import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/finance_management.dart';
import '../../models/reporting.dart';
import '../../models/request_id.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/common/summary_card.dart';
import '../../widgets/layout/app_page.dart';

class SalesFinanceScreen extends StatefulWidget {
  final ReportingRepository reportingRepository;
  final FinanceRepository financeRepository;
  final Listenable? refreshListenable;
  final VoidCallback? onDataChanged;

  const SalesFinanceScreen({
    super.key,
    required this.reportingRepository,
    required this.financeRepository,
    this.refreshListenable,
    this.onDataChanged,
  });

  @override
  State<SalesFinanceScreen> createState() => _SalesFinanceScreenState();
}

class _SalesFinanceScreenState extends State<SalesFinanceScreen> {
  int _days = 7;
  late Future<BusinessReport> _reportFuture;
  late Future<List<SupplierBalanceRecord>> _balancesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant SalesFinanceScreen oldWidget) {
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _reportFuture = widget.reportingRepository.getBusinessReport(
      from: today.subtract(Duration(days: _days - 1)),
      to: today,
    );
    _balancesFuture = widget.financeRepository.getSupplierBalances();
  }

  void _changeDays(int days) {
    setState(() {
      _days = days;
      _reload();
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _notifyDataChanged() {
    final callback = widget.onDataChanged;
    if (callback == null) {
      _refresh();
    } else {
      callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Sales & Finance',
      action: SizedBox(
        width: 180,
        child: DropdownButtonFormField<int>(
          initialValue: _days,
          decoration: const InputDecoration(labelText: 'Report Period'),
          items: const [
            DropdownMenuItem(value: 7, child: Text('Last 7 Days')),
            DropdownMenuItem(value: 30, child: Text('Last 30 Days')),
          ],
          onChanged: (value) {
            if (value != null) _changeDays(value);
          },
        ),
      ),
      child: FutureBuilder<BusinessReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load finance data.\n${errorText(snapshot.error)}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final report = snapshot.data!;
          final finance = report.summary;
          final days = report.section('by_day');
          // Newest first, and only days on which something happened.
          final dailyRows = days.rows.reversed
              .where(
                (row) =>
                    ((row['orders'] as num?) ?? 0) > 0 ||
                    ((row['refunds'] as num?) ?? 0) > 0,
              )
              .take(10)
              .toList();

          return SingleChildScrollView(
            child: Column(
              children: [
                SummaryCardGrid(
                  children: [
                    SummaryCard(
                      label: 'Net Sales',
                      value: _money(finance.netSales),
                      subtitle: '${_money(finance.refunds)} refunded in period',
                      accentColor: AppColors.primary,
                    ),
                    SummaryCard(
                      label: 'Expenses',
                      value: _money(finance.expenses),
                      subtitle: 'Posted operating expenses',
                      accentColor: AppColors.orange,
                    ),
                    SummaryCard(
                      label: 'Net Sales Less Expenses',
                      value: _money(finance.netSalesLessExpenses),
                      subtitle: 'Net sales less posted expenses. Not profit.',
                      accentColor: AppColors.black,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ResponsiveSplit(
                  primary: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sales Summary', style: AppTextStyles.h3),
                      const SizedBox(height: 12),
                      if (dailyRows.isEmpty)
                        const SectionCard(
                          child: Text('No completed sales in this period.'),
                        )
                      else
                        DataTableCard(
                          headers: const [
                            'Date',
                            'Orders',
                            'Gross Sales',
                            'Discounts',
                            'Refunds',
                            'Net Sales',
                          ],
                          flexes: const [2, 1, 2, 2, 2, 2],
                          rows: dailyRows
                              .map(
                                (row) => [
                                  for (final column in days.columns.take(6))
                                    Text(
                                      days.display(row, column),
                                      style:
                                          column.key == 'date' ||
                                              column.key == 'net_sales'
                                          ? AppTextStyles.bodyMedium
                                          : AppTextStyles.body,
                                    ),
                                ],
                              )
                              .toList(),
                        ),
                    ],
                  ),
                  secondary: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Financial Summary',
                          style: AppTextStyles.h3,
                        ),
                        const SizedBox(height: 24),
                        _FinanceRow('Gross Sales', _money(finance.grossSales)),
                        const SizedBox(height: 14),
                        _FinanceRow('Discounts', _money(finance.discounts)),
                        const SizedBox(height: 14),
                        _FinanceRow('Refunds', _money(finance.refunds)),
                        const SizedBox(height: 14),
                        _FinanceRow('Net Sales', _money(finance.netSales)),
                        const SizedBox(height: 14),
                        _FinanceRow('Expenses', _money(finance.expenses)),
                        const Divider(height: 32),
                        _FinanceRow(
                          'Net Sales Less Expenses',
                          _money(finance.netSalesLessExpenses),
                          emphasis: true,
                        ),
                        const SizedBox(height: 22),
                        _FinanceRow('Completed Orders', '${finance.orders}'),
                        const SizedBox(height: 14),
                        _FinanceRow(
                          'Average Order',
                          _money(finance.averageOrder),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Supplier Payables', style: AppTextStyles.h3),
                    ),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<SupplierBalanceRecord>>(
                  future: _balancesFuture,
                  builder: (context, balancesSnapshot) {
                    if (balancesSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (balancesSnapshot.hasError) {
                      return SectionCard(
                        child: Text(
                          'Unable to load supplier payables. '
                          '${balancesSnapshot.error}',
                        ),
                      );
                    }

                    final balances =
                        balancesSnapshot.data ??
                        const <SupplierBalanceRecord>[];

                    if (balances.isEmpty) {
                      return const SectionCard(
                        child: Text('No outstanding supplier balances.'),
                      );
                    }

                    return DataTableCard(
                      headers: const [
                        'Supplier',
                        'Invoice',
                        'Invoice Date',
                        'Due Date',
                        'Amount',
                        'Paid',
                        'Balance',
                        'Action',
                      ],
                      flexes: const [3, 2, 2, 2, 2, 2, 2, 1],
                      rows: balances
                          .map(
                            (bill) => [
                              Text(
                                bill.supplierName,
                                style: AppTextStyles.bodyMedium,
                              ),
                              Text(
                                bill.invoiceNumber.isEmpty
                                    ? '—'
                                    : bill.invoiceNumber,
                                style: AppTextStyles.body,
                              ),
                              Text(
                                _date(bill.invoiceDate),
                                style: AppTextStyles.body,
                              ),
                              Text(
                                bill.dueDate == null
                                    ? '—'
                                    : _date(bill.dueDate!),
                                style: AppTextStyles.body,
                              ),
                              Text(
                                _money(bill.amount),
                                style: AppTextStyles.body,
                              ),
                              Text(
                                _money(bill.amountPaid),
                                style: AppTextStyles.body,
                              ),
                              Text(
                                _money(bill.balance),
                                style: AppTextStyles.bodyMedium,
                              ),
                              TextButton(
                                onPressed: () => _showSupplierPayment(bill),
                                child: const Text('Pay'),
                              ),
                            ],
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSupplierPayment(SupplierBalanceRecord bill) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final methods = await widget.financeRepository.getPaymentMethods();

    if (!mounted || methods.isEmpty) return;

    FinancePaymentMethod selectedMethod = methods.first;
    final amountController = TextEditingController(
      text: bill.balance.toStringAsFixed(2),
    );
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Pay Supplier Bill',
      width: 560,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogRow('Supplier', bill.supplierName),
              _dialogRow('Balance', _money(bill.balance)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedMethod.id,
                decoration: const InputDecoration(
                  labelText: 'Payment Method *',
                ),
                items: methods
                    .map(
                      (method) => DropdownMenuItem(
                        value: method.id,
                        child: Text(method.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedMethod = methods.firstWhere(
                      (method) => method.id == value,
                    );
                    errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  prefixText: '₱',
                ),
              ),
              if (selectedMethod.requiresReference) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: referenceController,
                  decoration: InputDecoration(
                    labelText: '${selectedMethod.name} Reference *',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(amountController.text.trim());

            if (amount == null || amount <= 0 || amount > bill.balance) {
              updateDialogState?.call(() {
                errorMessage =
                    'Enter an amount between ₱0.01 and the current balance.';
              });
              return;
            }

            if (selectedMethod.requiresReference &&
                referenceController.text.trim().isEmpty) {
              updateDialogState?.call(() {
                errorMessage =
                    'A payment reference is required for this method.';
              });
              return;
            }

            try {
              await widget.financeRepository.recordSupplierPayment(
                clientRequestId: requestId,
                supplierBillId: bill.billId,
                paymentMethodId: selectedMethod.id,
                amount: amount,
                referenceNumber: referenceController.text.trim(),
                notes: notesController.text.trim(),
              );

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Supplier payment recorded.')),
              );
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = errorText(error);
              });
            }
          },
          child: const Text('Record Payment'),
        ),
      ],
    );

    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _money(double value) => '₱${value.toStringAsFixed(2)}';

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

class _FinanceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _FinanceRow(this.label, this.value, {this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(color: AppColors.gray700),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: emphasis
                ? AppTextStyles.h2.copyWith(color: AppColors.primary)
                : AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}
