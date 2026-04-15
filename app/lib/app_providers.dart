import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_provider.dart';

/// Reactive theme mode provider
final themeModeProvider = FutureProvider<ThemeMode>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final mode = await dao.getThemeMode();
  return switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

/// Incremented to signal DictionaryScreen to focus its search bar.
final searchBarFocusTrigger = NotifierProvider<_FocusTriggerNotifier, int>(
  _FocusTriggerNotifier.new,
);

class _FocusTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

/// Incremented by settings screen to trigger hotkey re-registration.
final hotKeyChangeTrigger = NotifierProvider<_HotKeyChangeNotifier, int>(
  _HotKeyChangeNotifier.new,
);

class _HotKeyChangeNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

/// Reads the tray icon setting from DB. Invalidate to reload after change.
final showTrayIconProvider = FutureProvider<bool>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  return dao.getShowTrayIcon();
});

/// Reads the dock visibility setting. Invalidate to reload after change.
final showInDockProvider = FutureProvider<bool>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  return dao.getShowInDock();
});

/// Clipboard text to auto-fill in search bar on hotkey trigger.
final clipboardSearchText = NotifierProvider<_ClipboardNotifier, String?>(
  _ClipboardNotifier.new,
);

class _ClipboardNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? text) => state = text;
}

/// True while Google Sign-In is in progress; suppresses window auto-hide.
final signInInProgressProvider = NotifierProvider<_SignInFlagNotifier, bool>(
  _SignInFlagNotifier.new,
);

class _SignInFlagNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// Fired to request opening the settings screen (from overlay or normal mode).
final openSettingsTrigger = NotifierProvider<_OpenSettingsTrigger, int>(
  _OpenSettingsTrigger.new,
);

class _OpenSettingsTrigger extends Notifier<int> {
  @override
  int build() => 0;
  void fire() => state++;
}

/// Whether the app is currently in overlay (Raycast-style) mode.
final isOverlayModeProvider = NotifierProvider<_OverlayModeNotifier, bool>(
  _OverlayModeNotifier.new,
);

class _OverlayModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}
