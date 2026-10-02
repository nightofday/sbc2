import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../models/catalog_management.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

/// Lets management maintain menu, inventory and expense categories.
class CategoriesScreen extends StatefulWidget {
  final CatalogRepository catalogRepository;

  /// Called after a change so screens that show categories reload.
  final VoidCallback? onDataChanged;

  const CategoriesScreen({
    super.key,
    required this.catalogRepository,
    this.onDataChanged,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoryDomain _domain = CategoryDomain.menu;
  late Future<List<CategoryRecord>> _categoriesFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _categoriesFuture = widget.catalogRepository.listCategories(_domain);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a change, then reloads this list and tells the other screens.
  Future<void> _run(Future<void> Function() change, String done) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await change();
      if (!mounted) return;
      widget.onDataChanged?.call();
      _showMessage(done);
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _reload();
        });
      }
    }
  }

  Future<void> _move(List<CategoryRecord> categories, int index, int step) {
    final ids = categories.map((category) => category.id).toList();
    final id = ids.removeAt(index);
    ids.insert(index + step, id);

    return _run(
      () => widget.catalogRepository.reorderCategories(_domain, ids),
      'Category order updated.',
    );
  }

  Future<void> _setActive(CategoryRecord category, bool active) {
    return _run(
      () => widget.catalogRepository.updateCategory(
        _domain,
        category.id,
        isActive: active,
      ),
      active
          ? '${category.name} is active again.'
          : '${category.name} archived.',
    );
  }

  Future<void> _confirmArchive(CategoryRecord category) async {
    final inUse = category.usageCount > 0
        ? 'It is used by ${category.usageCount} ${_domain.usageNoun}. They '
              'keep this category and stay as they are, but it will no '
              'longer be offered for new ones.'
        : 'Nothing uses it at the moment.';

    var confirmed = false;
    await showPrototypeDialog(
      context: context,
      title: 'Archive ${category.name}?',
      width: 480,
      content: Text(
        '$inUse You can reactivate it at any time.',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            confirmed = true;
            Navigator.pop(context);
          },
          child: const Text('Archive'),
        ),
      ],
    );

    if (confirmed && mounted) await _setActive(category, false);
  }

  Future<void> _showEditor({CategoryRecord? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    String? errorMessage;
    var saving = false;
    var saved = false;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: existing == null
          ? 'Add ${_domain.label} Category'
          : 'Edit Category',
      width: 480,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Category Name *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
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
            if (saving) return;

            final name = nameController.text.trim();
            if (name.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Category name is required.';
              });
              return;
            }

            saving = true;
            try {
              if (existing == null) {
                await widget.catalogRepository.createCategory(
                  _domain,
                  name: name,
                  description: descriptionController.text.trim(),
                );
              } else {
                await widget.catalogRepository.updateCategory(
                  _domain,
                  existing.id,
                  name: name,
                  description: descriptionController.text.trim(),
                );
              }

              saved = true;
              if (!mounted) return;
              Navigator.pop(context);
            } on PostgrestException catch (error) {
              updateDialogState?.call(() => errorMessage = error.message);
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.toString();
              });
            } finally {
              saving = false;
            }
          },
          child: Text(existing == null ? 'Add Category' : 'Save Changes'),
        ),
      ],
    );

    nameController.dispose();
    descriptionController.dispose();

    if (saved && mounted) {
      widget.onDataChanged?.call();
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Categories',
      subtitle:
          'Add, rename, reorder and archive the categories used across the '
          'system.',
      action: ElevatedButton.icon(
        onPressed: _showEditor,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Category'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final domain in CategoryDomain.values)
                ChoiceChip(
                  label: Text(domain.label),
                  selected: _domain == domain,
                  onSelected: (_) => setState(() {
                    _domain = domain;
                    _reload();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<CategoryRecord>>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to load categories.\n'
                          '${error is PostgrestException ? error.message : error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  );
                }

                final categories = snapshot.data ?? const <CategoryRecord>[];

                if (categories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No ${_domain.label.toLowerCase()} categories yet.',
                          style: AppTextStyles.h3,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _showEditor,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add the First Category'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _categoryCard(categories, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(List<CategoryRecord> categories, int index) {
    final category = categories[index];
    final usage = category.usageCount == 0
        ? 'Not in use'
        : 'Used by ${category.usageCount} ${_domain.usageNoun}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(category.name, style: AppTextStyles.bodyMedium),
              ),
              const SizedBox(width: 12),
              StatusBadge(category.isActive ? 'Active' : 'Archived'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            category.description.isEmpty
                ? usage
                : '${category.description} • $usage',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy || index == 0
                    ? null
                    : () => _move(categories, index, -1),
                child: const Text('Move Up'),
              ),
              OutlinedButton(
                onPressed: _busy || index == categories.length - 1
                    ? null
                    : () => _move(categories, index, 1),
                child: const Text('Move Down'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _showEditor(existing: category),
                child: const Text('Rename'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : category.isActive
                    ? () => _confirmArchive(category)
                    : () => _setActive(category, true),
                child: Text(category.isActive ? 'Archive' : 'Reactivate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
