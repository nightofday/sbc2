import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/user_repository.dart';
import '../../models/user_record.dart';

class SupabaseUserRepository implements UserRepository {
  final SupabaseClient _client;

  SupabaseUserRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<UserRecord>> getUsers() async {
    final rows = await _client
        .from('v_user_management')
        .select()
        .order('display_name', ascending: true);

    return (rows as List)
        .map((raw) => UserRecord.fromMap(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  @override
  Future<UserRecord?> getUserById(String id) async {
    final rows = await _client
        .from('v_user_management')
        .select()
        .eq('id', id)
        .limit(1);

    if ((rows as List).isEmpty) return null;

    return UserRecord.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<List<UserRoleOption>> getRoles() async {
    final rows = await _client
        .from('roles')
        .select('id, code, name')
        .order('name', ascending: true);

    return (rows as List)
        .map(
          (raw) =>
              UserRoleOption.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
  }

  @override
  Future<void> createEmployee({
    required String email,
    required String temporaryPassword,
    required String displayName,
    required String roleCode,
  }) async {
    final response = await _client.functions.invoke(
      'create-employee',
      body: {
        'email': email.trim(),
        'password': temporaryPassword,
        'display_name': displayName.trim(),
        'role_code': roleCode,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      throw Exception('Unable to create employee account.');
    }
  }

  @override
  Future<void> updateEmployee({
    required String userId,
    required String displayName,
    required String status,
    required String roleId,
  }) async {
    await _client.rpc(
      'update_employee_profile',
      params: {
        'p_user_id': userId,
        'p_display_name': displayName.trim(),
        'p_status': status.toUpperCase(),
        'p_role_id': roleId.isEmpty ? null : roleId,
      },
    );
  }

  @override
  Future<void> createUser(UserRecord user) {
    throw UnsupportedError(
      'Use createEmployee() to create an authenticated employee.',
    );
  }

  @override
  Future<void> updateUser(UserRecord user) async {
    await updateEmployee(
      userId: user.id,
      displayName: user.name,
      status: user.status,
      roleId: user.roleId,
    );
  }

  @override
  Future<void> deleteUser(String id) async {
    final user = await getUserById(id);
    if (user == null) return;

    await updateEmployee(
      userId: id,
      displayName: user.name,
      status: 'INACTIVE',
      roleId: user.roleId,
    );
  }
}
