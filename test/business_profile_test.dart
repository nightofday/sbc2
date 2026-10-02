import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/business_repository.dart';
import 'package:sbc_management_system/models/business_profile.dart';
import 'package:sbc_management_system/screens/orders/new_order_screen.dart';
import 'package:sbc_management_system/screens/users/business_details_screen.dart';
import 'package:sbc_management_system/widgets/common/business_profile_scope.dart';

import 'support/fake_order_repository.dart';

class _BusinessRepository implements BusinessRepository {
  BusinessProfile stored = const BusinessProfile(
    tradeName: 'Street Bowl Café',
    city: 'Davao City',
  );
  int saves = 0;

  @override
  Future<BusinessProfile> getBusinessProfile() async => stored;

  @override
  Future<void> saveBusinessProfile(BusinessProfile profile) async {
    saves++;
    stored = profile;
  }
}

class _ShiftRepository extends FakeOrderRepository {
  final List<double?> openingCash = [];
  bool shiftOpen = false;

  @override
  Future<String?> getOpenShiftId() async => shiftOpen ? 'shift-1' : null;

  @override
  Future<String> startShift({
    double? openingCash,
    String? clientRequestId,
  }) async {
    this.openingCash.add(openingCash);
    shiftOpen = true;
    return 'shift-1';
  }
}

void main() {
  test('receipt lines leave out what is not filled in', () {
    expect(BusinessProfile.fallback.receiptLines, isEmpty);

    const full = BusinessProfile(
      tradeName: 'Street Bowl Café',
      registeredName: 'Street Bowl Foods Inc.',
      tin: '123-456-789-000',
      addressLine: '12 Test Street',
      city: 'Davao City',
      province: 'Davao del Sur',
      postalCode: '8000',
      phone: '0917 000 0000',
    );

    expect(full.receiptLines, [
      'Street Bowl Foods Inc.',
      '12 Test Street, Davao City, Davao del Sur 8000',
      '0917 000 0000',
      'TIN 123-456-789-000',
    ]);
  });

  test('the details survive the device cache', () {
    const profile = BusinessProfile(
      tradeName: 'Test Café',
      tin: '1',
      requireOpeningCash: true,
    );
    final restored = BusinessProfile.fromMap(profile.toMap());

    expect(restored.tradeName, 'Test Café');
    expect(restored.tin, '1');
    expect(restored.requireOpeningCash, isTrue);
    expect(restored.requireClosingCash, isFalse);
  });

  for (final width in [1300.0, 360.0]) {
    testWidgets('business details can be edited at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _BusinessRepository();
      BusinessProfile? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusinessDetailsScreen(
              businessRepository: repository,
              onSaved: (profile) => saved = profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Business Name *'),
        '',
      );
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('The business name is required.'), findsOneWidget);
      expect(repository.saves, 0);

      await tester.enterText(
        find.widgetWithText(TextField, 'Business Name *'),
        'Street Bowl Café Matina',
      );
      await tester.enterText(find.widgetWithText(TextField, 'TIN'), '123-456');
      await tester.ensureVisible(find.text('Count the drawer to open'));
      await tester.tap(find.text('Count the drawer to open'));
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.saves, 1);
      expect(saved?.tradeName, 'Street Bowl Café Matina');
      expect(saved?.tin, '123-456');
      expect(saved?.requireOpeningCash, isTrue);
      // What was not touched is kept.
      expect(saved?.city, 'Davao City');
    });
  }

  testWidgets('a shift asks for its opening cash when that is the rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _ShiftRepository();
    final profile = ValueNotifier(
      const BusinessProfile(tradeName: 'Test Café', requireOpeningCash: true),
    );
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            BusinessProfileScope(notifier: profile, child: child!),
        home: NewOrderScreen(orderRepository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Shift').first);
    await tester.pumpAndSettle();
    expect(find.text('Opening Cash *'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Start Shift').last);
    await tester.pumpAndSettle();

    expect(find.text('Enter the cash in the drawer.'), findsOneWidget);
    expect(repository.openingCash, isEmpty);

    await tester.enterText(find.byType(TextField).last, '500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start Shift').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.openingCash, [500.0]);
  });
}
