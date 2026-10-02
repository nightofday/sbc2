class AppUserProfile {
  final String id;
  final String email;
  final String displayName;
  final String status;
  final String roleCode;
  final String roleName;

  /// Permission codes granted to this user's role, such as `menu.manage`.
  final Set<String> permissions;

  const AppUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.status,
    required this.roleCode,
    required this.roleName,
    this.permissions = const {},
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  /// Whether this user's role holds [permission]. The server checks the
  /// same permission again on every action; this only decides what the app
  /// shows.
  bool can(String permission) => isActive && permissions.contains(permission);

  factory AppUserProfile.fromMap(
    Map<String, dynamic> map, {
    required String email,
  }) {
    final role = map['roles'];
    final roleMap = role is Map<String, dynamic> ? role : <String, dynamic>{};
    final permissions = <String>{};
    for (final grant in (roleMap['role_permissions'] as List?) ?? const []) {
      final permission = grant is Map ? grant['permissions'] : null;
      final code = permission is Map ? permission['code']?.toString() : null;
      if (code != null && code.isNotEmpty) permissions.add(code);
    }

    return AppUserProfile(
      id: map['id']?.toString() ?? '',
      email: email,
      displayName: (map['display_name']?.toString().trim().isNotEmpty ?? false)
          ? map['display_name'].toString()
          : email,
      status: map['status']?.toString() ?? 'PENDING',
      roleCode: roleMap['code']?.toString() ?? '',
      roleName: roleMap['name']?.toString() ?? '',
      permissions: permissions,
    );
  }
}
