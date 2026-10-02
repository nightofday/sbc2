import '../../models/menu_management.dart';

abstract class MenuRepository {
  Future<List<MenuVariantRecord>> getVariants();

  Future<List<MenuCategoryOption>> getCategories();

  Future<List<MenuInventoryOption>> getInventoryOptions();

  Future<List<MenuModifierGroupRecord>> getModifierGroupsForMenuItem(
    String menuItemId,
  );

  /// Every modifier group on the menu, for reuse on another product.
  Future<List<ModifierGroupLibraryRecord>> getModifierGroupLibrary();

  /// Uses an existing, shared group on [menuItemId].
  Future<void> attachModifierGroup({
    required String menuItemId,
    required String groupId,
  });

  /// Takes a group off one product without deleting it.
  Future<void> detachModifierGroup({
    required String menuItemId,
    required String groupId,
  });

  /// Sets the order options are offered in.
  Future<void> reorderModifiers({
    required String groupId,
    required List<String> modifierIds,
  });

  Future<String> createModifierGroup({
    required String menuItemId,
    required String groupName,
    required int minSelections,
    int? maxSelections,
    required bool isRequired,
  });

  Future<void> updateModifierGroup({
    required String groupId,
    required String groupName,
    required int minSelections,
    int? maxSelections,
    required bool isRequired,
    required bool isActive,
  });

  Future<String> createModifier({
    required String groupId,
    required String name,
    required double priceDelta,
  });

  Future<void> updateModifier({
    required String modifierId,
    required String name,
    required double priceDelta,
    required bool isActive,
  });

  Future<void> createMenuItemWithVariant({
    required String itemName,
    required String categoryId,
    required String variantName,
    required String sku,
    required double price,
    required String inventoryMode,
    String finishedInventoryItemId = '',
  });

  Future<void> addVariant({
    required String menuItemId,
    required String variantName,
    required String sku,
    required double price,
    required String inventoryMode,
    String finishedInventoryItemId = '',
  });

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
  });
}
