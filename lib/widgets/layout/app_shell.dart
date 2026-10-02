import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/app_navigation_item.dart';
import '../../models/app_user_profile.dart';
import '../common/business_profile_scope.dart';
import 'app_navigation_drawer.dart';

/// The frame around every page: the navigation drawer, the app-wide banner
/// and the selected page.
class AppShell extends StatefulWidget {
  final AppUserProfile profile;
  final List<AppNavigationGroup> groups;
  final List<Widget> pages;
  final Future<void> Function() onSignOut;

  /// Shown above every page, for app-wide notices.
  final Widget? banner;

  const AppShell({
    super.key,
    required this.profile,
    required this.groups,
    required this.pages,
    required this.onSignOut,
    this.banner,
  });

  /// From this width the drawer stays open beside the page, as on a tablet
  /// in landscape. Below it the drawer slides in from a menu button.
  static const double permanentDrawerBreakpoint = 1000;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_selectedIndex >= widget.pages.length) {
      _selectedIndex = 0;
    }
  }

  AppNavigationDrawer _drawer({required bool closeOnSelect}) {
    return AppNavigationDrawer(
      profile: widget.profile,
      groups: widget.groups,
      selectedDestination: _selectedIndex,
      onDestinationSelected: (index) {
        _selectDestination(index);
        if (closeOnSelect) _scaffoldKey.currentState?.closeDrawer();
      },
      onSignOut: widget.onSignOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppShell.permanentDrawerBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: AppSpacing.sidebarWidth,
                  child: Theme(
                    // A permanent drawer sits flat beside the page.
                    data: Theme.of(context).copyWith(
                      drawerTheme: const DrawerThemeData(
                        elevation: 0,
                        width: AppSpacing.sidebarWidth,
                        shape: RoundedRectangleBorder(),
                      ),
                    ),
                    child: _drawer(closeOnSelect: false),
                  ),
                ),
                const VerticalDivider(width: 1, color: AppColors.gray200),
                Expanded(child: _buildPages()),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            // Each page shows its own title; the bar says whose system it is.
            title: Text(
              BusinessProfileScope.of(context).tradeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          drawer: _drawer(closeOnSelect: true),
          body: _buildPages(),
        );
      },
    );
  }

  Widget _buildPages() {
    final pages = IndexedStack(index: _selectedIndex, children: widget.pages);
    final banner = widget.banner;
    if (banner == null) return pages;

    return Column(
      children: [
        banner,
        Expanded(child: pages),
      ],
    );
  }

  void _selectDestination(int index) {
    if (index < 0 || index >= widget.pages.length || index == _selectedIndex) {
      return;
    }
    setState(() => _selectedIndex = index);
  }
}
