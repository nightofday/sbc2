import 'package:flutter/material.dart';

class AppNavigationItem {
  final String label;
  final IconData icon;
  final int destinationIndex;

  const AppNavigationItem({
    required this.label,
    required this.icon,
    required this.destinationIndex,
  });
}

/// A titled section of the navigation drawer.
class AppNavigationGroup {
  /// Shown above the section; empty for a section without a heading.
  final String label;
  final List<AppNavigationItem> items;

  const AppNavigationGroup({required this.label, required this.items});

  bool containsDestination(int destinationIndex) {
    return items.any((item) => item.destinationIndex == destinationIndex);
  }
}
