import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';

class SupabaseReportingRepository implements ReportingRepository {
  final SupabaseClient _client;

  SupabaseReportingRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<BusinessReport> getBusinessReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final results = await Future.wait<dynamic>([
      _client.rpc(
        'get_business_report',
        params: {'p_from': _dateOnly(from), 'p_to': _dateOnly(to)},
      ),
      _client
          .from('v_low_stock')
          .select('name, usable_quantity, reorder_level, base_uom_code')
          .order('name', ascending: true),
      _client
          .from('v_expiring_inventory_lots')
          .select(
            'item_name, lot_code, expiration_date, remaining_quantity, '
            'uom_code, days_until_expiry',
          )
          .gte('days_until_expiry', 0)
          .lte('days_until_expiry', 7)
          .order('expiration_date', ascending: true),
    ]);

    List<Map<String, dynamic>> rows(dynamic raw) => (raw as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    return BusinessReport.fromJson(
      Map<String, dynamic>.from(results[0] as Map),
      lowStock: rows(results[1]),
      expiringSoon: rows(results[2]),
    );
  }

  @override
  Future<List<TransactionTraceRecord>> getTransactionTrace({
    required int days,
  }) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final endExclusive = DateTime(now.year, now.month, now.day + 1);

    final rows = await _client
        .from('v_business_transaction_trace')
        .select()
        .gte('occurred_at', start.toUtc().toIso8601String())
        .lt('occurred_at', endExclusive.toUtc().toIso8601String())
        .order('occurred_at', ascending: false)
        .limit(500);

    return (rows as List)
        .map(
          (raw) => TransactionTraceRecord.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  String _dateOnly(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
