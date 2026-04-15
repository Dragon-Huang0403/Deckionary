import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app_providers.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/build_info.dart';
import '../../review/providers/review_providers.dart';
import '../../../core/sync/sync_provider.dart';
import '../../../main.dart';
import '../providers/settings_state.dart';
import 'widgets/section_header.dart';
import 'widgets/appearance_settings_tiles.dart';
import 'widgets/audio_settings_tiles.dart';
import 'widgets/review_settings_tiles.dart';
import 'widgets/macos_settings_tiles.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      await ref.read(authServiceProvider)?.signInWithGoogle();
      // Auto-sync on first sign-in: pull remote first, then push local
      final syncService = ref.read(syncServiceProvider);
      if (syncService != null) {
        await syncService.syncSearchHistory();
        await syncService.syncReviewData();
        await syncService.syncVocabularyData();
        final settingsPulled = await syncService.pullSettings();
        await syncService.pushDirtySettings();
        await syncService.cleanupSoftDeletes();

        ref.invalidate(reviewSummaryProvider);
        if (settingsPulled > 0) {
          ref.invalidate(themeModeProvider);
          ref.invalidate(reviewFilterProvider);
          ref.invalidate(settingsStateProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    } finally {
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
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsStateProvider);
    final cs = Theme.of(context).colorScheme;

    // Watch auth state to rebuild on sign in/out
    if (syncEnabled) ref.watch(authStateProvider);
    final isSignedIn =
        syncEnabled && (ref.read(authServiceProvider)?.isSignedIn ?? false);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        data: (settings) => ListView(
          children: [
            // Account at top if signed in
            if (isSignedIn) ...[_buildAccountHeader(cs), const Divider()],
            const SectionHeader('Audio'),
            PronunciationDisplayTile(settings.pronunciationDisplay, ref),
            if (settings.pronunciationDisplay == 'both')
              DialectTile(settings.dialect, ref),
            AutoPronounceTile(settings.autoPronounce, ref),
            const Divider(),
            const SectionHeader('Offline Audio'),
            const AudioDownloadSection(),
            const Divider(),
            const SectionHeader('Appearance'),
            ThemeTile(settings.themeMode, ref),
            // Quick Search (macOS only)
            if (Platform.isMacOS) ...[
              const Divider(),
              const SectionHeader('Quick Search'),
              HotKeyTile(settings.quickSearchHotKey, ref),
              ShowOnScreenTile(settings.showOnScreen, ref),
              TrayIconTile(settings.showTrayIcon, ref),
              DockTile(settings.showInDock, ref),
              LaunchOnStartupTile(settings.launchOnStartup, ref),
            ],
            const Divider(),
            const SectionHeader('Review'),
            ReviewAutoPlayModeTile(settings.reviewAutoPlayMode, ref),
            CardOrderTile(settings.reviewCardOrder, ref),
            NewCardsPerDayTile(
              settings.newCardsPerDay,
              settings.maxReviewsPerDay,
              ref,
            ),
            MaxReviewsPerDayTile(settings.maxReviewsPerDay, ref),
            if (ref
                    .watch(reviewSummaryProvider)
                    .whenOrNull(data: (s) => s.totalCards > 0) ==
                true) ...[
              const Divider(),
              ClearProgressTile(ref),
            ],
            // Sign in / Sign out at bottom
            if (syncEnabled) ...[
              const Divider(),
              if (!isSignedIn)
                _buildSignInButton(cs)
              else
                _buildSignOutButton(cs),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text(
                'v$appVersion${isDevBuild ? '-dev' : ''} · ${buildCommit.length > 7 ? buildCommit.substring(0, 7) : buildCommit}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildAccountHeader(ColorScheme cs) {
    final user = Supabase.instance.client.auth.currentUser;
    final meta = user?.userMetadata;
    final name = meta?['full_name'] as String? ?? meta?['name'] as String?;
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
  }

  Widget _buildSignInButton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: FilledButton.icon(
        onPressed: _signingIn ? null : _signIn,
        icon: _signingIn
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.login),
        label: Text(
          _signingIn ? 'Signing in...' : 'Sign in with Google to sync',
        ),
      ),
    );
  }

  Widget _buildSignOutButton(ColorScheme cs) {
    return ListTile(
      leading: Icon(Icons.logout, color: cs.error),
      title: Text('Sign out', style: TextStyle(color: cs.error)),
      onTap: _signOut,
    );
  }
}
