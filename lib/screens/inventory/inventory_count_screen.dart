import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/state/inventory_refresh_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_reference.dart';
import '../../models/request_id.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

class InventoryCountScreen extends StatefulWidget {
  final InventoryRepository inventoryRepository;
  final InventoryRefreshController? refreshController;

  const InventoryCountScreen({
    super.key,
    required this.inventoryRepository,
    this.refreshController,
  });

  @override
  State<InventoryCountScreen> createState() => _InventoryCountScreenState();
}

class _InventoryCountScreenState extends State<InventoryCountScreen> {
  late Future<List<StockCountSummary>> _countsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshController?.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(covariant InventoryCountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshController == widget.refreshController) return;
    oldWidget.refreshController?.removeListener(_handleExternalRefresh);
    widget.refreshController?.addListener(_handleExternalRefresh);
  }

  @override
  void dispose() {
    widget.refreshController?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _reload() {
    _countsFuture = widget.inventoryRepository.getStockCounts(limit: 100);
  }

  void _refresh() {
    final controller = widget.refreshController;
    if (controller == null) {
      _handleExternalRefresh();
      return;
    }
    controller.refresh();
  }

  void _handleExternalRefresh() {
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Inventory Count',
      subtitle:
          'Compare physical quantities with system stock and post variances.',
      action: ElevatedButton.icon(
        onPressed: _showCountDialog,
        icon: const Icon(Icons.playlist_add_check, size: 18),
        label: const Text('New Count'),
      ),
      child: FutureBuilder<List<StockCountSummary>>(
        future: _countsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildError(snapshot.error);

          final counts = snapshot.data ?? const <StockCountSummary>[];
          if (counts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 42,
                    color: AppColors.gray500,
                  ),
                  const SizedBox(height: 12),
                  const Text('No physical counts yet', style: AppTextStyles.h3),
                  const SizedBox(height: 6),
                  Text(
                    'Start a count when management verifies actual stock.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            child: DataTableCard(
              headers: const [
                'Count',
                'Counted At',
                'Items',
                'With Variance',
                'Counted By',
                'Status',
                'Action',
              ],
              flexes: const [2, 2, 1, 2, 2, 2, 2],
              rows: counts
                  .map(
                    (count) => [
                      Text(
                        'IC-${count.number}',
                        style: AppTextStyles.bodyMedium,
                      ),
                      Text(
                        _formatDateTime(count.countedAt),
                        style: AppTextStyles.body,
                      ),
                      Text('${count.itemCount}', style: AppTextStyles.body),
                      Text(
                        '${count.varianceItemCount}',
                        style: AppTextStyles.body,
                      ),
                      Text(
                        count.countedByName.isEmpty ? '—' : count.countedByName,
                        style: AppTextStyles.body,
                      ),
                      StatusBadge(count.status),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: count.status == 'POSTED'
                            ? OutlinedButton(
                                onPressed: () => _voidCount(count),
                                child: const Text('Void'),
                              )
                            : const Text('—', style: AppTextStyles.body),
                      ),
                    ],
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }

  Future<void> _voidCount(StockCountSummary count) async {
    final requestId = newRequestId();

    final voided = await showReasonDialog(
      context: context,
      title: 'Void Count IC-${count.number}',
      message:
          'This reverses the stock differences this count posted. The count '
          'stays on record as cancelled. It is only possible while any stock '
          'the count added has not been used.',
      confirmLabel: 'Void Count',
      onConfirm: (reason) async {
        try {
          await widget.inventoryRepository.voidStockCount(
            stockCountId: count.id,
            reason: reason,
            clientRequestId: requestId,
          );
          return null;
        } on PostgrestException catch (error) {
          return error.message;
        } catch (error) {
          return errorText(error);
        }
      },
    );

    if (!voided || !mounted) return;
    _refresh();
    _showMessage('Inventory count IC-${count.number} voided.');
  }

  Future<void> _showCountDialog() async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    List<InventoryItem> items;
    try {
      items = await widget.inventoryRepository.getInventoryItems();
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
      return;
    } catch (error) {
      if (mounted) _showMessage(errorText(error));
      return;
    }

    if (!mounted) return;
    if (items.isEmpty) {
      _showMessage('No active inventory items are available to count.');
      return;
    }

    final notesController = TextEditingController();
    final lines = <_CountDraftLine>[_CountDraftLine.fromItem(items.first)];
    String? errorMessage;
    bool isSaving = false;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'New Physical Inventory Count',
      width: 900,
      barrierDismissible: false,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;
          return SizedBox(
            height: 570,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the actual quantity physically counted. The system '
                    'calculates each variance before posting the whole count.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Count Notes',
                      hintText: 'Example: End-of-month physical count',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Items counted', style: AppTextStyles.h3),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final usedIds = lines
                              .map((line) => line.itemId)
                              .toSet();
                          final available = items.where(
                            (item) => !usedIds.contains(item.id),
                          );
                          if (available.isEmpty) {
                            setDialogState(() {
                              errorMessage = 'Every available inventory item is already included.';
                            });
                            return;
                          }
                          setDialogState(() {
                            lines.add(
                              _CountDraftLine.fromItem(available.first),
                            );
                            errorMessage = null;
                          });
                        },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (int index = 0; index < lines.length; index++) ...[
                    _buildCountLine(
                      line: lines[index],
                      index: index,
                      items: items,
                      onChanged: () => setDialogState(() {
                        errorMessage = null;
                      }),
                      onRemove: lines.length == 1
                          ? null
                          : () {
                              setDialogState(() {
                                lines.removeAt(index).dispose();
                                errorMessage = null;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      errorMessage!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  if (isSaving) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (isSaving) return;
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            if (isSaving) return;
            final selectedIds = lines.map((line) => line.itemId).toList();
            if (selectedIds.toSet().length != selectedIds.length) {
              updateDialogState?.call(() {
                errorMessage = 'Each item can appear only once in a count.';
              });
              return;
            }

            final inputs = <StockCountLineInput>[];
            for (final line in lines) {
              final item = items.firstWhere((item) => item.id == line.itemId);
              final counted = double.tryParse(
                line.countedController.text.trim(),
              );
              final unitCost =
                  double.tryParse(line.unitCostController.text.trim()) ?? -1;
              if (counted == null || counted < 0 || unitCost < 0) {
                updateDialogState?.call(() {
                  errorMessage = 'Every counted quantity and unit cost must be zero or greater.';
                });
                return;
              }
              final variance = counted - item.currentQuantity;
              if (variance > 0 &&
                  item.trackExpiry &&
                  line.expirationDate == null) {
                updateDialogState?.call(() {
                  errorMessage =
                      '${item.name} needs an expiration date for its positive variance.';
                });
                return;
              }
              inputs.add(
                StockCountLineInput(
                  inventoryItemId: item.id,
                  countedQuantity: counted,
                  notes: line.notesController.text,
                  adjustmentExpirationDate: line.expirationDate,
                  unitCostBase: variance > 0 ? unitCost : 0,
                ),
              );
            }

            updateDialogState?.call(() => isSaving = true);
            try {
              await widget.inventoryRepository.createAndPostStockCount(
                clientRequestId: requestId,
                items: inputs,
                notes: notesController.text,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Physical inventory count posted successfully.');
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = errorText(error);
              });
            }
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Post Count'),
        ),
      ],
    );

    notesController.dispose();
    for (final line in lines) {
      line.dispose();
    }
  }

  Widget _buildCountLine({
    required _CountDraftLine line,
    required int index,
    required List<InventoryItem> items,
    required VoidCallback onChanged,
    required VoidCallback? onRemove,
  }) {
    final item = items.firstWhere((item) => item.id == line.itemId);
    final counted = double.tryParse(line.countedController.text.trim()) ?? 0;
    final variance = counted - item.currentQuantity;
    final itemField = DropdownButtonFormField<String>(
      initialValue: line.itemId,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Item ${index + 1} *'),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        final selected = items.firstWhere((item) => item.id == value);
        line.itemId = value;
        line.countedController.text = _plainNumber(selected.currentQuantity);
        line.expirationDate = null;
        line.unitCostController.text = '0';
        onChanged();
      },
    );
    final countField = TextField(
      controller: line.countedController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Physical Count (${item.baseUomCode}) *',
      ),
      onChanged: (_) => onChanged(),
    );
    final removeButton = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Remove item',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 580) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: itemField),
                        ?removeButton,
                      ],
                    ),
                    const SizedBox(height: 10),
                    countField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: itemField),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: countField),
                  if (removeButton != null) ...[
                    const SizedBox(width: 6),
                    removeButton,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final systemText = Text(
                'System: ${_quantityWithUnit(item.currentQuantity, item.baseUomCode)}',
                style: AppTextStyles.caption,
              );
              final varianceText = Text(
                'Variance: ${_signedQuantity(variance, item.baseUomCode)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: variance == 0
                      ? AppColors.gray700
                      : variance > 0
                      ? AppColors.success
                      : AppColors.primary,
                ),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    systemText,
                    const SizedBox(height: 4),
                    varianceText,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: systemText),
                  varianceText,
                ],
              );
            },
          ),
          if (variance > 0) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final unitCostField = TextField(
                  controller: line.unitCostController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit Cost for Added Stock',
                    prefixText: '₱',
                  ),
                );
                final expiryButton = OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (date == null) return;
                    line.expirationDate = date;
                    onChanged();
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    line.expirationDate == null
                        ? 'Expiration Date *'
                        : _formatDate(line.expirationDate!),
                  ),
                );
                if (constraints.maxWidth < 580 && item.trackExpiry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      unitCostField,
                      const SizedBox(height: 10),
                      expiryButton,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: unitCostField),
                    if (item.trackExpiry) ...[
                      const SizedBox(width: 10),
                      Expanded(child: expiryButton),
                    ],
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: line.notesController,
            decoration: const InputDecoration(
              labelText: 'Line Notes',
              hintText: 'Optional explanation for this item variance',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: Text(
        errorText(error),
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: AppColors.error),
      ),
    );
  }

  String _signedQuantity(double quantity, String unit) {
    final sign = quantity > 0 ? '+' : '';
    return '$sign${_quantityWithUnit(quantity, unit)}';
  }

  String _quantityWithUnit(double quantity, String unit) {
    final value = _plainNumber(quantity);
    return unit.isEmpty ? value : '$value $unit';
  }

  String _plainNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    int hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour %= 12;
    if (hour == 0) hour = 12;
    return '${date.month}/${date.day}/${date.year} $hour:$minute $period';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CountDraftLine {
  String itemId;
  final TextEditingController countedController;
  final TextEditingController notesController;
  final TextEditingController unitCostController;
  DateTime? expirationDate;

  _CountDraftLine({
    required this.itemId,
    required this.countedController,
    required this.notesController,
    required this.unitCostController,
  });

  factory _CountDraftLine.fromItem(InventoryItem item) {
    return _CountDraftLine(
      itemId: item.id,
      countedController: TextEditingController(
        text: item.currentQuantity == item.currentQuantity.roundToDouble()
            ? item.currentQuantity.toInt().toString()
            : item.currentQuantity.toString(),
      ),
      notesController: TextEditingController(),
      unitCostController: TextEditingController(text: '0'),
    );
  }

  void dispose() {
    countedController.dispose();
    notesController.dispose();
    unitCostController.dispose();
  }
}
