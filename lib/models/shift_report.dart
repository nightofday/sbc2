import 'reporting.dart';

double _money(dynamic value) => (value as num?)?.toDouble() ?? 0;

double? _optionalMoney(dynamic value) => (value as num?)?.toDouble();

DateTime? _time(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String formatShiftTime(DateTime? time) {
  if (time == null) return '—';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${formatReportDate(time)} $hour:$minute '
      '${time.hour >= 12 ? 'PM' : 'AM'}';
}

/// One row of the shift list.
class ShiftSummary {
  final String id;
  final int number;
  final String status;
  final String employeeName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double openingCash;
  final double? expectedCash;
  final double? countedCash;
  final double? variance;
  final int orderCount;

  const ShiftSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.employeeName,
    required this.startedAt,
    required this.endedAt,
    required this.openingCash,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
    required this.orderCount,
  });

  bool get isOpen => status == 'OPEN';

  String get statusLabel => switch (status) {
    'OPEN' => 'Open',
    'FORCED_CLOSED' => 'Closed by manager',
    _ => 'Closed',
  };

  factory ShiftSummary.fromMap(Map<String, dynamic> map) {
    return ShiftSummary(
      id: map['shift_id']?.toString() ?? '',
      number: (map['shift_number'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? '',
      employeeName: map['employee_name']?.toString() ?? '',
      startedAt: _time(map['started_at']),
      endedAt: _time(map['ended_at']),
      openingCash: _money(map['opening_cash']),
      expectedCash: _optionalMoney(map['expected_cash']),
      countedCash: _optionalMoney(map['counted_cash']),
      variance: _optionalMoney(map['variance']),
      orderCount: (map['order_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ShiftPaymentTotal {
  final String paymentMethod;
  final bool isCash;
  final int paymentCount;
  final double received;
  final double refunded;
  final double net;

  const ShiftPaymentTotal({
    required this.paymentMethod,
    required this.isCash,
    required this.paymentCount,
    required this.received,
    required this.refunded,
    required this.net,
  });

  factory ShiftPaymentTotal.fromMap(Map<String, dynamic> map) {
    return ShiftPaymentTotal(
      paymentMethod: map['payment_method']?.toString() ?? '',
      isCash: map['is_cash'] == true,
      paymentCount: (map['payment_count'] as num?)?.toInt() ?? 0,
      received: _money(map['received']),
      refunded: _money(map['refunded']),
      net: _money(map['net']),
    );
  }
}

class ShiftCashMovement {
  final String type;
  final double amount;
  final String reason;
  final String recordedBy;
  final DateTime? createdAt;

  const ShiftCashMovement({
    required this.type,
    required this.amount,
    required this.reason,
    required this.recordedBy,
    required this.createdAt,
  });

  /// Money put into the drawer, as opposed to taken out of it.
  bool get addsCash => type == 'PAY_IN' || type == 'CORRECTION';

  String get typeLabel => switch (type) {
    'PAY_IN' => 'Cash in',
    'PAY_OUT' => 'Cash out',
    'CASH_DROP' => 'Cash drop',
    'CORRECTION' => 'Correction',
    _ => type,
  };

  factory ShiftCashMovement.fromMap(Map<String, dynamic> map) {
    return ShiftCashMovement(
      type: map['movement_type']?.toString() ?? '',
      amount: _money(map['amount']),
      reason: map['reason']?.toString() ?? '',
      recordedBy: map['recorded_by']?.toString() ?? '',
      createdAt: _time(map['created_at']),
    );
  }
}

/// The end-of-shift report: what was sold, how it was paid, and the drawer
/// count against what the system expected.
class ShiftReport {
  final String shiftId;
  final int number;
  final String status;
  final String employeeName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String closingNotes;

  final int orderCount;
  final int voidedCount;
  final double grossSales;
  final double discounts;
  final double refunds;
  final double netSales;

  final List<ShiftPaymentTotal> payments;
  final List<ShiftCashMovement> cashMovements;

  final double openingCash;
  final double cashSales;
  final double cashRefunds;
  final double cashIn;
  final double cashOut;
  final double expectedCash;
  final double? countedCash;
  final double? variance;

  const ShiftReport({
    required this.shiftId,
    required this.number,
    required this.status,
    required this.employeeName,
    required this.startedAt,
    required this.endedAt,
    required this.closingNotes,
    required this.orderCount,
    required this.voidedCount,
    required this.grossSales,
    required this.discounts,
    required this.refunds,
    required this.netSales,
    required this.payments,
    required this.cashMovements,
    required this.openingCash,
    required this.cashSales,
    required this.cashRefunds,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
  });

  bool get isOpen => status == 'OPEN';

  factory ShiftReport.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> section(String key) =>
        Map<String, dynamic>.from((map[key] as Map?) ?? const {});
    List<Map<String, dynamic>> rows(String key) => ((map[key] as List?) ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final sales = section('sales');
    final cash = section('cash');

    return ShiftReport(
      shiftId: map['shift_id']?.toString() ?? '',
      number: (map['shift_number'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? '',
      employeeName: map['employee_name']?.toString() ?? '',
      startedAt: _time(map['started_at']),
      endedAt: _time(map['ended_at']),
      closingNotes: map['closing_notes']?.toString() ?? '',
      orderCount: (sales['order_count'] as num?)?.toInt() ?? 0,
      voidedCount: (sales['voided_count'] as num?)?.toInt() ?? 0,
      grossSales: _money(sales['gross_sales']),
      discounts: _money(sales['discounts']),
      refunds: _money(sales['refunds']),
      netSales: _money(sales['net_sales']),
      payments: rows('by_payment_method').map(ShiftPaymentTotal.fromMap).toList(),
      cashMovements: rows('cash_movements')
          .map(ShiftCashMovement.fromMap)
          .toList(),
      openingCash: _money(cash['opening_cash']),
      cashSales: _money(cash['cash_sales']),
      cashRefunds: _money(cash['cash_refunds']),
      cashIn: _money(cash['cash_in']),
      cashOut: _money(cash['cash_out']),
      expectedCash: _money(cash['expected_cash']),
      countedCash: _optionalMoney(cash['counted_cash']),
      variance: _optionalMoney(cash['variance']),
    );
  }

  /// The report as plain text, for pasting into a message or a note.
  String toText() {
    final lines = <String>[
      'Shift #$number — $employeeName',
      'Opened: ${formatShiftTime(startedAt)}',
      'Closed: ${isOpen ? 'still open' : formatShiftTime(endedAt)}',
      '',
      'Orders: $orderCount${voidedCount > 0 ? ' ($voidedCount voided)' : ''}',
      'Gross sales: ${formatReportMoney(grossSales)}',
      'Discounts: ${formatReportMoney(-discounts)}',
      'Refunds: ${formatReportMoney(-refunds)}',
      'Net sales: ${formatReportMoney(netSales)}',
      '',
      for (final payment in payments)
        '${payment.paymentMethod}: ${formatReportMoney(payment.net)}',
      '',
      'Opening cash: ${formatReportMoney(openingCash)}',
      'Cash sales: ${formatReportMoney(cashSales)}',
      'Cash refunds: ${formatReportMoney(-cashRefunds)}',
      'Cash in: ${formatReportMoney(cashIn)}',
      'Cash out: ${formatReportMoney(-cashOut)}',
      'Expected in drawer: ${formatReportMoney(expectedCash)}',
      if (countedCash != null) 'Counted: ${formatReportMoney(countedCash!)}',
      if (variance != null)
        'Difference: ${formatReportMoney(variance!)}'
            '${variance! < 0
                ? ' short'
                : variance! > 0
                ? ' over'
                : ''}',
      if (closingNotes.isNotEmpty) 'Notes: $closingNotes',
    ];
    return lines.join('\n');
  }
}
