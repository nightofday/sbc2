import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/state/inventory_refresh_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../models/inventory_item.dart';
import '../../models/inventory_reference.dart';
import '../../models/request_id.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

enum InventoryView { overview, release, disposal, adjustment, history }

class InventoryScreen extends StatefulWidget {
  final InventoryRepository inventoryRepository;
  final InventoryRefreshController? refreshController;
  final bool canManageInventory;
  final InventoryView view;

  const InventoryScreen({
    super.key,
    required this.inventoryRepository,
    this.refreshController,
    required this.canManageInventory,
    this.view = InventoryView.overview,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<InventoryItem>> _itemsFuture;
  late Future<List<InventoryMovementRecord>> _movementsFuture;
  late Future<List<InventoryMovementRecord>> _recentMovementsFuture;
  late Future<List<StockOutSummary>> _stockOutsFuture;

  String _searchQuery = '';
  String _categoryFilter = 'All Categories';
  String _stockFilter = 'All Stock';
  String _historySearch = '';
  String _historyItemId = '';
  String _historyMovementType = '';
  String _historyDateRange = 'All Dates';

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshController?.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
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
    _itemsFuture = widget.inventoryRepository.getInventoryItems();
    _recentMovementsFuture = widget.view == InventoryView.overview
        ? widget.inventoryRepository.getAllRecentMovements()
        : Future.value(const <InventoryMovementRecord>[]);
    _movementsFuture = widget.view == InventoryView.history
        ? widget.inventoryRepository.getAllRecentMovements(limit: 250)
        : Future.value(const <InventoryMovementRecord>[]);
    _stockOutsFuture = widget.view == InventoryView.release
        ? widget.inventoryRepository.getStockOuts(limit: 100)
        : Future.value(const <StockOutSummary>[]);
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
    return switch (widget.view) {
      InventoryView.overview => _buildOverviewPage(),
      InventoryView.release => _buildReleasePage(),
      InventoryView.disposal => _buildDisposalPage(),
      InventoryView.adjustment => _buildAdjustmentPage(),
      InventoryView.history => _buildHistoryPage(),
    };
  }

  Widget _buildOverviewPage() {
    return AppPage(
      title: 'Stock Overview',
      subtitle: 'Monitor usable, expired, and total on-hand quantities.',
      action: widget.canManageInventory
          ? ElevatedButton.icon(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Item'),
            )
          : null,
      child: FutureBuilder<List<InventoryItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <InventoryItem>[];
          final categories =
              items
                  .map((item) => item.category)
                  .where((value) => value.trim().isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          if (_categoryFilter != 'All Categories' &&
              !categories.contains(_categoryFilter)) {
            _categoryFilter = 'All Categories';
          }

          final filtered = _filterItems(items);

          return Column(
            children: [
              _buildFilters(categories),
              const SizedBox(height: 18),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                    ? _buildError(snapshot.error)
                    : filtered.isEmpty
                    ? Center(
                        child: Text(
                          items.isEmpty
                              ? 'No inventory items yet.'
                              : 'No inventory items match the filters.',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      )
                    : _buildInventoryContent(filtered, items),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReleasePage() {
    return AppPage(
      title: 'Release Supplies',
      subtitle:
          'Post one traceable stock-out transaction for multiple supplies.',
      action: ElevatedButton.icon(
        onPressed: _showStockOutDialog,
        icon: const Icon(Icons.output_outlined, size: 18),
        label: const Text('New Release'),
      ),
      child: FutureBuilder<List<StockOutSummary>>(
        future: _stockOutsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildError(snapshot.error);

          final releases = snapshot.data ?? const <StockOutSummary>[];
          if (releases.isEmpty) {
            return _buildEmptyState(
              icon: Icons.output_outlined,
              title: 'No supply releases yet',
              message:
                  'Create a release when countable supplies leave storage.',
            );
          }

          return SingleChildScrollView(
            child: DataTableCard(
              headers: const [
                'Document',
                'Date',
                'Purpose',
                'Reference',
                'Items',
                'Recorded By',
                'Status',
                'Action',
              ],
              flexes: const [2, 2, 3, 2, 1, 2, 1, 2],
              rows: releases
                  .map(
                    (release) => [
                      Text(
                        'SO-${release.number}',
                        style: AppTextStyles.bodyMedium,
                      ),
                      Text(
                        _formatDateTime(release.occurredAt),
                        style: AppTextStyles.body,
                      ),
                      Text(release.purpose, style: AppTextStyles.body),
                      Text(
                        release.referenceNumber.isEmpty
                            ? '—'
                            : release.referenceNumber,
                        style: AppTextStyles.body,
                      ),
                      Text('${release.lineCount}', style: AppTextStyles.body),
                      Text(
                        release.recordedByName.isEmpty
                            ? '—'
                            : release.recordedByName,
                        style: AppTextStyles.body,
                      ),
                      StatusBadge(release.status),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            release.status == 'POSTED' &&
                                widget.canManageInventory
                            ? OutlinedButton(
                                onPressed: () => _voidStockOut(release),
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

  Widget _buildDisposalPage() {
    return AppPage(
      title: 'Dispose Stock',
      subtitle:
          'Record expired, damaged, or spoiled stock against its exact lot.',
      child: FutureBuilder<List<InventoryItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildError(snapshot.error);

          final items =
              (snapshot.data ?? const <InventoryItem>[])
                  .where((item) => item.currentQuantity > 0)
                  .toList()
                ..sort((a, b) {
                  final expiredOrder = b.expiredQuantity.compareTo(
                    a.expiredQuantity,
                  );
                  return expiredOrder != 0
                      ? expiredOrder
                      : a.name.compareTo(b.name);
                });

          if (items.isEmpty) {
            return _buildEmptyState(
              icon: Icons.delete_sweep_outlined,
              title: 'No stock available for disposal',
              message: 'Only lots with remaining on-hand stock appear here.',
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWorkflowNotice(
                  'Choose an item, review its lots, then dispose only the '
                  'affected batch. Expired quantities remain on hand until '
                  'this disposal is posted.',
                ),
                const SizedBox(height: 16),
                DataTableCard(
                  headers: const [
                    'Item',
                    'Category',
                    'Usable',
                    'Expired',
                    'On Hand',
                    'Action',
                  ],
                  flexes: const [3, 2, 2, 2, 2, 2],
                  rows: items
                      .map(
                        (item) => [
                          Text(item.name, style: AppTextStyles.bodyMedium),
                          Text(item.category, style: AppTextStyles.body),
                          Text(item.usableStock, style: AppTextStyles.body),
                          Text(
                            item.expiredStock,
                            style: AppTextStyles.body.copyWith(
                              color: item.expiredQuantity > 0
                                  ? AppColors.error
                                  : AppColors.gray700,
                            ),
                          ),
                          Text(item.stock, style: AppTextStyles.body),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: () => _showLots(item),
                              child: const Text('Review Lots'),
                            ),
                          ),
                        ],
                      )
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdjustmentPage() {
    return AppPage(
      title: 'Stock Adjustment',
      subtitle: 'Correct a verified physical-count difference with a required reason.',
      child: FutureBuilder<List<InventoryItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildError(snapshot.error);

          final items = snapshot.data ?? const <InventoryItem>[];
          if (items.isEmpty) {
            return _buildEmptyState(
              icon: Icons.tune,
              title: 'No inventory items available',
              message: 'Add an inventory item before recording adjustments.',
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWorkflowNotice(
                  'Use adjustments only after a physical count or a confirmed '
                  'recording error. Disposal and normal supply releases must '
                  'use their dedicated workflows.',
                ),
                const SizedBox(height: 16),
                DataTableCard(
                  headers: const [
                    'Item',
                    'Category',
                    'Usable',
                    'On Hand',
                    'Action',
                  ],
                  flexes: const [3, 2, 2, 2, 2],
                  rows: items
                      .map(
                        (item) => [
                          Text(item.name, style: AppTextStyles.bodyMedium),
                          Text(item.category, style: AppTextStyles.body),
                          Text(item.usableStock, style: AppTextStyles.body),
                          Text(item.stock, style: AppTextStyles.body),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: () => _showAdjustmentDialog(item),
                              child: const Text('Adjust'),
                            ),
                          ),
                        ],
                      )
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryPage() {
    return AppPage(
      title: 'Inventory History',
      subtitle:
          'Trace stock movements by item, movement type, date, or reference.',
      child: FutureBuilder<List<InventoryItem>>(
        future: _itemsFuture,
        builder: (context, itemSnapshot) {
          if (itemSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (itemSnapshot.hasError) return _buildError(itemSnapshot.error);

          final items = itemSnapshot.data ?? const <InventoryItem>[];
          return FutureBuilder<List<InventoryMovementRecord>>(
            future: _movementsFuture,
            builder: (context, movementSnapshot) {
              if (movementSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (movementSnapshot.hasError) {
                return _buildError(movementSnapshot.error);
              }

              final movements =
                  movementSnapshot.data ?? const <InventoryMovementRecord>[];
              final filtered = _filterMovements(movements, items);
              final itemById = {for (final item in items) item.id: item};

              return Column(
                children: [
                  _buildHistoryFilters(items),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState(
                            icon: Icons.history,
                            title: 'No matching movements',
                            message: 'Try changing the history filters or reference search.',
                          )
                        : SingleChildScrollView(
                            child: DataTableCard(
                              headers: const [
                                'Date',
                                'Item',
                                'Movement',
                                'Quantity',
                                'Source / Reference',
                                'Reason',
                              ],
                              flexes: const [2, 3, 2, 2, 3, 3],
                              rows: filtered
                                  .map(
                                    (movement) => [
                                      Text(
                                        _formatDateTime(movement.createdAt),
                                        style: AppTextStyles.body,
                                      ),
                                      Text(
                                        itemById[movement.inventoryItemId]
                                                ?.name ??
                                            'Inventory item',
                                        style: AppTextStyles.bodyMedium,
                                      ),
                                      Text(
                                        _movementLabel(movement.movementType),
                                        style: AppTextStyles.body,
                                      ),
                                      Text(
                                        _signedQuantity(
                                          movement.quantityDelta,
                                          itemById[movement.inventoryItemId]
                                                  ?.baseUomCode ??
                                              '',
                                        ),
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: movement.quantityDelta >= 0
                                                  ? AppColors.success
                                                  : AppColors.primary,
                                            ),
                                      ),
                                      Text(
                                        _movementReference(movement).isEmpty
                                            ? '—'
                                            : _movementReference(movement),
                                        style: AppTextStyles.body,
                                      ),
                                      Text(
                                        movement.reason.isEmpty
                                            ? '—'
                                            : movement.reason,
                                        style: AppTextStyles.body,
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
          );
        },
      ),
    );
  }

  Widget _buildHistoryFilters(List<InventoryItem> items) {
    const movementTypes = [
      'MANUAL_IN',
      'MANUAL_OUT',
      'PURCHASE_RECEIPT',
      'SALE_CONSUMPTION',
      'STOCK_COUNT_ADJUSTMENT',
      'WASTE',
      'DAMAGED',
      'EXPIRED',
      'COMPLIMENTARY',
      'STAFF_MEAL',
    ];
    const dateRanges = ['All Dates', 'Today', 'Last 7 Days', 'Last 30 Days'];

    final search = TextField(
      onChanged: (value) => setState(() => _historySearch = value),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search reference, reason, or item...',
      ),
    );
    final item = DropdownButtonFormField<String>(
      initialValue: _historyItemId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Item'),
      items: [
        const DropdownMenuItem(value: '', child: Text('All Items')),
        for (final item in items)
          DropdownMenuItem(
            value: item.id,
            child: Text(item.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _historyItemId = value);
      },
    );
    final movement = DropdownButtonFormField<String>(
      initialValue: _historyMovementType,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Movement'),
      items: [
        const DropdownMenuItem(value: '', child: Text('All Movements')),
        for (final type in movementTypes)
          DropdownMenuItem(value: type, child: Text(_movementLabel(type))),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _historyMovementType = value);
      },
    );
    final date = DropdownButtonFormField<String>(
      initialValue: _historyDateRange,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Date'),
      items: [
        for (final range in dateRanges)
          DropdownMenuItem(value: range, child: Text(range)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _historyDateRange = value);
      },
    );

    return ResponsiveFilterBar(
      primary: search,
      filters: [item, movement, date],
      filterWidths: const [220, 190, 160],
      breakpoint: 900,
      gap: 10,
    );
  }

  List<InventoryMovementRecord> _filterMovements(
    List<InventoryMovementRecord> movements,
    List<InventoryItem> items,
  ) {
    final query = _historySearch.trim().toLowerCase();
    final itemById = {for (final item in items) item.id: item};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return movements.where((movement) {
      if (_historyItemId.isNotEmpty &&
          movement.inventoryItemId != _historyItemId) {
        return false;
      }
      if (_historyMovementType.isNotEmpty &&
          movement.movementType != _historyMovementType) {
        return false;
      }

      final movementDate = DateTime(
        movement.createdAt.year,
        movement.createdAt.month,
        movement.createdAt.day,
      );
      final minimumDate = switch (_historyDateRange) {
        'Today' => today,
        'Last 7 Days' => today.subtract(const Duration(days: 6)),
        'Last 30 Days' => today.subtract(const Duration(days: 29)),
        _ => null,
      };
      if (minimumDate != null && movementDate.isBefore(minimumDate)) {
        return false;
      }

      if (query.isEmpty) return true;
      final searchable = [
        itemById[movement.inventoryItemId]?.name ?? '',
        _movementLabel(movement.movementType),
        movement.reason,
        movement.sourceDocumentNumber,
        movement.externalReferenceNumber,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Widget _buildWorkflowNotice(String message) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.gray500, size: 40),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.gray500),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(List<String> categories) {
    final search = TextField(
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search item or SKU...',
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
          DropdownMenuItem(value: category, child: Text(category)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _categoryFilter = value);
      },
    );
    final stock = DropdownButtonFormField<String>(
      initialValue: _stockFilter,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'All Stock', child: Text('All Stock')),
        DropdownMenuItem(value: 'Low Stock', child: Text('Low Stock')),
        DropdownMenuItem(value: 'Expiring Soon', child: Text('Expiring Soon')),
        DropdownMenuItem(value: 'Expired', child: Text('Expired')),
        DropdownMenuItem(value: 'In Stock', child: Text('In Stock')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _stockFilter = value);
      },
    );

    return ResponsiveFilterBar(
      primary: search,
      filters: [category, stock],
      filterWidths: const [220, 180],
    );
  }

  Widget _buildInventoryContent(
    List<InventoryItem> filtered,
    List<InventoryItem> allItems,
  ) {
    final table = DataTableCard(
      headers: const [
        'Item',
        'Category',
        'Availability',
        'Reorder Level',
        'Next Expiry',
        'Status',
      ],
      flexes: const [3, 2, 2, 2, 2, 2],
      rows: filtered
          .map(
            (item) => [
              InkWell(
                onTap: () => _showItemDetails(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    if (item.sku.isNotEmpty)
                      Text(item.sku, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Text(item.category, style: AppTextStyles.body),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usable: ${item.usableStock}',
                    style: AppTextStyles.bodyMedium,
                  ),
                  Text(
                    'On hand: ${item.stock}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                  if (item.expiredQuantity > 0)
                    Text(
                      'Expired: ${item.expiredStock}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
              Text(
                _quantityWithUnit(item.reorderLevel, item.baseUomCode),
                style: AppTextStyles.body,
              ),
              Text(item.expiration, style: AppTextStyles.body),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(item.status),
              ),
            ],
          )
          .toList(),
    );
    final activity = _buildRecentActivity(allItems);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1080) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: table)),
              const SizedBox(width: 18),
              SizedBox(
                width: 330,
                child: SingleChildScrollView(child: activity),
              ),
            ],
          );
        }

        return SingleChildScrollView(
          child: Column(
            children: [table, const SizedBox(height: 18), activity],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivity(List<InventoryItem> items) {
    final itemById = {for (final item in items) item.id: item};

    return SectionCard(
      child: FutureBuilder<List<InventoryMovementRecord>>(
        future: _recentMovementsFuture,
        builder: (context, snapshot) {
          final movements = snapshot.data ?? const <InventoryMovementRecord>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recent Activity', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text(
                'Latest inventory ledger entries',
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                Text(
                  'Unable to load recent activity.',
                  style: AppTextStyles.body.copyWith(color: AppColors.gray500),
                )
              else if (movements.isEmpty)
                Text(
                  'No stock movements recorded yet.',
                  style: AppTextStyles.body.copyWith(color: AppColors.gray500),
                )
              else
                for (int index = 0; index < movements.length; index++) ...[
                  _buildActivityRow(movements[index], itemById),
                  if (index != movements.length - 1)
                    const Divider(height: 20, color: AppColors.gray200),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivityRow(
    InventoryMovementRecord movement,
    Map<String, InventoryItem> itemById,
  ) {
    final item = itemById[movement.inventoryItemId];
    final positive = movement.quantityDelta >= 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: positive ? AppColors.gray100 : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            positive ? Icons.south_west : Icons.north_east,
            size: 17,
            color: positive ? AppColors.success : AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item?.name ?? 'Inventory item',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium,
              ),
              Text(
                '${_movementLabel(movement.movementType)} • '
                '${_formatDateTime(movement.createdAt)}',
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
              if (_movementReference(movement).isNotEmpty)
                Text(
                  _movementReference(movement),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _signedQuantity(movement.quantityDelta, item?.baseUomCode ?? ''),
          style: AppTextStyles.bodyMedium.copyWith(
            color: positive ? AppColors.success : AppColors.primary,
          ),
        ),
      ],
    );
  }

  List<InventoryItem> _filterItems(List<InventoryItem> items) {
    final query = _searchQuery.trim().toLowerCase();

    return items.where((item) {
      final searchMatches =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.sku.toLowerCase().contains(query);

      final categoryMatches =
          _categoryFilter == 'All Categories' ||
          item.category == _categoryFilter;

      final stockMatches =
          _stockFilter == 'All Stock' || item.status == _stockFilter;

      return searchMatches && categoryMatches && stockMatches;
    }).toList();
  }

  Widget _buildError(Object? error) {
    return Center(
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.primary, size: 40),
            const SizedBox(height: 12),
            const Text('Unable to load inventory', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Future<void> _voidStockOut(StockOutSummary release) async {
    final requestId = newRequestId();

    final voided = await showReasonDialog(
      context: context,
      title: 'Void Release SO-${release.number}',
      message:
          'This returns every quantity on this release to the stock it came '
          'from. The release stays on record as voided.',
      confirmLabel: 'Void Release',
      onConfirm: (reason) async {
        try {
          await widget.inventoryRepository.voidStockOut(
            stockOutId: release.id,
            reason: reason,
            clientRequestId: requestId,
          );
          return null;
        } on PostgrestException catch (error) {
          return error.message;
        } catch (error) {
          return error.toString();
        }
      },
    );

    if (!voided || !mounted) return;
    _refresh();
    _showMessage('Supply release SO-${release.number} voided.');
  }

  Future<void> _showItemDetails(InventoryItem item) async {
    final latest =
        await widget.inventoryRepository.getInventoryItemById(item.id) ?? item;
    final movements = await widget.inventoryRepository.getRecentMovements(
      item.id,
    );

    if (!mounted) return;

    await showPrototypeDialog(
      context: context,
      title: latest.name,
      width: 640,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(latest.status),
                if (latest.sku.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(latest.sku, style: AppTextStyles.caption),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _detailRow('Category', latest.category),
            _detailRow('Usable Stock', latest.usableStock),
            _detailRow('Expired Stock', latest.expiredStock),
            _detailRow('Total On Hand', latest.stock),
            _detailRow(
              'Reorder Level',
              _quantityWithUnit(latest.reorderLevel, latest.baseUomCode),
            ),
            _detailRow(
              'Expiry Tracking',
              latest.trackExpiry ? 'Enabled' : 'Disabled',
            ),
            _detailRow('Next Usable Expiration', latest.expiration),
            const Divider(height: 28),
            const Text('Recent Stock Movements', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            if (movements.isEmpty)
              Text(
                'No stock movements recorded yet.',
                style: AppTextStyles.body.copyWith(color: AppColors.gray500),
              )
            else
              for (final movement in movements)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _movementLabel(movement.movementType),
                              style: AppTextStyles.body,
                            ),
                            if (_movementReference(movement).isNotEmpty)
                              Text(
                                _movementReference(movement),
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.gray500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _signedQuantity(
                          movement.quantityDelta,
                          latest.baseUomCode,
                        ),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: movement.quantityDelta >= 0
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 120,
                        child: Text(
                          _formatDateTime(movement.createdAt),
                          textAlign: TextAlign.right,
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (widget.canManageInventory)
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _showLots(latest);
            },
            child: const Text('Manage Lots'),
          ),
        if (widget.canManageInventory && latest.currentQuantity <= 0)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _confirmArchiveItem(latest);
            },
            icon: const Icon(Icons.archive_outlined, size: 17),
            label: const Text('Archive'),
          ),
      ],
    );
  }

  Future<void> _confirmArchiveItem(InventoryItem item) async {
    await showPrototypeDialog(
      context: context,
      title: 'Archive Inventory Item',
      width: 460,
      content: Text(
        'Archive ${item.name}? It will be removed from active inventory, '
        'while its ledger history remains available for audit records.',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            try {
              await widget.inventoryRepository.deleteInventoryItem(item.id);

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Inventory item archived.');
            } on PostgrestException catch (error) {
              if (mounted) _showMessage(error.message);
            } catch (error) {
              if (mounted) _showMessage(error.toString());
            }
          },
          icon: const Icon(Icons.archive_outlined, size: 17),
          label: const Text('Archive Item'),
        ),
      ],
    );
  }

  Future<void> _showLots(InventoryItem item) async {
    List<InventoryLotRecord> lots;

    try {
      lots = await widget.inventoryRepository.getLots(item.id);
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
      title: 'Inventory Lots — ${item.name}',
      width: 720,
      content: SizedBox(
        height: 390,
        child: lots.isEmpty
            ? Center(
                child: Text(
                  'No available lots for this item.',
                  style: AppTextStyles.body.copyWith(color: AppColors.gray500),
                ),
              )
            : ListView.separated(
                itemCount: lots.length,
                separatorBuilder: (_, _) => const Divider(height: 18),
                itemBuilder: (_, index) {
                  final lot = lots[index];
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lot.lotCode.isEmpty
                                  ? 'Unlabeled Lot'
                                  : lot.lotCode,
                              style: AppTextStyles.bodyMedium,
                            ),
                            Text(
                              'Received ${_formatDate(lot.receivedAt)}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _quantityWithUnit(
                            lot.remainingQuantity,
                            lot.unitCode,
                          ),
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          lot.expirationDate == null
                              ? 'No expiry'
                              : _formatDate(lot.expirationDate!),
                          style: AppTextStyles.body,
                        ),
                      ),
                      if (widget.canManageInventory)
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showLotDisposal(item, lot);
                          },
                          child: const Text('Dispose'),
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
      ],
    );
  }

  Future<void> _showLotDisposal(
    InventoryItem item,
    InventoryLotRecord lot,
  ) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiration = lot.expirationDate;
    String movementType = expiration != null && expiration.isBefore(today)
        ? 'EXPIRED'
        : 'WASTE';
    String? errorMessage;
    StateSetter? dialogSetState;

    await showPrototypeDialog(
      context: context,
      title: 'Dispose Lot — ${item.name}',
      width: 540,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          dialogSetState = setDialogState;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                'Lot',
                lot.lotCode.isEmpty ? 'Unlabeled Lot' : lot.lotCode,
              ),
              _detailRow(
                'Available',
                _quantityWithUnit(lot.remainingQuantity, lot.unitCode),
              ),
              _detailRow(
                'Expiration',
                lot.expirationDate == null
                    ? '—'
                    : _formatDate(lot.expirationDate!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: movementType,
                decoration: const InputDecoration(labelText: 'Reason Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'WASTE',
                    child: Text('Waste / Spoilage'),
                  ),
                  DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged')),
                  DropdownMenuItem(value: 'EXPIRED', child: Text('Expired')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => movementType = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity (${lot.unitCode})',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason / Notes *',
                  hintText: 'Explain why this exact lot is being disposed',
                ),
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
            final quantity = double.tryParse(quantityController.text.trim());
            final reason = reasonController.text.trim();

            if (quantity == null ||
                quantity <= 0 ||
                quantity > lot.remainingQuantity) {
              dialogSetState?.call(() {
                errorMessage =
                    'Enter a quantity between 0 and ${_quantityWithUnit(lot.remainingQuantity, lot.unitCode)}.';
              });
              return;
            }
            if (reason.isEmpty) {
              dialogSetState?.call(() {
                errorMessage =
                    'A disposal reason is required for traceability.';
              });
              return;
            }

            try {
              await widget.inventoryRepository.disposeLot(
                clientRequestId: requestId,
                inventoryLotId: lot.id,
                movementType: movementType,
                quantity: quantity,
                reason: reason,
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Lot disposal recorded.');
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
          child: const Text('Record Disposal'),
        ),
      ],
    );

    quantityController.dispose();
    reasonController.dispose();
  }

  Future<void> _showAdjustmentDialog(InventoryItem item) async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final unitCostController = TextEditingController(text: '0');
    String movementType = 'STOCK_COUNT_ADJUSTMENT';
    DateTime? expirationDate;
    String? errorMessage;
    bool isSaving = false;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Adjust Stock — ${item.name}',
      width: 560,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;
          final isIncrease = movementType == 'MANUAL_IN';

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Current Usable', item.usableStock),
                _detailRow('Current On Hand', item.stock),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: movementType,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment Direction *',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'STOCK_COUNT_ADJUSTMENT',
                      child: Text('Decrease to match physical count'),
                    ),
                    DropdownMenuItem(
                      value: 'MANUAL_IN',
                      child: Text('Increase to match physical count'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      movementType = value;
                      expirationDate = null;
                      errorMessage = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Adjustment Quantity (${item.baseUomCode}) *',
                    helperText:
                        'Enter the difference, not the final physical count.',
                  ),
                ),
                if (isIncrease) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: unitCostController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit Cost',
                      prefixText: '₱',
                    ),
                  ),
                  if (item.trackExpiry) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: dialogContext,
                            initialDate: DateTime.now(),
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
                              ? 'Select Expiration Date *'
                              : 'Expiration: ${_formatDate(expirationDate!)}',
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment Reason *',
                    hintText: 'Example: Physical count variance on closing',
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            if (isSaving) return;

            final quantity = double.tryParse(quantityController.text.trim());
            final unitCost =
                double.tryParse(unitCostController.text.trim()) ?? -1;
            final reason = reasonController.text.trim();
            final isIncrease = movementType == 'MANUAL_IN';

            if (quantity == null || quantity <= 0) {
              updateDialogState?.call(() {
                errorMessage = 'Adjustment quantity must be greater than zero.';
              });
              return;
            }
            if (!isIncrease && quantity > item.currentQuantity) {
              updateDialogState?.call(() {
                errorMessage =
                    'The decrease cannot exceed the current on-hand stock.';
              });
              return;
            }
            if (reason.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'An adjustment reason is required.';
              });
              return;
            }
            if (unitCost < 0) {
              updateDialogState?.call(() {
                errorMessage = 'Unit cost cannot be negative.';
              });
              return;
            }
            if (isIncrease && item.trackExpiry && expirationDate == null) {
              updateDialogState?.call(() {
                errorMessage = 'Expiration date is required for this item.';
              });
              return;
            }

            updateDialogState?.call(() => isSaving = true);

            try {
              await widget.inventoryRepository.adjustStock(
                clientRequestId: requestId,
                inventoryItemId: item.id,
                movementType: movementType,
                quantity: quantity,
                reason: reason,
                expirationDate: expirationDate,
                unitCostBase: isIncrease ? unitCost : 0,
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Stock adjustment recorded in inventory history.');
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
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Record Adjustment'),
        ),
      ],
    );

    quantityController.dispose();
    reasonController.dispose();
    unitCostController.dispose();
  }

  Future<void> _showStockOutDialog() async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final results = await Future.wait([
      widget.inventoryRepository.getInventoryItems(),
      widget.inventoryRepository.getUnits(),
    ]);

    if (!mounted) return;

    final items = (results[0] as List<InventoryItem>)
        .where((item) => item.usableQuantity > 0)
        .toList();
    final units = results[1] as List<InventoryUnitOption>;

    if (items.isEmpty || units.isEmpty) {
      _showMessage(
        'No usable supplies are available. Expired stock must be recorded '
        'through Manage Lots and Dispose.',
      );
      return;
    }

    const purposeOptions = [
      'Released to service counter',
      'Operational use',
      'Complimentary',
      'Staff use',
      'Other',
    ];
    String selectedPurpose = purposeOptions.first;
    final otherPurposeController = TextEditingController();
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    final lines = <_StockOutDraftLine>[
      _StockOutDraftLine.fromItem(items.first),
    ];
    String? errorMessage;
    bool isSaving = false;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Release Multiple Supplies',
      width: 820,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return SizedBox(
            height: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record one stock-out transaction containing every supply '
                    'released for the same purpose.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPurpose,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Purpose / Destination *',
                    ),
                    items: purposeOptions
                        .map(
                          (purpose) => DropdownMenuItem(
                            value: purpose,
                            child: Text(purpose),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedPurpose = value;
                        errorMessage = null;
                      });
                    },
                  ),
                  if (selectedPurpose == 'Other') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherPurposeController,
                      decoration: const InputDecoration(
                        labelText: 'Other Purpose / Destination *',
                        hintText:
                            'Describe where or why supplies were released',
                      ),
                      onChanged: (_) => setDialogState(() {
                        errorMessage = null;
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      hintText: 'Optional request, log, or handover reference',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Supplies to release',
                          style: AppTextStyles.h3,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            lines.add(_StockOutDraftLine.fromItem(items.first));
                            errorMessage = null;
                          });
                        },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Add Supply'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (int index = 0; index < lines.length; index++) ...[
                    _buildStockOutLine(
                      line: lines[index],
                      index: index,
                      items: items,
                      units: units,
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
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Notes',
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
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            if (isSaving) return;

            final purpose = selectedPurpose == 'Other'
                ? otherPurposeController.text.trim()
                : selectedPurpose;
            final selectedIds = lines.map((line) => line.itemId).toList();
            final duplicateItems =
                selectedIds.toSet().length != selectedIds.length;

            final inputs = <StockOutLineInput>[];
            for (final line in lines) {
              final selectedItem = items.firstWhere(
                (item) => item.id == line.itemId,
              );
              final quantity = double.tryParse(
                line.quantityController.text.trim(),
              );
              final conversion = line.unitId == selectedItem.baseUomId
                  ? 1.0
                  : double.tryParse(line.conversionController.text.trim());
              if (quantity == null ||
                  quantity <= 0 ||
                  conversion == null ||
                  conversion <= 0) {
                updateDialogState?.call(() {
                  errorMessage = 'Every supply needs a quantity and a conversion greater than zero.';
                });
                return;
              }

              final deduction = quantity * conversion;
              if (deduction > selectedItem.usableQuantity) {
                updateDialogState?.call(() {
                  errorMessage =
                      '${selectedItem.name} only has '
                      '${selectedItem.usableStock} of usable stock.';
                });
                return;
              }

              inputs.add(
                StockOutLineInput(
                  inventoryItemId: line.itemId,
                  issueUomId: line.unitId,
                  issueQuantity: quantity,
                  baseQuantityPerIssueUnit: conversion,
                  notes: line.notesController.text,
                ),
              );
            }

            if (purpose.isEmpty || duplicateItems) {
              updateDialogState?.call(() {
                errorMessage = purpose.isEmpty
                    ? 'Enter the purpose or destination of this release.'
                    : 'Each supply can appear only once in a stock-out transaction.';
              });
              return;
            }

            updateDialogState?.call(() => isSaving = true);

            try {
              await widget.inventoryRepository.createStockOut(
                clientRequestId: requestId,
                purpose: purpose,
                items: inputs,
                referenceNumber: referenceController.text,
                notes: notesController.text,
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
              _showMessage('Supply release posted successfully.');
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
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Post Stock Out'),
        ),
      ],
    );

    otherPurposeController.dispose();
    referenceController.dispose();
    notesController.dispose();
    for (final line in lines) {
      line.dispose();
    }
  }

  Widget _buildStockOutLine({
    required _StockOutDraftLine line,
    required int index,
    required List<InventoryItem> items,
    required List<InventoryUnitOption> units,
    required VoidCallback onChanged,
    required VoidCallback? onRemove,
  }) {
    final selectedItem = items.firstWhere(
      (item) => item.id == line.itemId,
      orElse: () => items.first,
    );
    final baseUnit = units.firstWhere(
      (unit) => unit.id == selectedItem.baseUomId,
      orElse: () => units.first,
    );
    final compatibleUnits = units
        .where((unit) => unit.dimension == baseUnit.dimension)
        .toList();
    final selectedUnit = compatibleUnits.firstWhere(
      (unit) => unit.id == line.unitId,
      orElse: () => baseUnit,
    );
    final usesBaseUnit = selectedUnit.id == baseUnit.id;
    final needsPackageSize =
        !usesBaseUnit && _isVariablePackageUnit(selectedUnit);
    final issueQuantity =
        double.tryParse(line.quantityController.text.trim()) ?? 0;
    final basePerUnit =
        double.tryParse(line.conversionController.text.trim()) ?? 0;
    final baseDeduction = issueQuantity * basePerUnit;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: line.itemId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Supply ${index + 1} *',
                  ),
                  items: items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.name} (${item.usableStock} usable)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final item = items.firstWhere((item) => item.id == value);
                    line.itemId = value;
                    line.unitId = item.baseUomId;
                    line.conversionController.text = '1';
                    onChanged();
                  },
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove supply',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final unit = DropdownButtonFormField<String>(
                key: ValueKey('${line.itemId}-${line.unitId}'),
                initialValue: line.unitId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Release Unit *'),
                items: compatibleUnits
                    .map(
                      (unit) => DropdownMenuItem(
                        value: unit.id,
                        child: Text('${unit.name} (${unit.code})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final issueUnit = compatibleUnits.firstWhere(
                    (unit) => unit.id == value,
                  );
                  line.unitId = value;
                  if (value == baseUnit.id) {
                    line.conversionController.text = '1';
                  } else if (_isVariablePackageUnit(issueUnit)) {
                    line.conversionController.clear();
                  } else {
                    line.conversionController.text = _plainNumber(
                      issueUnit.factorToDimensionBase /
                          baseUnit.factorToDimensionBase,
                    );
                  }
                  onChanged();
                },
              );
              final quantity = TextField(
                controller: line.quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity *'),
                onChanged: (_) => onChanged(),
              );
              final conversion = usesBaseUnit
                  ? null
                  : TextField(
                      controller: line.conversionController,
                      readOnly: !needsPackageSize,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${selectedItem.baseUomCode} in one '
                            '${selectedUnit.name.toLowerCase()} *',
                        helperText: needsPackageSize
                            ? 'Example: enter 50 when one '
                                  '${selectedUnit.name.toLowerCase()} contains '
                                  '50 ${selectedItem.baseUomCode}'
                            : 'Calculated automatically from the selected units',
                      ),
                      onChanged: (_) => onChanged(),
                    );

              if (constraints.maxWidth < 650) {
                return Column(
                  children: [
                    unit,
                    const SizedBox(height: 10),
                    quantity,
                    if (conversion != null) ...[
                      const SizedBox(height: 10),
                      conversion,
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: unit),
                  const SizedBox(width: 10),
                  Expanded(child: quantity),
                  if (conversion != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: conversion),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Base stock deduction: '
              '${_quantityWithUnit(baseDeduction, selectedItem.baseUomCode)}',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray700),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: line.notesController,
            decoration: const InputDecoration(
              labelText: 'Line Notes',
              hintText: 'Optional condition or handover note',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog() async {
    final categories = await widget.inventoryRepository.getCategories();
    final units = await widget.inventoryRepository.getUnits();

    if (!mounted) return;

    if (categories.isEmpty || units.isEmpty) {
      _showMessage('Inventory categories or units are not configured yet.');
      return;
    }

    final nameController = TextEditingController();
    final skuController = TextEditingController();
    final reorderController = TextEditingController(text: '0');
    final initialStockController = TextEditingController(text: '0');
    final unitCostController = TextEditingController(text: '0');

    String categoryId = categories.first.id;
    String unitId = units.first.id;
    bool trackExpiry = false;
    DateTime? expirationDate;
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Add Inventory Item',
      width: 620,
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          updateDialogState = setDialogState;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    hintText: 'e.g. Fresh Milk',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: skuController,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                    hintText: 'Optional internal code',
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
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => categoryId = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: unitId,
                  decoration: const InputDecoration(labelText: 'Base Unit *'),
                  items: units
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit.id,
                          child: Text('${unit.name} (${unit.code})'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => unitId = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reorderController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Low Stock / Reorder Level',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: initialStockController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Initial Stock'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: unitCostController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Initial Unit Cost',
                    prefixText: '₱',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track Expiration'),
                  subtitle: const Text(
                    'Use this for perishable ingredients and products.',
                  ),
                  value: trackExpiry,
                  onChanged: (value) {
                    setDialogState(() {
                      trackExpiry = value;
                      if (!value) expirationDate = null;
                    });
                  },
                ),
                if (trackExpiry)
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
                        setDialogState(() => expirationDate = date);
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        expirationDate == null
                            ? 'Select Initial Expiration Date'
                            : 'Expiration: ${_formatDate(expirationDate!)}',
                      ),
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
            final reorder =
                double.tryParse(reorderController.text.trim()) ?? -1;
            final initial =
                double.tryParse(initialStockController.text.trim()) ?? -1;
            final unitCost =
                double.tryParse(unitCostController.text.trim()) ?? -1;

            if (name.isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Item name is required.';
              });
              return;
            }

            if (reorder < 0 || initial < 0 || unitCost < 0) {
              updateDialogState?.call(() {
                errorMessage =
                    'Reorder level, stock, and cost cannot be negative.';
              });
              return;
            }

            if (trackExpiry && initial > 0 && expirationDate == null) {
              updateDialogState?.call(() {
                errorMessage =
                    'Expiration date is required for the initial stock.';
              });
              return;
            }

            try {
              await widget.inventoryRepository
                  .createInventoryItemWithInitialStock(
                    name: name,
                    categoryId: categoryId,
                    baseUomId: unitId,
                    sku: skuController.text.trim(),
                    trackExpiry: trackExpiry,
                    reorderLevel: reorder,
                    initialQuantity: initial,
                    expirationDate: expirationDate,
                    unitCostBase: unitCost,
                  );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Inventory item created.')),
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
          child: const Text('Save Item'),
        ),
      ],
    );

    nameController.dispose();
    skuController.dispose();
    reorderController.dispose();
    initialStockController.dispose();
    unitCostController.dispose();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
          ),
          const SizedBox(width: 20),
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

  String _movementLabel(String type) {
    switch (type) {
      case 'MANUAL_IN':
        return 'Stock In';
      case 'MANUAL_OUT':
        return 'Stock Out';
      case 'SALE_CONSUMPTION':
        return 'Used in Sale';
      case 'PURCHASE_RECEIPT':
        return 'Purchase Receipt';
      case 'WASTE':
        return 'Waste / Spoilage';
      case 'DAMAGED':
        return 'Damaged';
      case 'EXPIRED':
        return 'Expired';
      case 'COMPLIMENTARY':
        return 'Complimentary';
      case 'STAFF_MEAL':
        return 'Staff Meal';
      default:
        return type
            .toLowerCase()
            .split('_')
            .map(
              (part) => part.isEmpty
                  ? part
                  : part[0].toUpperCase() + part.substring(1),
            )
            .join(' ');
    }
  }

  String _movementReference(InventoryMovementRecord movement) {
    final parts = <String>[];
    if (movement.sourceDocumentNumber.isNotEmpty) {
      parts.add(movement.sourceDocumentNumber);
    }
    if (movement.externalReferenceNumber.isNotEmpty) {
      parts.add('Ref: ${movement.externalReferenceNumber}');
    }
    return parts.join(' • ');
  }

  String _signedQuantity(double quantity, String unit) {
    final sign = quantity >= 0 ? '+' : '';
    return '$sign${_quantityWithUnit(quantity, unit)}';
  }

  String _quantityWithUnit(double quantity, String unit) {
    final value = _plainNumber(quantity);

    return unit.isEmpty ? value : '$value $unit';
  }

  bool _isVariablePackageUnit(InventoryUnitOption unit) {
    final code = unit.code.toLowerCase();
    return code == 'box' || code == 'pack';
  }

  String _plainNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();

    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatDate(DateTime date) {
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

  String _formatDateTime(DateTime date) {
    int hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour %= 12;
    if (hour == 0) hour = 12;

    return '${date.month}/${date.day} $hour:$minute $period';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StockOutDraftLine {
  String itemId;
  String unitId;
  final TextEditingController quantityController;
  final TextEditingController conversionController;
  final TextEditingController notesController;

  _StockOutDraftLine({
    required this.itemId,
    required this.unitId,
    required this.quantityController,
    required this.conversionController,
    required this.notesController,
  });

  factory _StockOutDraftLine.fromItem(InventoryItem item) {
    return _StockOutDraftLine(
      itemId: item.id,
      unitId: item.baseUomId,
      quantityController: TextEditingController(text: '1'),
      conversionController: TextEditingController(text: '1'),
      notesController: TextEditingController(),
    );
  }

  void dispose() {
    quantityController.dispose();
    conversionController.dispose();
    notesController.dispose();
  }
}
