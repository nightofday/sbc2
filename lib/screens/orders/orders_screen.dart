import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/reporting.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/order_record.dart';
import '../../models/refund_preview.dart';
import '../../models/request_id.dart';
import '../../widgets/common/copy_receipt_button.dart';
import '../../widgets/common/business_profile_scope.dart';
import '../../widgets/common/order_line.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';
import 'new_order_screen.dart';
import '../../core/theme/app_radius.dart';

class OrdersScreen extends StatefulWidget {
  final OrderRepository orderRepository;
  final bool canManageOrders;
  final Listenable? refreshListenable;
  final VoidCallback? onDataChanged;

  const OrdersScreen({
    super.key,
    required this.orderRepository,
    required this.canManageOrders,
    this.refreshListenable,
    this.onDataChanged,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<OrderRecord>> _ordersFuture;
  String _searchQuery = '';
  String _dateFilter = 'All Dates';
  String _typeFilter = 'All Types';
  String _statusFilter = 'All Status';

  @override
  void initState() {
    super.initState();
    _loadOrders();
    widget.refreshListenable?.addListener(_refreshOrders);
  }

  @override
  void didUpdateWidget(covariant OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_refreshOrders);
      widget.refreshListenable?.addListener(_refreshOrders);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_refreshOrders);
    super.dispose();
  }

  void _loadOrders() {
    _ordersFuture = widget.orderRepository.getOrders();
  }

  void _refreshOrders() {
    if (!mounted) return;
    setState(_loadOrders);
  }

