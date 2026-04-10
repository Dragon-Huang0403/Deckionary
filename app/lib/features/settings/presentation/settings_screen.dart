import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../account/presentation/account_screen.dart';

/// Settings loaded as a future
final _settingsProvider = FutureProvider<_AppSettings>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final results = await Future.wait([
    dao.getDialect(),
    dao.getAutoPronounce(),
    dao.getThemeMode(),
  ]);
  return _AppSettings(
    dialect: results[0] as String,
    autoPronounce: results[1] as bool,
    themeMode: results[2] as String,
  );
});

class _AppSettings {
  final String dialect;
  final bool autoPronounce;
  final String themeMode;
  _AppSettings({required this.dialect, required this.autoPronounce, required this.themeMode});
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(_settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        data: (settings) => ListView(
          children: [
            const _SectionHeader('Audio'),
            _DialectTile(settings.dialect, ref),
            _AutoPronounceTile(settings.autoPronounce, ref),
            const Divider(),
            const _SectionHeader('Offline Audio'),
            const _AudioDownloadSection(),
            const Divider(),
            const _SectionHeader('Appearance'),
            _ThemeTile(settings.themeMode, ref),
            const Divider(),
            const _SectionHeader('Account'),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Account & Sync'),
              subtitle: const Text('Sign in to sync across devices'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
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
      child: Text(title, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      )),
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
      subtitle: Text(current == 'light' ? 'Light' : current == 'dark' ? 'Dark' : 'System'),
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
                    Expanded(child: LinearProgressIndicator(value: s.progress > 0 ? s.progress : null)),
                    const SizedBox(width: 12),
                    Text('${(s.progress * 100).toInt()}%', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
              onPressed: () => ref.read(offlineAudioProvider.notifier).downloadAll(),
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
              onPressed: () => ref.read(offlineAudioProvider.notifier).clearCache(),
              child: const Text('Clear'),
            ),
          );
        }

        // Not fully downloaded (partial or empty)
        return ListTile(
          leading: Icon(Icons.download, color: cs.primary),
          title: Text(s.cachedFiles > 0
              ? 'Download all audio (${s.cachedFiles} cached)'
              : 'Download all audio'),
          subtitle: const Text('~1.7 GB — enables full offline use'),
          trailing: s.cachedFiles > 0
              ? TextButton(
                  onPressed: () => ref.read(offlineAudioProvider.notifier).clearCache(),
                  child: const Text('Clear'),
                )
              : null,
          onTap: () => ref.read(offlineAudioProvider.notifier).downloadAll(),
        );
      },
    );
  }
}
