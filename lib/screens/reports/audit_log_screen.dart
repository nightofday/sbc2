import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/export/copy_text.dart';
import '../../core/export/file_download.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/audit_entry.dart';
import '../../models/reporting.dart';
import '../../models/shift_report.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/layout/app_page.dart';

enum _Period { today, last7, last30, custom }

/// The audit trail for management: who changed a price, a role, a supplier
/// or a setting, and who posted, voided or refunded what.
class AuditLogScreen extends StatefulWidget {
  final ReportingRepository reportingRepository;
  final Listenable? refreshListenable;

  const AuditLogScreen({
    super.key,
    required this.reportingRepository,
    this.refreshListenable,
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  _Period _period = _Period.last7;
  late DateTime _from;
  late DateTime _to;
  String _search = '';
  Timer? _searchDelay;
  late Future<List<AuditEntry>> _entriesFuture;

  static const _periodLabels = {
    _Period.today: 'Today',
    _Period.last7: 'Last 7 Days',
    _Period.last30: 'Last 30 Days',
    _Period.custom: 'Custom Dates',
  };

  @override
  void initState() {
    super.initState();
    _applyPeriod(_period);
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AuditLogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_refresh);
      widget.refreshListenable?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _searchDelay?.cancel();
    widget.refreshListenable?.removeListener(_refresh);
    super.dispose();
  }

  void _applyPeriod(_Period period) {
    final today = DateUtils.dateOnly(DateTime.now());

    switch (period) {
      case _Period.today:
        _from = today;
        _to = today;
      case _Period.last7:
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case _Period.last30:
        _from = today.subtract(const Duration(days: 29));
        _to = today;
      case _Period.custom:
        // Keeps the dates already chosen.
        break;
    }
  }

  void _reload() {
    _entriesFuture = widget.reportingRepository.getAuditLog(
      from: _from,
      to: _to,
      search: _search,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _choosePeriod(_Period period) async {
    if (period == _Period.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to),
        helpText: 'Choose the dates',
      );
      if (picked == null || !mounted) return;

      setState(() {
        _period = _Period.custom;
        _from = DateUtils.dateOnly(picked.start);
        _to = DateUtils.dateOnly(picked.end);
        _reload();
      });
      return;
    }

    setState(() {
      _period = period;
      _applyPeriod(period);
      _reload();
    });
  }

  List<AuditEntry> _visibleEntries = const [];

  Future<void> _export() async {
    final entries = _visibleEntries;
    if (entries.isEmpty) {
      _showMessage('There is nothing to export for these dates and search.');
      return;
    }

    String two(int number) => number.toString().padLeft(2, '0');
    String when(DateTime date) =>
        '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';

    final header = ['Date & Time', 'Who', 'What', 'Record', 'Details'];
    final rows = [
      for (final entry in entries)
        [
          when(entry.createdAt),
          entry.actorName,
          entry.title,
          entry.label,
          entry.changes
              .map(
                (change) => change.before.isEmpty
                    ? '${change.field}: ${change.after}'
                    : '${change.field}: ${change.before} -> ${change.after}',
              )
              .join('; '),
        ],
    ];

    if (canDownloadFiles) {
      final csv = [
        header.map(csvField).join(','),
        for (final row in rows)
          row.map((cell) => csvField(safeCell(cell))).join(','),
      ].join('\r\n');
      downloadTextFile(
        fileName: reportFileName('audit-log', _from, _to),
        contents: csv,
      );
      _showMessage(
        'Saved to your downloads. It opens in Excel or Google Sheets.',
      );
      return;
    }

    final copied = await copyText(
      [
        header.join('\t'),
        for (final row in rows) row.map(safeCell).join('\t'),
      ].join('\n'),
    );
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

  void _onSearchChanged(String value) {
    _search = value;
    // Waits for a pause in typing before asking the server.
    _searchDelay?.cancel();
    _searchDelay = Timer(const Duration(milliseconds: 400), _refresh);
  }

  String get _rangeLabel => _from == _to
      ? formatReportDate(_from)
      : '${formatReportDate(_from)} to ${formatReportDate(_to)}';

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Audit Log',
      subtitle: _rangeLabel,
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _export,
            icon: Icon(
              canDownloadFiles ? Icons.download_outlined : Icons.copy_outlined,
              size: 17,
            ),
            label: Text(canDownloadFiles ? 'Download CSV' : 'Copy for Sheets'),
          ),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Refresh'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in _Period.values)
                ChoiceChip(
                  label: Text(_periodLabels[period]!),
                  selected: _period == period,
                  onSelected: (_) => _choosePeriod(period),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search a name, a product, a price or an action...',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<AuditEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to load the audit log.\n'
                          '${errorText(snapshot.error)}',
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

                final entries = snapshot.data!;
                _visibleEntries = entries;
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nothing was recorded for these dates and this search.',
                      style: AppTextStyles.body,
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _entry(entries[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(AuditEntry entry) {
    final changes = entry.changes;

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.label.isEmpty
                ? entry.title
                : '${entry.title}: ${entry.label}',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.actorName} · ${formatShiftTime(entry.createdAt)}',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  change.before.isEmpty
                      ? '${change.field}: ${change.after}'
                      : '${change.field}: ${change.before} → ${change.after}',
                  style: AppTextStyles.body,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
