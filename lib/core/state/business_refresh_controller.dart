import 'package:flutter/foundation.dart';

/// Notifies screens that read shared operational and financial data.
///
/// This keeps IndexedStack pages synchronized after orders, expenses, menu
/// changes, purchasing, refunds, and inventory transactions.
class BusinessRefreshController extends ChangeNotifier {
  void refresh() => notifyListeners();
}
