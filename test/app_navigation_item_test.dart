import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/app_navigation_item.dart';

void main() {
  test('navigation group identifies its destination indexes', () {
    const group = AppNavigationGroup(
      label: 'INVENTORY',
      icon: Icons.inventory_2_outlined,
      items: [
        AppNavigationItem(
          label: 'Stock Overview',
          icon: Icons.view_list_outlined,
          destinationIndex: 2,
        ),
        AppNavigationItem(
          label: 'Release Supplies',
          icon: Icons.output_outlined,
          destinationIndex: 3,
        ),
        AppNavigationItem(
          label: 'Dispose Stock',
          icon: Icons.delete_sweep_outlined,
          destinationIndex: 4,
        ),
        AppNavigationItem(
          label: 'Inventory Count',
          icon: Icons.fact_check_outlined,
          destinationIndex: 5,
        ),
        AppNavigationItem(
          label: 'Stock Adjustment',
          icon: Icons.tune,
          destinationIndex: 6,
        ),
        AppNavigationItem(
          label: 'Inventory History',
          icon: Icons.history,
          destinationIndex: 7,
        ),
      ],
    );

    expect(group.containsDestination(2), isTrue);
    expect(group.containsDestination(7), isTrue);
    expect(group.containsDestination(1), isFalse);
    expect(group.items.map((item) => item.destinationIndex), [
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
  });
}
