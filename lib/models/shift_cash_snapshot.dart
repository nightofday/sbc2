class ShiftCashSnapshot {
  final String shiftId;
  final double openingCash;
  final double cashSales;
  final double cashRefunds;
  final double cashIn;
  final double cashOut;
  final double expectedCash;
  final String status;

  const ShiftCashSnapshot({
    required this.shiftId,
    required this.openingCash,
    required this.cashSales,
    required this.cashRefunds,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    required this.status,
  });

  factory ShiftCashSnapshot.fromMap(Map<String, dynamic> map) {
    return ShiftCashSnapshot(
      shiftId: map['shift_id']?.toString() ?? '',
      openingCash: (map['opening_cash'] as num?)?.toDouble() ?? 0,
      cashSales: (map['cash_sales'] as num?)?.toDouble() ?? 0,
      cashRefunds: (map['cash_refunds'] as num?)?.toDouble() ?? 0,
      cashIn: (map['cash_in'] as num?)?.toDouble() ?? 0,
      cashOut: (map['cash_out'] as num?)?.toDouble() ?? 0,
      expectedCash: (map['expected_cash'] as num?)?.toDouble() ?? 0,
      status: map['status']?.toString() ?? '',
    );
  }
}
