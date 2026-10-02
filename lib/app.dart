import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/state/business_refresh_controller.dart';
import 'core/state/inventory_refresh_controller.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/supabase_dashboard_repository.dart';
import 'data/repositories/supabase_expense_repository.dart';
import 'data/repositories/supabase_finance_repository.dart';
import 'data/repositories/supabase_inventory_repository.dart';
import 'data/repositories/supabase_menu_repository.dart';
import 'data/repositories/supabase_order_repository.dart';
import 'data/repositories/supabase_purchasing_repository.dart';
import 'data/repositories/supabase_reporting_repository.dart';
import 'data/repositories/supabase_supplier_repository.dart';
import 'data/repositories/supabase_user_repository.dart';
import 'domain/repositories/dashboard_repository.dart';
import 'domain/repositories/expense_repository.dart';
import 'domain/repositories/finance_repository.dart';
import 'domain/repositories/inventory_repository.dart';
import 'domain/repositories/menu_repository.dart';
import 'domain/repositories/order_repository.dart';
import 'domain/repositories/purchasing_repository.dart';
import 'domain/repositories/reporting_repository.dart';
import 'domain/repositories/supplier_repository.dart';
import 'domain/repositories/user_repository.dart';
import 'models/app_navigation_item.dart';
import 'models/app_user_profile.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/expenses/expenses_screen.dart';
import 'screens/finance/sales_finance_screen.dart';
import 'screens/inventory/inventory_count_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/menu/menu_management_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/purchasing/purchasing_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/reports/transaction_traceability_screen.dart';
import 'screens/suppliers/suppliers_screen.dart';
import 'screens/users/users_screen.dart';
import 'widgets/layout/app_shell.dart';

class StreetBowlApp extends StatefulWidget {
  const StreetBowlApp({super.key});

  @override
  State<StreetBowlApp> createState() => _StreetBowlAppState();
}

class _StreetBowlAppState extends State<StreetBowlApp> {
  late final DashboardRepository _dashboardRepository;
  late final OrderRepository _orderRepository;
  late final ReportingRepository _reportingRepository;
  late final PurchasingRepository _purchasingRepository;
  late final InventoryRepository _inventoryRepository;
  late final MenuRepository _menuRepository;
  late final ExpenseRepository _expenseRepository;
  late final FinanceRepository _financeRepository;
  late final SupplierRepository _supplierRepository;
  late final UserRepository _userRepository;
  late final BusinessRefreshController _businessRefreshController;
  late final InventoryRefreshController _inventoryRefreshController;

  @override
  void initState() {
    super.initState();
    _dashboardRepository = SupabaseDashboardRepository();
    _orderRepository = SupabaseOrderRepository();
    _reportingRepository = SupabaseReportingRepository();
    _purchasingRepository = SupabasePurchasingRepository();
    _inventoryRepository = SupabaseInventoryRepository();
    _menuRepository = SupabaseMenuRepository();
    _expenseRepository = SupabaseExpenseRepository();
    _financeRepository = SupabaseFinanceRepository();
    _supplierRepository = SupabaseSupplierRepository();
    _userRepository = SupabaseUserRepository();
    _businessRefreshController = BusinessRefreshController();
    _inventoryRefreshController = InventoryRefreshController(
      onRefresh: _businessRefreshController.refresh,
    );
  }

