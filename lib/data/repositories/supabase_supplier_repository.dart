import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/supplier_repository.dart';
import '../../models/supplier_record.dart';

class SupabaseSupplierRepository implements SupplierRepository {
  final SupabaseClient _client;

  SupabaseSupplierRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<SupplierRecord>> getSuppliers() async {
    final rows = await _client
        .from('suppliers')
        .select('id, name, contact_person, phone, email, is_active')
        .order('name');

    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final contactParts = <String>[
        if ((row['contact_person']?.toString() ?? '').trim().isNotEmpty)
          row['contact_person'].toString(),
        if ((row['phone']?.toString() ?? '').trim().isNotEmpty)
          row['phone'].toString(),
        if ((row['email']?.toString() ?? '').trim().isNotEmpty)
          row['email'].toString(),
      ];

      return SupplierRecord(
        id: row['id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        contact: contactParts.isEmpty ? '—' : contactParts.join(' • '),
        itemsSupplied: 'View supplier items',
        status: row['is_active'] == true ? 'Active' : 'Inactive',
      );
    }).toList();
  }

  @override
  Future<SupplierRecord?> getSupplierById(String id) async {
    final rows = await _client
        .from('suppliers')
        .select('id, name, contact_person, phone, email, is_active')
        .eq('id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first as Map);
    final contactParts = <String>[
      if ((row['contact_person']?.toString() ?? '').trim().isNotEmpty)
        row['contact_person'].toString(),
      if ((row['phone']?.toString() ?? '').trim().isNotEmpty)
        row['phone'].toString(),
      if ((row['email']?.toString() ?? '').trim().isNotEmpty)
        row['email'].toString(),
    ];

    final itemRows = await _client
        .from('supplier_items')
        .select('inventory_items(name)')
        .eq('supplier_id', id);

    final itemNames = <String>[];
    for (final raw in itemRows as List) {
      final rel = (raw as Map)['inventory_items'];
      if (rel is Map && rel['name'] != null) {
        itemNames.add(rel['name'].toString());
      }
    }

    return SupplierRecord(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      contact: contactParts.isEmpty ? '—' : contactParts.join(' • '),
      itemsSupplied: itemNames.isEmpty
          ? 'None linked yet'
          : itemNames.join(', '),
      status: row['is_active'] == true ? 'Active' : 'Inactive',
    );
  }

  @override
  Future<void> createSupplier(SupplierRecord supplier) async {
    await _client.rpc(
      'create_supplier',
      params: {
        'p_name': supplier.name,
        'p_contact_person': null,
        'p_phone': supplier.contact,
        'p_email': null,
        'p_address': null,
        'p_payment_terms_days': 0,
        'p_notes': supplier.itemsSupplied == 'View supplier items'
            ? null
            : supplier.itemsSupplied,
      },
    );
  }

  @override
  Future<void> updateSupplier(SupplierRecord supplier) async {
    await _client.rpc(
      'update_supplier',
      params: {
        'p_supplier_id': supplier.id,
        'p_name': supplier.name,
        'p_contact_person': null,
        'p_phone': supplier.contact,
        'p_email': null,
        'p_address': null,
        'p_payment_terms_days': 0,
        'p_notes': supplier.itemsSupplied,
        'p_is_active': supplier.status.toLowerCase() == 'active',
      },
    );
  }

  @override
  Future<void> deleteSupplier(String id) async {
    final supplier = await getSupplierById(id);
    if (supplier == null) return;

    await updateSupplier(supplier.copyWith(status: 'Inactive'));
  }
}
