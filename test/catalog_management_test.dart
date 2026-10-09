import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/catalog_repository.dart';
import 'package:sbc_management_system/models/catalog_management.dart';
import 'package:sbc_management_system/models/pos_discount.dart';
import 'package:sbc_management_system/screens/menu/categories_screen.dart';
import 'package:sbc_management_system/screens/menu/discounts_screen.dart';

class _FakeCatalogRepository implements CatalogRepository {
  final List<CategoryRecord> categories = [
    const CategoryRecord(id: 'coffee', name: 'Coffee', usageCount: 3),
    const CategoryRecord(id: 'snacks', name: 'Snacks'),
  ];
  final List<String> calls = [];
  DiscountDefinition? createdDiscount;

  @override
  Future<List<CategoryRecord>> listCategories(CategoryDomain domain) async {
    return List.of(categories);
  }

  @override
  Future<void> createCategory(
    CategoryDomain domain, {
    required String name,
    String description = '',
  }) async {
    calls.add('create ${domain.code} $name');
    categories.add(CategoryRecord(id: name, name: name));
  }

  @override
  Future<void> updateCategory(
    CategoryDomain domain,
    String categoryId, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    calls.add('update $categoryId name=$name active=$isActive');
  }

  @override
  Future<void> reorderCategories(
    CategoryDomain domain,
    List<String> categoryIds,
  ) async {
    calls.add('reorder ${categoryIds.join(',')}');
  }

  @override
  Future<List<DiscountDefinition>> listDiscounts() async => const [
    DiscountDefinition(
      id: 'promo',
      name: 'Opening Week',
      calculationMethod: 'PERCENTAGE',
      value: 10,
    ),
    DiscountDefinition(
      id: 'senior',
      name: 'Senior Citizen',
      calculationMethod: 'PERCENTAGE',
      value: 20,
      isPosEnabled: false,
      isStatutory: true,
    ),
  ];

  @override
  Future<void> createDiscount(DiscountDefinition discount) async {
    createdDiscount = discount;
  }

  @override
  Future<void> updateDiscount(DiscountDefinition discount) async {}
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

void main() {
  test('a promotion with a fixed value ignores a value typed at the till', () {
    const fixed = PosDiscountType(
      id: 'promo',
      code: 'PROMO_A',
      name: 'Opening Week',
      calculationMethod: 'PERCENTAGE',
      defaultValue: 10,
      requiresAuthorization: true,
      allowCustomValue: false,
    );
    const adjustable = PosDiscountType(
      id: 'manual',
      code: 'PROMO_PERCENT',
      name: 'Promotional Percentage',
      calculationMethod: 'PERCENTAGE',
      defaultValue: null,
      requiresAuthorization: true,
    );

    expect(fixed.calculateDiscount(200, 90), 20);
    expect(adjustable.calculateDiscount(200, 25), 50);
  });

  test('a discount describes its value in plain words', () {
    const percent = DiscountDefinition(
      name: 'A',
      calculationMethod: 'PERCENTAGE',
      value: 10,
    );
    const amount = DiscountDefinition(
      name: 'B',
      calculationMethod: 'FIXED_AMOUNT',
      value: 20,
      allowCustomValue: true,
      maxValue: 50,
    );
    const open = DiscountDefinition(
      name: 'C',
      calculationMethod: 'MANUAL_AMOUNT',
      allowCustomValue: true,
    );

    expect(percent.valueLabel, '10% off');
    expect(amount.valueLabel, '₱20 off, changeable at the till, up to ₱50');
    expect(open.valueLabel, 'Entered at the till');
  });

  testWidgets('categories can be added, reordered and archived', (
    tester,
  ) async {
    final repository = _FakeCatalogRepository();
    var notified = 0;

    await _pump(
      tester,
      CategoriesScreen(
        catalogRepository: repository,
        onDataChanged: () => notified++,
      ),
    );

    expect(find.text('Used by 3 products'), findsOneWidget);
    expect(find.text('Not in use'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Move down').first);
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'reorder snacks,coffee');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Archive').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('used by 3 products'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'update coffee name=null active=false');

    await tester.tap(find.text('Add category').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add category').last);
    await tester.pumpAndSettle();
    expect(find.text('Category name is required.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Category name *'),
      '  Seasonal Drinks ',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add category').last);
    await tester.pumpAndSettle();

    expect(repository.calls.last, 'create MENU Seasonal Drinks');
    expect(find.text('Seasonal Drinks'), findsOneWidget);
    expect(notified, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discounts validate their value and hide statutory editing', (
    tester,
  ) async {
    final repository = _FakeCatalogRepository();

    await _pump(tester, DiscountsScreen(catalogRepository: repository));

    expect(find.text('10% off • No end date'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);

    await tester.tap(find.text('Add discount').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Discount name *'),
      'Payday Promo',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Percent off *'),
      '120',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add discount').last);
    await tester.pumpAndSettle();
    expect(
      find.text('A percentage discount cannot be more than 100.'),
      findsOneWidget,
    );
    expect(repository.createdDiscount, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Percent off *'),
      '15',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add discount').last);
    await tester.pumpAndSettle();

    final created = repository.createdDiscount!;
    expect(created.name, 'Payday Promo');
    expect(created.calculationMethod, 'PERCENTAGE');
    expect(created.value, 15);
    expect(created.allowCustomValue, isFalse);
    expect(tester.takeException(), isNull);
  });
}
