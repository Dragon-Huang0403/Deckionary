import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/speaking_result.dart';
import '../providers/speaking_providers.dart';
import 'widgets/correction_card.dart';

class SpeakingResultScreen extends ConsumerStatefulWidget {
  final String topic;
  final bool isCustomTopic;
  final SpeakingResult result;

  const SpeakingResultScreen({
    super.key,
    required this.topic,
    required this.isCustomTopic,
    required this.result,
  });

  @override
  ConsumerState<SpeakingResultScreen> createState() =>
      _SpeakingResultScreenState();
}

class _SpeakingResultScreenState extends ConsumerState<SpeakingResultScreen> {
  bool _loadingNatural = false;

  Future<void> _playNaturalVersion() async {
    final ttsService = ref.read(ttsCacheServiceProvider);
    if (ttsService == null) return;
    setState(() => _loadingNatural = true);
    try {
      await ttsService.play(widget.result.naturalVersion);
    } finally {
      if (mounted) setState(() => _loadingNatural = false);
    }
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = widget.result;
    final corrections = result.corrections;

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Overall note ──────────────────────────────────────────
            if (result.overallNote != null) ...[
              Card(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

            // ── Natural version ───────────────────────────────────────
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            tooltip: 'Listen',
                            onPressed: _playNaturalVersion,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(result.naturalVersion, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ),

            // ── Corrections ───────────────────────────────────────────
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

            // ── Your transcript ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ExpansionTile(
                title: Text(
                  'Your transcript',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      result.transcript,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Action buttons ────────────────────────────────────────
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _goHome,
                      child: const Text('Practice another topic'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _goHome,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
