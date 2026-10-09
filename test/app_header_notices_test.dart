import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/app_navigation_item.dart';
import 'package:sbc_management_system/models/app_user_profile.dart';
import 'package:sbc_management_system/widgets/layout/app_page.dart';
import 'package:sbc_management_system/widgets/layout/app_shell.dart';

void main() {
  for (final (width, where) in [(1280.0, 'page header'), (390.0, 'top bar')]) {
    testWidgets('at $width px the stock alerts bell is shown once, in the '
        '$where', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            profile: const AppUserProfile(
              id: 'u',
              email: 'ana@example.com',
              displayName: 'Ana',
              status: 'ACTIVE',
              roleCode: 'MANAGER',
              roleName: 'Manager',
            ),
            groups: const [
              AppNavigationGroup(
                label: 'Main',
                icon: Icons.home_outlined,
                collapsible: false,
                items: [
                  AppNavigationItem(
                    label: 'Dashboard',
                    icon: Icons.dashboard_outlined,
                    destinationIndex: 0,
                  ),
                ],
              ),
            ],
            pages: const [AppPage(title: 'Dashboard', child: SizedBox())],
            onSignOut: () async {},
            noticesBuilder: (_) => const Icon(Icons.notifications_none),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bell = find.byIcon(Icons.notifications_none);
      expect(bell, findsOneWidget);
      final inAppBar = find.descendant(of: find.byType(AppBar), matching: bell);
      expect(inAppBar, width < 700 ? findsOneWidget : findsNothing);
      // On a wide screen it sits at the top right, level with the title.
      if (width >= 700) {
        final bellBox = tester.getRect(bell);
        final titleBox = tester.getRect(find.text('Dashboard').last);
        expect(bellBox.left, greaterThan(titleBox.right));
        expect(bellBox.top, lessThan(titleBox.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
