import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/domain/repositories/supplier_repository.dart';
import 'package:sbc_management_system/models/supplier_record.dart';
import 'package:sbc_management_system/screens/suppliers/suppliers_screen.dart';

class _RecordingSupplierRepository implements SupplierRepository {
  SupplierRecord stored = const SupplierRecord(
    id: 'supplier-1',
    name: 'Davao Packaging',
    contact: 'Ana Cruz • 0917-000-1111 • ana@example.com',
    itemsSupplied: 'Paper Cups',
    status: 'Active',
    contactPerson: 'Ana Cruz',
    phone: '0917-000-1111',
    email: 'ana@example.com',
    address: '12 Bajada Road',
    paymentTermsDays: 15,
    notes: 'Delivers on Tuesdays',
  );
  SupplierRecord? lastUpdate;

  @override
  Future<List<SupplierRecord>> getSuppliers() async => [stored];

  @override
  Future<SupplierRecord?> getSupplierById(String id) async => stored;

  @override
  Future<void> createSupplier(SupplierRecord supplier) async {}

  @override
  Future<void> updateSupplier(SupplierRecord supplier) async {
    lastUpdate = supplier;
    stored = supplier;
  }
}

void main() {
  testWidgets('renaming a supplier sends back every other detail unchanged', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _RecordingSupplierRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SuppliersScreen(supplierRepository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Davao Packaging'));
    await tester.pumpAndSettle();

    expect(find.text('12 Bajada Road'), findsOneWidget);
    expect(find.text('15 days'), findsOneWidget);

    await tester.tap(find.text('Edit Supplier'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Supplier Name *'),
      'Davao Packaging Supply',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    final sent = repository.lastUpdate!;
    expect(sent.name, 'Davao Packaging Supply');
    expect(sent.contactPerson, 'Ana Cruz');
    expect(sent.phone, '0917-000-1111');
    expect(sent.email, 'ana@example.com');
    expect(sent.address, '12 Bajada Road');
    expect(sent.paymentTermsDays, 15);
    expect(sent.notes, 'Delivers on Tuesdays');
    expect(sent.status, 'Active');
  });
}
