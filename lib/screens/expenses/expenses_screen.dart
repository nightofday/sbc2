import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/reporting.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../models/expense_record.dart';
import '../../models/request_id.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/layout/app_page.dart';

class ExpensesScreen extends StatefulWidget {
  final ExpenseRepository expenseRepository;
  final Listenable? refreshListenable;
  final VoidCallback? onDataChanged;

  const ExpensesScreen({
    super.key,
    required this.expenseRepository,
    this.refreshListenable,
    this.onDataChanged,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<ExpenseRecord> _expenses = [];
  List<ExpenseCategoryOption> _categories = [];
  List<ExpenseSupplierOption> _suppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'All Categories';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
    widget.refreshListenable?.addListener(_loadExpenses);
  }

  @override
  void didUpdateWidget(covariant ExpensesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_loadExpenses);
      widget.refreshListenable?.addListener(_loadExpenses);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_loadExpenses);
    super.dispose();
  }

  void _notifyDataChanged() {
    final callback = widget.onDataChanged;
    if (callback == null) {
      _loadExpenses();
    } else {
      callback();
    }
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        widget.expenseRepository.getExpenses(),
        widget.expenseRepository.getCategories(),
        widget.expenseRepository.getSuppliers(),
      ]);

      if (!mounted) return;

      setState(() {
        _expenses = results[0] as List<ExpenseRecord>;
        _categories = results[1] as List<ExpenseCategoryOption>;
        _suppliers = results[2] as List<ExpenseSupplierOption>;
        _isLoading = false;

        if (_selectedCategory != 'All Categories' &&
            !_categories.any(
              (category) => category.name == _selectedCategory,
            )) {
          _selectedCategory = 'All Categories';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = errorText(error);
      });
    }
  }

  List<ExpenseRecord> get _filteredExpenses {
    final query = _searchQuery.trim().toLowerCase();

    return _expenses.where((expense) {
      final matchesSearch =
          query.isEmpty ||
          expense.description.toLowerCase().contains(query) ||
          expense.category.toLowerCase().contains(query) ||
          expense.supplierName.toLowerCase().contains(query) ||
          expense.referenceNumber.toLowerCase().contains(query) ||
          'ex-${expense.expenseNumber}'.contains(query);

      final matchesCategory =
          _selectedCategory == 'All Categories' ||
          expense.category == _selectedCategory;

      return matchesSearch && matchesCategory;
    }).toList();
  }

  double get _totalExpenses {
    return _filteredExpenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppPage(
        title: 'Expenses',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AppPage(
      title: 'Expenses',
      subtitle: 'Record untracked grocery purchases and operating costs with receipts.',
      action: ElevatedButton.icon(
        onPressed: _categories.isEmpty || _suppliers.isEmpty
            ? null
            : _showAddExpense,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Expense'),
      ),
      child: _loadError != null
          ? Center(
              child: Text(
                'Unable to load expenses.\n$_loadError',
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              children: [
                if (_suppliers.isEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Add the grocery store or supplier in Suppliers before '
                      'recording an expense.',
                      style: AppTextStyles.body,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Builder(
                  builder: (context) {
                    final search = TextField(
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search expense...',
                      ),
                    );
                    final category = DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'All Categories',
                          child: Text('All Categories'),
                        ),
                        for (final category in _categories)
                          DropdownMenuItem(
                            value: category.name,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedCategory = value);
                      },
                    );

                    return ResponsiveFilterBar(
                      primary: search,
                      filters: [category],
                      filterWidths: const [230],
                      breakpoint: 620,
                    );
                  },
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_filteredExpenses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No expenses found.'),
                          )
                        else
                          DataTableCard(
                            headers: const [
                              'Date',
                              'Purpose',
                              'Category',
                              'Supplier / Reference',
                              'Amount',
                              'Actions',
                            ],
                            flexes: const [2, 4, 3, 3, 2, 2],
                            rows: _filteredExpenses
                                .map(
                                  (expense) => [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          expense.date,
                                          style: AppTextStyles.bodyMedium,
                                        ),
                                        if (expense.expenseNumber > 0)
                                          Text(
                                            'EX-${expense.expenseNumber}',
                                            style: AppTextStyles.caption,
                                          ),
                                      ],
                                    ),
                                    Text(
                                      expense.description,
                                      style: AppTextStyles.body,
                                    ),
                                    Text(
                                      expense.category,
                                      style: AppTextStyles.body,
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          expense.supplierName.isEmpty
                                              ? '—'
                                              : expense.supplierName,
                                          style: AppTextStyles.body,
                                        ),
                                        if (expense.referenceNumber.isNotEmpty)
                                          Text(
                                            expense.referenceNumber,
                                            style: AppTextStyles.caption,
                                          ),
                                      ],
                                    ),
                                    Text(
                                      _money(expense.amount),
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          onPressed: () =>
                                              _showEditExpense(expense),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Void',
                                          onPressed: () =>
                                              _confirmVoidExpense(expense),
                                          icon: const Icon(
                                            Icons.block,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 330,
                            child: SectionCard(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Expenses',
                                    style: AppTextStyles.caption,
                                  ),
                                  Text(
                                    _money(_totalExpenses),
                                    style: AppTextStyles.h2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAddExpense() async {
    await _showExpenseEditor();
  }

  Future<void> _showEditExpense(ExpenseRecord expense) async {
    await _showExpenseEditor(existing: expense);
  }

  Future<void> _showExpenseEditor({ExpenseRecord? existing}) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    if (_categories.isEmpty || _suppliers.isEmpty) return;

    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final amountController = TextEditingController(
      text: existing == null ? '' : existing.amount.toString(),
    );
    final referenceController = TextEditingController(
      text: existing?.referenceNumber ?? '',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');

    String selectedCategory = existing?.category ?? _categories.first.name;
    String selectedSupplierId = existing?.supplierId ?? _suppliers.first.id;
    DateTime selectedDate = existing?.expenseDate ?? DateTime.now();

    if (!_categories.any((category) => category.name == selectedCategory)) {
      selectedCategory = _categories.first.name;
    }
    if (!_suppliers.any((supplier) => supplier.id == selectedSupplierId)) {
      selectedSupplierId = _suppliers.first.id;
    }

    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: existing == null ? 'Add Expense' : 'Edit Expense',
      width: 540,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date == null) return;
                      setDialogState(() => selectedDate = date);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('Date: ${_formatDate(selectedDate)}'),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Purpose *',
                    hintText: 'Example: milk and sugar for daily operations',
                  ),
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
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category *'),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.name,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedCategory = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedSupplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Supplier / Grocery *',
                  ),
                  items: _suppliers
                      .map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedSupplierId = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Receipt / Reference Number *',
                    hintText: 'Official receipt, invoice, or grocery reference',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Inventory purchases should be recorded through Purchasing, '
                    'not duplicated as operating expenses.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
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
            final description = descriptionController.text.trim();
            final amount = double.tryParse(amountController.text.trim());
            final referenceNumber = referenceController.text.trim();

            if (description.isEmpty ||
                amount == null ||
                amount <= 0 ||
                selectedSupplierId.isEmpty ||
                referenceNumber.isEmpty) {
              updateDialogState?.call(() {
                errorMessage =
                    'Purpose, amount, supplier/grocery, and receipt/reference '
                    'are required.';
              });
              return;
            }

            ExpenseSupplierOption? supplier;
            for (final entry in _suppliers) {
              if (entry.id == selectedSupplierId) {
                supplier = entry;
                break;
              }
            }

            final record = ExpenseRecord(
              id: existing?.id ?? '',
              expenseNumber: existing?.expenseNumber ?? 0,
              expenseType: existing?.expenseType ?? 'OPERATING',
              date: _formatDate(selectedDate),
              description: description,
              category: selectedCategory,
              amount: amount,
              expenseDate: selectedDate,
              supplierId: selectedSupplierId,
              supplierName: supplier?.name ?? '',
              referenceNumber: referenceNumber,
              notes: notesController.text.trim(),
            );

            try {
              if (existing == null) {
                await widget.expenseRepository.createExpense(
                  record,
                  clientRequestId: requestId,
                );
              } else {
                await widget.expenseRepository.updateExpense(record);
              }

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    existing == null ? 'Expense added.' : 'Expense updated.',
                  ),
                ),
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
          child: Text(existing == null ? 'Save Expense' : 'Save Changes'),
        ),
      ],
    );

    descriptionController.dispose();
    amountController.dispose();
    referenceController.dispose();
    notesController.dispose();
  }

  Future<void> _confirmVoidExpense(ExpenseRecord expense) async {
    final voided = await showReasonDialog(
      context: context,
      title: 'Void Expense',
      message:
          'This keeps the expense on record with your reason, but removes '
          '${expense.description} (${_money(expense.amount.toDouble())}) '
          'from expense totals.',
      confirmLabel: 'Void Expense',
      onConfirm: (reason) async {
        try {
          await widget.expenseRepository.deleteExpense(
            expense.id,
            reason: reason,
          );
          return null;
        } on PostgrestException catch (error) {
          return error.message;
        } catch (error) {
          return errorText(error);
        }
      },
    );

    if (voided && mounted) _notifyDataChanged();
  }

  String _money(double value) => formatReportMoney(value);

  String _formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
