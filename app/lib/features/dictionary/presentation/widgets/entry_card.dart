import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../../review/providers/my_words_providers.dart';
import '../../../../core/database/database_provider.dart';
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
              // My Words toggle
              _MyWordsButton(entry: entry),
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

class _MyWordsButton extends ConsumerWidget {
  final DictEntry entry;
  const _MyWordsButton({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containsAsync = ref.watch(myWordsContainsProvider(entry.id));
    final isAdded = containsAsync.value ?? false;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggle(ref, isAdded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdded ? Icons.bookmark : Icons.bookmark_outline,
                size: 16,
                color: isAdded
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                isAdded ? 'In My Words' : 'My Words',
                style: TextStyle(
                  fontSize: 12,
                  color: isAdded
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, bool isAdded) async {
    final dao = ref.read(vocabularyListDaoProvider);
    final list = await ref.read(myWordsListProvider.future);

    if (isAdded) {
      // Find and remove the entry
      final entries = await dao.getEntries(list.id);
      final match = entries.where((e) => e.entryId == entry.id).firstOrNull;
      if (match != null) {
        await dao.removeEntry(match.id);
        await dao.deleteReviewCard(entry.id);
      }
    } else {
      await dao.addEntry(
        listId: list.id,
        entryId: entry.id,
        headword: entry.headword,
        pos: entry.pos,
      );
    }
    ref.invalidate(myWordsEntriesProvider);
  }
}
