import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_providers.dart';
import 'speaking_history_detail_screen.dart';

class SpeakingHistoryScreen extends ConsumerWidget {
  const SpeakingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(speakingHistoryProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'No practice sessions yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start your first one!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _HistoryListTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _HistoryListTile extends ConsumerWidget {
  final SpeakingHistoryItem item;

  const _HistoryListTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: cs.error,
        child: Icon(Icons.delete_outline, color: cs.onError),
      ),
      confirmDismiss: (_) async {
        final service = ref.read(speakingServiceProvider);
        // TODO(Task 7/15): pass session_id once history items expose it.
        await service?.deleteSession(item.id);
        ref.invalidate(speakingHistoryProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Session deleted')));
        }
        return true;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: Text(
            item.topic,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (item.isCustomTopic) ...[
                  _Badge(label: 'Custom', color: Colors.blue),
                  const SizedBox(width: 6),
                ],
                _Badge(
                  label:
                      '${item.correctionsCount} ${item.correctionsCount == 1 ? 'correction' : 'corrections'}',
                  color: item.correctionsCount >= 2 ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  _relativeTime(item.createdAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SpeakingHistoryDetailScreen(id: item.id, topic: item.topic),
            ),
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
