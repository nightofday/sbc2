import 'package:flutter/material.dart';

import '../common/business_profile_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/app_navigation_item.dart';
import '../../models/app_user_profile.dart';
import '../../core/theme/app_radius.dart';

class AppSidebar extends StatefulWidget {
  final AppUserProfile profile;
  final List<AppNavigationGroup> groups;
  final int selectedIndex;
  final bool compact;
  final ValueChanged<int> onItemSelected;
  final Future<void> Function() onSignOut;
  final VoidCallback? onClose;

  /// Shown above the account, such as the stock alerts button. Told whether
  /// the sidebar is compact.
  final Widget Function(bool compact)? footerBuilder;

  const AppSidebar({
    super.key,
    required this.profile,
    required this.groups,
    required this.selectedIndex,
    this.compact = false,
    required this.onItemSelected,
    required this.onSignOut,
    this.onClose,
    this.footerBuilder,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  late final Map<String, bool> _expandedGroups;

  @override
  void initState() {
    super.initState();
    _expandedGroups = {
      for (final group in widget.groups)
        group.label:
            !group.collapsible ||
            group.initiallyExpanded ||
            group.containsDestination(widget.selectedIndex),
    };
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final availableGroups = widget.groups.map((group) => group.label).toSet();
    _expandedGroups.removeWhere((label, _) => !availableGroups.contains(label));

    for (final group in widget.groups) {
      _expandedGroups.putIfAbsent(
        group.label,
        () => !group.collapsible || group.initiallyExpanded,
      );
      if (group.containsDestination(widget.selectedIndex)) {
        _expandedGroups[group.label] = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.compact ? 76 : AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(right: BorderSide(color: AppColors.gray200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SidebarBrand(compact: widget.compact, onClose: widget.onClose),
          SizedBox(height: widget.compact ? 20 : 14),
          Expanded(
            child: widget.compact
                ? _buildCompactNavigation()
                : _buildGroupedNavigation(),
          ),
          if (widget.footerBuilder case final footer?)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 0 : 10,
                vertical: 6,
              ),
              child: Center(child: footer(widget.compact)),
            ),
          _SidebarAccount(
            profile: widget.profile,
            compact: widget.compact,
            onSignOut: widget.onSignOut,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNavigation() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (
          int groupIndex = 0;
          groupIndex < widget.groups.length;
          groupIndex++
        ) ...[
          if (groupIndex > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Divider(height: 1),
            ),
          for (final item in widget.groups[groupIndex].items)
            _SidebarItem(
              label: item.label,
              icon: item.icon,
              selected: widget.selectedIndex == item.destinationIndex,
              compact: true,
              onTap: () => widget.onItemSelected(item.destinationIndex),
            ),
        ],
      ],
    );
  }

  Widget _buildGroupedNavigation() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [for (final group in widget.groups) _buildGroup(group)],
    );
  }

  Widget _buildGroup(AppNavigationGroup group) {
    if (!group.collapsible) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(label: group.label),
            for (final item in group.items)
              _SidebarItem(
                label: item.label,
                icon: item.icon,
                selected: widget.selectedIndex == item.destinationIndex,
                onTap: () => widget.onItemSelected(item.destinationIndex),
              ),
          ],
        ),
      );
    }

    final expanded = _expandedGroups[group.label] ?? false;
    final selected = group.containsDestination(widget.selectedIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          _SidebarGroupHeader(
            label: group.label,
            icon: group.icon,
            expanded: expanded,
            selected: selected,
            onTap: () {
              setState(() => _expandedGroups[group.label] = !expanded);
            },
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: expanded
                  ? Column(
                      children: [
                        for (final item in group.items)
                          _SidebarItem(
                            label: item.label,
                            icon: item.icon,
                            selected:
                                widget.selectedIndex == item.destinationIndex,
                            indent: 18,
                            onTap: () =>
                                widget.onItemSelected(item.destinationIndex),
                          ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  final bool compact;
  final VoidCallback? onClose;

  const _SidebarBrand({required this.compact, this.onClose});

  @override
  Widget build(BuildContext context) {
    final businessName = BusinessProfileScope.of(context).tradeName;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Center(
          child: Tooltip(
            message: '$businessName Management System',
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.restaurant, size: 20, color: AppColors.white),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: AppTextStyles.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                const Text('MANAGEMENT SYSTEM', style: AppTextStyles.overline),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close navigation',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 18, 4),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.gray500,
          fontWeight: FontWeight.w700,
          letterSpacing: .7,
        ),
      ),
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarGroupHeader({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.gray700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.all,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .35,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 19,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final double indent;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    this.compact = false,
    this.indent = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final item = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 14 + indent,
        3,
        compact ? 8 : 14,
        3,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.all,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySoft : Colors.transparent,
              borderRadius: AppRadius.all,
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: AppRadius.corner,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 9),
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.gray700,
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: selected ? AppColors.primary : AppColors.gray700,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return compact ? Tooltip(message: label, child: item) : item;
  }
}

class _SidebarAccount extends StatelessWidget {
  final AppUserProfile profile;
  final bool compact;
  final Future<void> Function() onSignOut;

  const _SidebarAccount({
    required this.profile,
    required this.compact,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: profile.displayName,
              child: const CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: IconButton(
              tooltip: 'Sign out',
              onPressed: () => onSignOut(),
              icon: const Icon(Icons.logout, size: 19),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => onSignOut(),
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ],
    );
  }
}
