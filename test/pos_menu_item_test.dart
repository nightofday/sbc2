import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/pos_menu_item.dart';

void main() {
  PosMenuItem item({required String mode, double? availableQuantity}) {
    return PosMenuItem(
      variantId: 'variant',
      menuItemId: 'item',
      sku: 'SKU',
      name: 'Sample Bowl',
      variantName: 'Regular',
      category: 'Meals',
      price: 100,
      isDefault: true,
      inventoryTrackingMode: mode,
      availableQuantity: availableQuantity,
    );
  }

  test('prepared products remain available without recipe inventory', () {
    final prepared = item(mode: 'UNTRACKED');
    final legacyRecipe = item(mode: 'RECIPE', availableQuantity: 0);

    expect(prepared.tracksInventory, isFalse);
    expect(prepared.isOutOfStock, isFalse);
    expect(legacyRecipe.tracksInventory, isFalse);
    expect(legacyRecipe.isOutOfStock, isFalse);
  });

  test('countable finished goods are unavailable at zero usable stock', () {
    final finishedGood = item(mode: 'FINISHED_GOOD', availableQuantity: 0);

    expect(finishedGood.tracksInventory, isTrue);
    expect(finishedGood.isOutOfStock, isTrue);
  });
}
