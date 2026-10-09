import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/menu_repository.dart';
import 'package:sbc_management_system/models/menu_management.dart';
import 'package:sbc_management_system/screens/menu/menu_management_screen.dart';

class _FakeMenuRepository implements MenuRepository {
  final List<String> calls = [];

  @override
  Future<List<MenuVariantRecord>> getVariants() async => const [
    MenuVariantRecord(
      menuItemId: 'item-iced',
      itemName: 'Iced Coffee with a Long Product Name',
      categoryId: 'coffee',
      categoryName: 'Coffee',
      variantId: 'variant-iced',
      sku: 'PRD-003',
      variantName: 'Regular',
      price: 150,
      isDefault: true,
      isActive: true,
      inventoryTrackingMode: 'UNTRACKED',
      finishedInventoryItemId: '',
      finishedInventoryName: '',
    ),
  ];

  @override
  Future<List<MenuCategoryOption>> getCategories() async => const [
    MenuCategoryOption(id: 'coffee', name: 'Coffee'),
  ];

  @override
  Future<List<MenuInventoryOption>> getInventoryOptions() async => const [];

  @override
  Future<List<MenuModifierGroupRecord>> getModifierGroupsForMenuItem(
    String menuItemId,
  ) async => const [
    MenuModifierGroupRecord(
      menuItemId: 'item-iced',
      groupId: 'group-size',
      groupName: 'Size',
      minSelections: 1,
      maxSelections: 1,
      isRequired: true,
      isActive: true,
      productCount: 2,
      modifiers: [
        MenuModifierRecord(
          id: 'regular',
          name: 'Regular',
          priceDelta: 0,
          isActive: true,
        ),
        MenuModifierRecord(
          id: 'large',
          name: 'Large',
          priceDelta: 20,
          isActive: true,
        ),
      ],
    ),
  ];

  @override
  Future<List<ModifierGroupLibraryRecord>> getModifierGroupLibrary() async {
    return const [
      ModifierGroupLibraryRecord(
        groupId: 'group-size',
        groupName: 'Size',
        minSelections: 1,
        maxSelections: 1,
        isRequired: true,
        isActive: true,
        activeOptionCount: 2,
        productCount: 2,
        productNames: 'Hot Coffee, Iced Coffee',
      ),
      ModifierGroupLibraryRecord(
        groupId: 'group-addons',
        groupName: 'Bowl Add-ons',
        minSelections: 0,
        maxSelections: 2,
        isRequired: false,
        isActive: true,
        activeOptionCount: 3,
        productCount: 1,
        productNames: 'Chicken Bowl',
      ),
    ];
  }

  @override
  Future<void> attachModifierGroup({
    required String menuItemId,
    required String groupId,
  }) async => calls.add('attach $groupId to $menuItemId');

  @override
  Future<void> detachModifierGroup({
    required String menuItemId,
    required String groupId,
  }) async => calls.add('detach $groupId from $menuItemId');

  @override
  Future<void> reorderModifiers({
    required String groupId,
    required List<String> modifierIds,
  }) async => calls.add('reorder $groupId ${modifierIds.join(',')}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeMenuRepository> _open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = _FakeMenuRepository();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MenuManagementScreen(menuRepository: repository)),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Manage'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Modifiers and add-ons'));
  await tester.pumpAndSettle();

  return repository;
}

void main() {
  testWidgets('modifier rules, prices and sharing are spelled out', (
    tester,
  ) async {
    await _open(tester, const Size(1200, 1000));

    expect(find.text('Required · choose exactly 1'), findsOneWidget);
    expect(find.textContaining('Shared with 1 other product'), findsOneWidget);
    expect(find.text('Regular · Free'), findsOneWidget);
    expect(find.text('Large · +₱20.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('options can be reordered and groups reused or removed', (
    tester,
  ) async {
    final repository = await _open(tester, const Size(1200, 1000));

    await tester.tap(find.widgetWithText(TextButton, 'Move down').first);
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'reorder group-size large,regular');

    await tester.tap(find.text('Use existing group'));
    await tester.pumpAndSettle();
    expect(find.text('Bowl Add-ons'), findsOneWidget);
    expect(find.textContaining('Used by Chicken Bowl'), findsOneWidget);
    // The group this product already has is not offered again.
    expect(find.widgetWithText(OutlinedButton, 'Use'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'attach group-addons to item-iced');

    await tester.tap(find.text('Remove from Product'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('stay on the other products that use it'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'detach group-size from item-iced');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu table and modifiers dialog fit a phone', (
    tester,
  ) async {
    await _open(tester, const Size(360, 800));

    expect(find.text('Required · choose exactly 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
