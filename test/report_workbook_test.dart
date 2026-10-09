import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/export/report_workbook.dart';
import 'package:sbc_management_system/core/export/xlsx.dart';
import 'package:sbc_management_system/models/reporting.dart';

/// The parts of a workbook by name. The writer stores entries without
/// compression, so each part's bytes follow its local header.
Map<String, String> _parts(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final parts = <String, String>{};
  var offset = 0;
  while (data.getUint32(offset, Endian.little) == 0x04034b50) {
    expect(data.getUint16(offset + 8, Endian.little), 0, reason: 'stored');
    final size = data.getUint32(offset + 18, Endian.little);
    final nameLength = data.getUint16(offset + 26, Endian.little);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    final nameStart = offset + 30;
    final name = utf8.decode(zip.sublist(nameStart, nameStart + nameLength));
    final start = nameStart + nameLength + extraLength;
    parts[name] = utf8.decode(zip.sublist(start, start + size));
    offset = start + size;
  }
  return parts;
}

BusinessReport _report() => BusinessReport.fromJson({
  'from': '2026-10-01',
  'to': '2026-10-02',
  'summary': {
    'gross_sales': 1420,
    'discounts': 41,
    'refunds': 162,
    'net_sales': 1217,
    'orders': 3,
    'refund_count': 1,
    'average_order': 459.67,
    'expenses': 350,
    'net_sales_less_expenses': 867,
    'purchases': 200,
    'supplier_payments': 0,
    'stock_loss_cost': 28,
  },
  'by_day': [
    {
      'date': '2026-10-01',
      'orders': 1,
      'gross_sales': 420,
      'discounts': 0,
      'refunds': 0,
      'net_sales': 420,
      'expenses': 0,
    },
    {
      'date': '2026-10-02',
      'orders': 2,
      'gross_sales': 1000,
      'discounts': 41,
      'refunds': 162,
      'net_sales': 797,
      'expenses': 350,
    },
  ],
  'refunds': [
    {
      'refund_number': 7,
      'order_number': 12,
      'refunded_at': '2026-10-02T13:20:00Z',
      'sold_on': '2026-10-02',
      'amount': 162,
      'reason': '=cmd|calc & <b>\tsecond line',
    },
  ],
  'stock_movement': [
    {
      'item_name': 'Paper Cups',
      'unit': 'pc',
      'opening': 0,
      'received': 100,
      'sold': 0,
      'released': 12.5,
      'lost': 0,
      'other': 0,
      'closing': 87.5,
    },
  ],
});

void main() {
  final exportedAt = DateTime(2026, 10, 9, 21, 14);

  test('the whole report is one workbook with a sheet per section', () {
    final report = _report();
    final parts = _parts(
      businessReportWorkbook(report, exportedAt: exportedAt),
    );

    expect(parts.keys, contains('[Content_Types].xml'));
    expect(parts.keys, contains('xl/styles.xml'));
    final workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('<sheet name="Summary"'));
    for (final section in report.sections) {
      expect(workbook, contains('name="${section.title}"'));
    }
    expect(
      parts.keys.where((name) => name.startsWith('xl/worksheets/')),
      hasLength(report.sections.length + 1),
    );
  });

  test('amounts stay numbers and add up in a Total row', () {
    final sheet = _parts(
      reportSectionWorkbook(
        _report().section('by_day'),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        exportedAt: exportedAt,
      ),
    )['xl/worksheets/sheet1.xml']!;

    // Title, period and timezone above the table.
    expect(sheet, contains('Street Bowl Café — Sales by Day'));
    expect(
      sheet,
      contains('Oct 1, 2026 to Oct 2, 2026 · business days in Asia/Manila'),
    );
    // Header row 5 stays visible and carries the filter.
    expect(sheet, contains('<pane ySplit="5"'));
    expect(sheet, contains('<autoFilter ref="A5:G7"/>'));
    // 1 Oct 2026 as an Excel date serial, and an amount as a number.
    expect(sheet, contains('<v>46296</v>'));
    expect(sheet, contains('<v>797</v>'));
    // Totals are formulas with their values cached for viewers that do not
    // calculate.
    expect(sheet, contains('<f>SUM(B6:B7)</f><v>3</v>'));
    expect(sheet, contains('<f>SUM(C6:C7)</f><v>1420</v>'));
  });

  test('document numbers are not totalled and text is never a formula', () {
    final sheet = _parts(
      reportSectionWorkbook(
        _report().section('refunds'),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        exportedAt: exportedAt,
      ),
    )['xl/worksheets/sheet1.xml']!;

    expect(sheet, isNot(contains('SUM(A')));
    expect(sheet, isNot(contains('SUM(B')));
    expect(sheet, contains('SUM(E'));
    // Stored as text, escaped, on one line.
    expect(sheet, contains('t="inlineStr"'));
    expect(sheet, contains('=cmd|calc &amp; &lt;b&gt; second line'));
    expect(sheet, isNot(contains('<f>cmd')));
  });

  test('the order count in the summary is a count, not pesos', () {
    final summary = _parts(
      businessReportWorkbook(_report(), exportedAt: exportedAt),
    )['xl/worksheets/sheet1.xml']!;

    final orders = RegExp(
      r'Completed orders</t></is></c><c r="B\d+" s="(\d+)"><v>3</v>',
    ).firstMatch(summary);
    expect(orders, isNotNull);
    // Style 8 is the plain count format; money would be 6 or 12.
    expect(orders!.group(1), anyOf('8', '14'));
  });

  test('an empty section says so instead of an empty table', () {
    final sheet = _parts(
      reportSectionWorkbook(
        _report().section('by_discount'),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        exportedAt: exportedAt,
      ),
    )['xl/worksheets/sheet1.xml']!;

    expect(sheet, contains('No discounts given in this period.'));
    expect(sheet, isNot(contains('autoFilter')));
  });

  test('sheet names are unique and within Excel limits', () {
    const columns = [XlsxColumn('A', XlsxKind.text)];
    final parts = _parts(
      const XlsxWorkbook([
        XlsxSheet(
          name: 'Sales: by/day?',
          title: 't',
          columns: columns,
          rows: [],
        ),
        XlsxSheet(
          name: 'Sales  by day',
          title: 't',
          columns: columns,
          rows: [],
        ),
        XlsxSheet(
          name: 'A very long section title that keeps going',
          title: 't',
          columns: columns,
          rows: [],
        ),
      ]).encode(),
    );
    final workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('name="Sales by day"'));
    expect(workbook, contains('name="Sales by day (2)"'));
    expect(workbook, contains('name="A very long section title that"'));
  });

  test('writes a sample for manual checks when asked', () {
    final folder = Platform.environment['XLSX_SAMPLE_DIR'];
    if (folder == null) return;
    File('$folder/report.xlsx').writeAsBytesSync(
      businessReportWorkbook(_report(), exportedAt: exportedAt),
    );
  });
}