  @override
  void dispose() {
    _inventoryRefreshController.dispose();
    _businessRefreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Street Bowl Café Management System',
      theme: AppTheme.light,
      home: AuthGate(authenticatedBuilder: _buildAuthenticatedApp),
    );
  }

  Widget _buildAuthenticatedApp(AppUserProfile profile) {
    final isCashier = profile.isCashier;
    final pages = <Widget>[];

    AppNavigationItem destination({
      required String label,
      required IconData icon,
      required Widget page,
    }) {
      final destinationIndex = pages.length;
      pages.add(page);
      return AppNavigationItem(
        label: label,
        icon: icon,
        destinationIndex: destinationIndex,
      );
    }

    final groups = <AppNavigationGroup>[
      AppNavigationGroup(
        label: 'MAIN',
        icon: Icons.home_outlined,
        collapsible: false,
        items: [
          destination(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            page: DashboardScreen(
              orderRepository: _orderRepository,
              dashboardRepository: _dashboardRepository,
              refreshListenable: _businessRefreshController,
              onDataChanged: _inventoryRefreshController.refresh,
            ),
          ),
        ],
      ),
      AppNavigationGroup(
        label: 'SALES & FINANCE',
        icon: Icons.point_of_sale_outlined,
        initiallyExpanded: true,
        items: [
          destination(
            label: 'Orders / POS',
            icon: Icons.receipt_long_outlined,
            page: OrdersScreen(
              orderRepository: _orderRepository,
              canManageOrders: !isCashier,
              refreshListenable: _businessRefreshController,
              onDataChanged: _inventoryRefreshController.refresh,
            ),
          ),
          if (!isCashier)
            destination(
              label: 'Finance Overview',
              icon: Icons.account_balance_wallet_outlined,
              page: SalesFinanceScreen(
                reportingRepository: _reportingRepository,
                financeRepository: _financeRepository,
                refreshListenable: _businessRefreshController,
                onDataChanged: _businessRefreshController.refresh,
              ),
            ),
        ],
      ),
      if (!isCashier)
        AppNavigationGroup(
          label: 'MENU & PRODUCTS',
          icon: Icons.restaurant_menu_outlined,
          items: [
            destination(
              label: 'Menu Management',
              icon: Icons.fastfood_outlined,
              page: MenuManagementScreen(
                menuRepository: _menuRepository,
                refreshListenable: _businessRefreshController,
                onDataChanged: _businessRefreshController.refresh,
              ),
            ),
          ],
        ),
      AppNavigationGroup(
        label: 'INVENTORY',
        icon: Icons.inventory_2_outlined,
        initiallyExpanded: true,
        items: [
          destination(
            label: 'Stock Overview',
            icon: Icons.view_list_outlined,
            page: InventoryScreen(
              inventoryRepository: _inventoryRepository,
              refreshController: _inventoryRefreshController,
              canManageInventory: !isCashier,
              view: InventoryView.overview,
            ),
          ),
          if (!isCashier) ...[
            destination(
              label: 'Release Supplies',
              icon: Icons.output_outlined,
              page: InventoryScreen(
                inventoryRepository: _inventoryRepository,
                refreshController: _inventoryRefreshController,
                canManageInventory: true,
                view: InventoryView.release,
              ),
            ),
            destination(
              label: 'Dispose Stock',
              icon: Icons.delete_sweep_outlined,
              page: InventoryScreen(
                inventoryRepository: _inventoryRepository,
                refreshController: _inventoryRefreshController,
                canManageInventory: true,
                view: InventoryView.disposal,
              ),
            ),
            destination(
              label: 'Inventory Count',
              icon: Icons.fact_check_outlined,
              page: InventoryCountScreen(
                inventoryRepository: _inventoryRepository,
                refreshController: _inventoryRefreshController,
              ),
            ),
            destination(
              label: 'Stock Adjustment',
              icon: Icons.tune,
              page: InventoryScreen(
                inventoryRepository: _inventoryRepository,
                refreshController: _inventoryRefreshController,
                canManageInventory: true,
                view: InventoryView.adjustment,
              ),
            ),
            destination(
              label: 'Inventory History',
              icon: Icons.history,
              page: InventoryScreen(
                inventoryRepository: _inventoryRepository,
                refreshController: _inventoryRefreshController,
                canManageInventory: true,
                view: InventoryView.history,
              ),
            ),
          ],
        ],
      ),
      if (!isCashier) ...[
        AppNavigationGroup(
          label: 'PURCHASING',
          icon: Icons.shopping_cart_checkout_outlined,
          items: [
            destination(
              label: 'Purchase Orders',
              icon: Icons.assignment_outlined,
              page: PurchasingScreen(
                purchasingRepository: _purchasingRepository,
                onInventoryChanged: _inventoryRefreshController.refresh,
              ),
            ),
            destination(
              label: 'Suppliers',
              icon: Icons.local_shipping_outlined,
              page: SuppliersScreen(
                supplierRepository: _supplierRepository,
                onDataChanged: _businessRefreshController.refresh,
              ),
            ),
          ],
        ),
        AppNavigationGroup(
          label: 'EXPENSES',
          icon: Icons.payments_outlined,
          items: [
            destination(
              label: 'Expense Records',
              icon: Icons.receipt_outlined,
              page: ExpensesScreen(
                expenseRepository: _expenseRepository,
                refreshListenable: _businessRefreshController,
                onDataChanged: _businessRefreshController.refresh,
              ),
            ),
          ],
        ),
        AppNavigationGroup(
          label: 'REPORTS',
          icon: Icons.bar_chart_outlined,
          items: [
            destination(
              label: 'Reports Overview',
              icon: Icons.analytics_outlined,
              page: ReportsScreen(
                reportingRepository: _reportingRepository,
                refreshListenable: _businessRefreshController,
              ),
            ),
            destination(
              label: 'Transaction Traceability',
              icon: Icons.manage_search_outlined,
              page: TransactionTraceabilityScreen(
                reportingRepository: _reportingRepository,
                refreshListenable: _businessRefreshController,
              ),
            ),
          ],
        ),
        AppNavigationGroup(
          label: 'ADMINISTRATION',
          icon: Icons.admin_panel_settings_outlined,
          items: [
            destination(
              label: 'User Management',
              icon: Icons.people_outline,
              page: UsersScreen(
                userRepository: _userRepository,
                canManageRoles: profile.roleCode.toUpperCase() == 'ADMIN',
              ),
            ),
          ],
        ),
      ],
    ];

    return AppShell(
      profile: profile,
      groups: groups,
      pages: pages,
      onSignOut: () => Supabase.instance.client.auth.signOut(),
    );
  }
}
