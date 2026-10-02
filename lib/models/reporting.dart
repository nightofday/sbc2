/// How a report value is shown on screen and written to an export.
enum ReportValueKind { text, money, quantity, count, date, dateTime }

class ReportColumn {
  final String key;
  final String label;
  final ReportValueKind kind;

  const ReportColumn(this.key, this.label, [this.kind = ReportValueKind.text]);
}

/// One table of a report: its columns, its rows and what to say when empty.
class ReportSection {
  final String id;
  final String title;
  final String note;
  final String emptyText;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;

  const ReportSection({
    required this.id,
    required this.title,
    required this.columns,
    required this.rows,
    this.note = '',
    this.emptyText = 'Nothing recorded in this period.',
  });

  /// The value as shown on screen.
  String display(Map<String, dynamic> row, ReportColumn column) {
    final value = row[column.key];
    if (value == null) return '—';

    switch (column.kind) {
      case ReportValueKind.money:
        return formatReportMoney(_number(value));
      case ReportValueKind.quantity:
        return formatReportQuantity(_number(value));
      case ReportValueKind.count:
        return _number(value).round().toString();
      case ReportValueKind.date:
        final date = DateTime.tryParse(value.toString());
        return date == null ? value.toString() : formatReportDate(date);
      case ReportValueKind.dateTime:
        final date = DateTime.tryParse(value.toString())?.toLocal();
        if (date == null) return value.toString();
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final minute = date.minute.toString().padLeft(2, '0');
        return '${formatReportDate(date)} $hour:$minute '
            '${date.hour >= 12 ? 'PM' : 'AM'}';
      case ReportValueKind.text:
        final text = value.toString();
        return text.isEmpty ? '—' : text;
    }
  }

  /// The value as written to a spreadsheet: plain numbers and ISO dates, so
  /// the spreadsheet can total and sort them.
  String exportValue(Map<String, dynamic> row, ReportColumn column) {
    final value = row[column.key];
    if (value == null) return '';

    switch (column.kind) {
      case ReportValueKind.money:
        return _number(value).toStringAsFixed(2);
      case ReportValueKind.quantity:
        return formatReportQuantity(_number(value));
      case ReportValueKind.count:
        return _number(value).round().toString();
      case ReportValueKind.date:
        return value.toString().split('T').first;
      case ReportValueKind.dateTime:
        final date = DateTime.tryParse(value.toString())?.toLocal();
        if (date == null) return value.toString();
        String two(int number) => number.toString().padLeft(2, '0');
        return '${date.year}-${two(date.month)}-${two(date.day)} '
            '${two(date.hour)}:${two(date.minute)}';
      case ReportValueKind.text:
        return _safeText(value.toString());
    }
  }

  /// Tab-separated text. Pasted into Google Sheets or Excel it fills cells.
  String toTsv() {
    final lines = <String>[
      columns.map((column) => _safeText(column.label)).join('\t'),
      for (final row in rows)
        columns.map((column) => exportValue(row, column)).join('\t'),
    ];
    return lines.join('\n');
  }

