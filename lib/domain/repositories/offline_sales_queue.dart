import 'package:flutter/foundation.dart';

import '../../models/offline_sale.dart';

/// The sales waiting on this device to be sent. Listeners are told when the
/// queue, the connection state or a sync changes.
abstract class OfflineSalesQueue implements Listenable {
  /// True after the last attempt to reach the server failed.
  bool get isOffline;

  bool get isSyncing;

  /// Sales of the signed-in user still waiting, oldest first.
  List<OfflineSale> get waitingSales;

  /// Sales the server refused, kept for a manager to resolve.
  List<OfflineSale> get rejectedSales;

  /// Sends every waiting sale. Stops quietly if the server is unreachable.
  Future<void> syncPending();

  /// Puts a refused sale back in the queue to be sent again.
  Future<void> retrySale(String requestId);

  /// Removes a refused sale from this device. It is not recorded anywhere
  /// else, so the caller must have confirmed that with the user.
  Future<void> discardSale(String requestId);
}

/// Sends one stored sale to the server, dated at the time it was made.
abstract class OfflineSaleUploader {
  /// Completes when the server holds the sale. Sending the same sale again
  /// is safe: the server answers with the order it already stored.
  Future<void> uploadOfflineSale(OfflineSale sale);
}

/// Raised when something cannot be done until the connection is back.
class OfflineUnavailableException implements Exception {
  final String message;

  const OfflineUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Raised when an action needs every offline sale to be sent first.
class OfflineSalesPendingException implements Exception {
  final int count;

  const OfflineSalesPendingException(this.count);

  @override
  String toString() =>
      '$count offline ${count == 1 ? 'sale has' : 'sales have'} not been sent '
      'yet. Connect to the internet and wait for them to sync first.';
}
