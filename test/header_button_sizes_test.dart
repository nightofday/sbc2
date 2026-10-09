import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/state/stock_alerts_controller.dart';
import 'package:sbc_management_system/core/theme/app_theme.dart';
import 'package:sbc_management_system/domain/repositories/inventory_repository.dart';
import 'package:sbc_management_system/models/inventory_item.dart';
import 'package:sbc_management_system/widgets/common/stock_alerts_view.dart';

class _Inventory implements InventoryRepository {
  @override
  Future<List<InventoryItem>> getInventoryItems() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Desktop browsers default to a compact density that shrinks buttons; the
  // app keeps the same 44 px buttons on every platform.
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('on ${platform.name} header buttons and the bell are 44 px', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final alerts = StockAlertsController(_Inventory());
      addTearDown(alerts.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(onPressed: () {}, child: const Text('New')),
                  OutlinedButton(onPressed: () {}, child: const Text('Out')),
                  StockAlertsButton(controller: alerts, compact: true),
                ],
              ),
            ),
          ),
        ),
      );

      double visibleHeight(Finder finder) => tester
          .getSize(
            find.descendant(of: finder, matching: find.byType(Material)).first,
          )
          .height;

      expect(visibleHeight(find.byType(ElevatedButton)), 44);
      expect(visibleHeight(find.byType(OutlinedButton)), 44);
      expect(visibleHeight(find.byType(IconButton)), 44);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
