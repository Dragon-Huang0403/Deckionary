import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/logging_service.dart';
import '../../domain/speaking_result.dart';
import '../../providers/speaking_providers.dart';

/// Renders one mispronounced word with a tap-to-hear model pronunciation.
class PronunciationCard extends ConsumerStatefulWidget {
  final PronunciationIssue issue;

  const PronunciationCard({super.key, required this.issue});

  @override
  ConsumerState<PronunciationCard> createState() => _PronunciationCardState();
}

class _PronunciationCardState extends ConsumerState<PronunciationCard> {
  bool _playing = false;

  Future<void> _play() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _playing = true);
    try {
      await tts.play(widget.issue.word);
    } catch (e, st) {
      globalTalker.handle(e, st, '[Speaking] word playback failed');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final issue = widget.issue;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    issue.word,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                _playing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.volume_up),
                        tooltip: 'Hear correct pronunciation',
                        visualDensity: VisualDensity.compact,
                        onPressed: _play,
                      ),
              ],
            ),
            if (issue.heardAs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Heard as: ', style: textTheme.labelMedium),
                  Expanded(
                    child: Text(
                      issue.heardAs,
                      style: textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: cs.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (issue.tip.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Tip: ${issue.tip}',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
