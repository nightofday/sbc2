import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/expense_repository.dart';
import '../../models/expense_record.dart';

class SupabaseExpenseRepository implements ExpenseRepository {
  final SupabaseClient _client;

  SupabaseExpenseRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<ExpenseRecord>> getExpenses() async {
    final rows = await _client
        .from('expenses')
        .select(
          'id, expense_number, expense_type, expense_date, description, '
          'amount, status, '
          'supplier_id, reference_number, notes, expense_categories(name), '
          'suppliers(name)',
        )
        .neq('status', 'VOIDED')
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false);

    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final categoryRaw = row['expense_categories'];
      final category = categoryRaw is Map
          ? Map<String, dynamic>.from(categoryRaw)['name']?.toString() ??
                'Other'
          : 'Other';
      final supplierRaw = row['suppliers'];
      final supplierName = supplierRaw is Map
          ? Map<String, dynamic>.from(supplierRaw)['name']?.toString() ?? ''
          : '';
      final expenseDate = DateTime.parse(row['expense_date'].toString());

      return ExpenseRecord(
        id: row['id']?.toString() ?? '',
        expenseNumber: (row['expense_number'] as num?)?.toInt() ?? 0,
        expenseType: row['expense_type']?.toString() ?? 'OPERATING',
        date: _formatDate(expenseDate),
        description: row['description']?.toString() ?? '',
        category: category,
        amount: ((row['amount'] as num?) ?? 0).toDouble(),
        expenseDate: expenseDate,
        supplierId: row['supplier_id']?.toString() ?? '',
        supplierName: supplierName,
        referenceNumber: row['reference_number']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
      );
    }).toList();
  }

  @override
  Future<List<ExpenseCategoryOption>> getCategories() async {
    final rows = await _client
        .from('expense_categories')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

    return (rows as List)
        .map(
          (raw) => ExpenseCategoryOption.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<ExpenseSupplierOption>> getSuppliers() async {
    final rows = await _client
        .from('suppliers')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

    return (rows as List)
        .map(
          (raw) => ExpenseSupplierOption.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<ExpenseRecord?> getExpenseById(String id) async {
    final rows = await _client
        .from('expenses')
        .select(
          'id, expense_number, expense_type, expense_date, description, '
          'amount, status, supplier_id, reference_number, notes, '
          'expense_categories(name), suppliers(name)',
        )
        .eq('id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first as Map);
    final categoryRaw = row['expense_categories'];
    final category = categoryRaw is Map
        ? Map<String, dynamic>.from(categoryRaw)['name']?.toString() ?? 'Other'
        : 'Other';
    final supplierRaw = row['suppliers'];
    final supplierName = supplierRaw is Map
        ? Map<String, dynamic>.from(supplierRaw)['name']?.toString() ?? ''
        : '';
    final expenseDate = DateTime.parse(row['expense_date'].toString());

    return ExpenseRecord(
      id: row['id']?.toString() ?? '',
      expenseNumber: (row['expense_number'] as num?)?.toInt() ?? 0,
      expenseType: row['expense_type']?.toString() ?? 'OPERATING',
      date: _formatDate(expenseDate),
      description: row['description']?.toString() ?? '',
      category: category,
      amount: ((row['amount'] as num?) ?? 0).toDouble(),
      expenseDate: expenseDate,
      supplierId: row['supplier_id']?.toString() ?? '',
      supplierName: supplierName,
      referenceNumber: row['reference_number']?.toString() ?? '',
      notes: row['notes']?.toString() ?? '',
    );
  }

  @override
  Future<void> createExpense(
    ExpenseRecord expense, {
    String? clientRequestId,
  }) async {
    final categoryId = await _categoryIdForName(expense.category);

    await _client.rpc(
      'create_expense',
      params: {
        'p_expense_category_id': categoryId,
        'p_description': expense.description,
        'p_amount': expense.amount,
        'p_expense_date': _dateOnly(expense.expenseDate ?? DateTime.now()),
        'p_payment_method_id': null,
        'p_supplier_id': _nullable(expense.supplierId),
        'p_reference_number': _nullable(expense.referenceNumber),
        'p_notes': _nullable(expense.notes),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<void> updateExpense(ExpenseRecord expense) async {
    final categoryId = await _categoryIdForName(expense.category);

    await _client.rpc(
      'update_expense',
      params: {
        'p_expense_id': expense.id,
        'p_expense_category_id': categoryId,
        'p_description': expense.description,
        'p_amount': expense.amount,
        'p_expense_date': _dateOnly(expense.expenseDate ?? DateTime.now()),
        'p_payment_method_id': null,
        'p_supplier_id': _nullable(expense.supplierId),
        'p_reference_number': _nullable(expense.referenceNumber),
        'p_notes': _nullable(expense.notes),
      },
    );
  }

  @override
  Future<void> deleteExpense(String id, {required String reason}) async {
    await _client.rpc(
      'void_expense',
      params: {'p_expense_id': id, 'p_reason': reason.trim()},
    );
  }

  Future<String> _categoryIdForName(String name) async {
    final rows = await _client
        .from('expense_categories')
        .select('id')
        .eq('name', name)
        .eq('is_active', true)
        .limit(1);

    if ((rows as List).isNotEmpty) {
      return (rows.first as Map)['id'].toString();
    }

    final otherRows = await _client
        .from('expense_categories')
        .select('id')
        .eq('code', 'OTHER')
        .limit(1);

    if ((otherRows as List).isEmpty) {
      throw const FormatException('No usable expense category is configured.');
    }

    return (otherRows.first as Map)['id'].toString();
  }

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
