import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/data/repositories/mock_order_repository.dart';
import 'package:sbc_management_system/domain/repositories/dashboard_repository.dart';
import 'package:sbc_management_system/models/dashboard_summary.dart';
import 'package:sbc_management_system/screens/dashboard/dashboard_screen.dart';

class _CountingDashboardRepository implements DashboardRepository {
  int calls = 0;

  @override
  Future<DashboardSummary> getTodaySummary() async {
    calls++;
    final netSales = calls == 1 ? 0.0 : 207.0;
    return DashboardSummary(
      grossSales: netSales,
      refunds: 0,
      netSales: netSales,
      completedOrders: calls == 1 ? 0 : 1,
      openOrders: 0,
      averageOrder: netSales,
      expenses: 0,
      netAfterExpenses: netSales,
      businessScope: true,
    );
  }
}

void main() {
  testWidgets('dashboard reloads and redraws when a refresh is notified', (
    tester,
  ) async {
    final refresh = ChangeNotifier();
    final dashboardRepository = _CountingDashboardRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            orderRepository: MockOrderRepository(),
            dashboardRepository: dashboardRepository,
            refreshListenable: refresh,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('₱207.00'), findsNothing);

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    refresh.notifyListeners();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(dashboardRepository.calls, 2);
    expect(find.text('₱207.00'), findsWidgets);
  });
}
