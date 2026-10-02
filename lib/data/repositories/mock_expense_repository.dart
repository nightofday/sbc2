import '../../domain/repositories/expense_repository.dart';
import '../../models/expense_record.dart';
import '../mock_data.dart';

class MockExpenseRepository implements ExpenseRepository {
  final List<ExpenseRecord> _expenses = List<ExpenseRecord>.from(
    MockData.expenses,
  );

  @override
  Future<List<ExpenseRecord>> getExpenses() async {
    return List<ExpenseRecord>.unmodifiable(_expenses);
  }

  @override
  Future<ExpenseRecord?> getExpenseById(String id) async {
    for (final expense in _expenses) {
      if (expense.id == id) return expense;
    }
    return null;
  }

  @override
  Future<List<ExpenseCategoryOption>> getCategories() async => const [];

  @override
  Future<List<ExpenseSupplierOption>> getSuppliers() async => const [];

  @override
  Future<void> createExpense(ExpenseRecord expense) async {
    _expenses.insert(0, expense);
  }

  @override
  Future<void> updateExpense(ExpenseRecord expense) async {
    final index = _expenses.indexWhere((entry) => entry.id == expense.id);
    if (index == -1) return;
    _expenses[index] = expense;
  }

  @override
  Future<void> deleteExpense(String id) async {
    _expenses.removeWhere((expense) => expense.id == id);
  }
}
