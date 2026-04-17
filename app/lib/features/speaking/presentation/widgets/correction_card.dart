import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/speaking_result.dart';
import '../../providers/speaking_providers.dart';

class CorrectionCard extends ConsumerStatefulWidget {
  final SpeakingCorrection correction;

  const CorrectionCard({super.key, required this.correction});

  @override
  ConsumerState<CorrectionCard> createState() => _CorrectionCardState();
}

class _CorrectionCardState extends ConsumerState<CorrectionCard> {
  bool _isLoading = false;

  Future<void> _playNatural() async {
    final ttsService = ref.read(ttsCacheServiceProvider);
    if (ttsService == null) return;
    setState(() => _isLoading = true);
    try {
      await ttsService.play(widget.correction.natural);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final correction = widget.correction;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Original
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You said: ', style: textTheme.labelMedium),
                Expanded(
                  child: Text(
                    correction.original,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Natural
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('More natural: ', style: textTheme.labelMedium),
                Expanded(
                  child: Text(
                    correction.natural,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Play',
                    onPressed: _playNatural,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Explanation
            Text(
              'Why: ${correction.explanation}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
