import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../../models/supplier_record.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

class SuppliersScreen extends StatefulWidget {
  final SupplierRepository supplierRepository;
  final VoidCallback? onDataChanged;

  const SuppliersScreen({
    super.key,
    required this.supplierRepository,
    this.onDataChanged,
  });

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late Future<List<SupplierRecord>> _suppliersFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _suppliersFuture = widget.supplierRepository.getSuppliers();
  }

  void _refresh() {
    setState(_reload);
  }

  void _notifyDataChanged() {
    _refresh();
    widget.onDataChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Suppliers',
      action: ElevatedButton.icon(
        onPressed: _showAddSupplier,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Supplier'),
      ),
      child: Column(
        children: [
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search supplier...',
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<SupplierRecord>>(
              future: _suppliersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load suppliers.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final query = _search.trim().toLowerCase();
                final suppliers = (snapshot.data ?? const <SupplierRecord>[])
                    .where(
                      (supplier) =>
                          query.isEmpty ||
                          supplier.name.toLowerCase().contains(query) ||
                          supplier.contact.toLowerCase().contains(query),
                    )
                    .toList();

                if (suppliers.isEmpty) {
                  return const Center(child: Text('No suppliers found.'));
                }

                return SingleChildScrollView(
                  child: DataTableCard(
                    headers: const [
                      'Supplier',
                      'Contact',
                      'Items Supplied',
                      'Status',
                    ],
                    flexes: const [3, 3, 3, 2],
                    rows: suppliers
                        .map(
                          (supplier) => [
                            InkWell(
                              onTap: () => _showSupplierDetails(supplier),
                              child: Text(
                                supplier.name,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Text(supplier.contact, style: AppTextStyles.body),
                            Text(
                              supplier.itemsSupplied,
                              style: AppTextStyles.body,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(supplier.status),
                            ),
                          ],
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSupplierDetails(SupplierRecord supplier) async {
    final latest =
        await widget.supplierRepository.getSupplierById(supplier.id) ??
        supplier;

    if (!mounted) return;

    await showPrototypeDialog(
      context: context,
      title: latest.name,
      width: 560,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(latest.status),
          const SizedBox(height: 16),
          _row('Contact', latest.contact),
          _row('Items Supplied', latest.itemsSupplied),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _showEditSupplier(latest);
          },
          child: const Text('Edit Supplier'),
        ),
      ],
    );
  }

  Future<void> _showAddSupplier() async {
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Add Supplier',
      width: 520,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Supplier Name *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(labelText: 'Phone / Contact'),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
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
            if (nameController.text.trim().isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Supplier name is required.';
              });
              return;
            }

            try {
              await widget.supplierRepository.createSupplier(
                SupplierRecord(
                  name: nameController.text.trim(),
                  contact: contactController.text.trim(),
                  itemsSupplied: '',
                  status: 'Active',
                ),
              );

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();
            } on PostgrestException catch (error) {
              updateDialogState?.call(() => errorMessage = error.message);
            }
          },
          child: const Text('Save Supplier'),
        ),
      ],
    );

    nameController.dispose();
    contactController.dispose();
  }

  Future<void> _showEditSupplier(SupplierRecord supplier) async {
    final nameController = TextEditingController(text: supplier.name);
    final contactController = TextEditingController(text: supplier.contact);
    bool active = supplier.status.toLowerCase() == 'active';
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Edit Supplier',
      width: 520,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Supplier Name *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(labelText: 'Phone / Contact'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active Supplier'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
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
            try {
              await widget.supplierRepository.updateSupplier(
                supplier.copyWith(
                  name: nameController.text.trim(),
                  contact: contactController.text.trim(),
                  status: active ? 'Active' : 'Inactive',
                ),
              );

              if (!mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();
            } on PostgrestException catch (error) {
              updateDialogState?.call(() => errorMessage = error.message);
            }
          },
          child: const Text('Save Changes'),
        ),
      ],
    );

    nameController.dispose();
    contactController.dispose();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
