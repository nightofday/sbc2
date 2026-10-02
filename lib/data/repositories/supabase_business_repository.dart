import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/business_repository.dart';
import '../../models/business_profile.dart';

class SupabaseBusinessRepository implements BusinessRepository {
  final SupabaseClient _client;

  SupabaseBusinessRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<BusinessProfile> getBusinessProfile() async {
    final results = await Future.wait<dynamic>([
      _client
          .from('business_profile')
          .select(
            'trade_name, registered_name, tin, address_line, city, province, '
            'postal_code, phone, email',
          )
          .order('id', ascending: true)
          .limit(1),
      _client.from('system_settings').select('key, value').inFilter('key', [
        'require_opening_cash',
        'require_closing_cash',
      ]),
    ]);

    final profileRows = results[0] as List;
    final map = profileRows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(profileRows.first as Map);

    for (final raw in results[1] as List) {
      final setting = Map<String, dynamic>.from(raw as Map);
      map[setting['key'].toString()] = setting['value'] == true;
    }

    return BusinessProfile.fromMap(map);
  }

  @override
  Future<void> saveBusinessProfile(BusinessProfile profile) async {
    await _client.rpc(
      'update_business_profile',
      params: {
        'p_trade_name': profile.tradeName,
        'p_registered_name': profile.registeredName,
        'p_tin': profile.tin,
        'p_address_line': profile.addressLine,
        'p_city': profile.city,
        'p_province': profile.province,
        'p_postal_code': profile.postalCode,
        'p_phone': profile.phone,
        'p_email': profile.email,
      },
    );
    await _client.rpc(
      'update_shift_cash_rules',
      params: {
        'p_require_opening_cash': profile.requireOpeningCash,
        'p_require_closing_cash': profile.requireClosingCash,
      },
    );
  }
}
