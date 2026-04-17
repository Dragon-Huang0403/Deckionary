import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_providers.dart';
import 'widgets/correction_card.dart';

class SpeakingHistoryDetailScreen extends ConsumerStatefulWidget {
  final String id;
  final String topic;

  const SpeakingHistoryDetailScreen({
    super.key,
    required this.id,
    required this.topic,
  });

  @override
  ConsumerState<SpeakingHistoryDetailScreen> createState() =>
      _SpeakingHistoryDetailScreenState();
}

class _SpeakingHistoryDetailScreenState
    extends ConsumerState<SpeakingHistoryDetailScreen> {
  bool _loadingNatural = false;

  Future<void> _playNaturalVersion(String text) async {
    final ttsService = ref.read(ttsCacheServiceProvider);
    if (ttsService == null) return;
    setState(() => _loadingNatural = true);
    try {
      await ttsService.play(text);
    } finally {
      if (mounted) setState(() => _loadingNatural = false);
    }
  }

  Future<void> _deleteAndPop() async {
    final service = ref.read(speakingServiceProvider);
    // TODO(Task 15): delete by session_id once history is grouped per-session.
    await service?.deleteSession(widget.id);
    ref.invalidate(speakingHistoryProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(speakingResultByIdProvider(widget.id));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          TextButton(
            onPressed: _deleteAndPop,
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
      body: resultAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (result) {
          if (result == null) {
            return const Center(child: Text('Result not found'));
          }

          final corrections = result.corrections;

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Topic ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    widget.topic,
                    style: textTheme.titleSmall?.copyWith(color: cs.primary),
                  ),
                ),

                // ── Transcript ────────────────────────────────────
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your transcript',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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

                // ── Overall note ──────────────────────────────────
                if (result.overallNote != null) ...[
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                ],

                // ── Natural version ───────────────────────────────
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Natural version',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (_loadingNatural)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.volume_up),
                                tooltip: 'Listen',
                                onPressed: () =>
                                    _playNaturalVersion(result.naturalVersion),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          result.naturalVersion,
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Corrections ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Corrections (${corrections.length} found)',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (corrections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No corrections needed -- great job!',
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ...corrections.map((c) => CorrectionCard(correction: c)),
              ],
            ),
          );
        },
      ),
    );
  }
}
