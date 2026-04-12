import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';

class SearchHistoryList extends StatefulWidget {
  final List<SearchHistoryData> history;
  final int highlightedIndex;
  final ScrollController scrollController;
  final void Function(String word, {String? pos, int? entryId}) onTap;
  final VoidCallback onClearAll;
  final void Function(SearchHistoryData item) onDelete;

  const SearchHistoryList({
    super.key,
    required this.history,
    required this.highlightedIndex,
    required this.scrollController,
    required this.onTap,
    required this.onClearAll,
    required this.onDelete,
  });

  @override
  State<SearchHistoryList> createState() => _SearchHistoryListState();
}

class _SearchHistoryListState extends State<SearchHistoryList> {
  static const _estimatedItemHeight = 48.0;
  static const _headerHeight = 48.0;

  @override
  void didUpdateWidget(SearchHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedIndex != oldWidget.highlightedIndex) {
      _scrollToHighlighted();
    }
  }

  void _scrollToHighlighted() {
    if (!widget.scrollController.hasClients) return;
    final targetTop =
        _headerHeight + widget.highlightedIndex * _estimatedItemHeight;
    final targetBottom = targetTop + _estimatedItemHeight;
    final viewport = widget.scrollController.position;
    if (targetTop < viewport.pixels) {
      widget.scrollController.animateTo(
        targetTop,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > viewport.pixels + viewport.viewportDimension) {
      widget.scrollController.animateTo(
        targetBottom - viewport.viewportDimension,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: widget.history.length + 1,
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
                    if (confirmed == true) widget.onClearAll();
                  },
                  child: const Text('Clear all'),
                ),
              ],
            ),
          );
        }
        final itemIndex = index - 1;
        final item = widget.history[itemIndex];
        final word = item.headword ?? item.query;
        final pos = item.pos;
        final isHighlighted = itemIndex == widget.highlightedIndex;
        return ListTile(
          leading: Icon(Icons.history, color: cs.onSurfaceVariant, size: 20),
          title: Row(
            children: [
              Text(
                word,
                style: isHighlighted
                    ? TextStyle(color: cs.onPrimaryContainer)
                    : null,
              ),
              if (pos.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  pos,
                  style: TextStyle(
                    fontSize: 12,
                    color: isHighlighted ? cs.onPrimaryContainer : cs.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          tileColor: isHighlighted ? cs.primaryContainer : null,
          shape: isHighlighted
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _relativeTime(item.searchedAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                onPressed: () => widget.onDelete(item),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Remove',
              ),
            ],
          ),
          onTap: () => widget.onTap(
                word,
                pos: pos.isNotEmpty ? pos : null,
                entryId: item.entryId,
              ),
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
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
