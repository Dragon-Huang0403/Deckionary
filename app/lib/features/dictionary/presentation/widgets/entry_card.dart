import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import 'collapsible_section.dart';
import 'entry_card_header.dart';
import 'entry_card_phonetics.dart';
import 'entry_card_word_info.dart';
import 'entry_card_senses.dart';
import 'entry_card_extras.dart';

class EntryCard extends ConsumerWidget {
  final DictEntry entry;
  final void Function(String word)? onWordTap;

  const EntryCard({super.key, required this.entry, this.onWordTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: headword + POS + badges
              EntryCardHeader(
                headword: entry.headword,
                pos: entry.pos,
                cefrLevel: entry.cefrLevel,
                ox3000: entry.ox3000,
                ox5000: entry.ox5000,
              ),
              // Phonetics
              if (entry.pronunciations.isNotEmpty)
                EntryPhonetics(entry.pronunciations),
              // Word family
              if (entry.wordFamily.isNotEmpty)
                WordFamilyWidget(entry.wordFamily, onWordTap: onWordTap),
              // Verb forms
              if (entry.verbForms.isNotEmpty) VerbFormsWidget(entry.verbForms),
              // Cross-references
              if (entry.xrefs.isNotEmpty)
                XrefInlineWidget(entry.xrefs, onWordTap: onWordTap),
              // Senses
              ...entry.groups.map(
                (g) =>
                    SenseGroupWidget(group: g, ref: ref, onWordTap: onWordTap),
              ),
              // Synonyms
              if (entry.synonyms.isNotEmpty)
                CollapsibleSection(
                  title: 'Synonyms',
                  child: SynonymsWidget(entry.synonyms),
                ),
              // Idioms
              if (entry.idioms.isNotEmpty)
                CollapsibleSection(
                  title: 'Idioms',
                  child: IdiomsWidget(
                    entry.idioms,
                    ref: ref,
                    onWordTap: onWordTap,
                  ),
                ),
              // Word origin
              if (entry.wordOrigin != null)
                CollapsibleSection(
                  title: 'Word Origin',
                  child: WordOriginWidget(entry.wordOrigin),
                ),
              // Collocations
              if (entry.collocations.isNotEmpty)
                CollapsibleSection(
                  title: 'Collocations',
                  child: CollocationsWidget(
                    entry.collocations,
                    onWordTap: onWordTap,
                  ),
                ),
              // Phrasal verbs
              if (entry.phrasalVerbs.isNotEmpty)
                CollapsibleSection(
                  title: 'Phrasal Verbs',
                  child: PhrasalVerbsWidget(
                    entry.phrasalVerbs,
                    onWordTap: onWordTap,
                  ),
                ),
              // Extra examples
              if (entry.extraExamples.isNotEmpty)
                CollapsibleSection(
                  title: 'Extra Examples',
                  initiallyExpanded: false,
                  child: ExtraExamplesWidget(entry.extraExamples),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
