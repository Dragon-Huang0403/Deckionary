import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';

/// The single "My Words" list ID, lazily created on first access.
final myWordsListProvider = FutureProvider<VocabularyList>((ref) async {
  final dao = ref.read(vocabularyListDaoProvider);
  return dao.getOrCreateMyWordsList();
});

/// Reactive stream of all entries in the My Words list.
final myWordsEntriesProvider = StreamProvider<List<VocabularyListEntry>>((
  ref,
) async* {
  final list = await ref.watch(myWordsListProvider.future);
  final dao = ref.read(vocabularyListDaoProvider);
  yield* dao.watchEntries(list.id);
});

/// Check if a dictionary entry is in My Words. Family provider keyed by entryId.
final myWordsContainsProvider = FutureProvider.family<bool, int>((
  ref,
  entryId,
) async {
  // Watch entries so this invalidates when the list changes
  ref.watch(myWordsEntriesProvider);
  final list = await ref.read(myWordsListProvider.future);
  final dao = ref.read(vocabularyListDaoProvider);
  return dao.containsEntry(list.id, entryId);
});

/// Count of active entries in My Words.
final myWordsCountProvider = Provider<int>((ref) {
  final entries = ref.watch(myWordsEntriesProvider);
  return entries.value?.length ?? 0;
});

/// My Words ordering: 'fifo', 'lifo', or 'random'.
final myWordsOrderProvider =
    AsyncNotifierProvider<MyWordsOrderNotifier, String>(
      MyWordsOrderNotifier.new,
    );

class MyWordsOrderNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final dao = ref.read(settingsDaoProvider);
    return dao.getMyWordsOrder();
  }

  Future<void> setOrder(String order) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setMyWordsOrder(order);
    // Clear new cards queue so it rebuilds with new ordering
    await dao.clearNewCardsQueue();
    state = AsyncData(order);
  }
}
