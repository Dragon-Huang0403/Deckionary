import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app.dart'
    show
        serializeHotKey,
        hotKeyDisplayString,
        hotKeyChangeTrigger,
        showTrayIconProvider,
        showInDockProvider,
        themeModeProvider;
import '../../../core/audio/audio_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../review/providers/review_providers.dart';
import '../../../core/sync/sync_provider.dart';
import '../../../main.dart';

/// Settings loaded as a future
final _settingsProvider = FutureProvider<_AppSettings>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final dialect = await dao.getDialect();
  final pronunciationDisplay = await dao.getPronunciationDisplay();
  final autoPronounce = await dao.getAutoPronounce();
  final themeMode = await dao.getThemeMode();
  final newCardsPerDay = await dao.getNewCardsPerDay();
  final maxReviewsPerDay = await dao.getMaxReviewsPerDay();
  final reviewAutoPronounce = await dao.getReviewAutoPronounce();
  final reviewCardOrder = await dao.getReviewCardOrder();
  final quickSearchHotKey = Platform.isMacOS
      ? await dao.getQuickSearchHotKey()
      : '';
  final showTrayIcon = Platform.isMacOS ? await dao.getShowTrayIcon() : false;
  final showInDock = Platform.isMacOS ? await dao.getShowInDock() : true;
  return _AppSettings(
    dialect: dialect,
    pronunciationDisplay: pronunciationDisplay,
    autoPronounce: autoPronounce,
    themeMode: themeMode,
    newCardsPerDay: newCardsPerDay,
    maxReviewsPerDay: maxReviewsPerDay,
    reviewAutoPronounce: reviewAutoPronounce,
    reviewCardOrder: reviewCardOrder,
    quickSearchHotKey: quickSearchHotKey,
    showTrayIcon: showTrayIcon,
    showInDock: showInDock,
  );
});

class _AppSettings {
  final String dialect;
  final String pronunciationDisplay;
  final bool autoPronounce;
  final String themeMode;
  final int newCardsPerDay;
  final int maxReviewsPerDay;
  final bool reviewAutoPronounce;
  final String reviewCardOrder;
  final String quickSearchHotKey;
  final bool showTrayIcon;
  final bool showInDock;
  _AppSettings({
    required this.dialect,
    required this.pronunciationDisplay,
    required this.autoPronounce,
    required this.themeMode,
    required this.newCardsPerDay,
    required this.maxReviewsPerDay,
    required this.reviewAutoPronounce,
    required this.reviewCardOrder,
    required this.quickSearchHotKey,
    required this.showTrayIcon,
    required this.showInDock,
  });
}

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
      // Auto-sync on first sign-in
      ref.read(syncServiceProvider)?.syncSearchHistory();
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
    final settingsAsync = ref.watch(_settingsProvider);
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
            const _SectionHeader('Audio'),
            _PronunciationDisplayTile(settings.pronunciationDisplay, ref),
            if (settings.pronunciationDisplay == 'both')
              _DialectTile(settings.dialect, ref),
            _AutoPronounceTile(settings.autoPronounce, ref),
            const Divider(),
            const _SectionHeader('Offline Audio'),
            const _AudioDownloadSection(),
            const Divider(),
            const _SectionHeader('Appearance'),
            _ThemeTile(settings.themeMode, ref),
            // Quick Search (macOS only)
            if (Platform.isMacOS) ...[
              const Divider(),
              const _SectionHeader('Quick Search'),
              _HotKeyTile(settings.quickSearchHotKey, ref),
              _TrayIconTile(settings.showTrayIcon, ref),
              _DockTile(settings.showInDock, ref),
            ],
            const Divider(),
            const _SectionHeader('Review'),
            _ReviewAutoPronounceTile(settings.reviewAutoPronounce, ref),
            _CardOrderTile(settings.reviewCardOrder, ref),
            _NewCardsPerDayTile(
              settings.newCardsPerDay,
              settings.maxReviewsPerDay,
              ref,
            ),
            _MaxReviewsPerDayTile(settings.maxReviewsPerDay, ref),
            if (ref
                    .watch(reviewSummaryProvider)
                    .whenOrNull(data: (s) => s.totalCards > 0) ==
                true) ...[
              const Divider(),
              _ClearProgressTile(ref),
            ],
            // Sign in / Sign out at bottom
            if (syncEnabled) ...[
              const Divider(),
              if (!isSignedIn)
                _buildSignInButton(cs)
              else
                _buildSignOutButton(cs),
              const SizedBox(height: 32),
            ],
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _PronunciationDisplayTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const _PronunciationDisplayTile(this.current, this.ref);

  static const _labels = {
    'both': 'Both',
    'us': 'American (US)',
    'gb': 'British (GB)',
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Show pronunciation'),
      subtitle: Text(_labels[current] ?? 'Both'),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'both', label: Text('Both')),
          ButtonSegment(value: 'us', label: Text('US')),
          ButtonSegment(value: 'gb', label: Text('GB')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref
              .read(settingsDaoProvider)
              .setPronunciationDisplay(val.first);
          ref.invalidate(_settingsProvider);
          ref.invalidate(pronunciationDisplayProvider);
        },
      ),
    );
  }
}

