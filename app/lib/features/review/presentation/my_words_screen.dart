import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../dictionary/presentation/widgets/entry_card_header.dart';
import '../providers/my_words_providers.dart';
import 'word_detail_screen.dart';

class MyWordsScreen extends ConsumerStatefulWidget {
  const MyWordsScreen({super.key});

  @override
  ConsumerState<MyWordsScreen> createState() => _MyWordsScreenState();
}

class _MyWordsScreenState extends ConsumerState<MyWordsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final db = ref.read(dictionaryDbProvider);
    final rows = await db.searchPrefix(query.trim(), limit: 20);
    if (mounted) setState(() => _searchResults = rows);
  }

  Future<void> _addWord(Map<String, dynamic> entry) async {
    final list = await ref.read(myWordsListProvider.future);
    final dao = ref.read(vocabularyListDaoProvider);
    await dao.addEntry(
      listId: list.id,
      entryId: entry['id'] as int,
      headword: entry['headword'] as String,
      pos: (entry['pos'] as String?) ?? '',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${entry['headword']}" to My Words'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _removeEntry(VocabularyListEntry entry) async {
    final dao = ref.read(vocabularyListDaoProvider);
    final dictEntryId = await dao.removeEntry(entry.id);
    if (dictEntryId != null) {
      await dao.deleteReviewCard(dictEntryId);
    }
  }

  Future<void> _openDetail(int entryId) async {
    final dictDb = ref.read(dictionaryDbProvider);
    final entries = await dictDb.getEntriesByIds([entryId]);
    if (entries.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WordDetailScreen(entryRow: entries.first),
      ),
    );
  }

  void _showImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SearchHistoryImportSheet(
        onImport: (entries) async {
          final list = await ref.read(myWordsListProvider.future);
          final dao = ref.read(vocabularyListDaoProvider);
          for (final entry in entries) {
            await dao.addEntry(
              listId: list.id,
              entryId: entry.entryId!,
              headword: entry.headword ?? entry.query,
              pos: entry.pos,
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${entries.length} words to My Words'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(myWordsEntriesProvider);
    final order = ref.watch(myWordsOrderProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('My Words'),
            const SizedBox(width: 8),
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(myWordsCountProvider);
                if (count == 0) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search to add words...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (q) {
                setState(() => _isSearching = q.trim().isNotEmpty);
                _onSearch(q);
              },
              textInputAction: TextInputAction.search,
            ),
          ),

          // Search results overlay
          if (_isSearching && _searchResults.isNotEmpty)
            Expanded(child: _buildSearchResults())
          else ...[
            // Order selector + import
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  ...{
                    'oldest': 'Oldest',
                    'newest': 'Newest',
                    'random': 'Random',
                  }.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: order.value == e.key,
                        onSelected: (_) =>
                            ref.read(myWordsOrderProvider.notifier).setOrder(e.key),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showImportSheet,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ),

            // Word list
            Expanded(
              child: entries.when(
                data: (items) => items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.library_add_outlined,
                              size: 48,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No words yet',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Search above or import from history',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _WordListTile(
                            entry: item,
                            onRemove: () => _removeEntry(item),
                            onTap: () => _openDetail(item.entryId),
                          );
                        },
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults[index];
        final headword = entry['headword'] as String;
        final pos = (entry['pos'] as String?) ?? '';
        final cefr = (entry['cefr_level'] as String?) ?? '';
        final entryId = entry['id'] as int;

        return ListTile(
          title: Row(
            children: [
              Text(
                headword,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              if (pos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    pos,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (cefr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CefrBadge(cefr),
                ),
            ],
          ),
          trailing: Consumer(
            builder: (context, ref, _) {
              final contains = ref.watch(myWordsContainsProvider(entryId));
              final isAdded = contains.value ?? false;
              return isAdded
                  ? const Icon(Icons.check, color: Colors.green)
                  : IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _addWord(entry),
                    );
            },
          ),
        );
      },
    );
  }
}

class _WordListTile extends StatelessWidget {
  final VocabularyListEntry entry;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  const _WordListTile({
    required this.entry,
    required this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Row(
        children: [
          Text(
            entry.headword,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (entry.pos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                entry.pos,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: cs.primary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        'Added ${_formatRelativeDate(entry.addedAt)}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
        onPressed: onRemove,
      ),
      onTap: onTap,
    );
  }
}

String _formatRelativeDate(String isoDate) {
  final date = DateTime.parse(isoDate).toLocal();
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0 && date.day == now.day) return 'today';
  if (diff.inDays <= 1 && now.day - date.day == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${date.month}/${date.day}/${date.year}';
}

// ── Search History Import Sheet ─────────────────────────────────────────────

class _SearchHistoryImportSheet extends ConsumerStatefulWidget {
  final Future<void> Function(List<SearchHistoryData> entries) onImport;

  const _SearchHistoryImportSheet({required this.onImport});

  @override
  ConsumerState<_SearchHistoryImportSheet> createState() =>
      _SearchHistoryImportSheetState();
}

class _SearchHistoryImportSheetState
    extends ConsumerState<_SearchHistoryImportSheet> {
  List<SearchHistoryData> _history = [];
  final Set<int> _selectedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final dao = ref.read(searchHistoryDaoProvider);
    final items = await dao.getRecentUnique(limit: 50);
    // Only show items with a matched dictionary entry
    final withEntry = items.where((h) => h.entryId != null).toList();
    if (mounted) {
      setState(() {
        _history = withEntry;
        _loading = false;
      });
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _history.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_history.map((h) => h.id));
      }
    });
  }

  Future<void> _import() async {
    final selected = _history
        .where((h) => _selectedIds.contains(h.id))
        .toList();
    if (selected.isEmpty) return;
    Navigator.pop(context);
    await widget.onImport(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Import from Search History',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: _toggleSelectAll,
                      child: Text(
                        _selectedIds.length == _history.length
                            ? 'Deselect All'
                            : 'Select All',
                      ),
                    ),
                ],
              ),
            ),
            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _history.isEmpty
                  ? Center(
                      child: Text(
                        'No search history with matched words',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final selected = _selectedIds.contains(item.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (_) => setState(() {
                            if (selected) {
                              _selectedIds.remove(item.id);
                            } else {
                              _selectedIds.add(item.id);
                            }
                          }),
                          title: Text(
                            item.headword ?? item.query,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: item.pos.isNotEmpty
                              ? Text(
                                  item.pos,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: cs.primary,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
            // Import button
            if (_history.isNotEmpty)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selectedIds.isEmpty ? null : _import,
                      child: Text(
                        _selectedIds.isEmpty
                            ? 'Select words to import'
                            : 'Add ${_selectedIds.length} words',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
