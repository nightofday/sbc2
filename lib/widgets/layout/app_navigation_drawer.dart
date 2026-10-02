import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/app_navigation_item.dart';
import '../../models/app_user_profile.dart';
import '../common/business_profile_scope.dart';

/// The app's navigation: a Material 3 navigation drawer with the business
/// name and signed-in person at the top, one titled section per area, and
/// sign-out at the end.
///
/// The same widget is shown permanently beside the page on wide screens and
/// as a sliding drawer on narrow ones.
class AppNavigationDrawer extends StatelessWidget {
  final AppUserProfile profile;
  final List<AppNavigationGroup> groups;
  final int selectedDestination;
  final ValueChanged<int> onDestinationSelected;
  final Future<void> Function() onSignOut;

  const AppNavigationDrawer({
    super.key,
    required this.profile,
    required this.groups,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    // The drawer numbers its destinations in the order they are drawn; the
    // pages are numbered by destinationIndex. This list joins the two.
    final items = [for (final group in groups) ...group.items];
    final selected = items.indexWhere(
      (item) => item.destinationIndex == selectedDestination,
    );

    return NavigationDrawer(
      selectedIndex: selected < 0 ? null : selected,
      onDestinationSelected: (index) =>
          onDestinationSelected(items[index].destinationIndex),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _DrawerHeader(profile: profile),
        for (int g = 0; g < groups.length; g++) ...[
          if (g > 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 8, 28, 0),
              child: Divider(),
            ),
          if (groups[g].label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
              child: Text(
                groups[g].label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.gray700,
                ),
              ),
            ),
          for (final item in groups[g].items)
            NavigationDrawerDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 8, 28, 0),
          child: Divider(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          child: ListTile(
            shape: const StadiumBorder(),
            // Lines up with the destinations above it.
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            horizontalTitleGap: 12,
            minLeadingWidth: 24,
            leading: const Icon(Icons.logout),
            title: Text(
              'Sign out',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.gray700,
              ),
            ),
            onTap: onSignOut,
          ),
        ),
      ],
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final AppUserProfile profile;

  const _DrawerHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final businessName = BusinessProfileScope.of(context).tradeName;
    final initial = profile.displayName.trim().isEmpty
        ? '?'
        : profile.displayName.trim()[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.ramen_dining,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  businessName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  initial,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onPrimarySoft,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium,
                    ),
                    Text(
                      profile.roleName.isEmpty
                          ? profile.roleCode
                          : profile.roleName,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
