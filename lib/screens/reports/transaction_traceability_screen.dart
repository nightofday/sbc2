import 'package:flutter/material.dart';

import '../../core/export/copy_text.dart';
import '../../core/export/file_download.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/layout/app_page.dart';

class TransactionTraceabilityScreen extends StatefulWidget {
  final ReportingRepository reportingRepository;
  final Listenable? refreshListenable;

  const TransactionTraceabilityScreen({
    super.key,
    required this.reportingRepository,
    this.refreshListenable,
  });

  @override
  State<TransactionTraceabilityScreen> createState() =>
      _TransactionTraceabilityScreenState();
}

class _TransactionTraceabilityScreenState
    extends State<TransactionTraceabilityScreen> {
  int _days = 30;
  String _eventType = 'ALL';
  String _search = '';
  late Future<List<TransactionTraceRecord>> _traceFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant TransactionTraceabilityScreen oldWidget) {
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
    _traceFuture = widget.reportingRepository.getTransactionTrace(days: _days);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  /// What is on screen, with the filters applied, is what gets exported.
  List<TransactionTraceRecord> _visibleRecords = const [];

  Future<void> _export() async {
    final records = _visibleRecords;
    if (records.isEmpty) {
      _showMessage('There is nothing to export for these filters.');
      return;
    }

    String two(int number) => number.toString().padLeft(2, '0');
    String when(DateTime date) =>
        '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';

    final header = [
      'Date & Time',
      'Type',
      'Document',
      'External Reference',
      'Details',
      'Supplier / Customer',
      'Amount',
      'Recorded By',
      'Status',
      'Void Reason',
    ];
    final rows = [
      for (final record in records)
        [
          when(record.occurredAt),
          _eventLabel(record.eventType),
          record.documentNumber,
          record.externalReference,
          record.description,
          record.partyName,
          record.amount?.toStringAsFixed(2) ?? '',
          record.actorName,
          record.status,
          record.voidReason,
        ],
    ];

    if (canDownloadFiles) {
      final today = DateTime.now();
      final csv = [
        header.map(csvField).join(','),
        for (final row in rows)
          row.map((cell) => csvField(safeCell(cell))).join(','),
      ].join('\r\n');
      downloadTextFile(
        fileName: reportFileName(
          'transactions-last-$_days-days',
          today.subtract(Duration(days: _days - 1)),
          today,
        ),
        contents: csv,
      );
      _showMessage(
        'Saved to your downloads. It opens in Excel or Google Sheets.',
      );
      return;
    }

    final tsv = [
      header.join('\t'),
      for (final row in rows) row.map(safeCell).join('\t'),
    ].join('\n');
    final copied = await copyText(tsv);
    _showMessage(
      copied
          ? 'Copied. Paste it into Google Sheets or Excel.'
          : 'Copying did not work on this device. Try again.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Transaction Traceability',
      subtitle: 'Follow each document back to its receipt/reference and employee (up to 500 recent records).',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _export,
            icon: Icon(
              canDownloadFiles ? Icons.download_outlined : Icons.copy_outlined,
              size: 18,
            ),
            label: Text(canDownloadFiles ? 'Download CSV' : 'Copy for Sheets'),
          ),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
      child: FutureBuilder<List<TransactionTraceRecord>>(
        future: _traceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load transaction history.\n${errorText(snapshot.error)}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final records = _applyFilters(
            snapshot.data ?? const <TransactionTraceRecord>[],
          );
          _visibleRecords = records;

          return Column(
            children: [
              _buildFilters(),
              const SizedBox(height: 18),
              Expanded(
                child: records.isEmpty
                    ? const SectionCard(
                        child: Center(
                          child: Text(
                            'No transactions match the selected filters.',
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: DataTableCard(
                          headers: const [
                            'Date & Time',
                            'Type',
                            'Document / Reference',
                            'Details',
                            'Supplier / Customer',
                            'Amount',
                            'Recorded By',
                          ],
                          flexes: const [2, 2, 3, 4, 3, 2, 3],
                          rows: records
                              .map(
                                (record) => [
                                  Text(
                                    _dateTime(record.occurredAt),
                                    style: AppTextStyles.body,
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: _EventTypeBadge(
                                      label: _eventLabel(record.eventType),
                                      color: _eventColor(record.eventType),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record.documentNumber,
                                        style: AppTextStyles.bodyMedium,
                                      ),
                                      Text(
                                        record.externalReference.isEmpty
                                            ? 'No external reference'
                                            : record.externalReference,
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.gray500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record.description,
                                        style: AppTextStyles.body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (record.isVoided ||
                                          record.status == 'REVERSAL')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: StatusBadge(
                                            record.status == 'REVERSAL'
                                                ? 'Reversal'
                                                : record.status == 'REVERSED'
                                                ? 'Reversed'
                                                : 'Voided',
                                          ),
                                        ),
                                      if (record.voidReason.isNotEmpty)
                                        Text(
                                          'Reason: ${record.voidReason}',
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.gray700,
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    record.partyName.isEmpty
                                        ? '—'
                                        : record.partyName,
                                    style: AppTextStyles.body,
                                  ),
                                  Text(
                                    record.amount == null
                                        ? '—'
                                        : _money(record.amount!),
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: record.isVoided
                                          ? AppColors.gray500
                                          : (record.amount ?? 0) < 0
                                          ? AppColors.error
                                          : AppColors.black,
                                      decoration: record.isVoided
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  Text(
                                    record.actorName,
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
      ),
    );
  }

  Widget _buildFilters() {
    final search = TextField(
      onChanged: (value) => setState(() => _search = value),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText:
            'Search document, receipt, supplier, customer, or employee...',
      ),
    );

    final period = DropdownButtonFormField<int>(
      initialValue: _days,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Period'),
      items: const [
        DropdownMenuItem(value: 7, child: Text('Last 7 Days')),
        DropdownMenuItem(value: 30, child: Text('Last 30 Days')),
        DropdownMenuItem(value: 90, child: Text('Last 90 Days')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _days = value;
          _reload();
        });
      },
    );

    final type = DropdownButtonFormField<String>(
      initialValue: _eventType,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Transaction Type'),
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Transactions')),
        DropdownMenuItem(value: 'SALE', child: Text('Sales')),
        DropdownMenuItem(value: 'REFUND', child: Text('Refunds')),
        DropdownMenuItem(value: 'STOCK_IN', child: Text('Stock In')),
        DropdownMenuItem(value: 'STOCK_OUT', child: Text('Stock Out')),
        DropdownMenuItem(
          value: 'INVENTORY_COUNT',
          child: Text('Inventory Counts'),
        ),
        DropdownMenuItem(value: 'EXPENSE', child: Text('Expenses')),
        DropdownMenuItem(
          value: 'SUPPLIER_PAYMENT',
          child: Text('Supplier Payments'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _eventType = value);
      },
    );

    return ResponsiveFilterBar(
      primary: search,
      filters: [period, type],
      filterWidths: const [170, 210],
    );
  }

  List<TransactionTraceRecord> _applyFilters(
    List<TransactionTraceRecord> records,
  ) {
    final query = _search.trim().toLowerCase();

    return records.where((record) {
      final typeMatches = _eventType == 'ALL' || record.eventType == _eventType;
      final searchMatches =
          query.isEmpty ||
          record.documentNumber.toLowerCase().contains(query) ||
          record.externalReference.toLowerCase().contains(query) ||
          record.description.toLowerCase().contains(query) ||
          record.partyName.toLowerCase().contains(query) ||
          record.actorName.toLowerCase().contains(query);

      return typeMatches && searchMatches;
    }).toList();
  }

  String _eventLabel(String value) {
    switch (value) {
      case 'SALE':
        return 'Sale';
      case 'REFUND':
        return 'Refund';
      case 'STOCK_IN':
        return 'Stock In';
      case 'STOCK_OUT':
        return 'Stock Out';
      case 'INVENTORY_COUNT':
        return 'Count';
      case 'EXPENSE':
        return 'Expense';
      case 'SUPPLIER_PAYMENT':
        return 'Supplier Payment';
      default:
        return value;
    }
  }

  Color _eventColor(String value) {
    switch (value) {
      case 'SALE':
        return AppColors.success;
      case 'STOCK_IN':
        return AppColors.primary;
      case 'INVENTORY_COUNT':
        return AppColors.black;
      case 'REFUND':
      case 'EXPENSE':
      case 'SUPPLIER_PAYMENT':
        return AppColors.error;
      default:
        return AppColors.orange;
    }
  }

  String _money(double value) => formatReportMoney(value);

  String _dateTime(DateTime value) {
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
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${months[value.month - 1]} ${value.day}, ${value.year}\n'
        '$hour:$minute $period';
  }
}

class _EventTypeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _EventTypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
