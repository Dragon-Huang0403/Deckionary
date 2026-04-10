import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/sync/sync_provider.dart';
import '../../../main.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _syncing = false;
  String? _syncResult;

  Future<void> _signIn() async {
    try {
      await ref.read(authServiceProvider)?.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your local data will be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
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
    setState(() { _syncing = true; _syncResult = null; });
    try {
      final result = await syncService.syncSearchHistory();
      setState(() {
        _syncResult = 'Pushed ${result.pushed}, pulled ${result.pulled}';
      });
    } catch (e) {
      setState(() { _syncResult = 'Sync failed: $e'; });
    } finally {
      setState(() { _syncing = false; });
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
                Icon(Icons.cloud_off_outlined, size: 48, color: cs.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'Sync not configured',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Firebase and Supabase need to be set up to enable cross-device sync.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
                  Icon(Icons.cloud_outlined, size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to sync across devices',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your search history and progress will be available on all your devices.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person, color: cs.onPrimaryContainer),
              ),
              title: Text(authService?.currentUserId ?? 'Signed in'),
              subtitle: const Text('Google account'),
            ),
            const Divider(),
            ListTile(
              leading: _syncing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
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
