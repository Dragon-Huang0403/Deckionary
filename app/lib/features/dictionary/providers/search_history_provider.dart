import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

/// How many history items to load. Increase on scroll to load more.
final historyLimitProvider = NotifierProvider<_HistoryLimitNotifier, int>(_HistoryLimitNotifier.new);

class _HistoryLimitNotifier extends Notifier<int> {
  @override
  int build() => 30;
  void loadMore() => state += 30;
}

/// Stream of deduplicated recent searches, auto-updates when DB changes.
final searchHistoryProvider = StreamProvider<List<SearchHistoryData>>((ref) {
  final dao = ref.read(searchHistoryDaoProvider);
  final limit = ref.watch(historyLimitProvider);
  return dao.watchRecentUnique(limit: limit);
});
