import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/purchasing_repository.dart';
import '../../models/purchasing.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

class PurchasingScreen extends StatefulWidget {
  final PurchasingRepository purchasingRepository;
  final VoidCallback? onInventoryChanged;

  const PurchasingScreen({
    super.key,
    required this.purchasingRepository,
    this.onInventoryChanged,
  });

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  int _tab = 0;
  late Future<List<PurchaseOrderSummary>> _purchaseOrdersFuture;
  late Future<List<GoodsReceiptSummary>> _receiptsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _purchaseOrdersFuture = widget.purchasingRepository.getPurchaseOrders();
    _receiptsFuture = widget.purchasingRepository.getGoodsReceipts();
  }

  void _refresh() {
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Purchasing',
      subtitle: 'Create purchase orders and receive several traceable stock items at once.',
      action: ElevatedButton.icon(
        onPressed: _tab == 0
            ? _showCreatePurchaseOrder
            : () => _showReceiveStock(),
        icon: const Icon(Icons.add, size: 18),
        label: Text(_tab == 0 ? 'New Purchase Order' : 'Receive Stock'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Purchase Orders'),
                selected: _tab == 0,
                onSelected: (_) => setState(() => _tab = 0),
              ),
              ChoiceChip(
                label: const Text('Goods Receipts'),
                selected: _tab == 1,
                onSelected: (_) => setState(() => _tab = 1),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _tab == 0 ? _buildPurchaseOrders() : _buildGoodsReceipts(),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseOrders() {
    return FutureBuilder<List<PurchaseOrderSummary>>(
      future: _purchaseOrdersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _error(snapshot.error);
        }

        final orders = snapshot.data ?? const <PurchaseOrderSummary>[];

        if (orders.isEmpty) {
          return const Center(child: Text('No purchase orders recorded yet.'));
        }

        return SingleChildScrollView(
          child: DataTableCard(
            headers: const [
              'PO',
              'Supplier',
              'Lines',
              'Expected',
              'Total',
              'Status',
              'Actions',
            ],
            flexes: const [1, 3, 1, 2, 2, 2, 3],
            rows: orders
                .map(
                  (order) => [
                    Text('PO-${order.number}', style: AppTextStyles.bodyMedium),
                    Text(order.supplierName, style: AppTextStyles.body),
                    Text('${order.lineCount}', style: AppTextStyles.body),
                    Text(
                      order.expectedDate == null
                          ? '—'
                          : _formatDate(order.expectedDate!),
                      style: AppTextStyles.body,
                    ),
                    Text(
                      _money(order.totalAmount),
                      style: AppTextStyles.bodyMedium,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(_statusLabel(order.status)),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (order.status == 'DRAFT')
                          TextButton(
                            onPressed: () => _approvePurchaseOrder(order),
                            child: const Text('Approve'),
                          ),
                        if (order.status == 'APPROVED' ||
                            order.status == 'SENT' ||
                            order.status == 'PARTIALLY_RECEIVED')
                          TextButton(
                            onPressed: () => _showReceiveStock(order: order),
                            child: const Text('Receive'),
                          ),
                      ],
                    ),
                  ],
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildGoodsReceipts() {
    return FutureBuilder<List<GoodsReceiptSummary>>(
      future: _receiptsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _error(snapshot.error);
        }

        final receipts = snapshot.data ?? const <GoodsReceiptSummary>[];

        if (receipts.isEmpty) {
          return const Center(child: Text('No goods receipts recorded yet.'));
        }

        return SingleChildScrollView(
          child: DataTableCard(
            headers: const [
              'Receipt',
              'Supplier',
              'PO',
              'Invoice / Receipt',
              'Received',
              'Lines',
              'Total',
              'Status',
              'Actions',
            ],
            flexes: const [1, 3, 1, 2, 2, 1, 2, 2, 1],
            rows: receipts
                .map(
                  (receipt) => [
                    Text(
                      'GR-${receipt.number}',
                      style: AppTextStyles.bodyMedium,
                    ),
                    Text(receipt.supplierName, style: AppTextStyles.body),
                    Text(
                      receipt.purchaseOrderNumber == null
                          ? 'Direct'
                          : 'PO-${receipt.purchaseOrderNumber}',
                      style: AppTextStyles.body,
                    ),
                    Text(
                      receipt.supplierInvoiceNumber.isEmpty
                          ? '—'
                          : receipt.supplierInvoiceNumber,
                      style: AppTextStyles.body,
                    ),
                    Text(
                      _formatDate(receipt.receivedAt),
                      style: AppTextStyles.body,
                    ),
                    Text('${receipt.lineCount}', style: AppTextStyles.body),
                    Text(
                      _money(receipt.total),
                      style: AppTextStyles.bodyMedium,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(_statusLabel(receipt.status)),
                    ),
                    TextButton(
                      onPressed: () => _showReceiptDetails(receipt),
                      child: const Text('View'),
                    ),
                  ],
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _showReceiptDetails(GoodsReceiptSummary receipt) async {
    List<GoodsReceiptLineRecord> lines;
    try {
      lines = await widget.purchasingRepository.getGoodsReceiptLines(
        receipt.id,
      );
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
      return;
    } catch (error) {
      if (mounted) _showMessage(error.toString());
      return;
    }

    if (!mounted) return;

    await showPrototypeDialog(
      context: context,
      title: 'Goods Receipt GR-${receipt.number}',
      width: 820,
      content: SizedBox(
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  _receiptDetail('Supplier', receipt.supplierName),
                  _receiptDetail(
                    'External Reference',
                    receipt.supplierInvoiceNumber,
                  ),
                  _receiptDetail(
                    'Reference Date',
                    receipt.supplierInvoiceDate == null
                        ? '—'
                        : _formatDate(receipt.supplierInvoiceDate!),
                  ),
                  _receiptDetail(
                    'Purchase Order',
                    receipt.purchaseOrderNumber == null
                        ? 'Direct Receipt'
                        : 'PO-${receipt.purchaseOrderNumber}',
                  ),
                  _receiptDetail('Posted', _formatDate(receipt.receivedAt)),
                  _receiptDetail(
                    'Received By',
                    receipt.receivedByName.isEmpty
                        ? '—'
                        : receipt.receivedByName,
                  ),
                  _receiptDetail('Total', _money(receipt.total)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Received Items', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              if (lines.isEmpty)
                _emptyLines()
              else
                for (final line in lines) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gray200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.inventoryItemName,
                                style: AppTextStyles.bodyMedium,
                              ),
                            ),
                            Text(
                              _money(line.lineTotal),
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_qty(line.purchaseQuantity)} ${line.purchaseUomCode} '
                          '× ${_money(line.unitCost)} each',
                          style: AppTextStyles.body,
                        ),
                        Text(
                          'Conversion: 1 ${line.purchaseUomCode} = '
                          '${_qty(line.baseQuantityPerPurchaseUnit)} '
                          '${line.baseUomCode} • Added: '
                          '${_qty(line.baseQuantity)} ${line.baseUomCode}',
                          style: AppTextStyles.caption,
                        ),
                        Text(
                          'Lot: ${line.lotCode.isEmpty ? 'Auto-generated' : line.lotCode} '
                          '• Expiry: ${line.expirationDate == null ? 'Not applicable' : _formatDate(line.expirationDate!)} '
                          '• Remaining: ${_qty(line.remainingQuantity)} ${line.baseUomCode}',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptDetail(String label, String value) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Future<void> _showCreatePurchaseOrder() async {
    final refs = await Future.wait([
      widget.purchasingRepository.getSuppliers(),
      widget.purchasingRepository.getInventoryItems(),
      widget.purchasingRepository.getUnits(),
    ]);

    if (!mounted) return;

    final suppliers = refs[0] as List<PurchasingSupplierOption>;
    final inventory = refs[1] as List<PurchaseInventoryOption>;
    final units = refs[2] as List<PurchaseUnitOption>;

    if (suppliers.isEmpty) {
      _showMessage('Add an active supplier before creating a purchase order.');
      return;
    }

    if (inventory.isEmpty || units.isEmpty) {
      _showMessage('Inventory items and units must be configured first.');
      return;
    }

    String supplierId = suppliers.first.id;
    DateTime? expectedDate;
    final notesController = TextEditingController();
    List<PurchaseLineInput> lines = [];
    bool isSaving = false;
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'New Purchase Order',
      width: 760,
      barrierDismissible: false,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier *'),
                  items: suppliers
                      .map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => supplierId = value);
                  },
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: DateTime.now().add(
                          const Duration(days: 1),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (date == null) return;
                      setDialogState(() => expectedDate = date);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      expectedDate == null
                          ? 'Set Expected Date'
                          : 'Expected: ${_formatDate(expectedDate!)}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Items', style: AppTextStyles.h3),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final line = await _showLineEditor(
                          dialogContext,
                          inventory,
                          units,
                          receiptMode: false,
                        );

                        if (line == null) return;
                        setDialogState(() => lines.add(line));
                      },
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Add Item'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildLineList(
                  lines: lines,
                  inventory: inventory,
                  onRemove: (index) {
                    setDialogState(() => lines.removeAt(index));
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
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
        ElevatedButton(
          onPressed: () async {
            if (isSaving) return;
            if (lines.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Add at least one purchase item.';
              });
              return;
            }

            updateDialogState?.call(() => isSaving = true);
            try {
              await widget.purchasingRepository.createPurchaseOrder(
                supplierId: supplierId,
                items: lines,
                expectedDate: expectedDate,
                notes: notesController.text.trim(),
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Purchase order created as Draft.');
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = error.toString();
              });
            }
          },
          child: const Text('Create Purchase Order'),
        ),
      ],
    );

    notesController.dispose();
  }

  Future<void> _approvePurchaseOrder(PurchaseOrderSummary order) async {
    try {
      await widget.purchasingRepository.approvePurchaseOrder(order.id);
      if (!mounted) return;
      _refresh();
      _showMessage('Purchase order PO-${order.number} approved.');
    } on PostgrestException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  Future<void> _showReceiveStock({PurchaseOrderSummary? order}) async {
    final refs = await Future.wait([
      widget.purchasingRepository.getSuppliers(),
      widget.purchasingRepository.getInventoryItems(),
      widget.purchasingRepository.getUnits(),
      if (order != null)
        widget.purchasingRepository.getPurchaseOrderLines(order.id)
      else
        Future.value(<PurchaseOrderLineRecord>[]),
    ]);

    if (!mounted) return;

    final suppliers = refs[0] as List<PurchasingSupplierOption>;
    final inventory = refs[1] as List<PurchaseInventoryOption>;
    final units = refs[2] as List<PurchaseUnitOption>;
    final poLines = refs[3] as List<PurchaseOrderLineRecord>;

    if (suppliers.isEmpty) {
      _showMessage('No active supplier is available.');
      return;
    }

    String supplierId = order?.supplierId ?? suppliers.first.id;
    final invoiceController = TextEditingController();
    final notesController = TextEditingController();
    DateTime? invoiceDate = DateTime.now();
    DateTime? dueDate;
    bool createBill = true;
    bool isSaving = false;
    String? errorMessage;
    StateSetter? updateDialogState;

    List<PurchaseLineInput> lines = poLines
        .where((line) => line.remainingQuantity > 0)
        .map(
          (line) => PurchaseLineInput(
            inventoryItemId: line.inventoryItemId,
            purchaseUomId: line.purchaseUomId,
            quantity: line.remainingQuantity,
            baseQuantityPerPurchaseUnit: line.baseQuantityPerPurchaseUnit,
            unitCost: line.unitCost,
            purchaseOrderItemId: line.id,
          ),
        )
        .toList();

    await showPrototypeDialog(
      context: context,
      title: order == null ? 'Receive Stock' : 'Receive PO-${order.number}',
      width: 780,
      barrierDismissible: false,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier *'),
                  items: suppliers
                      .map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                      )
                      .toList(),
                  onChanged: order != null
                      ? null
                      : (value) {
                          if (value == null) return;
                          setDialogState(() => supplierId = value);
                        },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Invoice / Grocery Receipt Number *',
                    hintText: 'Required external reference',
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final invoiceDateButton = OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: dialogContext,
                          initialDate: invoiceDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 3650),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (date == null) return;
                        setDialogState(() => invoiceDate = date);
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        invoiceDate == null
                            ? 'Invoice / Receipt Date *'
                            : 'Reference: ${_formatDate(invoiceDate!)}',
                      ),
                    );
                    final dueDateButton = OutlinedButton.icon(
                      onPressed: createBill
                          ? () async {
                              final date = await showDatePicker(
                                context: dialogContext,
                                initialDate: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 3650),
                                ),
                              );
                              if (date == null) return;
                              setDialogState(() => dueDate = date);
                            }
                          : null,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        dueDate == null
                            ? 'Bill Due Date'
                            : 'Due: ${_formatDate(dueDate!)}',
                      ),
                    );

                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          invoiceDateButton,
                          const SizedBox(height: 10),
                          dueDateButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: invoiceDateButton),
                        const SizedBox(width: 10),
                        Expanded(child: dueDateButton),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Received Items', style: AppTextStyles.h3),
                    ),
                    if (order == null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final line = await _showLineEditor(
                            dialogContext,
                            inventory,
                            units,
                            receiptMode: true,
                          );
                          if (line == null) return;
                          setDialogState(() => lines.add(line));
                        },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Add Item'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (lines.isEmpty)
                  _emptyLines()
                else
                  for (int index = 0; index < lines.length; index++)
                    _receiptLineTile(
                      line: lines[index],
                      inventory: inventory,
                      units: units,
                      onEdit: () async {
                        final edited = await _showLineEditor(
                          dialogContext,
                          inventory,
                          units,
                          receiptMode: true,
                          initial: lines[index],
                        );
                        if (edited == null) return;

                        setDialogState(() => lines[index] = edited);
                      },
                      onRemove: lines.length == 1
                          ? null
                          : () => setDialogState(() => lines.removeAt(index)),
                    ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Create Supplier Bill'),
                  subtitle: const Text(
                    'Records the amount as payable to the supplier.',
                  ),
                  value: createBill,
                  onChanged: (value) {
                    setDialogState(() {
                      createBill = value;
                      if (!value) dueDate = null;
                    });
                  },
                ),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Receiving Notes',
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
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
        ElevatedButton(
          onPressed: () async {
            if (isSaving) return;
            if (invoiceController.text.trim().isEmpty) {
              updateDialogState?.call(() {
                errorMessage =
                    'Supplier invoice or grocery receipt number is required.';
              });
              return;
            }

            if (invoiceDate == null) {
              updateDialogState?.call(() {
                errorMessage =
                    'Supplier invoice or grocery receipt date is required.';
              });
              return;
            }

            if (lines.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Add at least one received item.';
              });
              return;
            }

            for (final line in lines) {
              final item = inventory.firstWhere(
                (entry) => entry.id == line.inventoryItemId,
              );
              if (item.trackExpiry && line.expirationDate == null) {
                updateDialogState?.call(() {
                  errorMessage =
                      'Expiration date is required for ${item.name}.';
                });
                return;
              }
            }

            updateDialogState?.call(() => isSaving = true);
            try {
              await widget.purchasingRepository.receiveStock(
                supplierId: supplierId,
                items: lines,
                purchaseOrderId: order?.id ?? '',
                supplierInvoiceNumber: invoiceController.text.trim(),
                supplierInvoiceDate: invoiceDate!,
                notes: notesController.text.trim(),
                createSupplierBill: createBill,
                dueDate: dueDate,
              );

              if (!mounted) return;
              widget.onInventoryChanged?.call();
              Navigator.pop(context);
              _refresh();
              _showMessage('Stock received and inventory updated.');
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                isSaving = false;
                errorMessage = error.toString();
              });
            }
          },
          child: const Text('Post Receipt'),
        ),
      ],
    );

    invoiceController.dispose();
    notesController.dispose();
  }

  Future<PurchaseLineInput?> _showLineEditor(
    BuildContext context,
    List<PurchaseInventoryOption> inventory,
    List<PurchaseUnitOption> units, {
    required bool receiptMode,
    PurchaseLineInput? initial,
  }) async {
    if (inventory.isEmpty || units.isEmpty) return null;

    String inventoryId = initial?.inventoryItemId ?? inventory.first.id;
    String purchaseUomId = initial?.purchaseUomId ?? inventory.first.baseUomId;

    final quantityController = TextEditingController(
      text: initial == null ? '' : _qty(initial.quantity),
    );
    final costController = TextEditingController(
      text: initial == null ? '' : initial.unitCost.toStringAsFixed(2),
    );
    final selectedItem = inventory.firstWhere(
      (entry) => entry.id == inventoryId,
    );
    final selectedBaseUnit = units.firstWhere(
      (unit) => unit.id == selectedItem.baseUomId,
    );
    final selectedPurchaseUnit = units.firstWhere(
      (unit) => unit.id == purchaseUomId,
    );
    final conversionController = TextEditingController(
      text: initial == null
          ? _qty(
              selectedPurchaseUnit.factorToBase / selectedBaseUnit.factorToBase,
            )
          : _qty(initial.baseQuantityPerPurchaseUnit),
    );
    final lotController = TextEditingController(text: initial?.lotCode ?? '');
    DateTime? expirationDate = initial?.expirationDate;
    String? errorMessage;

    final result = await showDialog<PurchaseLineInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) {
          final item = inventory.firstWhere((entry) => entry.id == inventoryId);
          final baseUnit = units.firstWhere(
            (unit) => unit.id == item.baseUomId,
          );
          final compatible = units
              .where((unit) => unit.dimension == baseUnit.dimension)
              .toList();

          if (!compatible.any((unit) => unit.id == purchaseUomId)) {
            purchaseUomId = item.baseUomId;
          }

          final purchaseUnit = compatible.firstWhere(
            (unit) => unit.id == purchaseUomId,
          );
          final standardConversion =
              purchaseUnit.factorToBase / baseUnit.factorToBase;
          final lockedToPurchaseOrder =
              initial?.purchaseOrderItemId.isNotEmpty == true;
          final needsPackageConversion =
              purchaseUnit.dimension == 'COUNT' &&
              purchaseUnit.id != item.baseUomId;

          return AlertDialog(
            title: Text(
              receiptMode ? 'Received Item' : 'Purchase Item',
              style: AppTextStyles.h2,
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: inventoryId,
                      decoration: const InputDecoration(
                        labelText: 'Inventory Item *',
                      ),
                      items: inventory
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.id,
                              child: Text(entry.name),
                            ),
                          )
                          .toList(),
                      onChanged: initial?.purchaseOrderItemId.isNotEmpty == true
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                inventoryId = value;
                                final next = inventory.firstWhere(
                                  (entry) => entry.id == value,
                                );
                                purchaseUomId = next.baseUomId;
                                conversionController.text = '1';
                                expirationDate = null;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: purchaseUomId,
                      decoration: const InputDecoration(
                        labelText: 'Purchase Unit *',
                      ),
                      items: compatible
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit.id,
                              child: Text('${unit.name} (${unit.code})'),
                            ),
                          )
                          .toList(),
                      onChanged: initial?.purchaseOrderItemId.isNotEmpty == true
                          ? null
                          : (value) {
                              if (value == null) return;
                              final nextUnit = compatible.firstWhere(
                                (unit) => unit.id == value,
                              );
                              setDialogState(() {
                                purchaseUomId = value;
                                final requiresManual =
                                    nextUnit.dimension == 'COUNT' &&
                                    nextUnit.id != item.baseUomId;
                                conversionController.text = requiresManual
                                    ? ''
                                    : _qty(
                                        nextUnit.factorToBase /
                                            baseUnit.factorToBase,
                                      );
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    if (needsPackageConversion && !lockedToPurchaseOrder)
                      TextField(
                        controller: conversionController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${item.baseUomCode} per ${purchaseUnit.code} *',
                          helperText:
                              'Example: enter 50 when one box contains 50 ${item.baseUomCode}.',
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '1 ${purchaseUnit.code} = '
                          '${_qty(lockedToPurchaseOrder ? initial!.baseQuantityPerPurchaseUnit : standardConversion)} '
                          '${item.baseUomCode}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: receiptMode
                            ? 'Quantity Received *'
                            : 'Quantity Ordered *',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cost per ${purchaseUnit.code} *',
                        prefixText: '₱',
                      ),
                    ),
                    if (receiptMode && item.trackExpiry) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: dialogContext,
                              initialDate:
                                  expirationDate ??
                                  DateTime.now().add(const Duration(days: 1)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 3650),
                              ),
                            );
                            if (date == null) return;
                            setDialogState(() => expirationDate = date);
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            expirationDate == null
                                ? 'Expiration Date *'
                                : 'Expires: ${_formatDate(expirationDate!)}',
                          ),
                        ),
                      ),
                    ],
                    if (receiptMode) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: lotController,
                        decoration: const InputDecoration(
                          labelText: 'Lot / Batch Code',
                        ),
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
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final quantity = double.tryParse(
                    quantityController.text.trim(),
                  );
                  final unitCost = double.tryParse(costController.text.trim());
                  final conversion = double.tryParse(
                    conversionController.text.trim(),
                  );

                  if (quantity == null ||
                      quantity <= 0 ||
                      unitCost == null ||
                      unitCost < 0 ||
                      conversion == null ||
                      conversion <= 0) {
                    setDialogState(() {
                      errorMessage = 'Enter a valid quantity, package conversion and unit cost.';
                    });
                    return;
                  }

                  if (receiptMode &&
                      item.trackExpiry &&
                      expirationDate == null) {
                    setDialogState(() {
                      errorMessage =
                          'Expiration date is required for ${item.name}.';
                    });
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    PurchaseLineInput(
                      inventoryItemId: inventoryId,
                      purchaseUomId: purchaseUomId,
                      quantity: quantity,
                      baseQuantityPerPurchaseUnit: conversion,
                      unitCost: unitCost,
                      purchaseOrderItemId: initial?.purchaseOrderItemId ?? '',
                      expirationDate: expirationDate,
                      lotCode: lotController.text.trim(),
                    ),
                  );
                },
                child: const Text('Save Item'),
              ),
            ],
          );
        },
      ),
    );

    quantityController.dispose();
    costController.dispose();
    conversionController.dispose();
    lotController.dispose();
    return result;
  }

  Widget _buildLineList({
    required List<PurchaseLineInput> lines,
    required List<PurchaseInventoryOption> inventory,
    required void Function(int index) onRemove,
  }) {
    if (lines.isEmpty) return _emptyLines();

    return Column(
      children: [
        for (int index = 0; index < lines.length; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gray200),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemName = inventory
                    .firstWhere(
                      (entry) => entry.id == lines[index].inventoryItemId,
                    )
                    .name;
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(itemName, style: AppTextStyles.bodyMedium),
                    Text(
                      '${_qty(lines[index].quantity)} × '
                      '${_money(lines[index].unitCost)}',
                      style: AppTextStyles.body,
                    ),
                  ],
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _money(lines[index].quantity * lines[index].unitCost),
                      style: AppTextStyles.bodyMedium,
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => onRemove(index),
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                  ],
                );

                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 4),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: details),
                    actions,
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _receiptLineTile({
    required PurchaseLineInput line,
    required List<PurchaseInventoryOption> inventory,
    required List<PurchaseUnitOption> units,
    required VoidCallback onEdit,
    VoidCallback? onRemove,
  }) {
    final item = inventory.firstWhere(
      (entry) => entry.id == line.inventoryItemId,
    );
    final purchaseUnit = units.firstWhere(
      (entry) => entry.id == line.purchaseUomId,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gray200),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: AppTextStyles.bodyMedium),
              Text(
                '${_qty(line.quantity)} ${purchaseUnit.code} received • '
                '1 ${purchaseUnit.code} = '
                '${_qty(line.baseQuantityPerPurchaseUnit)} ${item.baseUomCode}'
                '${line.expirationDate == null ? '' : ' • exp. ${_formatDate(line.expirationDate!)}'}',
                style: AppTextStyles.caption,
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _money(line.quantity * line.unitCost),
                style: AppTextStyles.bodyMedium,
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
            ],
          );

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _emptyLines() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'No items added yet.',
        style: AppTextStyles.body.copyWith(color: AppColors.gray500),
      ),
    );
  }

  Widget _error(Object? error) {
    return Center(
      child: Text(
        'Unable to load purchasing data.\n${error ?? ''}',
        textAlign: TextAlign.center,
      ),
    );
  }

  String _statusLabel(String status) {
    return status
        .toLowerCase()
        .split('_')
        .map(
          (part) =>
              part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
        )
        .join(' ');
  }

  static String _money(double value) {
    return '₱${value.toStringAsFixed(2)}';
  }

  static String _qty(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
