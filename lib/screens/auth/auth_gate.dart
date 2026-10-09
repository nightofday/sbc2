import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/offline/key_value_store.dart';
import '../../data/offline/offline_order_repository.dart'
    show isConnectionFailure;
import '../../models/app_user_profile.dart';
import 'login_screen.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

class AuthGate extends StatefulWidget {
  final Widget Function(AppUserProfile profile) authenticatedBuilder;

  /// Keeps the last loaded profile so a signed-in till can reopen offline.
  final KeyValueStore? profileCache;

  const AuthGate({
    super.key,
    required this.authenticatedBuilder,
    this.profileCache,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;

  AppUserProfile? _profile;
  bool _loading = true;
  String? _error;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _authSubscription = _supabase.auth.onAuthStateChange.listen((_) {
      _loadCurrentUser();
    });

    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final session = _supabase.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _error = null;
        _loading = false;
      });
      return;
    }

    // Supabase also emits auth events while the user is working, such as the
    // periodic token refresh. Showing the loading screen then would unmount
    // the whole app and discard an open cart or form, so an already loaded
    // profile for the same user is refreshed in place.
    final refreshingInPlace = _profile?.id == session.user.id;

    if (mounted && !refreshingInPlace) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select(
            'id, display_name, status, '
            'roles(code, name, role_permissions(permissions(code)))',
          )
          .eq('id', session.user.id)
          .maybeSingle();

      if (row == null) {
        throw const FormatException('Employee profile was not found.');
      }

      final profile = AppUserProfile.fromMap(
        row,
        email: session.user.email ?? '',
      );

      await widget.profileCache?.write(
        _profileCacheKey(session.user.id),
        jsonEncode(row),
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || refreshingInPlace) return;

      // Without a connection the profile last loaded on this device lets
      // the till open. The server still checks every action once it syncs.
      final cached = isConnectionFailure(error)
          ? _cachedProfile(session.user.id, session.user.email ?? '')
          : null;

      setState(() {
        _profile = cached;
        _error = cached != null
            ? null
            : error is PostgrestException
            ? error.message
            : isConnectionFailure(error)
            ? 'No connection. Connect to the internet to sign in on this '
                  'device for the first time.'
            : errorText(error);
        _loading = false;
      });
    }
  }

  String _profileCacheKey(String userId) => 'offline.profile.v1.$userId';

  AppUserProfile? _cachedProfile(String userId, String email) {
    final raw = widget.profileCache?.read(_profileCacheKey(userId));
    if (raw == null) return null;

    try {
      return AppUserProfile.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
        email: email,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.gray100,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_supabase.auth.currentSession == null) {
      return const LoginScreen();
    }

    if (_error != null) {
      return _AccountStateScreen(
        title: 'Unable to load account',
        message: _error!,
        onSignOut: _signOut,
        onRetry: _loadCurrentUser,
      );
    }

    final profile = _profile;
    if (profile == null) {
      return _AccountStateScreen(
        title: 'Employee profile unavailable',
        message: 'This account is signed in but does not have a usable employee profile.',
        onSignOut: _signOut,
        onRetry: _loadCurrentUser,
      );
    }

    if (!profile.isActive || profile.roleCode.isEmpty) {
      return _AccountStateScreen(
        title: 'Account awaiting activation',
        message: 'Your account exists, but management has not activated a system role for it yet.',
        onSignOut: _signOut,
        onRetry: _loadCurrentUser,
      );
    }

    return widget.authenticatedBuilder(profile);
  }
}

class _AccountStateScreen extends StatelessWidget {
  final String title;
  final String message;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onRetry;

  const _AccountStateScreen({
    required this.title,
    required this.message,
    required this.onSignOut,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray100,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              width: 460,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 400
                    ? AppSpacing.lg
                    : AppSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.gray200),
                borderRadius: AppRadius.all,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.manage_accounts_outlined,
                    size: 42,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h2,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: onSignOut,
                        child: const Text('Sign out'),
                      ),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
