import 'package:flutter/foundation.dart';

import '../../domain/repositories/inventory_repository.dart';
import '../../models/stock_alerts.dart';

/// Loads the stock alerts shown by the sidebar bell and the dashboard, and
/// reloads them whenever [refreshListenable] reports an inventory change.
/// Like the other refresh controllers this is in-process only: another
/// device's changes show after the next reload.
class StockAlertsController extends ChangeNotifier {
  final InventoryRepository _repository;
  final Listenable? refreshListenable;
  final DateTime Function() _today;

  StockAlerts _alerts = StockAlerts.empty;
  Object? _error;
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;

  StockAlertsController(
    this._repository, {
    this.refreshListenable,
    DateTime Function()? today,
  }) : _today = today ?? manilaToday {
    refreshListenable?.addListener(load);
  }

  StockAlerts get alerts => _alerts;

  /// The last load's failure, if it failed. Earlier alerts are kept.
  Object? get error => _error;

  bool get loading => _loading;

  Future<void> load() async {
    final generation = ++_generation;
    _loading = true;
    _notify();

    try {
      final items = await _repository.getInventoryItems();
      if (generation != _generation) return;
      _alerts = StockAlerts.fromItems(items, today: _today());
      _error = null;
    } catch (error) {
      if (generation != _generation) return;
      _error = error;
    }

    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    refreshListenable?.removeListener(load);
    super.dispose();
  }
}
