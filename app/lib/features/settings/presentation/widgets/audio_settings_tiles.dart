import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/audio_provider.dart';
import '../../../../core/database/database_provider.dart';
import '../../providers/settings_state.dart';

class PronunciationDisplayTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const PronunciationDisplayTile(this.current, this.ref, {super.key});

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
          ref.invalidate(settingsStateProvider);
          ref.invalidate(pronunciationDisplayProvider);
        },
      ),
    );
  }
}

class DialectTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const DialectTile(this.current, this.ref, {super.key});

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
          ref.invalidate(settingsStateProvider);
        },
      ),
    );
  }
}

class AutoPronounceTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const AutoPronounceTile(this.enabled, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Auto-pronounce on search'),
      subtitle: const Text('Play pronunciation when a word is found'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setAutoPronounce(val);
        ref.invalidate(settingsStateProvider);
      },
    );
  }
}

/// Single row: shows download/progress/complete depending on state
class AudioDownloadSection extends ConsumerWidget {
  const AudioDownloadSection({super.key});

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
          final packsText = s.retryRound > 0
              ? '${s.completedPacks} / ${s.totalPacks} packs \u00b7 retrying (round ${s.retryRound})'
              : '${s.completedPacks} / ${s.totalPacks} packs';
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
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        padding: EdgeInsets.zero,
                        onPressed: () => ref
                            .read(offlineAudioProvider.notifier)
                            .cancelDownload(),
                        tooltip: 'Cancel download',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  packsText,
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
            subtitle: Text('${s.cachedFiles} files'),
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
