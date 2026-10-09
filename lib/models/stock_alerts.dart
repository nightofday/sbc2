import 'inventory_item.dart';

/// Stock that needs someone's attention, in three groups. An item can be in
/// more than one group, for example expired lots plus too little usable
/// stock left.
class StockAlerts {
  /// Days ahead that count as "expiring soon", the same window the stock
  /// overview uses for its Expiring Soon status.
  static const expiringWithinDays = 7;

  /// Items holding expired quantity that still has to be disposed of.
  final List<InventoryItem> expired;

  /// Items whose next usable lot expires within [expiringWithinDays].
  final List<InventoryItem> expiringSoon;

  /// Items whose usable quantity is at or below their reorder level.
  final List<InventoryItem> belowReorder;

  const StockAlerts({
    this.expired = const [],
    this.expiringSoon = const [],
    this.belowReorder = const [],
  });

  static const empty = StockAlerts();

  /// Groups [items] against [today], the business date in Asia/Manila.
  factory StockAlerts.fromItems(
    Iterable<InventoryItem> items, {
    required DateTime today,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final expired = <InventoryItem>[];
    final expiringSoon = <InventoryItem>[];
    final belowReorder = <InventoryItem>[];

    for (final item in items) {
      if (item.expiredQuantity > 0) expired.add(item);

      final daysLeft = daysUntilExpiry(item, today: day);
      if (daysLeft != null &&
          daysLeft >= 0 &&
          daysLeft <= expiringWithinDays &&
          item.usableQuantity > 0) {
        expiringSoon.add(item);
      }

      if (item.usableQuantity <= item.reorderLevel) belowReorder.add(item);
    }

    // Soonest expiry first; for reorder, the biggest shortfall first.
    expiringSoon.sort(
      (a, b) => a.nextExpirationDate!.compareTo(b.nextExpirationDate!),
    );
    belowReorder.sort(
      (a, b) => (a.usableQuantity - a.reorderLevel).compareTo(
        b.usableQuantity - b.reorderLevel,
      ),
    );
    expired.sort((a, b) => a.name.compareTo(b.name));

    return StockAlerts(
      expired: List.unmodifiable(expired),
      expiringSoon: List.unmodifiable(expiringSoon),
      belowReorder: List.unmodifiable(belowReorder),
    );
  }

  /// Days from [today] to the item's next usable expiry, or null when it has
  /// none.
  static int? daysUntilExpiry(InventoryItem item, {required DateTime today}) {
    final expiry = item.nextExpirationDate;
    if (expiry == null) return null;
    final day = DateTime(today.year, today.month, today.day);
    return DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
    ).difference(day).inDays;
  }

  /// How many different items need attention.
  int get itemCount => {
    for (final item in [...expired, ...expiringSoon, ...belowReorder])
      item.id.isEmpty ? item.name : item.id,
  }.length;

  bool get isEmpty => itemCount == 0;

  /// One line for a banner, such as
  /// "2 expired, 1 expiring within 7 days, 3 below reorder level".
  String get summary {
    final parts = [
      if (expired.isNotEmpty) '${expired.length} expired',
      if (expiringSoon.isNotEmpty)
        '${expiringSoon.length} expiring within $expiringWithinDays days',
      if (belowReorder.isNotEmpty) '${belowReorder.length} below reorder level',
    ];
    return parts.join(', ');
  }
}

/// Today's date in Asia/Manila (UTC+8, no daylight saving), whatever the
/// device's own timezone.
DateTime manilaToday([DateTime? now]) {
  final manila = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime(manila.year, manila.month, manila.day);
}