  void _notifyDataChanged() {
    final callback = widget.onDataChanged;
    if (callback == null) {
      _refreshOrders();
    } else {
      callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Orders',
      action: ElevatedButton.icon(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  NewOrderScreen(orderRepository: widget.orderRepository),
            ),
          );
          if (changed == true) _notifyDataChanged();
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New Order'),
      ),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<OrderRecord>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load orders.'));
                }

                final orders = _applyFilters(
                  snapshot.data ?? const <OrderRecord>[],
                );

                if (orders.isEmpty) {
                  return Center(
                    child: Text(
                      'No orders match the selected filters.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: DataTableCard(
                    headers: const [
                      'Order',
                      'Customer / Table',
                      'Date & Time',
                      'Employee',
                      'Type',
                      'Amount',
                      'Status',
                    ],
                    flexes: const [2, 3, 3, 2, 2, 2, 3],
                    rows: orders
                        .map(
                          (order) => [
                            InkWell(
                              onTap: () => _showOrderDetails(context, order),
                              child: Text(
                                order.id,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Text(
                              _orderReference(order),
                              style: AppTextStyles.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _formatOrderDateTime(order.createdAt),
                              style: AppTextStyles.body,
                            ),
                            Text(order.employee, style: AppTextStyles.body),
                            Text(order.type, style: AppTextStyles.body),
                            Text(
                              _moneyDouble(order.amount),
                              style: AppTextStyles.body,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(order.status),
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

  Widget _buildFilters() {
    final search = TextField(
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search order, customer, or table...',
      ),
    );
    final date = DropdownButtonFormField<String>(
      initialValue: _dateFilter,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'All Dates', child: Text('All Dates')),
        DropdownMenuItem(value: 'Today', child: Text('Today')),
        DropdownMenuItem(value: 'Yesterday', child: Text('Yesterday')),
        DropdownMenuItem(value: 'Last 7 Days', child: Text('Last 7 Days')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _dateFilter = value);
      },
    );
    final type = DropdownButtonFormField<String>(
      initialValue: _typeFilter,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'All Types', child: Text('All Types')),
        DropdownMenuItem(value: 'Dine In', child: Text('Dine In')),
        DropdownMenuItem(value: 'Take Out', child: Text('Take Out')),
        DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _typeFilter = value);
      },
    );
    final status = DropdownButtonFormField<String>(
      initialValue: _statusFilter,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'All Status', child: Text('All Status')),
        DropdownMenuItem(value: 'Open', child: Text('Open')),
        DropdownMenuItem(value: 'Completed', child: Text('Completed')),
        DropdownMenuItem(value: 'Refunded', child: Text('Refunded')),
        DropdownMenuItem(value: 'Void', child: Text('Void')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _statusFilter = value);
      },
    );

    return ResponsiveFilterBar(
      primary: search,
      filters: [date, type, status],
      filterWidths: const [165, 160, 155],
      breakpoint: 900,
    );
  }

  List<OrderRecord> _applyFilters(List<OrderRecord> orders) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = orders.where((order) {
      final searchMatches =
          query.isEmpty ||
          order.id.toLowerCase().contains(query) ||
          order.customerName.toLowerCase().contains(query) ||
          order.tableNumber.toLowerCase().contains(query) ||
          order.deliveryReference.toLowerCase().contains(query);

      final dateMatches = _matchesDateFilter(order.createdAt);
      final typeMatches =
          _typeFilter == 'All Types' || order.type == _typeFilter;
      final statusMatches =
          _statusFilter == 'All Status' || order.status == _statusFilter;

      return searchMatches && dateMatches && typeMatches && statusMatches;
    }).toList();

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  bool _matchesDateFilter(DateTime dateTime) {
    if (_dateFilter == 'All Dates') return true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final orderDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (_dateFilter == 'Today') {
      return orderDay == today;
    }

    if (_dateFilter == 'Yesterday') {
      return orderDay == today.subtract(const Duration(days: 1));
    }

    if (_dateFilter == 'Last 7 Days') {
      final firstDay = today.subtract(const Duration(days: 6));
      return !orderDay.isBefore(firstDay) && !orderDay.isAfter(today);
    }

    return true;
  }

  Future<void> _showOrderDetails(
    BuildContext context,
    OrderRecord order,
  ) async {
    await showPrototypeDialog(
      context: context,
      title: 'Order ${order.id}',
      width: 620,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(order.status),
                ),
                const Spacer(),
                Text(
                  _formatFullDateTime(order.createdAt),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _detailRow('Customer / Table', _orderReference(order)),
            _detailRow('Order Type', order.type),
            if (order.invoiceNumber.isNotEmpty)
              _detailRow('Invoice', order.invoiceNumber),
            _detailRow('Employee', order.employee),
            if (order.deliveryReference.isNotEmpty)
              _detailRow('Delivery Reference', order.deliveryReference),
            _detailRow(
              'Payment',
              order.paymentMethod.isEmpty
                  ? 'Not paid yet'
                  : order.paymentMethod,
            ),
            const Divider(height: 28),
            const Text('Items', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            if (order.items.isEmpty)
              Text(
                'No detailed item data available for this sample order.',
                style: AppTextStyles.body.copyWith(color: AppColors.gray500),
              )
            else
              for (final item in order.items)
                OrderLine(item: item, total: _moneyDouble(item.lineTotal)),
            const Divider(height: 28),
            if (order.discountAmount > 0) ...[
              _detailRow('Subtotal', _moneyDouble(order.subtotal)),
              _detailRow(
                order.discountName.isEmpty
                    ? 'Discount'
                    : 'Discount (${order.discountName})',
                '-${_moneyDouble(order.discountAmount)}',
              ),
            ],
            _detailRow('Total', _moneyDouble(order.amount), emphasized: true),
            if (order.paymentMethod.isNotEmpty) ...[
              _detailRow('Amount Received', _moneyDouble(order.amountReceived)),
              _detailRow('Change', _moneyDouble(order.changeAmount)),
            ],
            if (order.refundedAmount > 0) ...[
              _detailRow('Refunded', _moneyDouble(-order.refundedAmount)),
              _detailRow(
                'Kept After Refunds',
                _moneyDouble(order.amount - order.refundedAmount),
                emphasized: true,
              ),
            ],
            if (order.lastActionReason.isNotEmpty) ...[
              const Divider(height: 28),
              Text('${order.status} Information', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              _detailRow('Reason', order.lastActionReason),
              if (order.authorizedBy.isNotEmpty)
                _detailRow('Authorized by', order.authorizedBy),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (widget.canManageOrders)
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _showActions(context, order);
            },
            child: const Text('Actions'),
          ),
        ElevatedButton(
          onPressed: () => _showReceipt(context, order),
          child: const Text('View Receipt'),
        ),
      ],
    );
  }

  Future<void> _showActions(BuildContext context, OrderRecord order) async {
    final isClosed = order.status == 'Void' || order.status == 'Refunded';

    await showPrototypeDialog(
      context: context,
      title: 'Order Actions',
      width: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('View Receipt'),
            onTap: () {
              Navigator.pop(context);
              _showReceipt(context, order);
            },
          ),
          if (order.status == 'Completed' ||
              order.status == 'Partially Refunded')
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Refund Items'),
              subtitle: const Text('Full or partial refund'),
              onTap: () {
                Navigator.pop(context);
                _showRefundDialog(context, order);
              },
            ),
          if (order.status == 'Partially Refunded' ||
              order.status == 'Refunded')
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Review Returned Stock'),
              subtitle: const Text('Restock eligible returned finished goods'),
              onTap: () {
                Navigator.pop(context);
                _showRefundRestockDialog(context, order);
              },
            ),
          if (order.status == 'Open')
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.primary),
              title: const Text(
                'Void Order',
                style: TextStyle(color: AppColors.primary),
              ),
              subtitle: const Text('Requires manager authorization'),
              onTap: () {
                Navigator.pop(context);
                _showManagerAuthorization(
                  context,
                  order: order,
                  action: _OrderAction.voidOrder,
                );
              },
            ),
          if (isClosed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'This order is already ${order.status.toLowerCase()}. No additional refund or void action is available.',
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showRefundDialog(
    BuildContext context,
    OrderRecord order,
  ) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    RefundPreview preview;

    try {
      preview = await widget.orderRepository.getRefundPreview(order.id);
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
      return;
    }

    if (!context.mounted) return;

    if (preview.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This order has nothing left to refund.')),
      );
      return;
    }

    final reasonController = TextEditingController();
    final referenceController = TextEditingController();
    final quantityControllers = <String, TextEditingController>{
      for (final item in preview.items)
        item.orderItemId: TextEditingController(text: '0'),
    };

    String? errorMessage;
    StateSetter? dialogSetState;

    double selectedTotal() {
      double total = 0;

      for (final item in preview.items) {
        final controller = quantityControllers[item.orderItemId]!;
        final quantity = double.tryParse(controller.text.trim()) ?? 0;
        if (quantity > 0) {
          total += quantity * item.unitRefundable;
        }
      }

      return total;
    }

    await showPrototypeDialog(
      context: context,
      title: 'Refund Order ${order.id}',
      width: 700,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          dialogSetState = setDialogState;

          return SizedBox(
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: AppRadius.all,
                    ),
                    child: Text(
                      'Refunds return through ${preview.paymentMethodName}. '
                      'Only quantities that have not already been refunded are available.',
                      style: AppTextStyles.body,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Items', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  for (final item in preview.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.gray100,
                        borderRadius: AppRadius.all,
                        border: Border.all(color: AppColors.gray200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: AppTextStyles.bodyMedium,
                                ),
                                Text(
                                  item.variantName.isEmpty
                                      ? 'Remaining: ${_refundQty(item.remainingQuantity)}'
                                      : '${item.variantName} • Remaining: ${_refundQty(item.remainingQuantity)}',
                                  style: AppTextStyles.caption,
                                ),
                                Text(
                                  '${_moneyDouble(item.unitRefundable)} refundable each',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: quantityControllers[item.orderItemId],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                              ),
                              onChanged: (_) {
                                setDialogState(() {
                                  errorMessage = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  _detailRow(
                    'Selected Refund',
                    _moneyDouble(selectedTotal()),
                    emphasized: true,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Refund Reason *',
                    ),
                    onChanged: (_) {
                      dialogSetState?.call(() => errorMessage = null);
                    },
                  ),
                  if (preview.requiresReference) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: referenceController,
                      decoration: InputDecoration(
                        labelText:
                            '${preview.paymentMethodName} Refund Reference *',
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
            final reason = reasonController.text.trim();
            final quantities = <String, double>{};
            String? validationError;

            for (final item in preview.items) {
              final raw = quantityControllers[item.orderItemId]!.text.trim();
              final quantity = double.tryParse(raw) ?? -1;

              if (quantity < 0) {
                validationError = 'Refund quantities must be zero or greater.';
                break;
              }

              if (quantity > item.remainingQuantity) {
                validationError =
                    '${item.itemName} only has ${_refundQty(item.remainingQuantity)} refundable.';
                break;
              }

              if (quantity > 0) {
                quantities[item.orderItemId] = quantity;
              }
            }

            if (validationError == null && quantities.isEmpty) {
              validationError = 'Select at least one quantity to refund.';
            }

            if (validationError == null && reason.isEmpty) {
              validationError = 'A refund reason is required.';
            }

            if (validationError == null &&
                preview.requiresReference &&
                referenceController.text.trim().isEmpty) {
              validationError = 'A refund transaction reference is required.';
            }

            if (validationError != null) {
              dialogSetState?.call(() {
                errorMessage = validationError;
              });
              return;
            }

            try {
              await widget.orderRepository.refundOrderItems(
                clientRequestId: requestId,
                order.id,
                quantities: quantities,
                reason: reason,
                externalReference: referenceController.text.trim(),
              );

              if (!context.mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Refund recorded for order ${order.id}.'),
                ),
              );
            } on PostgrestException catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              dialogSetState?.call(() {
                errorMessage = errorText(error);
              });
            }
          },
          child: const Text('Process Refund'),
        ),
      ],
    );

    reasonController.dispose();
    referenceController.dispose();
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
  }

  Future<void> _showRefundRestockDialog(
    BuildContext context,
    OrderRecord order,
  ) async {
    List<RefundRestockCandidate> candidates;

    try {
      candidates = await widget.orderRepository.getRefundRestockCandidates(
        order.id,
      );
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
      return;
    }

    if (!context.mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No refunded items are available for review.'),
        ),
      );
      return;
    }

    final pending = candidates
        .where((item) => item.eligibleForRestock && !item.restockApproved)
        .toList();

    await showPrototypeDialog(
      context: context,
      title: 'Returned Stock • ${order.id}',
      width: 680,
      content: SizedBox(
        height: 430,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gray100,
                  borderRadius: AppRadius.all,
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Text(
                  'Only returned finished goods can be added back to stock. '
                  'Prepared food and recipe-based drinks are not automatically '
                  'restocked because their ingredients were already consumed.',
                  style: AppTextStyles.body,
                ),
              ),
              const SizedBox(height: 16),
              for (final item in candidates)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.all,
                    border: Border.all(color: AppColors.gray200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemName,
                              style: AppTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.variantName.isEmpty
                                  ? '${_refundQty(item.refundedQuantity)} refunded'
                                  : '${item.variantName} • ${_refundQty(item.refundedQuantity)} refunded',
                              style: AppTextStyles.caption,
                            ),
                            if (item.inventoryItemName.isNotEmpty)
                              Text(
                                'Inventory: ${item.inventoryItemName}',
                                style: AppTextStyles.caption,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (item.restockApproved)
                        const StatusBadge('Restocked')
                      else if (!item.eligibleForRestock)
                        const StatusBadge('Not Restockable')
                      else
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _confirmRefundRestock(context, order, item);
                          },
                          child: const Text('Restock'),
                        ),
                    ],
                  ),
                ),
              if (pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'There are no finished goods waiting for restock approval.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRefundRestock(
    BuildContext context,
    OrderRecord order,
    RefundRestockCandidate item,
  ) async {
    final notesController = TextEditingController();
    String? errorMessage;
    StateSetter? dialogSetState;

    await showPrototypeDialog(
      context: context,
      title: 'Approve Restock',
      width: 520,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          dialogSetState = setDialogState;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Item', item.itemName),
              if (item.variantName.isNotEmpty)
                _detailRow('Variant', item.variantName),
              _detailRow('Quantity', _refundQty(item.refundedQuantity)),
              _detailRow('Inventory Item', item.inventoryItemName),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Restock Notes',
                  hintText: 'Optional condition or return notes...',
                ),
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
            try {
              await widget.orderRepository.approveRefundItemRestock(
                item.refundItemId,
                notes: notesController.text.trim(),
              );

              if (!context.mounted) return;
              Navigator.pop(context);
              _notifyDataChanged();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${item.itemName} was returned to inventory.'),
                ),
              );
            } on PostgrestException catch (error) {
              dialogSetState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              dialogSetState?.call(() {
                errorMessage = errorText(error);
              });
            }
          },
          child: const Text('Approve Restock'),
        ),
      ],
    );

    notesController.dispose();
  }

  Future<void> _showManagerAuthorization(
    BuildContext context, {
    required OrderRecord order,
    required _OrderAction action,
  }) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final reasonController = TextEditingController();
    String? errorMessage;
    StateSetter? updateDialogState;

    final actionName = action == _OrderAction.refund ? 'Refund' : 'Void';

    await showPrototypeDialog(
      context: context,
      title: '$actionName Order ${order.id}',
      width: 540,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppRadius.all,
                ),
                child: Text(
                  'Your signed-in Manager/Admin account will authorize this '
                  '${actionName.toLowerCase()} action.',
                  style: AppTextStyles.body,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                onChanged: (_) {
                  updateDialogState?.call(() => errorMessage = null);
                },
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'Enter the reason for this action',
                ),
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
            final reason = reasonController.text.trim();

            if (reason.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'A reason is required.';
              });
              return;
            }

            try {
              if (action == _OrderAction.refund) {
                await widget.orderRepository.refundOrder(
                  clientRequestId: requestId,
                  order.id,
                  reason: reason,
                );
              } else {
                await widget.orderRepository.voidOrder(
                  order.id,
                  reason: reason,
                );
              }

              if (!context.mounted) return;

              Navigator.pop(context);
              _notifyDataChanged();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Order ${order.id} ${actionName.toLowerCase()} completed.',
                  ),
                ),
              );
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = errorText(error);
              });
            }
          },
          child: Text('Confirm $actionName'),
        ),
      ],
    );

    reasonController.dispose();
  }

  Future<void> _showReceipt(BuildContext context, OrderRecord order) async {
    await showPrototypeDialog(
      context: context,
      title: 'Receipt',
      width: 560,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: ReceiptHeader()),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${order.id} · ${order.dateTimeLabel}',
                style: AppTextStyles.caption,
              ),
            ),
            if (order.invoiceNumber.isNotEmpty) ...[
              const SizedBox(height: 3),
              Center(
                child: Text(
                  'Invoice ${order.invoiceNumber}',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _detailRow('Date & Time', _formatFullDateTime(order.createdAt)),
            _detailRow('Customer / Table', _orderReference(order)),
            _detailRow('Order Type', order.type),
            _detailRow('Handled by', order.employee),
            if (order.deliveryReference.isNotEmpty)
              _detailRow('Delivery Reference', order.deliveryReference),
            const Divider(height: 28),
            if (order.items.isEmpty)
              Text(
                'Item details are not available for this sample order.',
                style: AppTextStyles.body.copyWith(color: AppColors.gray500),
              )
            else
              for (final item in order.items)
                OrderLine(item: item, total: _moneyDouble(item.lineTotal)),
            const Divider(height: 28),
            if (order.discountAmount > 0) ...[
              _detailRow('Subtotal', _moneyDouble(order.subtotal)),
              _detailRow(
                order.discountName.isEmpty
                    ? 'Discount'
                    : 'Discount (${order.discountName})',
                '-${_moneyDouble(order.discountAmount)}',
              ),
            ],
            _detailRow('Total', _moneyDouble(order.amount), emphasized: true),
            _detailRow(
              'Payment',
              order.paymentMethod.isEmpty
                  ? 'Not paid yet'
                  : order.paymentMethod,
            ),
            if (order.paymentMethod.isNotEmpty) ...[
              _detailRow('Amount Received', _moneyDouble(order.amountReceived)),
              _detailRow('Change', _moneyDouble(order.changeAmount)),
            ],
            if (order.refundedAmount > 0)
              _detailRow('Refunded', _moneyDouble(-order.refundedAmount)),
            const SizedBox(height: 12),
            Center(child: StatusBadge(order.status)),
            const SizedBox(height: 8),
            Center(child: CopyReceiptButton(order: order)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized ? AppTextStyles.bodyMedium : AppTextStyles.body,
            ),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: emphasized ? AppTextStyles.h3 : AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _moneyDouble(double value) => formatReportMoney(value);

  String _refundQty(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  String _orderReference(OrderRecord order) {
    if (order.type == 'Dine In' && order.tableNumber.trim().isNotEmpty) {
      if (order.customerName.trim().isNotEmpty) {
        return 'Table ${order.tableNumber} • ${order.customerName}';
      }
      return 'Table ${order.tableNumber}';
    }

    if (order.customerName.trim().isNotEmpty) {
      return order.customerName;
    }

    return 'Walk-in';
  }

  String _formatOrderDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final orderDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (orderDay == today) {
      return _formatTime(dateTime);
    }

    return '${_formatDate(dateTime)}\n${_formatTime(dateTime)}';
  }

  String _formatFullDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} • ${_formatTime(dateTime)}';
  }

  String _formatDate(DateTime dateTime) {
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

    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _formatTime(DateTime dateTime) {
    int hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour %= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }
}

enum _OrderAction { refund, voidOrder }
