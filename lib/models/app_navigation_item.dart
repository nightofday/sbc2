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

class AppNavigationGroup {
  final String label;
  final IconData icon;
  final List<AppNavigationItem> items;
  final bool collapsible;
  final bool initiallyExpanded;

  const AppNavigationGroup({
    required this.label,
    required this.icon,
    required this.items,
    this.collapsible = true,
    this.initiallyExpanded = false,
  });

  bool containsDestination(int destinationIndex) {
    return items.any((item) => item.destinationIndex == destinationIndex);
  }
}
