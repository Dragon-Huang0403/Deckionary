import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import 'word_detail_screen.dart';

class LearnedWordsScreen extends ConsumerStatefulWidget {
  const LearnedWordsScreen({super.key});

  @override
  ConsumerState<LearnedWordsScreen> createState() => _LearnedWordsScreenState();
}

class _LearnedWordsScreenState extends ConsumerState<LearnedWordsScreen> {
  static const _tabs = [
    _TabDef('All', null),
    _TabDef('Learning', 1),
    _TabDef('Review', 2),
    _TabDef('Relearning', 3),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learned Words'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _tabs
                .map((t) => Tab(
                      child: Text(
                        t.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs
              .map((t) => _LearnedWordListTab(stateFilter: t.stateFilter))
              .toList(),
        ),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final int? stateFilter;
  const _TabDef(this.label, this.stateFilter);
}

class _LearnedWordListTab extends ConsumerStatefulWidget {
  final int? stateFilter;
  const _LearnedWordListTab({required this.stateFilter});

  @override
  ConsumerState<_LearnedWordListTab> createState() =>
      _LearnedWordListTabState();
}

class _LearnedWordListTabState extends ConsumerState<_LearnedWordListTab>
    with AutomaticKeepAliveClientMixin {
  final _cards = <ReviewCard>[];
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _hasMore = true;
  static const _pageSize = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || (_loading && _cards.isNotEmpty)) return;
    setState(() => _loading = true);

    final dao = ref.read(reviewDaoProvider);
    final rows = await dao.getAllReviewCards(
      stateFilter: widget.stateFilter,
      limit: _pageSize,
      offset: _cards.length,
    );

    if (mounted) {
      setState(() {
        _cards.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading && _cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cards.isEmpty) {
      return const Center(child: Text('No words'));
    }

    final cs = Theme.of(context).colorScheme;

    return ListView.builder(
      controller: _scrollController,
      itemCount: _cards.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _cards.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final card = _cards[index];
        return ListTile(
          title: Text(
            card.headword,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (card.pos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        card.pos,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  _StateBadge(state: card.state),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Due: ${_formatDate(card.due)}  ·  '
                'Reviews: ${card.reps}  ·  '
                'Last: ${_formatDate(card.lastReview)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => _openDetail(card),
        );
      },
    );
  }

  Future<void> _openDetail(ReviewCard card) async {
    final dao = ref.read(reviewDaoProvider);
    final entries = await dao.getEntryDetails([card.entryId]);
    if (entries.isEmpty || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WordDetailScreen(entryRow: entries.first),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final int state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      0 || 1 => ('Learning', Theme.of(context).colorScheme.primary),
      2 => ('Review', const Color(0xFF4CAF50)),
      3 => ('Relearning', Theme.of(context).colorScheme.error),
      _ => ('Unknown', Theme.of(context).colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

String _formatDate(String? isoDate) {
  if (isoDate == null) return '--';
  final date = DateTime.parse(isoDate).toLocal();
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0 && date.day == now.day) return 'Today';
  if (diff.inDays <= 1 && now.day - date.day == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${date.month}/${date.day}/${date.year}';
}
