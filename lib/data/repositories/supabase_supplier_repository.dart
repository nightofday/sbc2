import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/supplier_repository.dart';
import '../../models/supplier_record.dart';

class SupabaseSupplierRepository implements SupplierRepository {
  final SupabaseClient _client;

  SupabaseSupplierRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const _columns =
      'id, name, contact_person, phone, email, address, payment_terms_days, '
      'notes, is_active';

  SupplierRecord _fromRow(
    Map<String, dynamic> row, {
    required String itemsSupplied,
  }) {
    String text(String key) => (row[key]?.toString() ?? '').trim();

    final contactParts = <String>[
      if (text('contact_person').isNotEmpty) text('contact_person'),
      if (text('phone').isNotEmpty) text('phone'),
      if (text('email').isNotEmpty) text('email'),
    ];

    return SupplierRecord(
      id: text('id'),
      name: text('name'),
      contact: contactParts.isEmpty ? '—' : contactParts.join(' • '),
      itemsSupplied: itemsSupplied,
      status: row['is_active'] == true ? 'Active' : 'Inactive',
      contactPerson: text('contact_person'),
      phone: text('phone'),
      email: text('email'),
      address: text('address'),
      paymentTermsDays: (row['payment_terms_days'] as num?)?.toInt() ?? 0,
      notes: text('notes'),
    );
  }

  @override
  Future<List<SupplierRecord>> getSuppliers() async {
    final rows = await _client
        .from('suppliers')
        .select(_columns)
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) => _fromRow(
            Map<String, dynamic>.from(raw as Map),
            itemsSupplied: 'View supplier items',
          ),
        )
        .toList();
  }

  @override
  Future<SupplierRecord?> getSupplierById(String id) async {
    final rows = await _client
        .from('suppliers')
        .select(_columns)
        .eq('id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

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

    return _fromRow(
      Map<String, dynamic>.from(rows.first as Map),
      itemsSupplied: itemNames.isEmpty
          ? 'None linked yet'
          : itemNames.join(', '),
    );
  }

  @override
  Future<void> createSupplier(SupplierRecord supplier) async {
    await _client.rpc(
      'create_supplier',
      params: {
        'p_name': supplier.name,
        'p_contact_person': supplier.contactPerson,
        'p_phone': supplier.phone,
        'p_email': supplier.email,
        'p_address': supplier.address,
        'p_payment_terms_days': supplier.paymentTermsDays,
        'p_notes': supplier.notes,
      },
    );
  }

  // Every editable field is sent with its own value. The database treats an
  // empty string as "clear this field" and null as "leave it unchanged".
  @override
  Future<void> updateSupplier(SupplierRecord supplier) async {
    await _client.rpc(
      'update_supplier',
      params: {
        'p_supplier_id': supplier.id,
        'p_name': supplier.name,
        'p_contact_person': supplier.contactPerson,
        'p_phone': supplier.phone,
        'p_email': supplier.email,
        'p_address': supplier.address,
        'p_payment_terms_days': supplier.paymentTermsDays,
        'p_notes': supplier.notes,
        'p_is_active': supplier.status.toLowerCase() == 'active',
      },
    );
  }

  // Archiving changes the status only; no other field is sent.
}
