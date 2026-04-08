import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/database_provider.dart';
import '../providers/search_provider.dart';
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
  int _selectedSuggestion = -1;
  List<String> _currentSuggestions = [];
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
      _selectedSuggestion = -1;
      _currentSuggestions = [];
      _entryKeys.clear();
    });
    ref.invalidate(searchResultsProvider);
    ref.read(searchQueryProvider.notifier).set(prev);
  }

  /// Called by TextField onSubmitted (Enter key)
  void _onSubmitted(String value) {
    final text = value.trim();
    if (text.isEmpty) return;

    if (!_committed && _currentSuggestions.isNotEmpty) {
      // Select first suggestion (or highlighted one)
      final idx = _selectedSuggestion >= 0 ? _selectedSuggestion : 0;
      _commitSearch(_currentSuggestions[idx]);
    } else {
      _commitSearch(text);
    }
    // Keep focus on search bar
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
    _selectedSuggestion = -1;
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
    }
    _lastAutoPronouncedQuery = null;
    _controller.text = word;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: word.length));
    setState(() {
      _committed = true;
      _selectedSuggestion = -1;
      _currentSuggestions = [];
      _entryKeys.clear();
    });
    // Force provider refresh even if same word
    ref.invalidate(searchResultsProvider);
    ref.read(searchQueryProvider.notifier).set(word);
  }

  void _autoPronounce(List<DictEntry> entries, String query) async {
    if (entries.isEmpty || query == _lastAutoPronouncedQuery) return;
    final first = entries.first;
    if (first.headword.toLowerCase() != query.toLowerCase()) return;

    _lastAutoPronouncedQuery = query;
    final historyDao = ref.read(searchHistoryDaoProvider);
    historyDao.addSearch(query, entryId: first.id, headword: first.headword);

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
      debugPrint('scrollToEntry($index): key=${key != null}, context=${key?.currentContext != null}, totalKeys=${_entryKeys.length}');
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.0,
        ).then((_) => debugPrint('scrollToEntry($index): done'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final suggestions = ref.watch(autocompleteSuggestionsProvider);

    results.whenData((entries) => _autoPronounce(entries, query));

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _FocusSearchIntent(),
      },
      child: Actions(
        actions: {
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) { _focusSearchBar(); return null; },
          ),
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
                    ? _buildWelcome()
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
    _currentSuggestions = words;
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
          final isSelected = index == _selectedSuggestion;
          return InkWell(
            onTap: () => _commitSearch(words[index]),
            child: Container(
              color: isSelected ? cs.primaryContainer : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                words[index],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? cs.onPrimaryContainer : null,
                ),
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
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}
