import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

/// Stream of deduplicated recent searches, auto-updates when DB changes.
final searchHistoryProvider = StreamProvider<List<SearchHistoryData>>((ref) {
  final dao = ref.read(searchHistoryDaoProvider);
  return dao.watchRecentUnique(limit: 30);
});
