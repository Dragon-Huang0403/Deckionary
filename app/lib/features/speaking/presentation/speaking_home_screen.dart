import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final topicsByCategory = ref.watch(curatedTopicsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Speaking Practice')),
      body: CustomScrollView(
        slivers: [
          // Custom topic input
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _customController,
                decoration: InputDecoration(
                  hintText: 'Enter your own topic...',
                  border: const OutlineInputBorder(),
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

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Curated Topics',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ),

          // Curated topics grouped by category
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final category = topicsByCategory.keys.elementAt(index);
              final topics = topicsByCategory[category]!;
              return ExpansionTile(
                title: Text(category.displayName),
                children: [
                  for (final topic in topics)
                    ListTile(
                      title: Text(
                        topic.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
    );
  }
}
