import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/widgets/tappable_text.dart';
import '../../providers/search_provider.dart';
import 'entry_card_header.dart';
import 'entry_card_phonetics.dart';

class SenseGroupWidget extends StatelessWidget {
  final SenseGroupWithSenses group;
  final WidgetRef ref;
  final void Function(String word)? onWordTap;

  const SenseGroupWidget({
    super.key,
    required this.group,
    required this.ref,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.topicEn.isNotEmpty || group.topicZh.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    group.topicEn,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade300
                          : Colors.orange.shade800,
                    ),
                  ),
                  if (group.topicZh.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      group.topicZh,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ...group.senses.map(
          (s) => SenseWidget(senseData: s, ref: ref, onWordTap: onWordTap),
        ),
        if (group.xrefs.isNotEmpty)
          XrefInlineWidget(group.xrefs, onWordTap: onWordTap),
      ],
    );
  }
}

class SenseWidget extends StatelessWidget {
  final SenseWithExamples senseData;
  final WidgetRef ref;
  final void Function(String word)? onWordTap;

  const SenseWidget({
    super.key,
    required this.senseData,
    required this.ref,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = senseData.sense;
    final num = s['sense_num'];
    final cefr = s['cefr_level'] as String? ?? '';
    final grammar = s['grammar'] as String? ?? '';
    final labels = s['labels'] as String? ?? '';
    final definition = s['definition'] as String? ?? '';
    final definitionZh = s['definition_zh'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sense header + definition on same line
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (num != null)
                Text(
                  '$num.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              if (cefr.isNotEmpty) CefrBadge(cefr),
              if (grammar.isNotEmpty)
                Text(
                  grammar,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (labels.isNotEmpty)
                Text(
                  labels,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (definition.isNotEmpty)
                TappableText(
                  text: definition,
                  onWordTap: (w) => onWordTap?.call(w),
                ),
              if (definitionZh.isNotEmpty)
                Text(
                  definitionZh,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          // Examples
          if (senseData.examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: senseData.examples
                    .map(
                      (ex) => ExampleWidget(
                        example: ex,
                        ref: ref,
                        onWordTap: onWordTap,
                      ),
                    )
                    .toList(),
              ),
            ),
          // Sense-level xrefs
          if (senseData.xrefs.isNotEmpty)
            XrefInlineWidget(senseData.xrefs, onWordTap: onWordTap),
        ],
      ),
    );
  }
}

class ExampleWidget extends StatelessWidget {
  final Map<String, dynamic> example;
  final WidgetRef? ref;
  final void Function(String word)? onWordTap;

  const ExampleWidget({
    super.key,
    required this.example,
    this.ref,
    this.onWordTap,
  });

  static Color _usColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF64B5F6)
      : const Color(0xFF1565C0);

  static Color _gbColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF8A65)
      : const Color(0xFFD84315);

  @override
  Widget build(BuildContext context) {
    final text = example['text_plain'] as String? ?? '';
    final textZh = example['text_zh'] as String? ?? '';
    final audioGb = example['audio_gb'] as String? ?? '';
    final audioUs = example['audio_us'] as String? ?? '';
    final display = ref != null
        ? (ref!.watch(pronunciationDisplayProvider).value ?? 'both')
        : 'both';
    final showUs = display != 'gb' && audioUs.isNotEmpty;
    final showGb = display != 'us' && audioGb.isNotEmpty;
    final hasAudio = showUs || showGb;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Icon(
              Icons.circle,
              size: 5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TappableText(
                        text: text,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        onWordTap: (w) => onWordTap?.call(w),
                      ),
                    ),
                    if (hasAudio && ref != null) ...[
                      const SizedBox(width: 4),
                      if (showUs)
                        AudioButton(
                          audioUs,
                          size: 22,
                          color: _usColor(context),
                        ),
                      if (showGb) ...[
                        const SizedBox(width: 2),
                        AudioButton(
                          audioGb,
                          size: 22,
                          color: _gbColor(context),
                        ),
                      ],
                    ],
                  ],
                ),
                if (textZh.isNotEmpty)
                  Text(
                    textZh,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
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

class XrefInlineWidget extends StatelessWidget {
  final List<XrefInfo> xrefs;
  final void Function(String)? onWordTap;

  const XrefInlineWidget(this.xrefs, {super.key, this.onWordTap});

  static const _xrefLabels = {
    'see': 'see also',
    'cp': 'compare',
    'opp': 'opposite',
    'syn': 'synonym',
    'nsyn': 'near synonym',
    'wordfinder': 'wordfinder',
    'pv': 'phrasal verb',
    'eq': 'equivalent',
  };

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<String>>{};
    for (final x in xrefs) {
      byType.putIfAbsent(x.xrefType, () => []).add(x.targetWord);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 4,
        children: byType.entries
            .expand(
              (e) => [
                Text(
                  '${_xrefLabels[e.key] ?? e.key} ',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                ...e.value.map(
                  (w) => MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => onWordTap?.call(w),
                      child: Text(
                        '$w ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
            .toList(),
      ),
    );
  }
}
