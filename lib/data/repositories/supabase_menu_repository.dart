import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/menu_repository.dart';
import '../../models/menu_management.dart';

class SupabaseMenuRepository implements MenuRepository {
  final SupabaseClient _client;

  SupabaseMenuRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<MenuVariantRecord>> getVariants() async {
    final rows = await _client
        .from('v_menu_management')
        .select()
        .order('item_name', ascending: true)
        .order('variant_name', ascending: true);

    return (rows as List)
        .map(
          (raw) =>
              MenuVariantRecord.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<List<MenuCategoryOption>> getCategories() async {
    final rows = await _client
        .from('menu_categories')
        .select('id, name')
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) =>
              MenuCategoryOption.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<List<MenuInventoryOption>> getInventoryOptions() async {
    final rows = await _client
        .from('v_inventory_catalog')
        .select('inventory_item_id, name, base_uom_code, usable_quantity')
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) => MenuInventoryOption.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> createMenuItemWithVariant({
    required String itemName,
    required String categoryId,
    required String variantName,
    required String sku,
    required double price,
    required String inventoryMode,
    String finishedInventoryItemId = '',
  }) async {
    await _client.rpc(
      'create_menu_item_with_variant',
      params: {
        'p_item_name': itemName.trim(),
        'p_category_id': categoryId,
        'p_variant_name': variantName.trim(),
        'p_sku': _nullable(sku),
        'p_price': price,
        'p_inventory_mode': inventoryMode,
        'p_finished_inventory_item_id': _nullable(finishedInventoryItemId),
        'p_recipe': const <Map<String, dynamic>>[],
      },
    );
  }

  @override
  Future<void> addVariant({
    required String menuItemId,
    required String variantName,
    required String sku,
    required double price,
    required String inventoryMode,
    String finishedInventoryItemId = '',
  }) async {
    await _client.rpc(
      'add_menu_variant',
      params: {
        'p_menu_item_id': menuItemId,
        'p_variant_name': variantName.trim(),
        'p_sku': _nullable(sku),
        'p_price': price,
        'p_inventory_mode': inventoryMode,
        'p_finished_inventory_item_id': _nullable(finishedInventoryItemId),
        'p_recipe': const <Map<String, dynamic>>[],
      },
    );
  }

  @override
  Future<void> updateVariant({
    required MenuVariantRecord variant,
    required String itemName,
    required String categoryId,
    required String variantName,
    required String sku,
    required double price,
    required bool isActive,
    required String inventoryMode,
    String finishedInventoryItemId = '',
  }) async {
    await _client.rpc(
      'update_menu_variant',
      params: {
        'p_variant_id': variant.variantId,
        'p_item_name': itemName.trim(),
        'p_category_id': categoryId,
        'p_variant_name': variantName.trim(),
        'p_sku': _nullable(sku),
        'p_price': price,
        'p_is_active': isActive,
        'p_inventory_mode': inventoryMode,
        'p_finished_inventory_item_id': _nullable(finishedInventoryItemId),
        'p_recipe': const <Map<String, dynamic>>[],
      },
    );
  }

  @override
  Future<List<MenuModifierGroupRecord>> getModifierGroupsForMenuItem(
    String menuItemId,
  ) async {
    final rows = await _client
        .from('v_menu_modifier_management')
        .select()
        .eq('menu_item_id', menuItemId)
        .order('group_sort_order', ascending: true)
        .order('modifier_sort_order', ascending: true);

    final groups = <String, _MutableMenuModifierGroup>{};

    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final groupId = row['modifier_group_id']?.toString() ?? '';

      final group = groups.putIfAbsent(
        groupId,
        () => _MutableMenuModifierGroup(
          menuItemId: row['menu_item_id']?.toString() ?? '',
          groupId: groupId,
          groupName: row['group_name']?.toString() ?? '',
          minSelections: (row['min_selections'] as num?)?.toInt() ?? 0,
          maxSelections: (row['max_selections'] as num?)?.toInt(),
          isRequired: row['is_required'] == true,
          isActive: row['group_active'] == true,
        ),
      );

      final modifierId = row['modifier_id']?.toString() ?? '';
      if (modifierId.isNotEmpty) {
        group.modifiers.add(
          MenuModifierRecord(
            id: modifierId,
            name: row['modifier_name']?.toString() ?? '',
            priceDelta: (row['price_delta'] as num?)?.toDouble() ?? 0,
            isActive: row['modifier_active'] == true,
          ),
        );
      }
    }

    return groups.values.map((group) => group.toRecord()).toList();
  }

  @override
  Future<String> createModifierGroup({
    required String menuItemId,
    required String groupName,
    required int minSelections,
    int? maxSelections,
    required bool isRequired,
  }) async {
    final result = await _client.rpc(
      'create_modifier_group_for_menu_item',
      params: {
        'p_menu_item_id': menuItemId,
        'p_group_name': groupName.trim(),
        'p_min_selections': minSelections,
        'p_max_selections': maxSelections,
        'p_is_required': isRequired,
      },
    );

    return result.toString();
  }

  @override
  Future<void> updateModifierGroup({
    required String groupId,
    required String groupName,
    required int minSelections,
    int? maxSelections,
    required bool isRequired,
    required bool isActive,
  }) async {
    await _client.rpc(
      'update_modifier_group',
      params: {
        'p_modifier_group_id': groupId,
        'p_group_name': groupName.trim(),
        'p_min_selections': minSelections,
        'p_max_selections': maxSelections,
        'p_is_required': isRequired,
        'p_is_active': isActive,
      },
    );
  }

  @override
  Future<String> createModifier({
    required String groupId,
    required String name,
    required double priceDelta,
  }) async {
    final result = await _client.rpc(
      'create_modifier',
      params: {
        'p_modifier_group_id': groupId,
        'p_name': name.trim(),
        'p_price_delta': priceDelta,
        'p_recipe': const <Map<String, dynamic>>[],
      },
    );

    return result.toString();
  }

  @override
  Future<void> updateModifier({
    required String modifierId,
    required String name,
    required double priceDelta,
    required bool isActive,
  }) async {
    await _client.rpc(
      'update_modifier',
      params: {
        'p_modifier_id': modifierId,
        'p_name': name.trim(),
        'p_price_delta': priceDelta,
        'p_is_active': isActive,
        'p_recipe': const <Map<String, dynamic>>[],
      },
    );
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MutableMenuModifierGroup {
  final String menuItemId;
  final String groupId;
  final String groupName;
  final int minSelections;
  final int? maxSelections;
  final bool isRequired;
  final bool isActive;
  final List<MenuModifierRecord> modifiers = [];

  _MutableMenuModifierGroup({
    required this.menuItemId,
    required this.groupId,
    required this.groupName,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
    required this.isActive,
  });

  MenuModifierGroupRecord toRecord() {
    return MenuModifierGroupRecord(
      menuItemId: menuItemId,
      groupId: groupId,
      groupName: groupName,
      minSelections: minSelections,
      maxSelections: maxSelections,
      isRequired: isRequired,
      isActive: isActive,
      modifiers: List<MenuModifierRecord>.unmodifiable(modifiers),
    );
  }
}
