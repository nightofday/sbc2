import '../../models/reporting.dart';

abstract class ReportingRepository {
  Future<ReportingSnapshot> getSnapshot({required int days});

  Future<List<TransactionTraceRecord>> getTransactionTrace({required int days});
}
