import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';

class SearchHistoryList extends StatelessWidget {
  final List<SearchHistoryData> history;
  final ScrollController scrollController;
  final void Function(String word, {String? pos}) onTap;
  final VoidCallback onClearAll;
  final void Function(int id) onDelete;

  const SearchHistoryList({
    super.key,
    required this.history,
    required this.scrollController,
    required this.onTap,
    required this.onClearAll,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: scrollController,
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
                    if (confirmed == true) onClearAll();
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
          onDismissed: (_) => onDelete(item.id),
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
            onTap: () => onTap(word, pos: pos.isNotEmpty ? pos : null),
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
