import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/dashboard_repository.dart';
import '../../models/dashboard_summary.dart';

class SupabaseDashboardRepository implements DashboardRepository {
  final SupabaseClient _client;

  SupabaseDashboardRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<DashboardSummary> getTodaySummary() async {
    final result = await _client.rpc('get_dashboard_summary');
    return DashboardSummary.fromMap(Map<String, dynamic>.from(result as Map));
  }
}
