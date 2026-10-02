import '../../models/user_record.dart';

abstract class UserRepository {
  Future<List<UserRecord>> getUsers();

  Future<UserRecord?> getUserById(String id);

  Future<List<UserRoleOption>> getRoles();

  Future<void> createEmployee({
    required String email,
    required String temporaryPassword,
    required String displayName,
    required String roleCode,
  });

  Future<void> updateEmployee({
    required String userId,
    required String displayName,
    required String status,
    required String roleId,
  });

  Future<void> createUser(UserRecord user);

  Future<void> updateUser(UserRecord user);

  Future<void> deleteUser(String id);
}
