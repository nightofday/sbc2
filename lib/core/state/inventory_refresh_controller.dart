import 'package:flutter/foundation.dart';

class InventoryRefreshController extends ChangeNotifier {
  final VoidCallback? onRefresh;

  InventoryRefreshController({this.onRefresh});

  void refresh() {
    notifyListeners();
    onRefresh?.call();
  }
}