  static double _number(Object value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  /// Keeps one value in one cell, and stops text that starts like a formula
  /// from being run by the spreadsheet.
  static String _safeText(String text) {
    final single = text.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
    if (single.isNotEmpty && '=+-@'.contains(single[0])) return "'$single";
    return single;
  }
}

String formatReportMoney(double value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '${negative ? '-' : ''}₱$whole.${parts[1]}';
}

String formatReportQuantity(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String formatReportDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// The headline figures of a period. Gross sales are before discounts; net
/// sales are gross sales less discounts less refunds.
class ReportSummary {
  final double grossSales;
  final double discounts;
  final double refunds;
  final double netSales;
  final int orders;
  final int refundCount;
  final double averageOrder;
  final double expenses;
  final double netSalesLessExpenses;
  final double purchases;
  final double supplierPayments;
  final double stockLossCost;

  const ReportSummary({
    this.grossSales = 0,
    this.discounts = 0,
    this.refunds = 0,
    this.netSales = 0,
    this.orders = 0,
    this.refundCount = 0,
    this.averageOrder = 0,
    this.expenses = 0,
    this.netSalesLessExpenses = 0,
    this.purchases = 0,
    this.supplierPayments = 0,
    this.stockLossCost = 0,
  });

  factory ReportSummary.fromMap(Map<String, dynamic> map) {
    double number(String key) => (map[key] as num?)?.toDouble() ?? 0;

    return ReportSummary(
      grossSales: number('gross_sales'),
      discounts: number('discounts'),
      refunds: number('refunds'),
      netSales: number('net_sales'),
      orders: (map['orders'] as num?)?.toInt() ?? 0,
      refundCount: (map['refund_count'] as num?)?.toInt() ?? 0,
      averageOrder: number('average_order'),
      expenses: number('expenses'),
      netSalesLessExpenses: number('net_sales_less_expenses'),
      purchases: number('purchases'),
      supplierPayments: number('supplier_payments'),
      stockLossCost: number('stock_loss_cost'),
    );
  }

  /// The summary as a two-column table, for export.
  ReportSection toSection() {
    return ReportSection(
      id: 'summary',
      title: 'Summary',
      columns: const [
        ReportColumn('measure', 'Measure'),
        ReportColumn('value', 'Value', ReportValueKind.money),
      ],
      rows: [
        {'measure': 'Gross sales (before discounts)', 'value': grossSales},
        {'measure': 'Discounts', 'value': discounts},
        {'measure': 'Refunds', 'value': refunds},
        {'measure': 'Net sales', 'value': netSales},
        {'measure': 'Completed orders', 'value': orders.toDouble()},
        {'measure': 'Average order', 'value': averageOrder},
        {'measure': 'Expenses', 'value': expenses},
        {'measure': 'Net sales less expenses', 'value': netSalesLessExpenses},
        {'measure': 'Stock received from suppliers', 'value': purchases},
        {'measure': 'Paid to suppliers', 'value': supplierPayments},
        {'measure': 'Cost of stock recorded as lost', 'value': stockLossCost},
      ],
    );
  }
}

/// A report for a period of business days, as returned by
/// `get_business_report`, plus the stock that needs attention now.
class BusinessReport {
  final DateTime from;
  final DateTime to;
  final ReportSummary summary;
  final List<ReportSection> sections;

  const BusinessReport({
    required this.from,
    required this.to,
    required this.summary,
    required this.sections,
  });

  factory BusinessReport.fromJson(
    Map<String, dynamic> json, {
    List<Map<String, dynamic>> lowStock = const [],
    List<Map<String, dynamic>> expiringSoon = const [],
  }) {
    List<Map<String, dynamic>> rows(String key) {
      return ((json[key] as List?) ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
    }

    const money = ReportValueKind.money;
    const quantity = ReportValueKind.quantity;
    const count = ReportValueKind.count;

    return BusinessReport(
      from: DateTime.parse(json['from'].toString()),
      to: DateTime.parse(json['to'].toString()),
      summary: ReportSummary.fromMap(
        Map<String, dynamic>.from((json['summary'] as Map?) ?? const {}),
      ),
      sections: [
        ReportSection(
          id: 'by_day',
          title: 'Sales by Day',
          note:
              'A refund is counted on the day it was made, not the day of '
              'the original sale.',
          columns: const [
            ReportColumn('date', 'Date', ReportValueKind.date),
            ReportColumn('orders', 'Orders', count),
            ReportColumn('gross_sales', 'Gross Sales', money),
            ReportColumn('discounts', 'Discounts', money),
            ReportColumn('refunds', 'Refunds', money),
            ReportColumn('net_sales', 'Net Sales', money),
            ReportColumn('expenses', 'Expenses', money),
          ],
          rows: rows('by_day'),
        ),
        ReportSection(
          id: 'by_payment_method',
          title: 'Payment Methods',
          note: 'Money taken and refunded through each method.',
          emptyText: 'No payments in this period.',
          columns: const [
            ReportColumn('payment_method', 'Payment Method'),
            ReportColumn('transactions', 'Payments', count),
            ReportColumn('payments', 'Collected', money),
            ReportColumn('refunds', 'Refunded', money),
            ReportColumn('net_collected', 'Net Collected', money),
          ],
          rows: rows('by_payment_method'),
        ),
        ReportSection(
          id: 'by_item',
          title: 'Items Sold',
          emptyText: 'No items sold in this period.',
          columns: const [
            ReportColumn('item_name', 'Item'),
            ReportColumn('variant_name', 'Variant'),
            ReportColumn('category_name', 'Category'),
            ReportColumn('quantity_sold', 'Qty Sold', quantity),
            ReportColumn('quantity_refunded', 'Qty Refunded', quantity),
            ReportColumn('gross_sales', 'Gross Sales', money),
            ReportColumn('discounts', 'Discounts', money),
            ReportColumn('refunds', 'Refunds', money),
            ReportColumn('net_sales', 'Net Sales', money),
          ],
          rows: rows('by_item'),
        ),
        ReportSection(
          id: 'by_category',
          title: 'Sales by Category',
          emptyText: 'No items sold in this period.',
          columns: const [
            ReportColumn('category_name', 'Category'),
            ReportColumn('quantity_sold', 'Qty Sold', quantity),
            ReportColumn('gross_sales', 'Gross Sales', money),
            ReportColumn('discounts', 'Discounts', money),
            ReportColumn('refunds', 'Refunds', money),
            ReportColumn('net_sales', 'Net Sales', money),
          ],
          rows: rows('by_category'),
        ),
        ReportSection(
          id: 'by_discount',
          title: 'Discounts Given',
          emptyText: 'No discounts given in this period.',
          columns: const [
            ReportColumn('discount_name', 'Discount'),
            ReportColumn('times_used', 'Times Used', count),
            ReportColumn('amount', 'Amount', money),
          ],
          rows: rows('by_discount'),
        ),
        ReportSection(
          id: 'by_employee',
          title: 'Sales by Employee',
          note: 'The employee who took the payment.',
          emptyText: 'No sales in this period.',
          columns: const [
            ReportColumn('employee_name', 'Employee'),
            ReportColumn('orders', 'Orders', count),
            ReportColumn('gross_sales', 'Gross Sales', money),
            ReportColumn('discounts', 'Discounts', money),
            ReportColumn('sales_after_discounts', 'After Discounts', money),
          ],
          rows: rows('by_employee'),
        ),
        ReportSection(
          id: 'refunds',
          title: 'Refunds',
          emptyText: 'No refunds in this period.',
          columns: const [
            ReportColumn('refund_number', 'Refund No.', count),
            ReportColumn('order_number', 'Order No.', count),
            ReportColumn('refunded_at', 'Refunded', ReportValueKind.dateTime),
            ReportColumn('sold_on', 'Sold On', ReportValueKind.date),
            ReportColumn('amount', 'Amount', money),
            ReportColumn('reason', 'Reason'),
          ],
          rows: rows('refunds'),
        ),
        ReportSection(
          id: 'expenses_by_category',
          title: 'Expenses by Category',
          emptyText: 'No expenses in this period.',
          columns: const [
            ReportColumn('category_name', 'Category'),
            ReportColumn('entries', 'Entries', count),
            ReportColumn('amount', 'Amount', money),
          ],
          rows: rows('expenses_by_category'),
        ),
        ReportSection(
          id: 'stock_losses',
          title: 'Stock Losses Recorded',
          note: 'Stock disposed of as waste, damaged or expired.',
          emptyText: 'No stock losses recorded in this period.',
          columns: const [
            ReportColumn('item_name', 'Item'),
            ReportColumn('reason', 'Reason'),
            ReportColumn('quantity', 'Quantity', quantity),
            ReportColumn('unit', 'Unit'),
            ReportColumn('cost', 'Cost', money),
          ],
          rows: rows('stock_losses'),
        ),
        ReportSection(
          id: 'expired_on_hand',
          title: 'Expired Stock Awaiting Disposal',
          note:
              'As of today. This stock is still on hand and has not been '
              'recorded as a loss yet.',
          emptyText: 'No expired stock on hand.',
          columns: const [
            ReportColumn('item_name', 'Item'),
            ReportColumn('quantity', 'Quantity', quantity),
            ReportColumn('unit', 'Unit'),
            ReportColumn('cost', 'Cost', money),
          ],
          rows: rows('expired_on_hand'),
        ),
        ReportSection(
          id: 'stock_movement',
          title: 'Stock Movement',
          note:
              'Opening + received − sold − released − lost + other = closing. '
              '"Other" is opening stock, count corrections and adjustments.',
          emptyText: 'No stock movement up to the end of this period.',
          columns: const [
            ReportColumn('item_name', 'Item'),
            ReportColumn('unit', 'Unit'),
            ReportColumn('opening', 'Opening', quantity),
            ReportColumn('received', 'Received', quantity),
            ReportColumn('sold', 'Sold', quantity),
            ReportColumn('released', 'Released', quantity),
            ReportColumn('lost', 'Lost', quantity),
            ReportColumn('other', 'Other', quantity),
            ReportColumn('closing', 'Closing', quantity),
          ],
          rows: rows('stock_movement'),
        ),
        ReportSection(
          id: 'low_stock',
          title: 'Low Stock Now',
          note: 'As of today: usable stock at or below its reorder level.',
          emptyText: 'Nothing is at or below its reorder level.',
          columns: const [
            ReportColumn('name', 'Item'),
            ReportColumn('usable_quantity', 'Usable', quantity),
            ReportColumn('reorder_level', 'Reorder Level', quantity),
            ReportColumn('base_uom_code', 'Unit'),
          ],
          rows: lowStock,
        ),
        ReportSection(
          id: 'expiring_soon',
          title: 'Expiring Within 7 Days',
          note: 'As of today.',
          emptyText: 'Nothing expires in the next 7 days.',
          columns: const [
            ReportColumn('item_name', 'Item'),
            ReportColumn('lot_code', 'Lot'),
            ReportColumn('expiration_date', 'Expires', ReportValueKind.date),
            ReportColumn('remaining_quantity', 'Quantity', quantity),
            ReportColumn('uom_code', 'Unit'),
          ],
          rows: expiringSoon,
        ),
      ],
    );
  }

  ReportSection section(String id) {
    return sections.firstWhere((section) => section.id == id);
  }

  /// Every table, one after another, for pasting into a spreadsheet.
  String toTsv() {
    return [
      'Street Bowl Café report\t${formatReportDate(from)} to '
          '${formatReportDate(to)}',
      '',
      'Summary',
      summary.toSection().toTsv(),
      for (final section in sections) ...['', section.title, section.toTsv()],
    ].join('\n');
  }
}

class TransactionTraceRecord {
  final String eventKey;
  final DateTime occurredAt;
  final String eventType;
  final String documentNumber;
  final String externalReference;
  final String description;
  final String partyName;
  final double? amount;
  final String actorName;
  final String status;
  final String voidReason;

  /// Voided and reversed documents stay listed but are not live.
  bool get isVoided => status == 'VOIDED' || status == 'REVERSED';

  const TransactionTraceRecord({
    required this.eventKey,
    required this.occurredAt,
    required this.eventType,
    required this.documentNumber,
    required this.externalReference,
    required this.description,
    required this.partyName,
    required this.amount,
    required this.actorName,
    required this.status,
    this.voidReason = '',
  });

  factory TransactionTraceRecord.fromMap(Map<String, dynamic> map) {
    return TransactionTraceRecord(
      eventKey: map['event_key']?.toString() ?? '',
      occurredAt: DateTime.parse(map['occurred_at'].toString()).toLocal(),
      eventType: map['event_type']?.toString() ?? '',
      documentNumber: map['document_number']?.toString() ?? '',
      externalReference: map['external_reference']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      partyName: map['party_name']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble(),
      actorName: map['actor_name']?.toString() ?? 'Unknown Employee',
      status: map['status']?.toString() ?? '',
      voidReason: map['void_reason']?.toString() ?? '',
    );
  }
}
