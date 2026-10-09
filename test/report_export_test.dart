import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/export/export_file.dart';
import 'package:sbc_management_system/models/reporting.dart';

void main() {
  test('copied for Sheets, a section is rows of plain numbers', () {
    final section = ReportSection(
      id: 'by_item',
      title: 'Items Sold',
      columns: const [
        ReportColumn('item_name', 'Item'),
        ReportColumn('quantity_sold', 'Sold', ReportValueKind.quantity),
        ReportColumn('net_sales', 'Net Sales', ReportValueKind.money),
      ],
      rows: const [
        {
          'item_name': 'Beef Bowl, Large',
          'quantity_sold': 3,
          'net_sales': 1540.5,
        },
        // Text that starts like a formula is not run by the spreadsheet,
        // and a tab stays inside its cell.
        {'item_name': '=cmd\tx', 'quantity_sold': 1.5, 'net_sales': 0},
        {'item_name': '-5 damaged', 'quantity_sold': 0, 'net_sales': 0},
      ],
    );

    expect(section.toTsv().split('\n'), [
      'Item\tSold\tNet Sales',
      'Beef Bowl, Large\t3\t1540.50',
      "'=cmd x\t1.5\t0.00",
      "'-5 damaged\t0\t0.00",
    ]);
  });

  test('export files are named after what they hold and their dates', () {
    expect(
      reportFileName(
        'Sales by Day',
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 7),
      ),
      'sales-by-day_2026-10-01_2026-10-07.xlsx',
    );
  });

  test('outside the browser an export goes to the share sheet', () {
    expect(exportSavesToDownloads, isFalse);
    expect(exportExcelLabel, 'Share Excel');
  });

  test('a date and time reads as on screen', () {
    expect(
      formatReportDateTime(DateTime(2026, 10, 9, 21, 4)),
      'Oct 9, 2026 9:04 PM',
    );
    expect(
      formatReportDateTime(DateTime(2026, 10, 9, 0, 30)),
      'Oct 9, 2026 12:30 AM',
    );
  });
}
