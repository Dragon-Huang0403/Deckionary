import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';

final settingsStateProvider = FutureProvider<AppSettings>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final dialect = await dao.getDialect();
  final pronunciationDisplay = await dao.getPronunciationDisplay();
  final autoPronounce = await dao.getAutoPronounce();
  final themeMode = await dao.getThemeMode();
  final newCardsPerDay = await dao.getNewCardsPerDay();
  final maxReviewsPerDay = await dao.getMaxReviewsPerDay();
  final reviewAutoPlayMode = await dao.getReviewAutoPlayMode();
  final reviewCardOrder = await dao.getReviewCardOrder();
  final quickSearchHotKey = Platform.isMacOS
      ? await dao.getQuickSearchHotKey()
      : '';
  final showTrayIcon = Platform.isMacOS ? await dao.getShowTrayIcon() : false;
  final showInDock = Platform.isMacOS ? await dao.getShowInDock() : true;
  return AppSettings(
    dialect: dialect,
    pronunciationDisplay: pronunciationDisplay,
    autoPronounce: autoPronounce,
    themeMode: themeMode,
    newCardsPerDay: newCardsPerDay,
    maxReviewsPerDay: maxReviewsPerDay,
    reviewAutoPlayMode: reviewAutoPlayMode,
    reviewCardOrder: reviewCardOrder,
    quickSearchHotKey: quickSearchHotKey,
    showTrayIcon: showTrayIcon,
    showInDock: showInDock,
  );
});

class AppSettings {
  final String dialect;
  final String pronunciationDisplay;
  final bool autoPronounce;
  final String themeMode;
  final int newCardsPerDay;
  final int maxReviewsPerDay;
  final String reviewAutoPlayMode;
  final String reviewCardOrder;
  final String quickSearchHotKey;
  final bool showTrayIcon;
  final bool showInDock;
  AppSettings({
    required this.dialect,
    required this.pronunciationDisplay,
    required this.autoPronounce,
    required this.themeMode,
    required this.newCardsPerDay,
    required this.maxReviewsPerDay,
    required this.reviewAutoPlayMode,
    required this.reviewCardOrder,
    required this.quickSearchHotKey,
    required this.showTrayIcon,
    required this.showInDock,
  });
}
