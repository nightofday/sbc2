import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/user_repository.dart';
import '../../models/user_record.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/responsive_filter_bar.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

class UsersScreen extends StatefulWidget {
  final UserRepository userRepository;
  final bool canManageRoles;

  const UsersScreen({
    super.key,
    required this.userRepository,
    required this.canManageRoles,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<UserRecord>> _usersFuture;
  String _search = '';
  String _roleFilter = 'All Roles';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _usersFuture = widget.userRepository.getUsers();
  }

  void _refresh() {
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Users',
      action: widget.canManageRoles
          ? ElevatedButton.icon(
              onPressed: _showAddUser,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add User'),
            )
          : null,
      child: FutureBuilder<List<UserRecord>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load users.\n${errorText(snapshot.error)}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final all = snapshot.data ?? const <UserRecord>[];
          final roles =
              all
                  .map((user) => user.role)
                  .where((role) => role.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          if (_roleFilter != 'All Roles' && !roles.contains(_roleFilter)) {
            _roleFilter = 'All Roles';
          }

          final query = _search.trim().toLowerCase();
          final users = all.where((user) {
            final matchesSearch =
                query.isEmpty ||
                user.name.toLowerCase().contains(query) ||
                user.email.toLowerCase().contains(query);
            final matchesRole =
                _roleFilter == 'All Roles' || user.role == _roleFilter;
            return matchesSearch && matchesRole;
          }).toList();

          return Column(
            children: [
              Builder(
                builder: (context) {
                  final search = TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name or email...',
                    ),
                  );
                  final role = DropdownButtonFormField<String>(
                    initialValue: _roleFilter,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'All Roles',
                        child: Text('All Roles'),
                      ),
                      for (final role in roles)
                        DropdownMenuItem(value: role, child: Text(role)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _roleFilter = value);
                    },
                  );

                  return ResponsiveFilterBar(
                    primary: search,
                    filters: [role],
                    filterWidths: const [190],
                    breakpoint: 620,
                  );
                },
              ),
              const SizedBox(height: 18),
              Expanded(
                child: users.isEmpty
                    ? const Center(child: Text('No users found.'))
                    : SingleChildScrollView(
                        child: DataTableCard(
                          headers: const [
                            'Name',
                            'Email',
                            'Role',
                            'Status',
                            'Actions',
                          ],
                          flexes: const [3, 4, 2, 2, 2],
                          rows: users
                              .map(
                                (user) => [
                                  InkWell(
                                    onTap: () => _showUserDetails(user),
                                    child: Text(
                                      user.name,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    user.email.isEmpty
                                        ? user.username
                                        : user.email,
                                    style: AppTextStyles.body,
                                  ),
                                  Text(user.role, style: AppTextStyles.body),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: StatusBadge(user.status),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit User',
                                    onPressed: () => _showEditUser(user),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 19,
                                    ),
                                  ),
                                ],
                              )
                              .toList(),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showUserDetails(UserRecord user) async {
    final latest = await widget.userRepository.getUserById(user.id) ?? user;
    if (!mounted) return;

    await showPrototypeDialog(
      context: context,
      title: latest.name,
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(latest.status),
          ),
          const SizedBox(height: 16),
          _row('Email', latest.email),
          _row('Role', latest.role),
          _row('Access Status', latest.status),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _showEditUser(latest);
          },
          child: const Text('Edit User'),
        ),
      ],
    );
  }

  Future<void> _showAddUser() async {
    final roles = await widget.userRepository.getRoles();
    if (!mounted || roles.isEmpty) return;

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String roleCode = roles
        .firstWhere((role) => role.code == 'CASHIER', orElse: () => roles.first)
        .code;
    String? errorMessage;
    StateSetter? updateDialogState;

    await showPrototypeDialog(
      context: context,
      title: 'Add User',
      width: 560,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display Name *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary Password *',
                  helperText: 'Minimum 8 characters.',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: roleCode,
                decoration: const InputDecoration(labelText: 'Role *'),
                items: roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.code,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => roleCode = value);
                },
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final email = emailController.text.trim();
            final password = passwordController.text;

            if (name.isEmpty ||
                email.isEmpty ||
                !email.contains('@') ||
                password.length < 8) {
              updateDialogState?.call(() {
                errorMessage = 'Enter a name, valid email, and password of at least 8 characters.';
              });
              return;
            }

            try {
              await widget.userRepository.createEmployee(
                email: email,
                temporaryPassword: password,
                displayName: name,
                roleCode: roleCode,
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Employee account created.')),
              );
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = _friendlyError(error);
              });
            }
          },
          child: const Text('Create User'),
        ),
      ],
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _showEditUser(UserRecord user) async {
    final roles = await widget.userRepository.getRoles();
    if (!mounted) return;

    final nameController = TextEditingController(text: user.name);
    String roleId = user.roleId;
    String status = user.status.toUpperCase();
    String? errorMessage;
    StateSetter? updateDialogState;

    if (roleId.isEmpty && roles.isNotEmpty) {
      roleId = roles.first.id;
    }

    await showPrototypeDialog(
      context: context,
      title: 'Edit User',
      width: 540,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          updateDialogState = setDialogState;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display Name *'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                initialValue: user.email,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText:
                      'Email changes are handled through Supabase Auth.',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: roleId.isEmpty ? null : roleId,
                decoration: const InputDecoration(labelText: 'Role'),
                items: roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.id,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: widget.canManageRoles
                    ? (value) {
                        if (value == null) return;
                        setDialogState(() => roleId = value);
                      }
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  DropdownMenuItem(
                    value: 'SUSPENDED',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => status = value);
                },
              ),
              if (!widget.canManageRoles) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Only an Administrator can change roles.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (nameController.text.trim().isEmpty) {
              updateDialogState?.call(() {
                errorMessage = 'Display name is required.';
              });
              return;
            }

            try {
              await widget.userRepository.updateEmployee(
                userId: user.id,
                displayName: nameController.text.trim(),
                status: status,
                roleId: roleId,
              );

              if (!mounted) return;
              Navigator.pop(context);
              _refresh();

              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('User updated.')));
            } on PostgrestException catch (error) {
              updateDialogState?.call(() {
                errorMessage = error.message;
              });
            } catch (error) {
              updateDialogState?.call(() {
                errorMessage = _friendlyError(error);
              });
            }
          },
          child: const Text('Save Changes'),
        ),
      ],
    );

    nameController.dispose();
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: AppColors.gray700),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = errorText(error);
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }
}
