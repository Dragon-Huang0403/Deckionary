import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/curated_topics.dart';
import '../providers/speaking_providers.dart';
import 'speaking_history_detail_screen.dart';
import 'speaking_history_screen.dart';
import 'speaking_record_screen.dart';

class SpeakingHomeScreen extends ConsumerStatefulWidget {
  const SpeakingHomeScreen({super.key});

  @override
  ConsumerState<SpeakingHomeScreen> createState() => _SpeakingHomeScreenState();
}

class _SpeakingHomeScreenState extends ConsumerState<SpeakingHomeScreen> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _goToRecordScreen(String topic, {required bool isCustom}) {
    if (topic.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SpeakingRecordScreen(topic: topic.trim(), isCustomTopic: isCustom),
      ),
    );
  }

  void _submitCustomTopic() {
    _goToRecordScreen(_customController.text, isCustom: true);
    _customController.clear();
  }

  void _showRandomTopicSheet() {
    var topic = curatedTopics[Random().nextInt(curatedTopics.length)];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            final textTheme = Theme.of(ctx).textTheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Category
                    Text(
                      topic.category.displayName,
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Topic
                    Text(
                      topic.title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle, size: 18),
                            label: const Text('Shuffle'),
                            onPressed: () {
                              setSheetState(() {
                                topic =
                                    curatedTopics[Random().nextInt(
                                      curatedTopics.length,
                                    )];
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _goToRecordScreen(topic.title, isCustom: false);
                            },
                            child: const Text('Start Practice'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topicsByCategory = ref.watch(curatedTopicsProvider);
    final historyAsync = ref.watch(speakingHistoryProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Headline ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Speaking Practice',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: 'History',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SpeakingHistoryScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Custom Topic Input ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _customController,
                  decoration: InputDecoration(
                    hintText: 'Enter your own topic...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'Go',
                      onPressed: _submitCustomTopic,
                    ),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submitCustomTopic(),
                ),
              ),
            ),

            // ── Random Topic Card ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _showRandomTopicSheet,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.casino_outlined,
                            size: 28,
                            color: cs.onPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Random Topic',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Start with a surprise topic',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onPrimary.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: cs.onPrimary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Recent Practice ───────────────────────────────────
            ...historyAsync.when(
              loading: () => [
                const SliverToBoxAdapter(child: SizedBox.shrink()),
              ],
              error: (e, st) => [
                const SliverToBoxAdapter(child: SizedBox.shrink()),
              ],
              data: (items) {
                if (items.isEmpty) {
                  return [const SliverToBoxAdapter(child: SizedBox.shrink())];
                }
                final recentItems = items.take(5).toList();
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Text(
                            'Recent Practice',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SpeakingHistoryScreen(),
                              ),
                            ),
                            child: const Text('See all'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: recentItems.length,
                        separatorBuilder: (_, i) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = recentItems[index];
                          return _RecentPracticeCard(
                            item: item,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SpeakingHistoryDetailScreen(
                                  id: item.id,
                                  topic: item.topic,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ];
              },
            ),

            // ── Browse Topics Header ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Browse Topics',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            ),

            // ── Browse Topics List ────────────────────────────────
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final category = topicsByCategory.keys.elementAt(index);
                final topics = topicsByCategory[category]!;
                return ExpansionTile(
                  title: Text(category.displayName),
                  subtitle: Text(
                    '${topics.length} topics',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    for (final topic in topics)
                      ListTile(
                        title: Text(topic.title, style: textTheme.bodyMedium),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: cs.onSurfaceVariant,
                        ),
                        onTap: () =>
                            _goToRecordScreen(topic.title, isCustom: false),
                      ),
                  ],
                );
              }, childCount: topicsByCategory.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPracticeCard extends StatelessWidget {
  final SpeakingHistoryItem item;
  final VoidCallback onTap;

  const _RecentPracticeCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = item.correctionsCount >= 2 ? Colors.red : Colors.green;

    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item.correctionsCount} ${item.correctionsCount == 1 ? 'fix' : 'fixes'}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _relativeTime(item.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}
