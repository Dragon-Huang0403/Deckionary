import 'package:flutter/material.dart';

class WordFamilyWidget extends StatelessWidget {
  final List<Map<String, dynamic>> wordFamily;
  final void Function(String word)? onWordTap;

  const WordFamilyWidget(this.wordFamily, {this.onWordTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: wordFamily.map((wf) {
          final word = wf['word'] as String? ?? '';
          final pos = wf['pos'] as String? ?? '';
          final opp = wf['opposite'] as String? ?? '';
          return GestureDetector(
            onTap: onWordTap != null ? () => onWordTap!(word) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    word,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                  if (pos.isNotEmpty)
                    Text(
                      ' $pos',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (opp.isNotEmpty)
                    Text(
                      ' $opp',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade300),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class VerbFormsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> verbForms;

  const VerbFormsWidget(this.verbForms, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: verbForms.map((vf) {
          final label = vf['form_label'] as String? ?? '';
          final text = vf['form_text'] as String? ?? '';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label.isNotEmpty) ...[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