class _DialectTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const _DialectTile(this.current, this.ref);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Pronunciation dialect'),
      subtitle: Text(current == 'us' ? 'American (US)' : 'British (GB)'),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'us', label: Text('US')),
          ButtonSegment(value: 'gb', label: Text('GB')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref.read(settingsDaoProvider).setDialect(val.first);
          ref.invalidate(_settingsProvider);
        },
      ),
    );
  }
}

class _AutoPronounceTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const _AutoPronounceTile(this.enabled, this.ref);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Auto-pronounce on search'),
      subtitle: const Text('Play pronunciation when a word is found'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setAutoPronounce(val);
        ref.invalidate(_settingsProvider);
      },
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const _ThemeTile(this.current, this.ref);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Theme'),
      subtitle: Text(
        current == 'light'
            ? 'Light'
            : current == 'dark'
            ? 'Dark'
            : 'System',
      ),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'system', label: Text('Auto')),
          ButtonSegment(value: 'light', label: Text('Light')),
          ButtonSegment(value: 'dark', label: Text('Dark')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref.read(settingsDaoProvider).setThemeMode(val.first);
          ref.invalidate(_settingsProvider);
          ref.invalidate(themeModeProvider);
        },
      ),
    );
  }
}

/// Single row: shows download/progress/complete depending on state
class _AudioDownloadSection extends ConsumerWidget {
  const _AudioDownloadSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(offlineAudioProvider);
    final cs = Theme.of(context).colorScheme;

    return stateAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.storage),
        title: Text('Checking audio...'),
      ),
      error: (e, _) => ListTile(
        leading: Icon(Icons.error_outline, color: cs.error),
        title: const Text('Error'),
        subtitle: Text('$e'),
      ),
      data: (s) {
        // Downloading
        if (s.downloading) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: s.progress > 0 ? s.progress : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(s.progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${s.completedPacks} / ${s.totalPacks} packs (${s.cacheSizeFormatted})',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        // Error with retry
        if (s.error != null) {
          return ListTile(
            leading: Icon(Icons.error_outline, color: cs.error),
            title: Text('Download failed', style: TextStyle(color: cs.error)),
            subtitle: Text(s.error!, style: const TextStyle(fontSize: 12)),
            trailing: FilledButton.tonal(
              onPressed: () =>
                  ref.read(offlineAudioProvider.notifier).downloadAll(),
              child: const Text('Retry'),
            ),
          );
        }

        // Fully downloaded
        if (s.isFullyDownloaded) {
          return ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green.shade600),
            title: const Text('All audio downloaded'),
            subtitle: Text('${s.cachedFiles} files (${s.cacheSizeFormatted})'),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(offlineAudioProvider.notifier).clearCache(),
              child: const Text('Clear'),
            ),
          );
        }

        // Not fully downloaded (partial or empty)
        return ListTile(
          leading: Icon(Icons.download, color: cs.primary),
          title: Text(
            s.cachedFiles > 0
                ? 'Download all audio (${s.cachedFiles} cached)'
                : 'Download all audio',
          ),
          subtitle: const Text('~1.7 GB — enables full offline use'),
          trailing: s.cachedFiles > 0
              ? TextButton(
                  onPressed: () =>
                      ref.read(offlineAudioProvider.notifier).clearCache(),
                  child: const Text('Clear'),
                )
              : null,
          onTap: () => ref.read(offlineAudioProvider.notifier).downloadAll(),
        );
      },
    );
  }
}

class _CardOrderTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const _CardOrderTile(this.current, this.ref);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('New card order'),
      subtitle: Text(current == 'random' ? 'Random' : 'Alphabetical'),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'alphabetical', label: Text('A-Z')),
          ButtonSegment(value: 'random', label: Text('Random')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref.read(settingsDaoProvider).setReviewCardOrder(val.first);
          ref.invalidate(_settingsProvider);
          ref.invalidate(reviewSummaryProvider);
        },
      ),
    );
  }
}

class _NewCardsPerDayTile extends StatelessWidget {
  final int current;
  final int maxReviews;
  final WidgetRef ref;
  const _NewCardsPerDayTile(this.current, this.maxReviews, this.ref);

