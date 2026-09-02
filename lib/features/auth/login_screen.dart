import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'sign_in_message.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A redirect sign-in leaves the page and comes back here. If it failed,
    // this is the only place that ever hears about it — otherwise the screen
    // simply reappears and the button looks like it did nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectRedirect());
  }

  Future<void> _collectRedirect() async {
    try {
      await ref.read(authRepositoryProvider).completeRedirectSignIn();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = signInMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    }
  }

  Future<void> _signIn({bool chooseAccount = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(chooseAccount: chooseAccount);
      // The router redirect reacts to auth state; no manual navigation.
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = signInMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.child_care,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Baby App', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Sign in to track feeds, diapers, and growth across devices.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                // Said before sign-in, not after: anyone who has not been
                // invited would otherwise hand over a Google account only to
                // be turned away, with no idea why.
                Text(
                  'Access is by invitation.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 4),
                // Signing out of the app ends the Firebase session, not the
                // browser's Google one — so the button above takes the one
                // account already signed in and never asks. That is the
                // right default on a shared tablet, and a dead end for the
                // second person in the house.
                TextButton(
                  onPressed: _busy ? null : () => _signIn(chooseAccount: true),
                  child: const Text('Use a different account'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
