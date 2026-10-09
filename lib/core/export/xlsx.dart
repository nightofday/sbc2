import 'dart:convert';
import 'dart:typed_data';

/// How a column's values are stored and formatted in the workbook.
enum XlsxKind { text, money, quantity, count, date, dateTime }

class XlsxColumn {
  final String label;
  final XlsxKind kind;

  /// Adds the column up in the sheet's Total row.
  final bool summed;

  const XlsxColumn(this.label, this.kind, {this.summed = false});

  /// Amounts, quantities and counts sit on the right; text and dates on the
  /// left.
  bool get alignsRight =>
      kind == XlsxKind.money ||
      kind == XlsxKind.quantity ||
      kind == XlsxKind.count;
}

/// A value formatted as [kind] instead of its column's kind, such as an
/// order count in a column of amounts.
class XlsxCell {
  final Object? value;
  final XlsxKind kind;

  const XlsxCell(this.value, this.kind);
}

/// One worksheet: a title block, a header row, the rows, and a Total row
/// when any column is [XlsxColumn.summed].
class XlsxSheet {
  final String name;
  final String title;

  /// Lines under the title: the period, timezone and export time, notes.
  final List<String> subtitles;
  final List<XlsxColumn> columns;

  /// One list per row, a value per column: a [num], a [DateTime] (for date
  /// columns), a [String], an [XlsxCell] or null.
  final List<List<Object?>> rows;

  /// Shown instead of the table when there are no rows.
  final String emptyText;

  const XlsxSheet({
    required this.name,
    required this.title,
    this.subtitles = const [],
    required this.columns,
    required this.rows,
    this.emptyText = 'Nothing recorded in this period.',
  });
}

/// Writes formatted .xlsx workbooks without a third-party package. The file
/// is a zip of SpreadsheetML parts, stored uncompressed, which Excel, Google
/// Sheets and LibreOffice all open.
///
/// Each sheet gets a bold title, a brand-red header row that wraps and stays
/// visible while scrolling, ₱ amounts kept as real numbers, dates as real
/// dates, banded rows, a filter on the header, fitted column widths, a Total
/// row using SUM formulas, and landscape printing one page wide.
class XlsxWorkbook {
  final List<XlsxSheet> sheets;

  const XlsxWorkbook(this.sheets);

  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Uint8List encode() {
    final names = _uniqueSheetNames();
    final files = <String, String>{
      '[Content_Types].xml': _contentTypes(),
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook(names),
      'xl/_rels/workbook.xml.rels': _workbookRels(),
      'xl/styles.xml': _styles,
      for (var i = 0; i < sheets.length; i++)
        'xl/worksheets/sheet${i + 1}.xml': _sheet(sheets[i]),
    };
    return _zip({
      for (final entry in files.entries) entry.key: utf8.encode(entry.value),
    });
  }

  // ---------------------------------------------------------------- parts

  String _contentTypes() {
    final sheetTypes = [
      for (var i = 1; i <= sheets.length; i++)
        '<Override PartName="/xl/worksheets/sheet$i.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.worksheet+xml"/>',
    ].join();
    return '$_xmlHeader<Types xmlns="http://schemas.openxmlformats.org/'
        'package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/'
        'vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '$sheetTypes</Types>';
  }

