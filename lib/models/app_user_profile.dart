class AppUserProfile {
  final String id;
  final String email;
  final String displayName;
  final String status;
  final String roleCode;
  final String roleName;

  const AppUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.status,
    required this.roleCode,
    required this.roleName,
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';
  bool get isCashier => roleCode.toUpperCase() == 'CASHIER';

  factory AppUserProfile.fromMap(
    Map<String, dynamic> map, {
    required String email,
  }) {
    final role = map['roles'];
    final roleMap = role is Map<String, dynamic> ? role : <String, dynamic>{};

    return AppUserProfile(
      id: map['id']?.toString() ?? '',
      email: email,
      displayName: (map['display_name']?.toString().trim().isNotEmpty ?? false)
          ? map['display_name'].toString()
          : email,
      status: map['status']?.toString() ?? 'PENDING',
      roleCode: roleMap['code']?.toString() ?? '',
      roleName: roleMap['name']?.toString() ?? '',
    );
  }
}
