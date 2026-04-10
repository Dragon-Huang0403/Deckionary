import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../providers/search_provider.dart';
import '../providers/search_history_provider.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/entry_card.dart';

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String? _lastAutoPronouncedQuery;
  bool _committed = false;
  final _history = <String>[]; // navigation history stack

  // Keys for scrolling to POS entries
  final _entryKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
  }

  void _goBack() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _lastAutoPronouncedQuery = prev; // don't re-pronounce when going back
    _controller.text = prev;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: prev.length));
    setState(() {
      _committed = true;
      _entryKeys.clear();
    });
    ref.invalidate(searchResultsProvider);
    ref.read(searchQueryProvider.notifier).set(prev);
  }

  /// Called by TextField onSubmitted (Enter key)
  void _onSubmitted(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    _commitSearch(text);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusSearchBar() {
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _onSearchChanged(String value) {
    _committed = false;
    _entryKeys.clear();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).set(value.trim());
    });
  }

  /// Called when user taps a suggestion or presses Enter - commit the search
  void _commitSearch(String word) {
    // Push current query to history for back navigation
    final current = ref.read(searchQueryProvider);
    if (current.isNotEmpty && current.toLowerCase() != word.toLowerCase()) {
      _history.add(current);
      if (_history.length > 50) _history.removeAt(0);
    }
    _lastAutoPronouncedQuery = null;
    _controller.text = word;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: word.length));
    setState(() {
      _committed = true;
      _entryKeys.clear();
    });
    // Save to search history on every explicit commit
    ref.read(searchHistoryDaoProvider).addSearch(word, headword: word);
    // Force provider refresh even if same word
    ref.invalidate(searchResultsProvider);
    ref.read(searchQueryProvider.notifier).set(word);
  }

  void _autoPronounce(List<DictEntry> entries, String query) async {
    if (entries.isEmpty || query == _lastAutoPronouncedQuery) return;
    final first = entries.first;
    if (first.headword.toLowerCase() != query.toLowerCase()) return;

    _lastAutoPronouncedQuery = query;

    // Auto-pronounce if: committed (Enter/tap) OR no other suggestions
    if (!_committed) {
      final suggestions = ref.read(autocompleteSuggestionsProvider);
      final hasOtherSuggestions = suggestions.when(
        data: (words) => words.any((w) => w.toLowerCase() != query.toLowerCase()),
        loading: () => true,
        error: (_, _) => false,
      );
      if (hasOtherSuggestions) return;
    }

    final settings = ref.read(settingsDaoProvider);
    if (!await settings.getAutoPronounce()) return;
    final dialect = await settings.getDialect();
    ref.read(audioServiceProvider).playPronunciation(first.pronunciations, dialect: dialect);
  }

  void _scrollToEntry(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _entryKeys[index];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final suggestions = ref.watch(autocompleteSuggestionsProvider);

    ref.listen(searchResultsProvider, (prev, next) {
      next.whenData((entries) => _autoPronounce(entries, ref.read(searchQueryProvider)));
    });

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _focusSearchBar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
          body: SafeArea(
            child: Column(
            children: [
              _buildSearchBar(context),
              // Autocomplete suggestions - hide when committed
              if (query.isNotEmpty && !_committed)
                suggestions.when(
                  data: (words) => words.isNotEmpty ? _buildSuggestions(words) : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              // POS tabs (when multiple entries for same headword)
              results.when(
                data: (entries) => _buildPosTabs(entries),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              // Results (SelectionArea enables text selection)
              Expanded(
                child: SelectionArea(
                  child: query.isEmpty
                    ? _buildHomeScreen()
                    : results.when(
                        data: (entries) {
                          if (entries.isEmpty) {
                            return Center(
                              child: Text(
                                'No results for "$query"',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            );
                          }
                          // Ensure we have stable keys for each entry
                          for (var i = _entryKeys.length; i < entries.length; i++) {
                            _entryKeys[i] = GlobalKey();
                          }
                          return SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                for (var i = 0; i < entries.length; i++)
                                  Container(
                                    key: _entryKeys[i],
                                    child: EntryCard(
                                      entry: entries[i],
                                      onWordTap: _commitSearch,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                      ),
                ),
              ),
            ],
          ),
          ),
        ),
      );
  }

  /// POS tab bar: shows when multiple entries exist (noun, verb, idiom, etc.)
  Widget _buildPosTabs(List<DictEntry> entries) {
    if (entries.length <= 1) return const SizedBox.shrink();

    // Group by headword to see if it's same word with different POS
    final headwords = entries.map((e) => e.headword.toLowerCase()).toSet();
    // Only show tabs if there are multiple POS for same-ish word
    if (headwords.length > 3) return const SizedBox.shrink();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final e = entries[index];
          final label = e.pos.isNotEmpty ? '${e.headword} (${e.pos})' : e.headword;
          return ActionChip(
            label: Text(label, style: const TextStyle(fontSize: 13)),
            onPressed: () => _scrollToEntry(index),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  /// Autocomplete dropdown
  Widget _buildSuggestions(List<String> words) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: words.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () => _commitSearch(words[index]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                words[index],
                style: const TextStyle(fontSize: 15),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
              tooltip: 'Back',
            ),
          Expanded(child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            onSubmitted: _onSubmitted,
            textInputAction: TextInputAction.search,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search for a word...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        ref.read(searchQueryProvider.notifier).set('');
                        _focusNode.requestFocus();
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          )),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeScreen() {
    final historyAsync = ref.watch(searchHistoryProvider);
    return historyAsync.when(
      data: (history) => history.isEmpty ? _buildWelcome() : _buildSearchHistory(history),
      loading: () => _buildWelcome(),
      error: (_, _) => _buildWelcome(),
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
        ],
      ),
    );
  }

  Widget _buildSearchHistory(List<SearchHistoryData> history) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                'Recent',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear search history?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    ref.read(searchHistoryDaoProvider).clearAll();
                  }
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        ...history.map((item) {
          final word = item.headword ?? item.query;
          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: cs.errorContainer,
              child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
            ),
            onDismissed: (_) {
              ref.read(searchHistoryDaoProvider).deleteByHeadword(word);
            },
            child: ListTile(
              leading: Icon(Icons.history, color: cs.onSurfaceVariant, size: 20),
              title: Text(word),
              trailing: Text(
                _relativeTime(item.searchedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              onTap: () => _commitSearch(word),
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          );
        }),
      ],
    );
  }

  String _relativeTime(String isoString) {
    final date = DateTime.tryParse(isoString);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}