  static const _rootRels =
      '$_xmlHeader<Relationships xmlns="http://schemas.openxmlformats.org/'
      'package/2006/relationships"><Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  String _workbook(List<String> names) {
    final sheetTags = StringBuffer();
    final filters = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      sheetTags.write(
        '<sheet name="${_escape(names[i])}" sheetId="${i + 1}" '
        'r:id="rId${i + 1}"/>',
      );
      final layout = _Layout(sheets[i]);
      if (layout.hasTable) {
        // Excel expects the filter range as a hidden name on each sheet.
        filters.write(
          '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" '
          'hidden="1">${_escape(_quoteSheet(names[i]))}!'
          '${layout.filterRange(absolute: true)}</definedName>',
        );
      }
    }
    final definedNames = filters.isEmpty
        ? ''
        : '<definedNames>$filters</definedNames>';
    return '$_xmlHeader<workbook xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships"><bookViews><workbookView/>'
        '</bookViews><sheets>$sheetTags</sheets>$definedNames</workbook>';
  }

  String _workbookRels() {
    final rels = StringBuffer();
    for (var i = 1; i <= sheets.length; i++) {
      rels.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet$i.xml"/>',
      );
    }
    rels.write(
      '<Relationship Id="rId${sheets.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/styles" Target="styles.xml"/>',
    );
    return '$_xmlHeader<Relationships xmlns="http://schemas.openxmlformats.'
        'org/package/2006/relationships">$rels</Relationships>';
  }

  String _sheet(XlsxSheet sheet) {
    final layout = _Layout(sheet);
    final columnCount = sheet.columns.isEmpty ? 1 : sheet.columns.length;
    final lastColumn = _columnName(columnCount - 1);
    final data = StringBuffer();

    void row(int number, String cells, {double? height}) {
      final ht = height == null ? '' : ' ht="$height" customHeight="1"';
      data.write('<row r="$number"$ht>$cells</row>');
    }

    row(1, _textCell('A1', sheet.title, _Style.title), height: 24);
    for (var i = 0; i < sheet.subtitles.length; i++) {
      row(2 + i, _textCell('A${2 + i}', sheet.subtitles[i], _Style.subtitle));
    }

    if (!layout.hasTable) {
      final r = layout.headerRow;
      row(r, _textCell('A$r', sheet.emptyText, _Style.subtitle));
    } else {
      final header = StringBuffer();
      for (var c = 0; c < sheet.columns.length; c++) {
        final column = sheet.columns[c];
        header.write(
          _textCell(
            '${_columnName(c)}${layout.headerRow}',
            column.label,
            column.alignsRight ? _Style.headerRight : _Style.header,
          ),
        );
      }
      row(layout.headerRow, header.toString(), height: 32);

      for (var i = 0; i < sheet.rows.length; i++) {
        final r = layout.firstDataRow + i;
        final banded = i.isOdd;
        final cells = StringBuffer();
        for (var c = 0; c < sheet.columns.length; c++) {
          final value = c < sheet.rows[i].length ? sheet.rows[i][c] : null;
          cells.write(
            _valueCell(
              '${_columnName(c)}$r',
              sheet.columns[c].kind,
              value,
              banded: banded,
            ),
          );
        }
        row(r, cells.toString());
      }

      if (layout.hasTotals) {
        final r = layout.totalRow;
        final cells = StringBuffer();
        for (var c = 0; c < sheet.columns.length; c++) {
          final column = sheet.columns[c];
          final ref = '${_columnName(c)}$r';
          if (column.summed) {
            final sum = sheet.rows.fold<num>(0, (total, values) {
              var value = c < values.length ? values[c] : null;
              if (value is XlsxCell) value = value.value;
              return total + (value is num ? value : 0);
            });
            final range =
                '${_columnName(c)}${layout.firstDataRow}:'
                '${_columnName(c)}${layout.lastDataRow}';
            cells.write(
              '<c r="$ref" s="${_Style.total(column.kind)}">'
              '<f>SUM($range)</f><v>${_number(sum)}</v></c>',
            );
          } else if (c == 0) {
            cells.write(_textCell(ref, 'Total', _Style.totalText));
          } else {
            cells.write('<c r="$ref" s="${_Style.totalText}"/>');
          }
        }
        row(r, cells.toString());
      }
    }

    final widths = _columnWidths(sheet);
    final cols = [
      for (var c = 0; c < widths.length; c++)
        '<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" '
            'customWidth="1"/>',
    ].join();

    final pane = layout.hasTable
        ? '<pane ySplit="${layout.headerRow}" '
              'topLeftCell="A${layout.firstDataRow}" activePane="bottomLeft" '
              'state="frozen"/><selection pane="bottomLeft" '
              'activeCell="A${layout.firstDataRow}" '
              'sqref="A${layout.firstDataRow}"/>'
        : '';
    final filter = layout.hasTable
        ? '<autoFilter ref="${layout.filterRange()}"/>'
        : '';

    return '$_xmlHeader<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<dimension ref="A1:$lastColumn${layout.lastRow}"/>'
        '<sheetViews><sheetView workbookViewId="0" showGridLines="0">$pane'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="15"/>'
        '<cols>$cols</cols><sheetData>$data</sheetData>$filter'
        '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
        '</worksheet>';
  }

  // ---------------------------------------------------------------- cells

  String _textCell(String ref, String text, int style) {
    return '<c r="$ref" t="inlineStr" s="$style"><is><t xml:space="preserve">'
        '${_escape(text)}</t></is></c>';
  }

  String _valueCell(
    String ref,
    XlsxKind kind,
    Object? value, {
    required bool banded,
  }) {
    if (value is XlsxCell) {
      return _valueCell(ref, value.kind, value.value, banded: banded);
    }
    final style = _Style.data(kind, banded: banded);
    if (value == null || (value is String && value.isEmpty)) {
      return '<c r="$ref" s="$style"/>';
    }

    switch (kind) {
      case XlsxKind.money:
      case XlsxKind.quantity:
      case XlsxKind.count:
        if (value is num) {
          return '<c r="$ref" s="$style"><v>${_number(value)}</v></c>';
        }
      case XlsxKind.date:
      case XlsxKind.dateTime:
        if (value is DateTime) {
          final serial = _excelSerial(
            value,
            withTime: kind == XlsxKind.dateTime,
          );
          return '<c r="$ref" s="$style"><v>${_number(serial)}</v></c>';
        }
      case XlsxKind.text:
        break;
    }
    return _textCell(
      ref,
      value.toString(),
      _Style.data(XlsxKind.text, banded: banded),
    );
  }

  /// Days since 30 Dec 1899, the date system Excel and Sheets use.
  static num _excelSerial(DateTime date, {required bool withTime}) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final days = day.difference(DateTime.utc(1899, 12, 30)).inDays;
    if (!withTime) return days;
    final seconds = date.hour * 3600 + date.minute * 60 + date.second;
    return days + seconds / 86400;
  }

  static String _number(num value) {
    if (value is int || value == value.roundToDouble()) {
      return value.round().toString();
    }
    // Enough places for a quantity in numeric(14,4) or a time of day.
    return double.parse(value.toStringAsFixed(10)).toString();
  }

  // --------------------------------------------------------------- layout

  List<String> _uniqueSheetNames() {
    final used = <String>{};
    return [
      for (final sheet in sheets)
        () {
          var base = sheet.name.replaceAll(RegExp(r"[\[\]:*?/\\']"), ' ');
          base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (base.isEmpty) base = 'Sheet';
          if (base.length > 31) base = base.substring(0, 31).trim();
          var name = base;
          var n = 2;
          while (!used.add(name.toLowerCase())) {
            final suffix = ' ($n)';
            n++;
            name =
                '${base.substring(0, (31 - suffix.length).clamp(0, base.length)).trim()}$suffix';
          }
          return name;
        }(),
    ];
  }

  static List<int> _columnWidths(XlsxSheet sheet) {
    return [
      for (var c = 0; c < sheet.columns.length; c++)
        () {
          final column = sheet.columns[c];
          // A wrapped header needs room for its longest word, and two lines.
          final words = column.label.split(' ');
          var width = [
            column.label.length / 2,
            ...words.map((w) => w.length.toDouble()),
          ].reduce((a, b) => a > b ? a : b);

          for (final row in sheet.rows) {
            var value = c < row.length ? row[c] : null;
            if (value is XlsxCell) value = value.value;
            final length = switch (column.kind) {
              XlsxKind.money =>
                value is num ? _moneyLength(value) : '$value'.length,
              XlsxKind.date => 12,
              XlsxKind.dateTime => 20,
              _ => value == null ? 0 : '$value'.length,
            };
            if (length > width) width = length.toDouble();
          }
          // Room either side, so a right-aligned amount does not run into
          // the text of the next column.
          final max = column.kind == XlsxKind.text ? 50 : 24;
          return (width + 5).clamp(12, max).ceil();
        }(),
    ];
  }

  static int _moneyLength(num value) {
    final whole = value.abs().truncate().toString().length;
    return whole + (whole - 1) ~/ 3 + 4 + (value < 0 ? 1 : 0);
  }

  static String _quoteSheet(String name) => "'${name.replaceAll("'", "''")}'";

  static const _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  static String _escape(String text) => text
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ------------------------------------------------------------------ zip

  /// A zip archive with every entry stored, which needs no compression
  /// library and works on the web as well as on the tablet.
  static Uint8List _zip(Map<String, List<int>> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var count = 0;

    void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
    void u32(BytesBuilder b, int v) =>
        b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

    for (final entry in files.entries) {
      final name = utf8.encode(entry.key);
      final data = entry.value;
      final crc = _crc32(data);
      final offset = out.length;
      const dosTime = 0;
      const dosDate = (1 << 5) | 1; // 1 Jan 1980

      u32(out, 0x04034b50);
      u16(out, 20);
      u16(out, 0x0800); // names are UTF-8
      u16(out, 0); // stored
      u16(out, dosTime);
      u16(out, dosDate);
      u32(out, crc);
      u32(out, data.length);
      u32(out, data.length);
      u16(out, name.length);
      u16(out, 0);
      out.add(name);
      out.add(data);

      u32(central, 0x02014b50);
      u16(central, 20);
      u16(central, 20);
      u16(central, 0x0800);
      u16(central, 0);
      u16(central, dosTime);
      u16(central, dosDate);
      u32(central, crc);
      u32(central, data.length);
      u32(central, data.length);
      u16(central, name.length);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0);
      u32(central, 0);
      u32(central, offset);
      central.add(name);
      count++;
    }

    final centralOffset = out.length;
    final centralBytes = central.takeBytes();
    out.add(centralBytes);
    u32(out, 0x06054b50);
    u16(out, 0);
    u16(out, 0);
    u16(out, count);
    u16(out, count);
    u32(out, centralBytes.length);
    u32(out, centralOffset);
    u16(out, 0);
    return out.takeBytes();
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

