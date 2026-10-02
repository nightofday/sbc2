import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/package_memory.dart';

/// Reads the package sizes recorded when stock was received.
Future<PackageMemory> loadPackageMemory(SupabaseClient client) async {
  final rows = await client
      .from('supplier_items')
      .select(
        'supplier_id, inventory_item_id, purchase_uom_id, '
        'base_quantity_per_purchase_unit, last_unit_cost',
      )
      .eq('is_active', true)
      .order('updated_at', ascending: false);

  return PackageMemory(
    (rows as List)
        .map(
          (raw) => PackageSize.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList(),
  );
}
