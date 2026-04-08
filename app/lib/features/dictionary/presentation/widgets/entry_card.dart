import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/audio_provider.dart';
import '../../providers/search_provider.dart';

class EntryCard extends ConsumerWidget {
  final DictEntry entry;
  final void Function(String word)? onWordTap;

  const EntryCard({super.key, required this.entry, this.onWordTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: headword + POS + badges
            _buildHeader(context),
            // Phonetics
            if (entry.pronunciations.isNotEmpty) _buildPhonetics(context, ref),
            // Word family
            if (entry.wordFamily.isNotEmpty) _buildWordFamily(context),
            // Verb forms
            if (entry.verbForms.isNotEmpty) _buildVerbForms(context),
            // Cross-references
            if (entry.xrefs.isNotEmpty) _buildXrefs(context),
            // Senses
            ...entry.groups.map((g) => _buildSenseGroup(context, g, ref)),
            // Synonyms
            if (entry.synonyms.isNotEmpty) _buildCollapsible(context, 'Synonyms', _buildSynonyms(context)),
            // Collocations
            if (entry.collocations.isNotEmpty) _buildCollapsible(context, 'Collocations', _buildCollocations(context)),
            // Phrasal verbs
            if (entry.phrasalVerbs.isNotEmpty) _buildCollapsible(context, 'Phrasal Verbs', _buildPhrasalVerbs(context)),
            // Extra examples
            if (entry.extraExamples.isNotEmpty)
              _buildCollapsible(context, 'Extra Examples (${entry.extraExamples.length})', _buildExtraExamples(context)),
            // Word origin
            if (entry.wordOrigin != null) _buildCollapsible(context, 'Word Origin', _buildWordOrigin(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(entry.headword, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.primary)),
        if (entry.pos.isNotEmpty)
          Text(entry.pos, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
        if (entry.cefrLevel.isNotEmpty) _cefrBadge(entry.cefrLevel),
        if (entry.ox3000) _oxBadge('3000', cs),
        if (entry.ox5000 && !entry.ox3000) _oxBadge('5000', cs),
      ],
    );
  }

  Widget _cefrBadge(String level) {
    final colors = {
      'a1': Colors.green, 'a2': Colors.lightGreen,
      'b1': Colors.orange, 'b2': Colors.deepOrange,
      'c1': Colors.purple, 'c2': Colors.deepPurple,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors[level] ?? Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(level.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _oxBadge(String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4)),
      child: Text('Oxford $label', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  static const _usColor = Color(0xFF1565C0); // blue
  static const _gbColor = Color(0xFFD84315); // deep orange

  Widget _buildPhonetics(BuildContext context, WidgetRef ref) {
    final gb = entry.pronunciations.where((p) => p['dialect'] == 'gb').firstOrNull;
    final us = entry.pronunciations.where((p) => p['dialect'] == 'us').firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Wrap(
        spacing: 16,
        children: [
          if (us != null) _phonGroup(ref, 'US', us['ipa'] as String? ?? '', us['audio_file'] as String? ?? '', _usColor),
          if (gb != null) _phonGroup(ref, 'GB', gb['ipa'] as String? ?? '', gb['audio_file'] as String? ?? '', _gbColor),
        ],
      ),
    );
  }

  Widget _phonGroup(WidgetRef ref, String label, String ipa, String audioFile, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 6),
        Text(ipa, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        if (audioFile.isNotEmpty) ...[
          const SizedBox(width: 4),
          _audioButton(ref, audioFile, color: color),
        ],
      ],
    );
  }

  Widget _audioButton(WidgetRef ref, String filename, {double size = 28, Color? color}) {
    final c = color ?? _usColor;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: size * 0.55,
        style: IconButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.volume_up),
        onPressed: () => ref.read(audioServiceProvider).play(filename),
      ),
    );
  }

  Widget _buildSenseGroup(BuildContext context, SenseGroupWithSenses group, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.topicEn.isNotEmpty || group.topicZh.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
              child: Row(
                children: [
                  Text(group.topicEn, style: TextStyle(fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: Colors.orange.shade800)),
                  if (group.topicZh.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(group.topicZh, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ),
        ...group.senses.map((s) => _buildSense(context, s, ref)),
        if (group.xrefs.isNotEmpty) _buildXrefInline(context, group.xrefs),
      ],
    );
  }

  Widget _buildSense(BuildContext context, SenseWithExamples senseData, WidgetRef ref) {
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
          // Sense header
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (num != null) Text('$num.', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              if (cefr.isNotEmpty) _cefrBadge(cefr),
              if (grammar.isNotEmpty) Text(grammar, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              if (labels.isNotEmpty) Text(labels, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 2),
          Text(definition),
          if (definitionZh.isNotEmpty)
            Text(definitionZh, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          // Examples
          if (senseData.examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: senseData.examples.map((ex) => _buildExample(context, ex, ref: ref)).toList(),
              ),
            ),
          // Sense-level xrefs
          if (senseData.xrefs.isNotEmpty) _buildXrefInline(context, senseData.xrefs),
        ],
      ),
    );
  }

  Widget _buildExample(BuildContext context, Map<String, dynamic> ex, {WidgetRef? ref}) {
    final text = ex['text_plain'] as String? ?? '';
    final textZh = ex['text_zh'] as String? ?? '';
    final audioGb = ex['audio_gb'] as String? ?? '';
    final audioUs = ex['audio_us'] as String? ?? '';
    final hasAudio = audioGb.isNotEmpty || audioUs.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 8),
            child: Icon(Icons.circle, size: 5, color: Colors.grey),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                    ),
                    if (hasAudio && ref != null) ...[
                      const SizedBox(width: 4),
                      if (audioUs.isNotEmpty) _audioButton(ref, audioUs, size: 22, color: _usColor),
                      if (audioGb.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        _audioButton(ref, audioGb, size: 22, color: _gbColor),
                      ],
                    ],
                  ],
                ),
                if (textZh.isNotEmpty)
                  Text(textZh, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordFamily(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: entry.wordFamily.map((wf) {
          final word = wf['word'] as String? ?? '';
          final pos = wf['pos'] as String? ?? '';
          final opp = wf['opposite'] as String? ?? '';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(word, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                if (pos.isNotEmpty) Text(' $pos', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                if (opp.isNotEmpty) Text(' $opp', style: TextStyle(fontSize: 12, color: Colors.red.shade300)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVerbForms(BuildContext context) {
    return _buildCollapsible(context, 'Verb Forms', Column(
      children: entry.verbForms.map((vf) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(vf['form_text'] as String? ?? '', style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
    ));
  }

  static const _xrefLabels = {
    'see': 'see also', 'cp': 'compare', 'opp': 'opposite', 'syn': 'synonym',
    'nsyn': 'near synonym', 'wordfinder': 'wordfinder', 'pv': 'phrasal verb', 'eq': 'equivalent',
  };

  Widget _buildXrefs(BuildContext context) {
    return _buildXrefInline(context, entry.xrefs);
  }

  Widget _buildXrefInline(BuildContext context, List<XrefInfo> xrefs) {
    final byType = <String, List<String>>{};
    for (final x in xrefs) {
      byType.putIfAbsent(x.xrefType, () => []).add(x.targetWord);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 4,
        children: byType.entries.expand((e) => [
          Text('${_xrefLabels[e.key] ?? e.key} ', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 13)),
          ...e.value.map((w) => GestureDetector(
            onTap: () => onWordTap?.call(w),
            child: Text('$w ', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, decoration: TextDecoration.underline)),
          )),
        ]).toList(),
      ),
    );
  }

  Widget _buildSynonyms(BuildContext context) {
    final words = entry.synonyms.map((s) => s['word'] as String? ?? '').toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: words.map((w) => Chip(
        label: Text(w, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
  }

  Widget _buildCollocations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entry.collocations.map((c) {
        final cat = c['category'] as String? ?? '';
        final words = c['words'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700, letterSpacing: 0.3)),
              Text(words, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhrasalVerbs(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: entry.phrasalVerbs.map((pv) {
        final phrase = pv['phrase'] as String? ?? '';
        return ActionChip(
          label: Text(phrase, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
          onPressed: () => onWordTap?.call(phrase),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  Widget _buildExtraExamples(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entry.extraExamples.map((ex) => _buildExample(context, ex)).toList(),
    );
  }

  Widget _buildWordOrigin(BuildContext context) {
    final text = entry.wordOrigin?['text_plain'] as String? ?? '';
    return Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.5));
  }

  Widget _buildCollapsible(BuildContext context, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        dense: true,
        children: [child],
      ),
    );
  }
}
