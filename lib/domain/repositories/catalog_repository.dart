import '../../models/catalog_management.dart';

/// Maintenance of the reference lists management owns: categories and
/// promotional discounts.
abstract class CatalogRepository {
  /// Every category of [domain], archived ones included, in display order.
  Future<List<CategoryRecord>> listCategories(CategoryDomain domain);

  Future<void> createCategory(
    CategoryDomain domain, {
    required String name,
    String description = '',
  });

  /// Changes only the fields given.
  Future<void> updateCategory(
    CategoryDomain domain,
    String categoryId, {
    String? name,
    String? description,
    bool? isActive,
  });

  /// Sets the display order to the order of [categoryIds].
  Future<void> reorderCategories(
    CategoryDomain domain,
    List<String> categoryIds,
  );

  Future<List<DiscountDefinition>> listDiscounts();

  Future<void> createDiscount(DiscountDefinition discount);

  Future<void> updateDiscount(DiscountDefinition discount);
}
