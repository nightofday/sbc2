import '../../models/finance_management.dart';

abstract class FinanceRepository {
  Future<List<SupplierBalanceRecord>> getSupplierBalances();

  Future<List<FinancePaymentMethod>> getPaymentMethods();

  Future<void> recordSupplierPayment({
    required String supplierBillId,
    required String paymentMethodId,
    required double amount,
    String referenceNumber = '',
    String notes = '',
    String? clientRequestId,
  });

  /// The most recent supplier payments and reversals, newest first.
  Future<List<SupplierPaymentRecord>> getSupplierPayments({int limit = 50});

  /// Undoes a payment by recording a matching negative entry. The bill
  /// returns to what was owed before it.
  Future<void> voidSupplierPayment({
    required String paymentId,
    required String reason,
    String? clientRequestId,
  });
}
