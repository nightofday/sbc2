import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/core/theme/app_theme.dart';
import 'package:sbc_management_system/models/app_navigation_item.dart';
import 'package:sbc_management_system/models/app_user_profile.dart';
import 'package:sbc_management_system/widgets/layout/app_shell.dart';

const _profile = AppUserProfile(
  id: 'user-1',
  email: 'ana@example.com',
  displayName: 'Ana Reyes',
  status: 'ACTIVE',
  roleCode: 'MANAGER',
  roleName: 'Manager',
);

// Labels are short because the test font draws every letter 14 px wide.
const _groups = [
  AppNavigationGroup(
    label: '',
    items: [
      AppNavigationItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        destinationIndex: 0,
      ),
    ],
  ),
  AppNavigationGroup(
    label: 'Inventory',
    items: [
      AppNavigationItem(
        label: 'Stock',
        icon: Icons.view_list_outlined,
        destinationIndex: 1,
      ),
      AppNavigationItem(
        label: 'History',
        icon: Icons.history,
        destinationIndex: 2,
      ),
    ],
  ),
];

Widget _app({required Future<void> Function() onSignOut}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: AppShell(
      profile: _profile,
      groups: _groups,
      onSignOut: onSignOut,
      pages: const [
        Center(child: Text('Dashboard page')),
        Center(child: Text('Stock page')),
        Center(child: Text('History page')),
      ],
    ),
  );
}

void main() {
  testWidgets('on a tablet in landscape the drawer stays beside the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(onSignOut: () async {}));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDrawer), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Dashboard page'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('History page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a narrow screen the drawer opens from the menu button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var signedOut = false;
    await tester.pumpWidget(_app(onSignOut: () async => signedOut = true));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.text('Street Bowl Café'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();

    // Choosing a page closes the drawer.
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.text('Stock page'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });
}