  @override
  Widget build(BuildContext context) {
    final suggestedMin = current * 7;
    final showWarning = maxReviews < suggestedMin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('New cards per day'),
          subtitle: Text('$current cards'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: current.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: '$current',
              onChanged: (val) async {
                await ref
                    .read(settingsDaoProvider)
                    .setNewCardsPerDay(val.round());
                ref.invalidate(_settingsProvider);
                ref.invalidate(reviewSummaryProvider);
              },
            ),
          ),
        ),
        if (showWarning)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Tip: With $current new cards/day, consider setting max reviews to at least $suggestedMin to avoid a backlog.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
            ),
          ),
      ],
    );
  }
}

class _ReviewAutoPronounceTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const _ReviewAutoPronounceTile(this.enabled, this.ref);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Auto-pronounce in review'),
      subtitle: const Text('Play pronunciation when a card appears'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setReviewAutoPronounce(val);
        ref.invalidate(_settingsProvider);
      },
    );
  }
}

class _MaxReviewsPerDayTile extends StatelessWidget {
  final int current;
  final WidgetRef ref;
  const _MaxReviewsPerDayTile(this.current, this.ref);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Max reviews per day'),
      subtitle: Text('$current reviews'),
      trailing: SizedBox(
        width: 200,
        child: Slider(
          value: current.toDouble(),
          min: 50,
          max: 500,
          divisions: 18,
          label: '$current',
          onChanged: (val) async {
            await ref
                .read(settingsDaoProvider)
                .setMaxReviewsPerDay(val.round());
            ref.invalidate(_settingsProvider);
            ref.invalidate(reviewSummaryProvider);
          },
        ),
      ),
    );
  }
}

class _HotKeyTile extends StatefulWidget {
  final String hotKeyJson;
  final WidgetRef ref;
  const _HotKeyTile(this.hotKeyJson, this.ref);

  @override
  State<_HotKeyTile> createState() => _HotKeyTileState();
}

class _HotKeyTileState extends State<_HotKeyTile> {
  bool _recording = false;

  /// Modifier-only USB HID codes — ignore these until a real key is pressed.
  static const _modifierUsbHids = {
    0x000700E0, 0x000700E1, 0x000700E2, 0x000700E3, // L: Ctrl, Shift, Alt, Meta
    0x000700E4, 0x000700E5, 0x000700E6, 0x000700E7, // R: Ctrl, Shift, Alt, Meta
  };

  @override
  Widget build(BuildContext context) {
    final display = hotKeyDisplayString(widget.hotKeyJson);

    return ListTile(
      title: const Text('Global shortcut'),
      subtitle: Text(_recording ? 'Press modifier + key...' : display),
      trailing: _recording
          ? SizedBox(
              width: 200,
              child: HotKeyRecorder(
                onHotKeyRecorded: (newHotKey) async {
                  // Ignore modifier-only presses (user still building the combo)
                  if (_modifierUsbHids.contains(
                    newHotKey.physicalKey.usbHidUsage,
                  )) {
                    return;
                  }

                  final json = serializeHotKey(newHotKey);
                  await widget.ref
                      .read(settingsDaoProvider)
                      .setQuickSearchHotKey(json);
                  widget.ref.invalidate(_settingsProvider);
                  // Directly trigger hotkey re-registration in app state
                  widget.ref.read(hotKeyChangeTrigger.notifier).fire();
                  if (mounted) setState(() => _recording = false);
                },
              ),
            )
          : TextButton(
              onPressed: () => setState(() => _recording = true),
              child: const Text('Change'),
            ),
    );
  }
}

class _TrayIconTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const _TrayIconTile(this.enabled, this.ref);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Menu bar icon'),
      subtitle: const Text('Show icon in menu bar for quick access'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setShowTrayIcon(val);
        ref.invalidate(_settingsProvider);
        ref.invalidate(showTrayIconProvider);
      },
    );
  }
}

class _DockTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const _DockTile(this.enabled, this.ref);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Show in Dock'),
      subtitle: const Text('Keep Dock icon visible when window is hidden'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setShowInDock(val);
        ref.invalidate(_settingsProvider);
        ref.invalidate(showInDockProvider);
      },
    );
  }
}

class _ClearProgressTile extends StatelessWidget {
  final WidgetRef ref;
  const _ClearProgressTile(this.ref);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_outline, color: cs.error),
      title: Text('Clear review progress', style: TextStyle(color: cs.error)),
      subtitle: const Text('Delete all review cards and history'),
      onTap: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final dao = ref.read(reviewDaoProvider);
    final totalCards = await dao.countTotalCards();
    if (totalCards == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No review progress to clear')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all progress?'),
        content: Text(
          'This will delete $totalCards review cards and all review history. '
          'You will start from scratch. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await dao.clearAllProgress();
      // Also clear remote data so it doesn't sync back
      final sync = ref.read(syncServiceProvider);
      sync?.clearRemoteReviewData();
      ref.invalidate(reviewSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review progress cleared')),
        );
      }
    }
  }
}
