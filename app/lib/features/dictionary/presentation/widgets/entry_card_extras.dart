import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import 'entry_card_senses.dart';

class SynonymsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> synonyms;

  const SynonymsWidget(this.synonyms, {super.key});

  @override
  Widget build(BuildContext context) {
    final words = synonyms.map((s) => s['word'] as String? ?? '').toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: words
          .map(
            (w) => Chip(
              label: Text(
                w,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }
}

class CollocationsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> collocations;
  final void Function(String word)? onWordTap;

  const CollocationsWidget(this.collocations, {super.key, this.onWordTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: collocations.map((c) {
        final cat = c['category'] as String? ?? '';
        final words = c['words'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cat,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.shade300
                      : Colors.orange.shade700,
                  letterSpacing: 0.3,
                ),
              ),
              Wrap(spacing: 0, children: _buildClickableWords(words, context)),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildClickableWords(String words, BuildContext context) {
    final parts = words.split(',');
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final widgets = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final word = parts[i].trim();
      if (word.isEmpty) continue;
      if (widgets.isNotEmpty) {
        widgets.add(Text(', ', style: TextStyle(fontSize: 13, color: muted)));
      }
      widgets.add(
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onWordTap?.call(word),
            child: Text(
              word,
              style: TextStyle(
                fontSize: 13,
                color: muted,
                decoration: TextDecoration.underline,
                decorationColor: muted.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

class IdiomsWidget extends StatelessWidget {
  final List<IdiomEntry> idioms;
  final WidgetRef ref;
  final void Function(String word)? onWordTap;

  const IdiomsWidget(
    this.idioms, {
    super.key,
    required this.ref,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: idioms.map((idiom) => _buildIdiomItem(context, idiom)).toList(),
    );
  }

  Widget _buildIdiomItem(BuildContext context, IdiomEntry idiom) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Idiom phrase
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Icon(
                  Icons.circle,
                  size: 6,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onWordTap?.call(idiom.phrase),
                  child: Text(
                    idiom.phrase,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Senses under this idiom
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in idiom.groups)
                  ...group.senses.map(
                    (s) => SenseWidget(
                      senseData: s,
                      ref: ref,
                      onWordTap: onWordTap,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PhrasalVerbsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> phrasalVerbs;
  final void Function(String word)? onWordTap;

  const PhrasalVerbsWidget(this.phrasalVerbs, {super.key, this.onWordTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: phrasalVerbs.map((pv) {
        final phrase = pv['phrase'] as String? ?? '';
        return ActionChip(
          label: Text(
            phrase,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onPressed: () => onWordTap?.call(phrase),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

class ExtraExamplesWidget extends StatelessWidget {
  final List<Map<String, dynamic>> extraExamples;

  const ExtraExamplesWidget(this.extraExamples, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: extraExamples.map((ex) => ExampleWidget(example: ex)).toList(),
    );
  }
}

class WordOriginWidget extends StatelessWidget {
  final Map<String, dynamic>? wordOrigin;

  const WordOriginWidget(this.wordOrigin, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = wordOrigin?['text_plain'] as String? ?? '';
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}
