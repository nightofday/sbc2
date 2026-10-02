import '../../models/expense_record.dart';

abstract class ExpenseRepository {
  Future<List<ExpenseRecord>> getExpenses();

  Future<List<ExpenseCategoryOption>> getCategories();

  Future<List<ExpenseSupplierOption>> getSuppliers();

  Future<void> createExpense(ExpenseRecord expense, {String? clientRequestId});

  Future<void> updateExpense(ExpenseRecord expense);

  /// Voids the expense. It stays on record with the reason.
  Future<void> deleteExpense(String id, {required String reason});
}
