import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/menu_repository.dart';
import '../../models/menu_management.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

class MenuManagementScreen extends StatefulWidget {
  final MenuRepository menuRepository;
  final Listenable? refreshListenable;
  final VoidCallback? onDataChanged;

  const MenuManagementScreen({
    super.key,
    required this.menuRepository,
    this.refreshListenable,
    this.onDataChanged,
  });

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  late Future<List<MenuVariantRecord>> _variantsFuture;
  String _search = '';
  String _categoryFilter = 'All Categories';

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant MenuManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_refresh);
      widget.refreshListenable?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_refresh);
    super.dispose();
  }

  void _reload() {
    _variantsFuture = widget.menuRepository.getVariants();
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _notifyDataChanged() {
    final callback = widget.onDataChanged;
    if (callback == null) {
      _refresh();
    } else {
      callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Menu Management',
      action: ElevatedButton.icon(
        onPressed: _showCreateProduct,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Product'),
      ),
      child: FutureBuilder<List<MenuVariantRecord>>(
        future: _variantsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load menu.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final all = snapshot.data ?? const <MenuVariantRecord>[];
          final categories =
              all.map((variant) => variant.categoryName).toSet().toList()
                ..sort();

          if (_categoryFilter != 'All Categories' &&
              !categories.contains(_categoryFilter)) {
            _categoryFilter = 'All Categories';
          }

          final query = _search.trim().toLowerCase();
          final variants = all.where((variant) {
            final matchesSearch =
                query.isEmpty ||
                variant.itemName.toLowerCase().contains(query) ||
                variant.variantName.toLowerCase().contains(query) ||
                variant.sku.toLowerCase().contains(query);
            final matchesCategory =
                _categoryFilter == 'All Categories' ||
                variant.categoryName == _categoryFilter;
            return matchesSearch && matchesCategory;
          }).toList();

          return Column(
            children: [
              Builder(
                builder: (context) {
                  final search = TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search product, variant, or SKU...',
                    ),
                  );
                  final category = DropdownButtonFormField<String>(
                    initialValue: _categoryFilter,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'All Categories',
                        child: Text('All Categories'),
                      ),
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _categoryFilter = value);
                    },
                  );

                  return ResponsiveFilterBar(
                    primary: search,
                    filters: [category],
                    filterWidths: const [220],
                    breakpoint: 620,
                  );
                },
              ),
              const SizedBox(height: 18),
              Expanded(
                child: variants.isEmpty
                    ? const Center(child: Text('No menu variants found.'))
                    : SingleChildScrollView(
                        child: DataTableCard(
                          headers: const [
                            'Product',
                            'Variant',
                            'SKU',
                            'Price',
                            'Inventory',
                            'Status',
                            'Actions',
                          ],
                          flexes: const [3, 2, 2, 2, 3, 2, 2],
                          rows: variants
                              .map(
                                (variant) => [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        variant.itemName,
                                        style: AppTextStyles.bodyMedium,
                                      ),
                                      Text(
                                        variant.categoryName,
                                        style: AppTextStyles.caption,
                                      ),
                                    ],
                                  ),
                                  Text(
                                    variant.variantName,
                                    style: AppTextStyles.body,
                                  ),
                                  Text(
                                    variant.sku.isEmpty ? '—' : variant.sku,
                                    style: AppTextStyles.body,
                                  ),
                                  Text(
                                    _money(variant.price),
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                  Text(
                                    _inventorySummary(variant),
                                    style: AppTextStyles.body,
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: StatusBadge(
                                      variant.isActive ? 'Active' : 'Inactive',
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit Variant',
                                        onPressed: () =>
                                            _showEditVariant(variant),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 19,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Add Variant',
                                        onPressed: () =>
                                            _showAddVariant(variant),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 19,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Modifiers',
                                        onPressed: () =>
                                            _showModifiers(variant),
                                        icon: const Icon(
                                          Icons.tune_outlined,
                                          size: 19,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                              .toList(),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateProduct() async {
    final categories = await widget.menuRepository.getCategories();
    final inventory = await widget.menuRepository.getInventoryOptions();

    if (!mounted || categories.isEmpty) return;

    await _showVariantEditor(
      title: 'Add Product',
      categories: categories,
      inventory: inventory,
      existing: null,
      addVariantTo: null,
    );
  }

  Future<void> _showAddVariant(MenuVariantRecord parent) async {
    final categories = await widget.menuRepository.getCategories();
    final inventory = await widget.menuRepository.getInventoryOptions();

    if (!mounted) return;

    await _showVariantEditor(
      title: 'Add Variant to ${parent.itemName}',
      categories: categories,
      inventory: inventory,
      existing: null,
      addVariantTo: parent,
    );
  }

  Future<void> _showEditVariant(MenuVariantRecord variant) async {
    final results = await Future.wait([
      widget.menuRepository.getCategories(),
      widget.menuRepository.getInventoryOptions(),
    ]);

    if (!mounted) return;

    await _showVariantEditor(
      title: 'Edit ${variant.itemName} — ${variant.variantName}',
      categories: results[0] as List<MenuCategoryOption>,
      inventory: results[1] as List<MenuInventoryOption>,
      existing: variant,
      addVariantTo: null,
    );
  }

  Future<void> _showVariantEditor({
    required String title,
    required List<MenuCategoryOption> categories,
    required List<MenuInventoryOption> inventory,
    required MenuVariantRecord? existing,
    required MenuVariantRecord? addVariantTo,
  }) async {
    final isEditing = existing != null;
    final isAddingVariant = addVariantTo != null;

    final itemNameController = TextEditingController(
      text: existing?.itemName ?? addVariantTo?.itemName ?? '',
    );
    final variantNameController = TextEditingController(
      text: existing?.variantName ?? '',
    );
    final skuController = TextEditingController(text: existing?.sku ?? '');
    final priceController = TextEditingController(
      text: existing == null ? '' : existing.price.toStringAsFixed(2),
    );

    String categoryId =
        existing?.categoryId ?? addVariantTo?.categoryId ?? categories.first.id;
    String inventoryMode = existing?.inventoryTrackingMode == 'FINISHED_GOOD'
        ? 'FINISHED_GOOD'
        : 'UNTRACKED';
    String finishedInventoryId = existing?.finishedInventoryItemId ?? '';
    bool isActive = existing?.isActive ?? true;

    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: title,
      width: 720,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: itemNameController,
                  enabled: !isAddingVariant,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category *'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: isAddingVariant
                      ? null
                      : (value) {
                          if (value == null) return;
                          setDialogState(() => categoryId = value);
                        },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: variantNameController,
                        decoration: const InputDecoration(
                          labelText: 'Variant Name *',
                          hintText: 'Regular, Small, Large, 330 ml Can...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: skuController,
                        decoration: const InputDecoration(labelText: 'SKU'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling Price *',
                    prefixText: '₱',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: inventoryMode,
                  decoration: const InputDecoration(
                    labelText: 'Inventory Tracking',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'UNTRACKED',
                      child: Text('Prepared to Order'),
                    ),
                    DropdownMenuItem(
                      value: 'FINISHED_GOOD',
                      child: Text('Countable Finished Product'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      inventoryMode = value;
                      errorMessage = null;
                    });
                  },
                ),
                if (inventoryMode == 'FINISHED_GOOD') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: finishedInventoryId.isEmpty
                        ? null
                        : finishedInventoryId,
                    decoration: const InputDecoration(
                      labelText: 'Linked Inventory Item *',
                    ),
                    items: inventory
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              '${item.name} — ${_qty(item.usableQuantity)} ${item.unitCode} usable',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => finishedInventoryId = value);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inventoryMode == 'FINISHED_GOOD'
                        ? 'Each sale deducts one unit from the linked countable product.'
                        : 'Prepared items remain sellable without tracking recipe ingredients.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
                if (isEditing) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Variant Active'),
                    subtitle: const Text(
                      'Inactive variants are hidden from the POS.',
                    ),
                    value: isActive,
                    onChanged: (value) =>
                        setDialogState(() => isActive = value),
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final price = double.tryParse(priceController.text.trim());

            if (itemNameController.text.trim().isEmpty ||
                variantNameController.text.trim().isEmpty ||
                price == null ||
                price < 0) {
              updateDialogState?.call(() {
                errorMessage = 'Product name, variant name, and a valid price are required.';
              });
              return;
            }

            if (inventoryMode == 'FINISHED_GOOD' &&
                finishedInventoryId.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Select the linked inventory item.';
              });
              return;
            }

            try {
              if (existing != null) {
                await widget.menuRepository.updateVariant(
                  variant: existing,
                  itemName: itemNameController.text.trim(),
                  categoryId: categoryId,
                  variantName: variantNameController.text.trim(),
                  sku: skuController.text.trim(),
                  price: price,
                  isActive: isActive,
                  inventoryMode: inventoryMode,
                  finishedInventoryItemId: finishedInventoryId,
                );
              } else if (addVariantTo != null) {
                await widget.menuRepository.addVariant(
                  menuItemId: addVariantTo.menuItemId,
                  variantName: variantNameController.text.trim(),
                  sku: skuController.text.trim(),
                  price: price,
                  inventoryMode: inventoryMode,
                  finishedInventoryItemId: finishedInventoryId,
                );
              } else {
                await widget.menuRepository.createMenuItemWithVariant(
                  itemName: itemNameController.text.trim(),
                  categoryId: categoryId,
                  variantName: variantNameController.text.trim(),
                  sku: skuController.text.trim(),
                  price: price,
                  inventoryMode: inventoryMode,
                  finishedInventoryItemId: finishedInventoryId,
                );
              }

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menu configuration saved.')),
              );
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.toString();
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    itemNameController.dispose();
    variantNameController.dispose();
    skuController.dispose();
    priceController.dispose();
  }

  Future<void> _showModifiers(MenuVariantRecord variant) async {
    final groups = await widget.menuRepository.getModifierGroupsForMenuItem(
      variant.menuItemId,
    );

    if (!mounted) return;

    await showPrototypeDialog(
      context: context,
      title: 'Modifiers — ${variant.itemName}',
      width: 720,
      content: SizedBox(
        height: 430,
        child: groups.isEmpty
            ? Center(
                child: Text(
                  'No modifier groups configured yet.',
                  style: AppTextStyles.body.copyWith(color: AppColors.gray500),
                ),
              )
            : ListView.separated(
                itemCount: groups.length,
                separatorBuilder: (_, _) => const Divider(height: 24),
                itemBuilder: (_, index) {
                  final group = groups[index];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(group.groupName, style: AppTextStyles.h3),
                                Text(
                                  _modifierGroupRule(group),
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(group.isActive ? 'Active' : 'Inactive'),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Edit Group',
                            onPressed: () {
                              Navigator.pop(context);
                              _showModifierGroupEditor(
                                variant,
                                existing: group,
                              );
                            },
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                          IconButton(
                            tooltip: 'Add Modifier',
                            onPressed: () {
                              Navigator.pop(context);
                              _showModifierEditor(variant, group);
                            },
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 19,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (group.modifiers.isEmpty)
                        Text(
                          'No options in this group.',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.gray500,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: group.modifiers
                              .map(
                                (modifier) => ActionChip(
                                  avatar: Icon(
                                    modifier.isActive
                                        ? Icons.check_circle_outline
                                        : Icons.hide_source_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    modifier.priceDelta == 0
                                        ? modifier.name
                                        : '${modifier.name} (+${_money(modifier.priceDelta)})',
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showModifierEditor(
                                      variant,
                                      group,
                                      existing: modifier,
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _showModifierGroupEditor(variant);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Modifier Group'),
        ),
      ],
    );
  }

  Future<void> _showModifierGroupEditor(
    MenuVariantRecord variant, {
    MenuModifierGroupRecord? existing,
  }) async {
    final nameController = TextEditingController(
      text: existing?.groupName ?? '',
    );
    final minController = TextEditingController(
      text: '${existing?.minSelections ?? 0}',
    );
    final maxController = TextEditingController(
      text: existing?.maxSelections?.toString() ?? '',
    );
    var required = existing?.isRequired ?? false;
    var active = existing?.isActive ?? true;
    String? errorMessage;
    StateSetter? dialogSetState;

    await showPrototypeDialog(
      context: context,
      title: existing == null ? 'Add Modifier Group' : 'Edit Modifier Group',
      width: 540,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          dialogSetState = setDialogState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name *',
                  hintText: 'e.g. Milk Choice, Add-ons',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimum Selections',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maximum',
                        hintText: 'Blank = no limit',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required'),
                value: required,
                onChanged: (value) {
                  setDialogState(() {
                    required = value;
                    if (required &&
                        (int.tryParse(minController.text) ?? 0) < 1) {
                      minController.text = '1';
                    }
                  });
                },
              ),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final min = int.tryParse(minController.text.trim());
            final maxText = maxController.text.trim();
            final max = maxText.isEmpty ? null : int.tryParse(maxText);

            if (name.isEmpty ||
                min == null ||
                min < 0 ||
                (maxText.isNotEmpty && max == null) ||
                (max != null && (max < 1 || max < min)) ||
                (required && min < 1)) {
              dialogSetState?.call(() {
                errorMessage =
                    'Check the name and minimum/maximum selection rules.';
              });
              return;
            }

            try {
              if (existing == null) {
                await widget.menuRepository.createModifierGroup(
                  menuItemId: variant.menuItemId,
                  groupName: name,
                  minSelections: min,
                  maxSelections: max,
                  isRequired: required,
                );
              } else {
                await widget.menuRepository.updateModifierGroup(
                  groupId: existing.groupId,
                  groupName: name,
                  minSelections: min,
                  maxSelections: max,
                  isRequired: required,
                  isActive: active,
                );
              }

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();
              _showModifiers(variant);
            } on PostgrestException catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.toString();
              });
            }
          },
          child: Text(existing == null ? 'Create Group' : 'Save Changes'),
        ),
      ],
    );

    nameController.dispose();
    minController.dispose();
    maxController.dispose();
  }

  Future<void> _showModifierEditor(
    MenuVariantRecord variant,
    MenuModifierGroupRecord group, {
    MenuModifierRecord? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(
      text: existing == null ? '0' : existing.priceDelta.toStringAsFixed(2),
    );

    var active = existing?.isActive ?? true;
    if (!mounted) return;

    String? errorMessage;
    StateSetter? dialogSetState;

    await showPrototypeDialog(
      context: context,
      title: existing == null
          ? 'Add Modifier — ${group.groupName}'
          : 'Edit ${existing.name}',
      width: 650,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          dialogSetState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Modifier Name *',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Additional Price',
                    prefixText: '₱',
                  ),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Modifiers may change the selling price. They do not '
                    'deduct ingredients from inventory.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final price = double.tryParse(priceController.text.trim());

            if (name.isEmpty || price == null) {
              dialogSetState?.call(() {
                errorMessage = 'Enter a modifier name and a valid price.';
              });
              return;
            }

            try {
              if (existing == null) {
                await widget.menuRepository.createModifier(
                  groupId: group.groupId,
                  name: name,
                  priceDelta: price,
                );
              } else {
                await widget.menuRepository.updateModifier(
                  modifierId: existing.id,
                  name: name,
                  priceDelta: price,
                  isActive: active,
                );
              }

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();
              _showModifiers(variant);
            } on PostgrestException catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.toString();
              });
            }
          },
          child: Text(existing == null ? 'Add Modifier' : 'Save Changes'),
        ),
      ],
    );

    nameController.dispose();
    priceController.dispose();
  }

  String _modifierGroupRule(MenuModifierGroupRecord group) {
    final max = group.maxSelections;
    if (max == null) {
      return 'Minimum ${group.minSelections}'
          '${group.isRequired ? ' • Required' : ''}';
    }
    if (group.minSelections == max) {
      return 'Select exactly $max'
          '${group.isRequired ? ' • Required' : ''}';
    }
    return 'Select ${group.minSelections}–$max'
        '${group.isRequired ? ' • Required' : ''}';
  }

  String _inventorySummary(MenuVariantRecord variant) {
    switch (variant.inventoryTrackingMode) {
      case 'FINISHED_GOOD':
        return variant.finishedInventoryName.isEmpty
            ? 'Countable product'
            : 'Countable: ${variant.finishedInventoryName}';
      default:
        return 'Prepared to order';
    }
  }

  static String _money(double value) {
    return '₱${value.toStringAsFixed(2)}';
  }

  static String _qty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}
