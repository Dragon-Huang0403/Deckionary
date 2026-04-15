import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/settings_dao.dart';

final settingsStateProvider = FutureProvider<AppSettings>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final all = await dao.getAll();

  // Handle reviewAutoPlayMode migration (from old bool key)
  String reviewAutoPlayMode;
  final mode = all['review_auto_play_mode'];
  if (mode != null) {
    reviewAutoPlayMode = mode;
  } else if (all['review_auto_pronounce'] == 'false') {
    await dao.setReviewAutoPlayMode('off');
    reviewAutoPlayMode = 'off';
  } else {
    reviewAutoPlayMode = 'pronunciation';
  }

  return AppSettings(
    dialect: all['audio_dialect'] ?? 'us',
    pronunciationDisplay: all['pronunciation_display'] ?? 'both',
    autoPronounce: all['auto_pronounce'] != 'false',
    themeMode: all['theme_mode'] ?? 'system',
    newCardsPerDay: int.tryParse(all['new_cards_per_day'] ?? '') ?? 20,
    maxReviewsPerDay: int.tryParse(all['max_reviews_per_day'] ?? '') ?? 200,
    reviewAutoPlayMode: reviewAutoPlayMode,
    reviewCardOrder: all['review_card_order'] ?? 'random',
    quickSearchHotKey: Platform.isMacOS
        ? all['quick_search_hotkey'] ?? SettingsDao.defaultHotKey
        : '',
    showTrayIcon: Platform.isMacOS ? all['show_tray_icon'] != 'false' : false,
    showInDock: Platform.isMacOS ? all['show_in_dock'] != 'false' : true,
    showOnScreen: Platform.isMacOS ? all['show_on_screen'] ?? 'mouse' : 'mouse',
    launchOnStartup: Platform.isMacOS
        ? all['launch_on_startup'] == 'true'
        : false,
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
  final String showOnScreen;
  final bool launchOnStartup;
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
    required this.showOnScreen,
    required this.launchOnStartup,
  });
}
