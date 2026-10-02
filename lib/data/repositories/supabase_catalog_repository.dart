import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/catalog_repository.dart';
import '../../models/catalog_management.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  final SupabaseClient _client;

  SupabaseCatalogRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<CategoryRecord>> listCategories(CategoryDomain domain) async {
    final rows = await _client.rpc(
      'list_categories',
      params: {'p_domain': domain.code},
    );

    return (rows as List)
        .map(
          (raw) =>
              CategoryRecord.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<void> createCategory(
    CategoryDomain domain, {
    required String name,
    String description = '',
  }) async {
    await _client.rpc(
      'create_category',
      params: {
        'p_domain': domain.code,
        'p_name': name,
        'p_description': description,
      },
    );
  }

  @override
  Future<void> updateCategory(
    CategoryDomain domain,
    String categoryId, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    await _client.rpc(
      'update_category',
      params: {
        'p_domain': domain.code,
        'p_category_id': categoryId,
        'p_name': name,
        'p_description': description,
        'p_is_active': isActive,
      },
    );
  }

  @override
  Future<void> reorderCategories(
    CategoryDomain domain,
    List<String> categoryIds,
  ) async {
    await _client.rpc(
      'reorder_categories',
      params: {'p_domain': domain.code, 'p_category_ids': categoryIds},
    );
  }

  @override
  Future<List<DiscountDefinition>> listDiscounts() async {
    final rows = await _client
        .from('discount_types')
        .select(
          'id, name, calculation_method, default_value, allow_custom_value, '
          'max_value, valid_from, valid_until, is_active, is_pos_enabled, '
          'requires_id, is_tax_exempt_related, notes',
        )
        .order('name');

    return (rows as List)
        .map(
          (raw) =>
              DiscountDefinition.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<void> createDiscount(DiscountDefinition discount) async {
    await _client.rpc(
      'create_discount_type',
      params: {
        'p_name': discount.name,
        'p_calculation_method': discount.calculationMethod,
        'p_value': discount.value,
        'p_allow_custom_value': discount.allowCustomValue,
        'p_max_value': discount.maxValue,
        'p_valid_from': _dateOnly(discount.validFrom),
        'p_valid_until': _dateOnly(discount.validUntil),
        'p_notes': discount.notes,
      },
    );
  }

  @override
  Future<void> updateDiscount(DiscountDefinition discount) async {
    await _client.rpc(
      'update_discount_type',
      params: {
        'p_discount_type_id': discount.id,
        'p_name': discount.name,
        'p_value': discount.value,
        'p_allow_custom_value': discount.allowCustomValue,
        'p_max_value': discount.maxValue,
        'p_valid_from': _dateOnly(discount.validFrom),
        'p_valid_until': _dateOnly(discount.validUntil),
        'p_is_active': discount.isActive,
        'p_notes': discount.notes,
      },
    );
  }

  String? _dateOnly(DateTime? date) {
    if (date == null) return null;

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
