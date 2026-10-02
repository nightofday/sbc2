import '../../models/reporting.dart';

abstract class ReportingRepository {
  /// The report for the business days [from] to [to], both included.
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  });

  Future<List<TransactionTraceRecord>> getTransactionTrace({required int days});
}
