import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_session_notifier.dart';
import 'speaking_record_screen.dart';
import 'widgets/attempt_stack.dart';

class SpeakingResultScreen extends ConsumerWidget {
  const SpeakingResultScreen({super.key});

  Future<void> _endAndGoHome(BuildContext context, WidgetRef ref) async {
    await ref.read(speakingSessionNotifierProvider.notifier).endSession();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _tryAgain(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SpeakingRecordScreen(isRetry: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(speakingSessionNotifierProvider);

    if (session == null) {
      // Defensive: no active session means the user got here without starting
      // one. Pop back to home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _endAndGoHome(context, ref);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            session.topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AttemptStack(attempts: session.attempts),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _endAndGoHome(context, ref),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                        onPressed: () => _tryAgain(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
