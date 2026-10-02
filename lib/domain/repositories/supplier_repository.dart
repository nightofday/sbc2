import '../../models/supplier_record.dart';

abstract class SupplierRepository {
  Future<List<SupplierRecord>> getSuppliers();

  Future<SupplierRecord?> getSupplierById(String id);

  Future<void> createSupplier(SupplierRecord supplier);

  Future<void> updateSupplier(SupplierRecord supplier);

  Future<void> deleteSupplier(String id);
}
