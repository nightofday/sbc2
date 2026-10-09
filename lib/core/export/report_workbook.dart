import 'dart:typed_data';

import '../../models/reporting.dart';
import 'xlsx.dart';

/// Formatted Excel workbooks for the Reports screen: one sheet per report
/// section, with the period, timezone and export time under each title.

/// The whole report: a Summary sheet, then a sheet for every section.
Uint8List businessReportWorkbook(
  BusinessReport report, {
  required DateTime exportedAt,
  String businessName = 'Street Bowl Café',
}) {
  final period = _period(report.from, report.to, exportedAt);
  final summary = report.summary;
  final money = XlsxKind.money;

  return XlsxWorkbook([
    XlsxSheet(
      name: 'Summary',
      title: '$businessName — Summary',
      subtitles: [
        period,
        'Purchases, supplier payments, expenses and stock losses are separate '
            'events. None of them is profit.',
      ],
      columns: const [
        XlsxColumn('Measure', XlsxKind.text),
        XlsxColumn('Value', XlsxKind.money),
      ],
      rows: [
        ['Gross sales (before discounts)', summary.grossSales],
        ['Discounts', summary.discounts],
        ['Refunds', summary.refunds],
        ['Net sales', summary.netSales],
        ['Completed orders', XlsxCell(summary.orders, XlsxKind.count)],
        ['Average order', XlsxCell(summary.averageOrder, money)],
        ['Expenses', summary.expenses],
        ['Net sales less expenses', summary.netSalesLessExpenses],
        ['Stock received from suppliers', summary.purchases],
        ['Paid to suppliers', summary.supplierPayments],
        ['Cost of stock recorded as lost', summary.stockLossCost],
      ],
    ),
    for (final section in report.sections)
      _sectionSheet(section, period: period, businessName: businessName),
  ]).encode();
}

/// One section on its own.
Uint8List reportSectionWorkbook(
  ReportSection section, {
  required DateTime from,
  required DateTime to,
  required DateTime exportedAt,
  String businessName = 'Street Bowl Café',
}) {
  return XlsxWorkbook([
    _sectionSheet(
      section,
      period: _period(from, to, exportedAt),
      businessName: businessName,
    ),
  ]).encode();
}

XlsxSheet _sectionSheet(
  ReportSection section, {
  required String period,
  required String businessName,
}) {
  return XlsxSheet(
    name: section.title,
    title: '$businessName — ${section.title}',
    subtitles: [period, if (section.note.isNotEmpty) section.note],
    emptyText: section.emptyText,
    columns: [
      for (final column in section.columns)
        XlsxColumn(column.label, _kind(column.kind), summed: _summed(column)),
    ],
    rows: [
      for (final row in section.rows)
        [for (final column in section.columns) _value(row[column.key], column)],
    ],
  );
}

/// Amounts and counts add up in a Total row. Quantities do not, because a
/// section can mix units, and neither do document numbers.
bool _summed(ReportColumn column) {
  if (column.key.endsWith('_number')) return false;
  return column.kind == ReportValueKind.money ||
      column.kind == ReportValueKind.count;
}

XlsxKind _kind(ReportValueKind kind) => switch (kind) {
  ReportValueKind.text => XlsxKind.text,
  ReportValueKind.money => XlsxKind.money,
  ReportValueKind.quantity => XlsxKind.quantity,
  ReportValueKind.count => XlsxKind.count,
  ReportValueKind.date => XlsxKind.date,
  ReportValueKind.dateTime => XlsxKind.dateTime,
};

Object? _value(Object? value, ReportColumn column) {
  if (value == null) return null;
  switch (column.kind) {
    case ReportValueKind.money:
    case ReportValueKind.quantity:
      return value is num ? value : num.tryParse(value.toString());
    case ReportValueKind.count:
      final number = value is num ? value : num.tryParse(value.toString());
      return number?.round();
    case ReportValueKind.date:
      // A business date such as 2026-10-07, kept as that calendar day.
      final date = DateTime.tryParse(value.toString().split('T').first);
      return date ?? value.toString();
    case ReportValueKind.dateTime:
      // Shown in the device's time, as on screen.
      return DateTime.tryParse(value.toString())?.toLocal() ?? value.toString();
    case ReportValueKind.text:
      return value.toString().replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  }
}

String _period(DateTime from, DateTime to, DateTime exportedAt) {
  final range = from == to
      ? formatReportDate(from)
      : '${formatReportDate(from)} to ${formatReportDate(to)}';
  return '$range · business days in Asia/Manila · exported '
      '${formatReportDateTime(exportedAt)}';
}
