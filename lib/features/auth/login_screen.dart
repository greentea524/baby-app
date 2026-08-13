import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // The router redirect reacts to auth state; no manual navigation.
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns a Firebase auth error into an actionable message. Includes the
  /// raw code so misconfigurations are diagnosable rather than opaque.
  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project. '
            'Enable it in Authentication → Sign-in method. [${e.code}]';
      case 'unauthorized-domain':
        return 'This domain is not authorized for sign-in. Add it under '
            'Authentication → Settings → Authorized domains. [${e.code}]';
      case 'popup-blocked':
        return 'The sign-in popup was blocked by the browser. Allow popups '
            'for this site and try again. [${e.code}]';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';
      default:
        return 'Sign-in failed: ${e.message ?? e.code} [${e.code}]';
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
