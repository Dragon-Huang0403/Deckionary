import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import '../../../core/audio/audio_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../dictionary/providers/search_provider.dart';
import '../../dictionary/presentation/widgets/entry_card.dart';
import '../domain/review_session.dart';
import '../providers/review_providers.dart';
import 'widgets/rating_bar.dart';

class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() =>
      _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  bool _showBack = false;
  DictEntry? _currentEntry;
  bool _loadingEntry = false;
  Map<fsrs.Rating, String> _intervals = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentCard();
  }

  Future<void> _loadCurrentCard() async {
    final session = ref.read(reviewSessionProvider).value;
    if (session == null || session.isComplete) return;

    final card = session.currentCard;
    if (card == null) return;

    setState(() {
      _showBack = false;
      _loadingEntry = true;
      _currentEntry = null;
      _intervals = session.previewCurrentIntervals();
    });

    // Load the full entry from dictionary DB by entry ID (reliable)
    final dictDb = ref.read(dictionaryDbProvider);
    final entries = await dictDb.getEntriesByIds([card.entryId]);
    if (entries.isNotEmpty) {
      final fullEntry = await loadFullEntry(dictDb, entries.first);
      if (mounted) {
        setState(() {
          _currentEntry = fullEntry;
          _loadingEntry = false;
        });
        _autoPronounce(fullEntry);
      }
    } else {
      if (mounted) setState(() => _loadingEntry = false);
    }
  }

  Future<void> _autoPronounce(DictEntry entry) async {
    final settings = ref.read(settingsDaoProvider);
    final mode = await settings.getReviewAutoPlayMode();
    if (mode == 'off') return;
    if (entry.pronunciations.isEmpty) return;
    final display = await settings.getPronunciationDisplay();
    final dialect = display == 'both' ? await settings.getDialect() : display;
    final audio = ref.read(audioServiceProvider);

    final sentenceAudio =
        (mode == 'sentence' || mode == 'sentence_pronunciation')
        ? _findFirstExampleAudio(entry, dialect)
        : null;

    if (mode == 'sentence') {
      if (sentenceAudio != null) await audio.play(sentenceAudio);
      return;
    }

    // 'pronunciation' or 'sentence_pronunciation'
    await audio.playPronunciation(entry.pronunciations, dialect: dialect);
    if (sentenceAudio != null) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await audio.play(sentenceAudio);
    }
  }

  /// Find the first example sentence audio filename for the given dialect.
  String? _findFirstExampleAudio(DictEntry entry, String dialect) {
    final audioKey = dialect == 'gb' ? 'audio_gb' : 'audio_us';
    for (final group in entry.groups) {
      for (final sense in group.senses) {
        for (final example in sense.examples) {
          final file = example[audioKey] as String?;
          if (file != null && file.isNotEmpty) return file;
        }
      }
    }
    return null;
  }

  Future<void> _rate(fsrs.Rating rating) async {
    final session = ref.read(reviewSessionProvider).value;
    if (session == null) return;

    await session.rateCurrentCard(rating);

    if (session.isComplete) {
      if (mounted) _showSummary(session);
    } else {
      _loadCurrentCard();
    }
  }

  void _showSummary(ReviewSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow('Cards reviewed', '${session.stats.reviewed}'),
            _StatRow('New words learned', '${session.stats.newLearned}'),
            _StatRow('Again count', '${session.stats.againCount}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              ref.read(reviewSessionProvider.notifier).endSession();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(reviewSessionProvider).value;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final card = session.currentCard;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${session.currentIndex + 1} / ${session.total}',
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(reviewSessionProvider.notifier).endSession();
            Navigator.pop(context);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: session.total > 0 ? session.currentIndex / session.total : 0,
          ),
        ),
      ),
      body: card == null || _loadingEntry
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () {
                if (!_showBack) setState(() => _showBack = true);
              },
              child: Column(
                children: [
                  Expanded(
                    child: _showBack ? _buildBack() : _buildFront(card, cs),
                  ),
                  if (_showBack)
                    RatingBar(intervals: _intervals, onRate: _rate)
                  else
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Tap to show answer',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFront(QueueCard card, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card.isNew)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            Text(
              card.headword,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            if (card.pos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  card.pos,
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                ),
              ),
            if (_currentEntry != null &&
                _currentEntry!.pronunciations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildPhonetics(_currentEntry!.pronunciations),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    if (_currentEntry == null) {
      return const Center(child: Text('Entry not found'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: EntryCard(
        entry: _currentEntry!,
        onWordTap: (_) {}, // no navigation during review
      ),
    );
  }

  static Color _usColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF64B5F6)
      : const Color(0xFF1565C0);

  static Color _gbColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF8A65)
      : const Color(0xFFD84315);

  Widget _buildPhonetics(List<Map<String, dynamic>> pronunciations) {
    final display = ref.watch(pronunciationDisplayProvider).value ?? 'both';
    final us = pronunciations.where((p) => p['dialect'] == 'us').firstOrNull;
    final gb = pronunciations.where((p) => p['dialect'] == 'gb').firstOrNull;
    final showUs = display != 'gb';
    final showGb = display != 'us';
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (us != null && showUs)
          _phonGroup(
            'US',
            us['ipa'] as String? ?? '',
            us['audio_file'] as String? ?? '',
            _usColor(context),
          ),
        if (gb != null && showGb)
          _phonGroup(
            'GB',
            gb['ipa'] as String? ?? '',
            gb['audio_file'] as String? ?? '',
            _gbColor(context),
          ),
      ],
    );
  }

  Widget _phonGroup(String label, String ipa, String audioFile, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ipa,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        if (audioFile.isNotEmpty) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 15.4,
              style: IconButton.styleFrom(backgroundColor: color),
              color: Colors.white,
              icon: const Icon(Icons.volume_up),
              onPressed: () => ref.read(audioServiceProvider).play(audioFile),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
