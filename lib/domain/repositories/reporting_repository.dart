import '../../models/audit_entry.dart';
import '../../models/reporting.dart';

abstract class ReportingRepository {
  /// The report for the business days [from] to [to], both included.
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  });

  Future<List<TransactionTraceRecord>> getTransactionTrace({required int days});

  /// Who changed what between [from] and [to], newest first.
  Future<List<AuditEntry>> getAuditLog({
    required DateTime from,
    required DateTime to,
    String search = '',
  });
}
