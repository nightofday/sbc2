import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../models/catalog_management.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';
import '../../core/theme/app_radius.dart';

/// Lets management define the promotional discounts offered at the till.
class DiscountsScreen extends StatefulWidget {
  final CatalogRepository catalogRepository;

  /// Called after a change so the till reloads its discount list.
  final VoidCallback? onDataChanged;

  const DiscountsScreen({
    super.key,
    required this.catalogRepository,
    this.onDataChanged,
  });

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  late Future<List<DiscountDefinition>> _discountsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _discountsFuture = widget.catalogRepository.listDiscounts();
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _validity(DiscountDefinition discount) {
    final from = discount.validFrom;
    final until = discount.validUntil;

    if (from == null && until == null) return 'No end date';
    if (from != null && until != null) {
      return '${_formatDate(from)} to ${_formatDate(until)}';
    }
    if (from != null) return 'From ${_formatDate(from)}';
    return 'Until ${_formatDate(until!)}';
  }

  Future<void> _showEditor({DiscountDefinition? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final valueController = TextEditingController(
      text: _plain(existing?.value),
    );
    final maxController = TextEditingController(
      text: _plain(existing?.maxValue),
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var method = existing?.calculationMethod ?? 'PERCENTAGE';
    var allowCustom = existing?.allowCustomValue ?? false;
    var active = existing?.isActive ?? true;
    DateTime? validFrom = existing?.validFrom;
    DateTime? validUntil = existing?.validUntil;
    String? errorMessage;
    var saving = false;
    var saved = false;
    StateSetter? updateDialogState;

    Future<void> pickDate({required bool start}) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: (start ? validFrom : validUntil) ?? DateTime.now(),
        firstDate: DateTime(2024),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      updateDialogState?.call(() {
        if (start) {
          validFrom = picked;
        } else {
          validUntil = picked;
        }
      });
    }

    await showPrototypeDialog(
      context: context,
      title: existing == null ? 'Add Discount' : 'Edit Discount',
      width: 520,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;
          final percentage = method == 'PERCENTAGE';

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Discount Name *'),
              ),
              const SizedBox(height: 14),
              if (existing == null)
                DropdownButtonFormField<String>(
                  initialValue: method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: const [
                    DropdownMenuItem(
                      value: 'PERCENTAGE',
                      child: Text('Percentage off'),
                    ),
                    DropdownMenuItem(
                      value: 'FIXED_AMOUNT',
                      child: Text('Fixed amount off'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                )
              else
                Text(
                  'Type: ${percentage ? 'Percentage off' : 'Amount off'} '
                  '(cannot be changed once created)',
                  style: AppTextStyles.caption,
                ),
              const SizedBox(height: 14),
              TextField(
                controller: valueController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: percentage ? 'Percent Off *' : 'Amount Off (₱) *',
                  helperText: percentage
                      ? 'For example 10 for 10% off. 100 at most.'
                      : 'For example 20 for ₱20 off.',
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Value can be changed at the till'),
                subtitle: const Text(
                  'Off: the till always applies the value above.',
                ),
                value: allowCustom,
                onChanged: (value) => setDialogState(() => allowCustom = value),
              ),
              if (allowCustom) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: maxController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: percentage
                        ? 'Highest Percent Allowed'
                        : 'Highest Amount Allowed (₱)',
                    helperText: 'Leave blank for no limit.',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => pickDate(start: true),
                    child: Text(
                      validFrom == null
                          ? 'Starts: any time'
                          : 'Starts: ${_formatDate(validFrom!)}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => pickDate(start: false),
                    child: Text(
                      validUntil == null
                          ? 'Ends: no end date'
                          : 'Ends: ${_formatDate(validUntil!)}',
                    ),
                  ),
                  if (validFrom != null || validUntil != null)
                    TextButton(
                      onPressed: () => setDialogState(() {
                        validFrom = null;
                        validUntil = null;
                      }),
                      child: const Text('Clear Dates'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (existing != null) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Off: the discount is kept but not offered at the till.',
                  ),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
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

            void fail(String message) {
              updateDialogState?.call(() => errorMessage = message);
            }

            final name = nameController.text.trim();
            if (name.isEmpty) return fail('Discount name is required.');

            final valueText = valueController.text.trim();
            final value = double.tryParse(valueText);
            final needsValue = !(allowCustom && valueText.isEmpty);
            if (needsValue && (value == null || value <= 0)) {
              return fail('Enter a discount value greater than zero.');
            }
            if (method == 'PERCENTAGE' && value != null && value > 100) {
              return fail('A percentage discount cannot be more than 100.');
            }

            final maxText = maxController.text.trim();
            final maxValue = allowCustom && maxText.isNotEmpty
                ? double.tryParse(maxText)
                : null;
            if (allowCustom && maxText.isNotEmpty && maxValue == null) {
              return fail('The highest value allowed must be a number.');
            }

            if (validFrom != null &&
                validUntil != null &&
                validUntil!.isBefore(validFrom!)) {
              return fail('The end date cannot be before the start date.');
            }

            final discount = DiscountDefinition(
              id: existing?.id ?? '',
              name: name,
              calculationMethod: method,
              value: value,
              allowCustomValue: allowCustom,
              maxValue: maxValue,
              validFrom: validFrom,
              validUntil: validUntil,
              isActive: active,
              notes: notesController.text.trim(),
            );

            saving = true;
            try {
              if (existing == null) {
                await widget.catalogRepository.createDiscount(discount);
              } else {
                await widget.catalogRepository.updateDiscount(discount);
              }

              saved = true;
              if (!mounted) return;
              Navigator.pop(context);
            } on PostgrestException catch (error) {
              fail(error.message);
            } catch (error) {
              fail(errorText(error));
            } finally {
              saving = false;
            }
          },
          child: Text(existing == null ? 'Add Discount' : 'Save Changes'),
        ),
      ],
    );

    nameController.dispose();
    valueController.dispose();
    maxController.dispose();
    notesController.dispose();

    if (saved && mounted) {
      widget.onDataChanged?.call();
      _refresh();
    }
  }

  String _plain(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Discounts',
      subtitle:
          'Promotions offered at payment. Only staff allowed to apply '
          'discounts can use them.',
      action: ElevatedButton.icon(
        onPressed: _showEditor,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Discount'),
      ),
      child: FutureBuilder<List<DiscountDefinition>>(
        future: _discountsFuture,
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
                    'Unable to load discounts.\n'
                    '${errorText(error)}',
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

          final discounts = snapshot.data ?? const <DiscountDefinition>[];

          if (discounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No discounts yet.', style: AppTextStyles.h3),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showEditor,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add the First Discount'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: discounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _discountCard(discounts[index]),
          );
        },
      ),
    );
  }

  Widget _discountCard(DiscountDefinition discount) {
    final status = discount.isStatutory
        ? 'Not Available'
        : discount.isActive
        ? 'Active'
        : 'Inactive';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.all,
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(discount.name, style: AppTextStyles.bodyMedium),
              ),
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(status),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            discount.isStatutory
                ? 'Not offered at the till until the café\'s tax rules for '
                      'this discount are confirmed.'
                : '${discount.valueLabel} • ${_validity(discount)}',
            style: AppTextStyles.caption,
          ),
          if (!discount.isStatutory) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _showEditor(existing: discount),
              child: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }
}
