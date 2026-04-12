import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../../app.dart'
    show searchBarFocusTrigger, clipboardSearchText, isOverlayModeProvider;
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../providers/search_provider.dart';
import '../providers/search_history_provider.dart';
import '../../../core/sync/sync_provider.dart';
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
        // Came from home screen — return there
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
    // No history but has text — clear search, go home
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

  void _autoPronounce(List<DictEntry> entries, String query) async {
    if (entries.isEmpty || !_committed || query == _lastAutoPronouncedQuery) {
      return;
    }
    final first = entries.first;
    if (first.headword.toLowerCase() != query.toLowerCase()) return;

    _lastAutoPronouncedQuery = query;
    _autoPronounceEntry(first);
  }

  String? _lastSavedHeadword;

  /// Save to history only for single-entry results (multi-entry saves on selection).
  void _saveToHistory(List<DictEntry> entries, String query) {
    if (!_committed || entries.isEmpty) return;
    // Multi-entry: history is saved when user picks an option in _selectEntry
    if (entries.length > 1) return;
    final entry = entries.first;
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

    // Focus search bar when global hotkey fires
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
      next.whenData((entries) {
        final q = ref.read(searchQueryProvider);
        _saveToHistory(entries, q);
        // Auto-select if single entry or pending POS from history tap
        if (entries.length == 1) {
          if (_selectedEntryIndex == null) {
            setState(() {
              _selectedEntryIndex = 0;
              _entryAutoSelected = true;
            });
          }
          _autoPronounce(entries, q);
        } else if (_pendingPos != null && entries.length > 1) {
          final idx = entries.indexWhere((e) => e.pos == _pendingPos);
          if (idx >= 0) {
            setState(() {
              _selectedEntryIndex = idx;
              _entryAutoSelected = true;
            });
            // Save to history and auto-pronounce
            _lastSavedHeadword = '${entries[idx].headword}:${entries[idx].pos}';
            ref
                .read(searchHistoryDaoProvider)
                .addSearch(
                  entries[idx].headword,
                  entryId: entries[idx].id,
                  headword: entries[idx].headword,
                  pos: entries[idx].pos,
                )
                .then((_) => ref.read(syncServiceProvider)?.pushLatestSearch());
            _autoPronounceEntry(entries[idx]);
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
          if (_controller.text.isNotEmpty) {
            // Clear search first
            _controller.clear();
            ref.read(searchQueryProvider.notifier).set('');
            _focusSearchBar();
          } else if (Platform.isMacOS && ref.read(isOverlayModeProvider)) {
            // Empty search in overlay mode: hide window
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
                _buildSearchBar(context),
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
                                  entries.length - 1,
                                );
                                return SingleChildScrollView(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: EntryCard(
                                    entry: entries[idx],
                                    onWordTap: _commitSearch,
                                  ),
                                );
                              }
                              // Multiple entries: show options list
                              return _buildOptionslist(entries);
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

  /// Options list: shows each POS variant for the user to pick
  Widget _buildOptionslist(List<DictEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              e.headword,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: e.pos.isNotEmpty
                ? Text(
                    e.pos,
                    style: TextStyle(
                      color: cs.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e.cefrLevel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.cefrLevel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                if (e.ox3000) ...[
                  const SizedBox(width: 6),
                  Text(
                    '3K',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
                if (e.ox5000 && !e.ox3000) ...[
                  const SizedBox(width: 6),
                  Text(
                    '5K',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
              ],
            ),
            onTap: () => _selectEntry(index, e),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (_canGoBack())
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
              tooltip: 'Back',
            ),
          Expanded(
            child: TextField(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeScreen() {
    final historyAsync = ref.watch(searchHistoryProvider);
    // Use .hasValue to keep showing previous data while loading more,
    // preventing the list from jumping to top on pagination.
    if (historyAsync.hasValue && historyAsync.value!.isNotEmpty) {
      return _buildSearchHistory(historyAsync.value!);
    }
    return _buildWelcome();
  }

  Widget _buildWelcome() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
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
    // +1 for the header row
    return ListView.builder(
      controller: _historyScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: history.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'Recent',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear search history?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear'),
                          ),
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
          );
        }
        final item = history[index - 1];
        final word = item.headword ?? item.query;
        final pos = item.pos;
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
            ref.read(searchHistoryDaoProvider).deleteById(item.id);
          },
          child: ListTile(
            leading: Icon(Icons.history, color: cs.onSurfaceVariant, size: 20),
            title: Row(
              children: [
                Text(word),
                if (pos.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    pos,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
            trailing: Text(
              _relativeTime(item.searchedAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            onTap: () => _commitSearch(word, pos: pos.isNotEmpty ? pos : null),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        );
      },
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