/// Where a sheet's parts fall, by row number.
class _Layout {
  final XlsxSheet sheet;

  _Layout(this.sheet);

  int get headerRow => sheet.subtitles.length + 3;
  int get firstDataRow => headerRow + 1;
  int get lastDataRow => headerRow + sheet.rows.length;
  bool get hasTable => sheet.rows.isNotEmpty && sheet.columns.isNotEmpty;
  bool get hasTotals =>
      hasTable && sheet.columns.any((column) => column.summed);
  int get totalRow => lastDataRow + 1;
  int get lastRow => !hasTable
      ? headerRow
      : hasTotals
      ? totalRow
      : lastDataRow;

  String filterRange({bool absolute = false}) {
    final last = _columnName(sheet.columns.length - 1);
    return absolute
        ? '\$A\$$headerRow:\$$last\$$lastDataRow'
        : 'A$headerRow:$last$lastDataRow';
  }
}

String _columnName(int index) {
  var n = index + 1;
  var name = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    name = String.fromCharCode(65 + rem) + name;
    n = (n - 1) ~/ 26;
  }
  return name;
}

/// Cell style indexes into `styles.xml` below.
class _Style {
  static const title = 1;
  static const subtitle = 2;
  static const header = 3;
  static const headerRight = 4;
  static const totalText = 17;

