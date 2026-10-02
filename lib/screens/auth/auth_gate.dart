import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/app_user_profile.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  final Widget Function(AppUserProfile profile) authenticatedBuilder;

  const AuthGate({super.key, required this.authenticatedBuilder});

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
          .select('id, display_name, status, roles(code, name)')
          .eq('id', session.user.id)
          .maybeSingle();

      if (row == null) {
        throw const FormatException('Employee profile was not found.');
      }

      final profile = AppUserProfile.fromMap(
        row,
        email: session.user.email ?? '',
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted || refreshingInPlace) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || refreshingInPlace) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
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
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 460,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 400 ? 20 : 28,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.gray200),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.manage_accounts_outlined,
                    size: 42,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.h2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: onSignOut,
                        child: const Text('Sign out'),
                      ),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
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
