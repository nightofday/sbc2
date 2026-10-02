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
  });
}
