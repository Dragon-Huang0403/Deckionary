import 'package:flutter/material.dart';

import '../../domain/speaking_result.dart';

class CorrectionCard extends StatelessWidget {
  final SpeakingCorrection correction;

  const CorrectionCard({super.key, required this.correction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              ],
            ),
            const SizedBox(height: 8),
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
