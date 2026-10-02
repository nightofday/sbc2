class UserRecord {
  final String id;
  final String name;
  final String username;
  final String email;
  final String role;
  final String roleCode;
  final String roleId;
  final String status;

  const UserRecord({
    this.id = '',
    required this.name,
    required this.username,
    this.email = '',
    required this.role,
    this.roleCode = '',
    this.roleId = '',
    required this.status,
  });

  factory UserRecord.fromMap(Map<String, dynamic> map) {
    final email = map['email']?.toString() ?? '';

    return UserRecord(
      id: map['id']?.toString() ?? '',
      name: map['display_name']?.toString() ?? email,
      username: email,
      email: email,
      role: map['role_name']?.toString() ?? 'Unassigned',
      roleCode: map['role_code']?.toString() ?? '',
      roleId: map['role_id']?.toString() ?? '',
      status: _statusLabel(map['status']?.toString() ?? 'PENDING'),
    );
  }

  UserRecord copyWith({
    String? id,
    String? name,
    String? username,
    String? email,
    String? role,
    String? roleCode,
    String? roleId,
    String? status,
  }) {
    return UserRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      roleCode: roleCode ?? this.roleCode,
      roleId: roleId ?? this.roleId,
      status: status ?? this.status,
    );
  }

  static String _statusLabel(String value) {
    final lower = value.toLowerCase();
    return lower.isEmpty ? value : lower[0].toUpperCase() + lower.substring(1);
  }
}

class UserRoleOption {
  final String id;
  final String code;
  final String name;

  const UserRoleOption({
    required this.id,
    required this.code,
    required this.name,
  });

  factory UserRoleOption.fromMap(Map<String, dynamic> map) {
    return UserRoleOption(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}
