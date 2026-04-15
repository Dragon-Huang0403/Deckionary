import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_screen.dart';
import '../providers/my_words_providers.dart';
import '../providers/review_providers.dart';
import 'learned_words_screen.dart';
import 'my_words_screen.dart';
import 'review_session_screen.dart';
import 'study_words_screen.dart';
import 'widgets/filter_selector.dart';

class ReviewHomeScreen extends ConsumerWidget {
  const ReviewHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(reviewSummaryProvider);
    final filterAsync = ref.watch(reviewFilterProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: summaryAsync.when(
          data: (summary) {
            final hasCards = summary.dueCount > 0 || summary.newAvailable > 0;
            return Column(
              children: [
                Expanded(
                  child: _buildContent(context, ref, summary, filterAsync, cs),
                ),
                if (hasCards)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            'Start Review (${summary.dueCount + summary.newAvailable})',
                          ),
                          onPressed: () => _startSession(context, ref),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ReviewSummary summary,
    AsyncValue filterAsync,
    ColorScheme cs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Title row with settings icon
        Row(
          children: [
            Expanded(
              child: Text(
                'Review',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Daily summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CountColumn(
                  'Due',
                  summary.dueCount,
                  color: summary.dueCount > 0 ? cs.error : cs.onSurfaceVariant,
                ),
                _CountColumn(
                  'New',
                  summary.newAvailable,
                  color: summary.newAvailable > 0
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                _CountColumn(
                  'Reviewed',
                  summary.reviewedToday,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Study words section
        Text(
          'Study Words',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),

        // Active filter chips
        filterAsync.when(
          data: (filter) {
            if (filter.isEmpty) {
              return Card(
                child: ListTile(
                  leading: Icon(Icons.add_circle_outline, color: cs.primary),
                  title: const Text('Select words to study'),
                  subtitle: const Text(
                    'Choose CEFR levels or Oxford word lists',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => FilterSelector.show(context),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  InkWell(
                    onTap: () => FilterSelector.show(context),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Active Filter',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.edit,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...filter.cefrLevels.map(
                                (l) => Chip(
                                  label: Text(l.toUpperCase()),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              if (filter.ox3000)
                                const Chip(
                                  label: Text('Oxford 3000'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (filter.ox5000)
                                const Chip(
                                  label: Text('Oxford 5000'),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.list_alt, color: cs.primary),
                    title: const Text('Browse Words'),
                    trailing: const Icon(Icons.chevron_right),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StudyWordsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),

        const SizedBox(height: 12),

        // My Words card
        Card(
          child: ListTile(
            leading: Icon(Icons.bookmark_outline, color: cs.primary),
            title: const Text('My Words'),
            subtitle: Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(myWordsCountProvider);
                return Text(
                  count == 0 ? 'Add custom words to study' : '$count words',
                );
              },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyWordsScreen()),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Stats
        if (summary.totalCards > 0) ...[
          Text(
            'Progress',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CountColumn(
                    'Total Cards',
                    summary.totalCards,
                    color: cs.onSurfaceVariant,
                    onTap: summary.totalCards > 0
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearnedWordsScreen(),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref) async {
    final session = await ref
        .read(reviewSessionProvider.notifier)
        .startSession();
    if (session.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cards to review right now')),
        );
      }
      return;
    }
    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReviewSessionScreen()),
      );
      // Refresh summary when returning
      ref.invalidate(reviewSummaryProvider);
    }
  }
}

class _CountColumn extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;
  const _CountColumn(this.label, this.count, {required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: content,
      ),
    );
  }
}
