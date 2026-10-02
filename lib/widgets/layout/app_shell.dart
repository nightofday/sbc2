import 'package:flutter/material.dart';

import '../common/business_profile_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/app_navigation_item.dart';
import '../../models/app_user_profile.dart';
import 'app_sidebar.dart';

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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _phoneBreakpoint = 700;
  static const double _expandedSidebarBreakpoint = 1120;

  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_selectedIndex >= widget.pages.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _phoneBreakpoint) {
          return _buildPhoneShell(constraints.maxWidth);
        }

        final compactNavigation =
            constraints.maxWidth < _expandedSidebarBreakpoint;

        return Scaffold(
          backgroundColor: AppColors.gray100,
          body: Row(
            children: [
              AppSidebar(
                profile: widget.profile,
                groups: widget.groups,
                selectedIndex: _selectedIndex,
                compact: compactNavigation,
                onItemSelected: _selectDestination,
                onSignOut: widget.onSignOut,
              ),
              Expanded(child: _buildPages()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhoneShell(double availableWidth) {
    final drawerWidth = availableWidth < 360 ? availableWidth * .88 : 320.0;

    return Scaffold(
      backgroundColor: AppColors.gray100,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        // Each page shows its own title; the bar says whose system it is.
        title: Text(
          BusinessProfileScope.of(context).tradeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h3,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: Drawer(
        width: drawerWidth,
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: Builder(
            builder: (drawerContext) => AppSidebar(
              profile: widget.profile,
              groups: widget.groups,
              selectedIndex: _selectedIndex,
              onItemSelected: (index) {
                _selectDestination(index);
                Navigator.of(drawerContext).pop();
              },
              onSignOut: widget.onSignOut,
              onClose: () => Navigator.of(drawerContext).pop(),
            ),
          ),
        ),
      ),
      body: _buildPages(),
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
