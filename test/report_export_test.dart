import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/export/file_download.dart';
import 'package:sbc_management_system/models/reporting.dart';

void main() {
  test('a CSV cell is quoted only when it has to be', () {
    expect(csvField('Hot Coffee'), 'Hot Coffee');
    expect(csvField('Rice Bowls, Meals'), '"Rice Bowls, Meals"');
    expect(csvField('Say "hi"'), '"Say ""hi"""');
    expect(csvField('two\nlines'), '"two\nlines"');
  });

  test('text that looks like a formula is not run by the spreadsheet', () {
    expect(safeCell('=SUM(A1:A9)'), "'=SUM(A1:A9)");
    expect(safeCell('-5 damaged'), "'-5 damaged");
    expect(safeCell('Table\tT1'), 'Table T1');
  });

  test('a section exports as rows of plain numbers under its headings', () {
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
        {'item_name': '=cmd', 'quantity_sold': 1.5, 'net_sales': 0},
      ],
    );

    expect(section.toCsv().split('\r\n'), [
      'Item,Sold,Net Sales',
      '"Beef Bowl, Large",3,1540.50',
      "'=cmd,1.5,0.00",
    ]);
  });

  test('export files are named after what they hold and their dates', () {
    expect(
      reportFileName(
        'Sales by Day',
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 7),
      ),
      'sales-by-day_2026-10-01_2026-10-07.csv',
    );
  });

  test('outside the browser the app copies instead of saving a file', () {
    expect(canDownloadFiles, isFalse);
    expect(downloadTextFile(fileName: 'a.csv', contents: 'a'), isFalse);
  });
}
