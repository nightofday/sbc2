import 'package:flutter/widgets.dart';

/// Corner rounding. The café's look is near-square, so every card, button,
/// field, badge and dialog uses the same small radius.
class AppRadius {
  const AppRadius._();

  static const double value = 2;
  static const Radius corner = Radius.circular(value);
  static const BorderRadius all = BorderRadius.all(corner);
}
