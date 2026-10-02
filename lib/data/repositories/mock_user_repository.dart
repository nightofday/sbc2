import '../../domain/repositories/user_repository.dart';
import '../../models/user_record.dart';
import '../mock_data.dart';

class MockUserRepository implements UserRepository {
  final List<UserRecord> _users = List<UserRecord>.from(MockData.users);

  @override
  Future<List<UserRecord>> getUsers() async {
    return List<UserRecord>.unmodifiable(_users);
  }

  @override
  Future<UserRecord?> getUserById(String id) async {
    for (final user in _users) {
      if (user.id == id) return user;
    }
    return null;
  }

  @override
  Future<List<UserRoleOption>> getRoles() async => const [];

  @override
  Future<void> createEmployee({
    required String email,
    required String temporaryPassword,
    required String displayName,
    required String roleCode,
  }) async {}

  @override
  Future<void> updateEmployee({
    required String userId,
    required String displayName,
    required String status,
    required String roleId,
  }) async {
    final index = _users.indexWhere((entry) => entry.id == userId);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(
      name: displayName,
      status: status,
      roleId: roleId,
    );
  }

  @override
  Future<void> createUser(UserRecord user) async {
    _users.add(user);
  }

  @override
  Future<void> updateUser(UserRecord user) async {
    final index = _users.indexWhere((entry) => entry.id == user.id);
    if (index == -1) return;
    _users[index] = user;
  }

  @override
  Future<void> deleteUser(String id) async {
    _users.removeWhere((user) => user.id == id);
  }
}
