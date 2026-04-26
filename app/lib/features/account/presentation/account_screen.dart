import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/sync/sync_provider.dart';
import '../../../main.dart';
import '../../review/providers/review_providers.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  static const _windowChannel = MethodChannel('com.deckionary/window');

  bool _signingIn = false;
  bool _syncing = false;
  String? _syncResult;

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    ref.read(signInInProgressProvider.notifier).set(true);
    final wasOverlay = ref.read(isOverlayModeProvider);
    if (Platform.isMacOS && wasOverlay) {
      await _windowChannel.invokeMethod('setNormalMode');
    }
    try {
      await ref.read(authServiceProvider)?.signInWithGoogle();
      // Auto-sync on first sign-in: push all existing local history
      if (mounted) _syncNow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    } finally {
      ref.read(signInInProgressProvider.notifier).set(false);
      if (Platform.isMacOS && wasOverlay) {
        await _windowChannel.invokeMethod('setOverlayMode');
      }
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your local data will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authServiceProvider)?.signOut();
    }
  }

  Future<void> _syncNow() async {
    final syncService = ref.read(syncServiceProvider);
    if (syncService == null) return;
    setState(() {
      _syncing = true;
      _syncResult = null;
    });
    try {
      // Each sync*Data orchestrator pushes local writes first, then pulls.
      // Settings stays pull-then-push because settings_sync uses dirty
      // tracking to avoid clobbering local edits.
      await syncService.syncSearchHistory();
      await syncService.syncReviewData();
      await syncService.syncVocabularyData();
      final settingsPulled = await syncService.pullSettings();
      await syncService.pushDirtySettings();
      await syncService.cleanupSoftDeletes();

      // reviewSummaryProvider is driven by drift streams on review_cards /
      // review_logs, so it auto-refreshes after the sync writes. We only
      // need to invalidate settings-derived providers here.
      if (settingsPulled > 0) {
        ref.invalidate(themeModeProvider);
        ref.invalidate(reviewFilterProvider);
      }

      if (mounted) {
        setState(() {
          _syncResult = 'Sync complete';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncResult = 'Sync failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Sync not configured yet
    if (!syncEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account & Sync')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sync not configured',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Firebase and Supabase need to be set up to enable cross-device sync.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Watch auth state to rebuild on sign in/out
    ref.watch(authStateProvider);
    final authService = ref.read(authServiceProvider);
    final isSignedIn = authService?.isSignedIn ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Account & Sync')),
      body: ListView(
        children: [
          if (!isSignedIn) ...[
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    size: 48,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to sync across devices',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your search history and progress will be available on all your devices.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _signingIn ? null : _signIn,
                    icon: _signingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _signingIn ? 'Signing in...' : 'Sign in with Google',
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            () {
              final user = Supabase.instance.client.auth.currentUser;
              final meta = user?.userMetadata;
              final name =
                  meta?['full_name'] as String? ?? meta?['name'] as String?;
              final email = user?.email ?? meta?['email'] as String?;
              final avatar =
                  meta?['avatar_url'] as String? ?? meta?['picture'] as String?;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                  child: avatar == null
                      ? Icon(Icons.person, color: cs.onPrimaryContainer)
                      : null,
                ),
                title: Text(name ?? 'Signed in'),
                subtitle: Text(email ?? 'Google account'),
              );
            }(),
            const Divider(),
            ListTile(
              leading: _syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              title: const Text('Sync now'),
              subtitle: _syncResult != null ? Text(_syncResult!) : null,
              onTap: _syncing ? null : _syncNow,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: cs.error),
              title: Text('Sign out', style: TextStyle(color: cs.error)),
              onTap: _signOut,
            ),
          ],
        ],
      ),
    );
  }
}
