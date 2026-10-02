import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_management_system/models/app_user_profile.dart';

Map<String, dynamic> _row({
  String status = 'ACTIVE',
  List<String> permissions = const ['orders.checkout', 'inventory.view'],
}) => {
  'id': 'user-1',
  'display_name': 'Ana',
  'status': status,
  'roles': {
    'code': 'CASHIER',
    'name': 'Cashier',
    'role_permissions': [
      for (final code in permissions)
        {
          'permissions': {'code': code},
        },
    ],
  },
};

void main() {
  test('a user can do only what their role was granted', () {
    final profile = AppUserProfile.fromMap(_row(), email: 'ana@example.com');

    expect(profile.can('orders.checkout'), isTrue);
    expect(profile.can('inventory.view'), isTrue);
    expect(profile.can('orders.refund'), isFalse);
    expect(profile.can('menu.manage'), isFalse);
  });

  test('an inactive account can do nothing', () {
    final profile = AppUserProfile.fromMap(
      _row(status: 'SUSPENDED'),
      email: 'ana@example.com',
    );

    expect(profile.can('orders.checkout'), isFalse);
  });

  test('a role with no grants, or a missing role, fails closed', () {
    expect(
      AppUserProfile.fromMap(
        _row(permissions: const []),
        email: '',
      ).can('orders.checkout'),
      isFalse,
    );
    expect(
      AppUserProfile.fromMap(const {
        'id': 'user-2',
        'status': 'ACTIVE',
        'roles': null,
      }, email: '').can('orders.checkout'),
      isFalse,
    );
  });

  test('permissions survive the device cache used when offline', () {
    final restored = AppUserProfile.fromMap(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_row())) as Map),
      email: 'ana@example.com',
    );

    expect(restored.can('orders.checkout'), isTrue);
    expect(restored.roleCode, 'CASHIER');
  });
}
