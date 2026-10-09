import 'package:flutter/foundation.dart';

/// Lets a widget outside the sidebar, such as the stock alerts panel, ask
/// the shell to show another destination.
class AppNavigationController extends ChangeNotifier {
  int? _requested;

  /// The destination last asked for. The shell reads it when notified.
  int? get requested => _requested;

  void show(int destinationIndex) {
    _requested = destinationIndex;
    notifyListeners();
  }
}
