import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_provider.dart';
import '../../../review/providers/review_providers.dart';
import '../../../../core/sync/sync_provider.dart';
import '../../providers/settings_state.dart';

class ReviewAutoPlayModeTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const ReviewAutoPlayModeTile(this.current, this.ref, {super.key});

  static const _labels = {
    'off': 'Off',
    'pronunciation': 'Pronunciation only',
    'sentence': 'Sentence only',
    'sentence_pronunciation': 'Pronunciation + Sentence',
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Auto-play in review'),
      subtitle: Text(_labels[current] ?? 'Pronunciation only'),
      trailing: PopupMenuButton<String>(
        initialValue: current,
        onSelected: (val) async {
          await ref.read(settingsDaoProvider).setReviewAutoPlayMode(val);
          ref.invalidate(settingsStateProvider);
        },
        itemBuilder: (_) => _labels.entries
            .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
      ),
    );
  }
}

class CardOrderTile extends StatelessWidget {
  final String current;
  final WidgetRef ref;
  const CardOrderTile(this.current, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('New card order'),
      subtitle: Text(current == 'random' ? 'Random' : 'Alphabetical'),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'alphabetical', label: Text('A-Z')),
          ButtonSegment(value: 'random', label: Text('Random')),
        ],
        selected: {current},
        onSelectionChanged: (val) async {
          await ref.read(settingsDaoProvider).setReviewCardOrder(val.first);
          ref.invalidate(settingsStateProvider);
          ref.invalidate(reviewSummaryProvider);
        },
      ),
    );
  }
}

class NewCardsPerDayTile extends StatelessWidget {
  final int current;
  final int maxReviews;
  final WidgetRef ref;
  const NewCardsPerDayTile(
    this.current,
    this.maxReviews,
    this.ref, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final suggestedMin = current * 7;
    final showWarning = maxReviews < suggestedMin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('New cards per day'),
          subtitle: Text('$current cards'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: current.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: '$current',
              onChanged: (val) async {
                await ref
                    .read(settingsDaoProvider)
                    .setNewCardsPerDay(val.round());
                ref.invalidate(settingsStateProvider);
                ref.invalidate(reviewSummaryProvider);
              },
            ),
          ),
        ),
        if (showWarning)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Tip: With $current new cards/day, consider setting max reviews to at least $suggestedMin to avoid a backlog.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orange.shade300
                    : Colors.orange.shade700,
              ),
            ),
          ),
      ],
    );
  }
}

class MaxReviewsPerDayTile extends StatelessWidget {
  final int current;
  final WidgetRef ref;
  const MaxReviewsPerDayTile(this.current, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Max reviews per day'),
      subtitle: Text('$current reviews'),
      trailing: SizedBox(
        width: 200,
        child: Slider(
          value: current.toDouble(),
          min: 50,
          max: 500,
          divisions: 18,
          label: '$current',
          onChanged: (val) async {
            await ref
                .read(settingsDaoProvider)
                .setMaxReviewsPerDay(val.round());
            ref.invalidate(settingsStateProvider);
            ref.invalidate(reviewSummaryProvider);
          },
        ),
      ),
    );
  }
}

class ClearProgressTile extends StatelessWidget {
  final WidgetRef ref;
  const ClearProgressTile(this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_outline, color: cs.error),
      title: Text('Clear review progress', style: TextStyle(color: cs.error)),
      subtitle: const Text('Delete all review cards and history'),
      onTap: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final dao = ref.read(reviewDaoProvider);
    final totalCards = await dao.countTotalCards();
    if (totalCards == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No review progress to clear')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all progress?'),
        content: Text(
          'This will delete $totalCards review cards and all review history. '
          'You will start from scratch. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await dao.clearAllProgress();
      // Also clear remote data so it doesn't sync back
      final sync = ref.read(syncServiceProvider);
      sync?.clearRemoteReviewData();
      ref.invalidate(reviewSummaryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review progress cleared')),
        );
      }
    }
  }
}
