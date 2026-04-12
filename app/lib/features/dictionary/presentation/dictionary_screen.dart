import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../../app.dart'
    show searchBarFocusTrigger, clipboardSearchText, isOverlayModeProvider;
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/database_provider.dart';
import '../providers/search_provider.dart';
import '../providers/search_history_provider.dart';
import '../../../core/sync/sync_provider.dart';
import 'widgets/dictionary_search_bar.dart';
import 'widgets/dictionary_welcome.dart';
import 'widgets/entry_card.dart';
import 'widgets/entry_options_list.dart';
import 'widgets/search_history_list.dart';

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _historyScrollController = ScrollController();
  Timer? _debounce;
  String? _lastAutoPronouncedQuery;
  bool _committed = false;
  final _history = <String>[]; // navigation history stack

  // Two-step search: null = show options list, int = show that entry
  int? _selectedEntryIndex;
  // true when entry was auto-selected (single result or pendingPos), not manually picked from options list
  bool _entryAutoSelected = false;
  // When navigating from history with POS, auto-select matching entry
  String? _pendingPos;

  @override
  void initState() {
    super.initState();
    _historyScrollController.addListener(_onHistoryScroll);
  }

  void _onHistoryScroll() {
    final pos = _historyScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
        !ref.read(searchHistoryProvider).isLoading) {
      ref.read(historyLimitProvider.notifier).loadMore();
    }
  }

  bool _canGoBack() {
    return _history.isNotEmpty ||
        _selectedEntryIndex != null ||
        _controller.text.isNotEmpty;
  }

  void _goBack() {
    // If user manually picked from multi-POS options list, go back to that list
    if (_selectedEntryIndex != null && !_entryAutoSelected) {
      setState(() => _selectedEntryIndex = null);
      return;
    }
    if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      if (prev.isEmpty) {
        // Came from home screen -- return there
        _controller.clear();
        setState(() {
          _committed = false;
          _selectedEntryIndex = null;
          _entryAutoSelected = false;
          _pendingPos = null;
        });
        ref.read(searchQueryProvider.notifier).set('');
        return;
      }
      _lastAutoPronouncedQuery = prev; // don't re-pronounce when going back
      _controller.text = prev;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: prev.length),
      );
      setState(() {
        _committed = true;
        _selectedEntryIndex = null;
        _entryAutoSelected = false;
        _pendingPos = null;
      });
      ref.invalidate(searchResultsProvider);
      ref.read(searchQueryProvider.notifier).set(prev);
      return;
    }
    // No history but has text -- clear search, go home
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      setState(() {
        _committed = false;
        _selectedEntryIndex = null;
        _entryAutoSelected = false;
        _pendingPos = null;
      });
      ref.read(searchQueryProvider.notifier).set('');
    }
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
    _historyScrollController.removeListener(_onHistoryScroll);
    _historyScrollController.dispose();
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
    _selectedEntryIndex = null;
    _entryAutoSelected = false;
    _pendingPos = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).set(value.trim());
    });
  }

  /// Called when user taps a suggestion or presses Enter - commit the search
  void _commitSearch(String word, {String? pos}) {
    // Push current query to history for back navigation (empty string = home screen)
    final current = ref.read(searchQueryProvider);
    if (current.toLowerCase() != word.toLowerCase()) {
      _history.add(current);
      if (_history.length > 50) _history.removeAt(0);
    }
    _lastAutoPronouncedQuery = null;
    _controller.text = word;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: word.length),
    );
    setState(() {
      _committed = true;
      _selectedEntryIndex = null;
      _entryAutoSelected = false;
      _pendingPos = pos;
    });
    // Force provider refresh even if same word
    ref.invalidate(searchResultsProvider);
    ref.read(searchQueryProvider.notifier).set(word);
  }

  /// Called when user picks a specific POS option from the options list
  void _selectEntry(int index, DictEntry entry) {
    setState(() {
      _selectedEntryIndex = index;
      _entryAutoSelected = false;
    });
    // Save to history with POS
    _lastSavedHeadword = '${entry.headword}:${entry.pos}';
    ref
        .read(searchHistoryDaoProvider)
        .addSearch(
          entry.headword,
          entryId: entry.id,
          headword: entry.headword,
          pos: entry.pos,
        )
        .then((_) => ref.read(syncServiceProvider)?.pushLatestSearch());
    // Auto-pronounce the selected entry
    _autoPronounceEntry(entry);
  }

  void _autoPronounceEntry(DictEntry entry) async {
    final settings = ref.read(settingsDaoProvider);
    if (!await settings.getAutoPronounce()) return;
    final display = await settings.getPronunciationDisplay();
    final dialect = display == 'both' ? await settings.getDialect() : display;
    ref
        .read(audioServiceProvider)
        .playPronunciation(entry.pronunciations, dialect: dialect);
  }

  void _autoPronounce(List<SearchResult> results, String query) async {
    if (results.isEmpty || !_committed || query == _lastAutoPronouncedQuery) {
      return;
    }
    final first = results.first.entry;
    if (first.headword.toLowerCase() != query.toLowerCase()) return;

    _lastAutoPronouncedQuery = query;
    _autoPronounceEntry(first);
  }

  String? _lastSavedHeadword;

  /// Save to history only for single-entry results (multi-entry saves on selection).
  void _saveToHistory(List<SearchResult> results, String query) {
    if (!_committed || results.isEmpty) return;
    // Multi-entry: history is saved when user picks an option in _selectEntry
    if (results.length > 1) return;
    final entry = results.first.entry;
    final key = '${entry.headword}:${entry.pos}';
    if (key == _lastSavedHeadword) return;
    _lastSavedHeadword = key;
    ref
        .read(searchHistoryDaoProvider)
        .addSearch(
          entry.headword,
          entryId: entry.id,
          headword: entry.headword,
          pos: entry.pos,
        )
        .then((_) => ref.read(syncServiceProvider)?.pushLatestSearch());
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    // Reset to fresh search screen when overlay opens
    ref.listen(isOverlayModeProvider, (prev, next) {
      if (next) {
        setState(() {
          _controller.clear();
          _selectedEntryIndex = null;
          _entryAutoSelected = false;
          _history.clear();
          _committed = false;
        });
        ref.read(searchQueryProvider.notifier).set('');
      }
    });

    // Focus search bar when global hotkey fires, auto-fill clipboard word
    ref.listen(searchBarFocusTrigger, (prev, next) {
      final clipText = ref.read(clipboardSearchText);
      if (clipText != null) {
        ref.read(clipboardSearchText.notifier).set(null);
        _commitSearch(clipText);
      }
      _focusSearchBar();
    });

    ref.listen(searchResultsProvider, (prev, next) {
      next.whenData((results) {
        final q = ref.read(searchQueryProvider);
        _saveToHistory(results, q);
        // Auto-select if single entry or pending POS from history tap
        if (results.length == 1) {
          if (_selectedEntryIndex == null) {
            setState(() {
              _selectedEntryIndex = 0;
              _entryAutoSelected = true;
            });
          }
          _autoPronounce(results, q);
        } else if (_pendingPos != null && results.length > 1) {
          final idx = results.indexWhere((r) => r.entry.pos == _pendingPos);
          if (idx >= 0) {
            final entry = results[idx].entry;
            setState(() {
              _selectedEntryIndex = idx;
              _entryAutoSelected = true;
            });
            // Save to history and auto-pronounce
            _lastSavedHeadword = '${entry.headword}:${entry.pos}';
            ref
                .read(searchHistoryDaoProvider)
                .addSearch(
                  entry.headword,
                  entryId: entry.id,
                  headword: entry.headword,
                  pos: entry.pos,
                )
                .then((_) => ref.read(syncServiceProvider)?.pushLatestSearch());
            _autoPronounceEntry(entry);
          }
          _pendingPos = null;
        }
      });
    });

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_canGoBack()) {
            _goBack();
            _focusSearchBar();
          } else if (Platform.isMacOS && ref.read(isOverlayModeProvider)) {
            windowManager.hide();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: !_canGoBack(),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                DictionarySearchBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSubmitted,
                  canGoBack: _canGoBack(),
                  onBack: _goBack,
                  onClear: () {
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).set('');
                    _focusNode.requestFocus();
                  },
                  isOverlay: ref.watch(isOverlayModeProvider),
                ),
                // Results (SelectionArea enables text selection)
                Expanded(
                  child: SelectionArea(
                    child: query.isEmpty
                        ? _buildHomeScreen()
                        : results.when(
                            data: (searchResults) {
                              if (searchResults.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No results for "$query"',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              }
                              // Single entry or entry selected: show full card
                              if (_selectedEntryIndex != null) {
                                final idx = _selectedEntryIndex!.clamp(
                                  0,
                                  searchResults.length - 1,
                                );
                                return SingleChildScrollView(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: EntryCard(
                                    entry: searchResults[idx].entry,
                                    onWordTap: _commitSearch,
                                  ),
                                );
                              }
                              // Multiple entries: show options list
                              return EntryOptionsList(
                                results: searchResults,
                                onSelect: _selectEntry,
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
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

  Widget _buildHomeScreen() {
    final historyAsync = ref.watch(searchHistoryProvider);
    // Use .hasValue to keep showing previous data while loading more,
    // preventing the list from jumping to top on pagination.
    if (historyAsync.hasValue && historyAsync.value!.isNotEmpty) {
      return SearchHistoryList(
        history: historyAsync.value!,
        scrollController: _historyScrollController,
        onTap: (word, {String? pos}) => _commitSearch(word, pos: pos),
        onClearAll: () => ref.read(searchHistoryDaoProvider).clearAll(),
        onDelete: (id) => ref.read(searchHistoryDaoProvider).deleteById(id),
      );
    }
    return const DictionaryWelcome();
  }
}
