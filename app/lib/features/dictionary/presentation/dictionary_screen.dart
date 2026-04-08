import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/audio_provider.dart';
import '../providers/search_provider.dart';
import 'widgets/entry_card.dart';

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String? _lastAutoPronouncedQuery;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).set(value.trim());
    });
  }

  void _searchWord(String word) {
    _controller.text = word;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: word.length),
    );
    ref.read(searchQueryProvider.notifier).set(word);
    _focusNode.requestFocus();
  }

  /// Auto-pronounce the first entry when search results arrive
  void _autoPronounce(List<DictEntry> entries, String query) {
    if (entries.isEmpty) return;
    if (query == _lastAutoPronouncedQuery) return;

    // Only auto-pronounce on exact match (not prefix search results)
    final first = entries.first;
    if (first.headword.toLowerCase() != query.toLowerCase()) return;

    _lastAutoPronouncedQuery = query;
    final audio = ref.read(audioServiceProvider);
    audio.playPronunciation(first.pronunciations, dialect: 'us');
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    // Auto-pronounce when results arrive
    results.whenData((entries) => _autoPronounce(entries, query));

    return CallbackShortcuts(
      bindings: {
        // Cmd+K to focus search (Spotlight-style)
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          _focusNode.requestFocus();
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        },
        // Escape to clear search
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_controller.text.isNotEmpty) {
            _controller.clear();
            ref.read(searchQueryProvider.notifier).set('');
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildSearchBar(context),
                Expanded(
                  child: query.isEmpty
                      ? _buildWelcome()
                      : results.when(
                          data: (entries) => entries.isEmpty
                              ? Center(
                                  child: Text(
                                    'No results for "$query"',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: entries.length,
                                  itemBuilder: (context, index) => EntryCard(
                                    entry: entries[index],
                                    onWordTap: _searchWord,
                                  ),
                                ),
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onSearchChanged,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search for a word...  (⌘K)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).set('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'OALD10 Dictionary',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Type a word to look it up',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '⌘K to focus search',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}
