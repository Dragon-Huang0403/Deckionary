import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_provider.dart';
import '../../domain/review_filter.dart';
import '../../providers/my_words_providers.dart';
import '../../providers/review_providers.dart';

/// Dialog for selecting which words to study (CEFR levels + Oxford lists).
class FilterSelector extends ConsumerStatefulWidget {
  const FilterSelector({super.key});

  @override
  ConsumerState<FilterSelector> createState() => _FilterSelectorState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const Dialog(child: FilterSelector()),
    );
  }
}

class _FilterSelectorState extends ConsumerState<FilterSelector> {
  late Set<String> _cefrLevels;
  late bool _ox3000;
  late bool _ox5000;
  int? _wordCount;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    final filter = await ref.read(reviewFilterProvider.future);
    setState(() {
      _cefrLevels = Set.from(filter.cefrLevels);
      _ox3000 = filter.ox3000;
      _ox5000 = filter.ox5000;
      _loaded = true;
    });
    _updateWordCount();
  }

  Future<void> _updateWordCount() async {
    final dictDb = ref.read(dictionaryDbProvider);
    final count = await dictDb.countFilteredEntries(
      cefrLevels: _cefrLevels.toList(),
      ox3000: _ox3000,
      ox5000: _ox5000,
    );
    if (mounted) setState(() => _wordCount = count);
  }

  void _toggleCefr(String level) {
    setState(() {
      if (_cefrLevels.contains(level)) {
        _cefrLevels.remove(level);
      } else {
        _cefrLevels.add(level);
      }
    });
    _updateWordCount();
  }

  Future<void> _save() async {
    final filter = ReviewFilter(
      cefrLevels: _cefrLevels,
      ox3000: _ox3000,
      ox5000: _ox5000,
    );
    await ref.read(reviewFilterProvider.notifier).setFilter(filter);
    ref.invalidate(reviewSummaryProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_loaded) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('Study Words', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // CEFR level chips
            Text(
              'CEFR Level',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['a1', 'a2', 'b1', 'b2', 'c1'].map((level) {
                final selected = _cefrLevels.contains(level);
                return FilterChip(
                  label: Text(level.toUpperCase()),
                  selected: selected,
                  onSelected: (_) => _toggleCefr(level),
                  selectedColor: _cefrColor(level).withValues(alpha: 0.2),
                  checkmarkColor: _cefrColor(level),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Oxford list toggles
            Text(
              'Oxford Word Lists',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('Oxford 3000'),
              subtitle: const Text('Core vocabulary (~3,771 words)'),
              value: _ox3000,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) {
                setState(() => _ox3000 = v);
                _updateWordCount();
              },
            ),
            SwitchListTile(
              title: const Text('Oxford 5000'),
              subtitle: const Text('Extended vocabulary (~5,900 words)'),
              value: _ox5000,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) {
                setState(() => _ox5000 = v);
                _updateWordCount();
              },
            ),

            // My Words indicator
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(myWordsCountProvider);
                if (count == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'My Words: $count words',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 12),

            // Word count + save
            Row(
              children: [
                if (_wordCount != null)
                  Text(
                    '$_wordCount words selected',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _cefrColor(String level) {
    return switch (level) {
      'a1' => const Color(0xFF4CAF50),
      'a2' => const Color(0xFF8BC34A),
      'b1' => const Color(0xFFFFC107),
      'b2' => const Color(0xFFFF9800),
      'c1' => const Color(0xFF9C27B0),
      _ => const Color(0xFF607D8B),
    };
  }
}
