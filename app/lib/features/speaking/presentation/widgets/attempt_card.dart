import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/logging_service.dart';
import '../../domain/speaking_attempt.dart';
import '../../providers/speaking_providers.dart';
import 'correction_card.dart';
import 'pronunciation_card.dart';
import 'shadow_block.dart';

class AttemptCard extends StatelessWidget {
  final SpeakingAttempt attempt;
  final int totalAttempts;
  final bool expanded;
  final bool readOnly;
  final VoidCallback onToggle;

  const AttemptCard({
    super.key,
    required this.attempt,
    required this.totalAttempts,
    required this.expanded,
    required this.readOnly,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = attempt.result;
    final corrections = result.corrections;

    if (!expanded) {
      return InkWell(
        onTap: onToggle,
        child: Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Attempt ${attempt.attemptNumber}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${corrections.length} ${corrections.length == 1 ? 'correction' : 'corrections'}',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(Icons.expand_more, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  'Attempt ${attempt.attemptNumber} of $totalAttempts',
                  style: textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.expand_less, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),

        Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Your transcript',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (readOnly &&
                        (attempt.audioStorageKey != null ||
                            attempt.audioLocalPath != null))
                      _OwnRecordingPlayer(attempt: attempt),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.transcript,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (result.overallNote != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.thumb_up_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result.overallNote!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Natural version',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(result.naturalVersion, style: textTheme.bodyMedium),
                const SizedBox(height: 12),
                if (readOnly)
                  _ReadOnlyModelPlayer(text: result.naturalVersion)
                else
                  ShadowBlock(
                    attemptId: attempt.id,
                    naturalVersion: result.naturalVersion,
                    shadowAudioPath: attempt.shadowAudioPath,
                  ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Corrections (${corrections.length} found)',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (corrections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No corrections needed -- great job!',
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          ...corrections.map((c) => CorrectionCard(correction: c)),

        if (result.pronunciationIssues != null &&
            result.pronunciationIssues!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Pronunciation to work on (${result.pronunciationIssues!.length})',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...result.pronunciationIssues!.map(
            (issue) => PronunciationCard(issue: issue),
          ),
        ],

        const SizedBox(height: 8),
        const Divider(height: 32),
      ],
    );
  }
}

/// Plays the user's own recorded attempt. Local-first: if the audio file is
/// already on disk, plays it immediately. Otherwise downloads from Supabase
/// Storage, caches locally, then plays.
class _OwnRecordingPlayer extends ConsumerStatefulWidget {
  final SpeakingAttempt attempt;
  const _OwnRecordingPlayer({required this.attempt});

  @override
  ConsumerState<_OwnRecordingPlayer> createState() =>
      _OwnRecordingPlayerState();
}

class _OwnRecordingPlayerState extends ConsumerState<_OwnRecordingPlayer> {
  bool _loading = false;
  String? _resolvedPath;

  Future<void> _play() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _loading = true);
    try {
      var path = _resolvedPath ?? widget.attempt.audioLocalPath;
      if (path == null || !File(path).existsSync()) {
        final service = ref.read(speakingServiceProvider);
        final storageKey = widget.attempt.audioStorageKey;
        if (service == null || storageKey == null) {
          throw StateError('Audio not available');
        }
        path = await service.downloadAttemptAudio(
          attemptId: widget.attempt.id,
          storageKey: storageKey,
        );
      }
      _resolvedPath = path;
      await tts.playLocalFile(path);
    } catch (e, st) {
      globalTalker.handle(e, st, '[Speaking] own recording playback failed');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not play recording: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      icon: const Icon(Icons.play_circle_outline),
      tooltip: 'Play your recording',
      visualDensity: VisualDensity.compact,
      onPressed: _play,
    );
  }
}

class _ReadOnlyModelPlayer extends ConsumerStatefulWidget {
  final String text;
  const _ReadOnlyModelPlayer({required this.text});

  @override
  ConsumerState<_ReadOnlyModelPlayer> createState() =>
      _ReadOnlyModelPlayerState();
}

class _ReadOnlyModelPlayerState extends ConsumerState<_ReadOnlyModelPlayer> {
  bool _loading = false;

  Future<void> _play() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _loading = true);
    try {
      await tts.play(widget.text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      icon: const Icon(Icons.volume_up),
      tooltip: 'Play model',
      onPressed: _play,
    );
  }
}
