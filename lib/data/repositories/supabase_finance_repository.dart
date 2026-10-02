import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/finance_repository.dart';
import '../../models/finance_management.dart';

class SupabaseFinanceRepository implements FinanceRepository {
  final SupabaseClient _client;

  SupabaseFinanceRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<SupplierBalanceRecord>> getSupplierBalances() async {
    final rows = await _client
        .from('v_supplier_balances')
        .select()
        .gt('balance', 0)
        .order('due_date', ascending: true)
        .order('invoice_date', ascending: true);

    return (rows as List)
        .map(
          (raw) => SupplierBalanceRecord.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<FinancePaymentMethod>> getPaymentMethods() async {
    final rows = await _client
        .from('payment_methods')
        .select('id, code, name, requires_reference')
        .eq('is_active', true)
        .order('sort_order', ascending: true);

    return (rows as List)
        .map(
          (raw) => FinancePaymentMethod.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> recordSupplierPayment({
    required String supplierBillId,
    required String paymentMethodId,
    required double amount,
    String referenceNumber = '',
    String notes = '',
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'record_supplier_bill_payment',
      params: {
        'p_supplier_bill_id': supplierBillId,
        'p_payment_method_id': paymentMethodId,
        'p_amount': amount,
        'p_reference_number': referenceNumber.trim().isEmpty
            ? null
            : referenceNumber.trim(),
        'p_notes': notes.trim().isEmpty ? null : notes.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }

  @override
  Future<List<SupplierPaymentRecord>> getSupplierPayments({
    int limit = 50,
  }) async {
    final rows = await _client
        .from('v_supplier_bill_payments')
        .select()
        .order('paid_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map(
          (raw) => SupplierPaymentRecord.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> voidSupplierPayment({
    required String paymentId,
    required String reason,
    String? clientRequestId,
  }) async {
    await _client.rpc(
      'void_supplier_bill_payment',
      params: {
        'p_payment_id': paymentId,
        'p_reason': reason.trim(),
        'p_client_request_id': clientRequestId,
      },
    );
  }
}