  static const _order = [
    XlsxKind.text,
    XlsxKind.money,
    XlsxKind.quantity,
    XlsxKind.count,
    XlsxKind.date,
    XlsxKind.dateTime,
  ];

  static int data(XlsxKind kind, {required bool banded}) =>
      5 + _order.indexOf(kind) + (banded ? 6 : 0);

  static int total(XlsxKind kind) => switch (kind) {
    XlsxKind.money => 18,
    XlsxKind.quantity => 19,
    XlsxKind.count => 20,
    _ => totalText,
  };
}

// Number formats: 164 pesos with red negatives, 165 date, 166 date and
// time. Quantities use General, so 100 shows as 100 and 2.5 as 2.5.
// Fonts: 0 body, 1 bold, 2 title, 3 header white bold, 4 grey note.
// Fills: 2 brand red header, 3 band. Borders: 1 hairline under a row,
// 2 total (thin above, double below).
const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="3">'
    '<numFmt numFmtId="164" formatCode="&quot;₱&quot;#,##0.00;[Red]\\-&quot;₱&quot;#,##0.00"/>'
    '<numFmt numFmtId="165" formatCode="mmm d, yyyy"/>'
    '<numFmt numFmtId="166" formatCode="mmm d, yyyy h:mm AM/PM"/>'
    '</numFmts>'
    '<fonts count="5">'
    '<font><sz val="11"/><color rgb="FF1A1A1A"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><color rgb="FF1A1A1A"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="16"/><color rgb="FF1A1A1A"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'
    '<font><sz val="10"/><color rgb="FF5B5B5B"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFC90002"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFBF3F3"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="3">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right/><top/><bottom style="thin"><color rgb="FFE2E0DC"/></bottom><diagonal/></border>'
    '<border><left/><right/><top style="thin"><color rgb="FF1A1A1A"/></top><bottom style="double"><color rgb="FF1A1A1A"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="21">'
    // 0 default
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 title, 2 subtitle
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 3 header, 4 header for a number column
    '<xf numFmtId="0" fontId="3" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1" indent="1"/></xf>'
    '<xf numFmtId="0" fontId="3" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" indent="1"/></xf>'
    // 5-10 data: text, money, quantity, count, date, date-time
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1" indent="1"/></xf>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="3" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" indent="1"/></xf>'
    // 11-16 the same on a banded row
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1" indent="1"/></xf>'
    '<xf numFmtId="164" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="3" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="165" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" indent="1"/></xf>'
    '<xf numFmtId="166" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" indent="1"/></xf>'
    // 17-20 total row: label, money, quantity, count
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment indent="1"/></xf>'
    '<xf numFmtId="164" fontId="1" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf>'
    '<xf numFmtId="3" fontId="1" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
