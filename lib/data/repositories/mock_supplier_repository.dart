import '../../domain/repositories/supplier_repository.dart';
import '../../models/supplier_record.dart';
import '../mock_data.dart';

class MockSupplierRepository implements SupplierRepository {
  final List<SupplierRecord> _suppliers = List<SupplierRecord>.from(
    MockData.suppliers,
  );

  @override
  Future<List<SupplierRecord>> getSuppliers() async {
    return List<SupplierRecord>.unmodifiable(_suppliers);
  }

  @override
  Future<SupplierRecord?> getSupplierById(String id) async {
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  @override
  Future<void> createSupplier(SupplierRecord supplier) async {
    _suppliers.add(supplier);
  }

  @override
  Future<void> updateSupplier(SupplierRecord supplier) async {
    final index = _suppliers.indexWhere((entry) => entry.id == supplier.id);
    if (index == -1) return;
    _suppliers[index] = supplier;
  }

  @override
  Future<void> deleteSupplier(String id) async {
    _suppliers.removeWhere((supplier) => supplier.id == id);
  }
}
