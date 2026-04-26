import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/audio/audio_provider.dart';
import 'core/database/database_provider.dart';
import 'core/sync/sync_provider.dart';
import 'core/update/update_provider.dart';
import 'core/update/update_service.dart';
import 'core/update/play_store_update_service.dart';
import 'features/dictionary/presentation/dictionary_screen.dart';
import 'features/review/presentation/review_home_screen.dart';
import 'features/review/providers/review_providers.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/speaking/presentation/speaking_home_screen.dart';
import 'main.dart';

export 'app_providers.dart';
export 'core/hotkey/hotkey_helpers.dart';

import 'app_providers.dart';
import 'core/hotkey/hotkey_helpers.dart';
import 'core/logging/logging_service.dart';
import 'core/window/window_positioner.dart';

class DeckionaryApp extends ConsumerStatefulWidget {
  const DeckionaryApp({super.key});

  @override
  ConsumerState<DeckionaryApp> createState() => _DeckionaryAppState();
}

class _DeckionaryAppState extends ConsumerState<DeckionaryApp>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  static const _windowChannel = MethodChannel('com.deckionary/window');

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  int _currentTab = 0;
  HotKey? _registeredHotKey;
  DateTime? _lastSyncAt;
  bool _syncInitialized = false;
  bool _settingsOpen = false;
  bool _showInDock = true;
  bool _windowTransitioning = false;
  String? _lastSeenClipText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      _initMacOS();
    }
    _checkForUpdate();
  }

  Future<void> _initMacOS() async {
    final dao = ref.read(settingsDaoProvider);
    final hotKeyJson = await dao.getQuickSearchHotKey();
    await _registerHotKey(hotKeyJson);

    final showTray = await dao.getShowTrayIcon();
    if (showTray) await _setupTrayIcon();

    _showInDock = await dao.getShowInDock();

    // Listen for native-to-Flutter calls
    _windowChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'dockClicked':
          await _showNormalMode();
        case 'onClickOutside':
          _onClickOutside();
      }
    });

    // Snapshot clipboard so pre-existing content is treated as stale
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      _lastSeenClipText = data?.text?.trim();
    } catch (_) {}

    // Show window in normal mode on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _windowChannel.invokeMethod('setNormalMode');
      await windowManager.show();
      await windowManager.focus();
    });
  }

  void _checkForUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        await _checkPlayStoreUpdate();
      } else {
        await _checkGitHubUpdate();
      }
    });
  }

  Future<void> _checkGitHubUpdate() async {
    final info = await ref.read(updateInfoProvider.future);
    if (info == null || !mounted) return;

    final dao = ref.read(settingsDaoProvider);
    final skipped = await dao.getSkippedVersion();
    if (skipped == info.latestVersion) return;

    if (mounted) _showUpdateDialog(info);
  }

  Future<void> _checkPlayStoreUpdate() async {
    final updateInfo = await checkPlayStoreUpdate();
    if (updateInfo == null || !mounted) return;

    final versionCode =
        updateInfo.availableVersionCode?.toString() ?? 'play_update';

    final dao = ref.read(settingsDaoProvider);
    final skipped = await dao.getSkippedVersion();
    if (skipped == versionCode) return;

    if (mounted) _showPlayStoreUpdateDialog(versionCode);
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${info.latestVersion} is available '
              '(you have ${info.currentVersion}).',
            ),
            if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'What\'s new:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes!,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(settingsDaoProvider)
                  .setSkippedVersion(info.latestVersion);
              Navigator.pop(ctx);
            },
            child: const Text('Skip this version'),
          ),
          FilledButton(
            onPressed: () {
              launchUrl(
                Uri.parse(info.releaseUrl),
                mode: LaunchMode.externalApplication,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showPlayStoreUpdateDialog(String versionCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: const Text(
          'A new version is available on Google Play. '
          'Would you like to update now?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(settingsDaoProvider).setSkippedVersion(versionCode);
              Navigator.pop(ctx);
            },
            child: const Text('Skip this version'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              startFlexibleUpdate();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.comma &&
        HardwareKeyboard.instance.isMetaPressed) {
      _openSettingsFromAnywhere();
      return true;
    }
    return false;
  }

  Future<void> _openSettingsFromAnywhere() async {
    if (ref.read(isOverlayModeProvider)) {
      await _showNormalMode();
    }
    _openSettings();
  }

  void _openSettings() {
    if (_settingsOpen) return;
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    _settingsOpen = true;
    nav
        .push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _settingsOpen = false);
  }

  Future<void> _registerHotKey(String hotKeyJson) async {
    await hotKeyManager.unregisterAll();
    _registeredHotKey = null;
    try {
      final hotKey = deserializeHotKey(hotKeyJson);
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _toggleWindow(),
      );
      _registeredHotKey = hotKey;
    } catch (e, st) {
      globalTalker.error('[App] Failed to register hotkey', e, st);
    }
  }

  Future<void> _setupTrayIcon() async {
    try {
      await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
      await trayManager.setToolTip('Deckionary');

      final menu = Menu(
        items: [
          MenuItem(label: 'Show/Hide Deckionary'),
          MenuItem.separator(),
          MenuItem(label: 'Quit'),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e, st) {
      globalTalker.error('[App] Failed to setup tray icon', e, st);
    }
  }

  Future<void> _removeTrayIcon() async {
    await trayManager.destroy();
  }

  Future<void> _toggleWindow() async {
    if (_windowTransitioning) return;
    _windowTransitioning = true;
    try {
      final isVisible = await windowManager.isVisible();
      final isOverlay = ref.read(isOverlayModeProvider);

      if (isVisible && isOverlay) {
        // Overlay visible -> hide it
        await _hideWindow();
      } else {
        // Normal visible or hidden -> show as overlay
        await _showOverlay();
      }
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> _showOverlay() async {
    // Pop any pushed routes so they don't cover the overlay.
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);

    // 1. Configure overlay + space-jump BEFORE showing (same as original)
    await _windowChannel.invokeMethod('setOverlayMode');
    await _windowChannel.invokeMethod('prepareForShow');
    await _positionOnTargetDisplay();

    // 2. Show transparent so Flutter renders the overlay UI
    await windowManager.setOpacity(0);
    await windowManager.show();

    ref.read(isOverlayModeProvider.notifier).set(true);
    setState(() => _currentTab = 0);

    // Wait for overlay UI to render (no nav bar, no settings)
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    await completer.future;

    // 3. Reveal with correct UI
    await windowManager.setOpacity(1);
    await windowManager.focus();
    _readClipboardAndFocusSearch();
  }

  void _readClipboardAndFocusSearch() async {
    String? clipText;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null &&
          text.isNotEmpty &&
          looksLikeSearchQuery(text) &&
          text != _lastSeenClipText) {
        clipText = text;
      }
    } catch (_) {}
    ref.read(clipboardSearchText.notifier).set(clipText);
    ref.read(searchBarFocusTrigger.notifier).increment();
  }

  Future<void> _hideWindow() async {
    // Snapshot clipboard so next overlay open only pastes new content
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      _lastSeenClipText = data?.text?.trim();
    } catch (_) {}
    ref.read(isOverlayModeProvider.notifier).set(false);
    await _windowChannel.invokeMethod('setNormalMode');
    await _windowChannel.invokeMethod('resetLevel', _showInDock);
    await windowManager.hide();
  }

  Future<void> _showNormalMode() async {
    if (ref.read(isOverlayModeProvider)) {
      ref.read(isOverlayModeProvider.notifier).set(false);
      await _windowChannel.invokeMethod('setNormalMode');
    }
    await windowManager.show();
    await windowManager.focus();
  }

  late final _displayAdapter = PlatformDisplayAdapter(_windowChannel);

  Future<void> _positionOnTargetDisplay() async {
    final setting = await ref.read(settingsDaoProvider).getShowOnScreen();
    await _displayAdapter.positionWindow(setting);
  }

  @override
  void onWindowClose() async {
    if (ref.read(isOverlayModeProvider)) {
      await _hideWindow();
    } else {
      await _windowChannel.invokeMethod('resetLevel', _showInDock);
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    _toggleTrayWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.label) {
      case 'Show/Hide Deckionary':
        _toggleTrayWindow();
      case 'Quit':
        windowManager.setPreventClose(false);
        windowManager.close();
    }
  }

  Future<void> _toggleTrayWindow() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      if (ref.read(isOverlayModeProvider)) {
        await _hideWindow();
      } else {
        await _windowChannel.invokeMethod('resetLevel', _showInDock);
        await windowManager.hide();
      }
    } else {
      await _showNormalMode();
    }
  }

  void _onClickOutside() {
    if (_windowTransitioning) return;
    if (!ref.read(isOverlayModeProvider)) return;
    if (ref.read(signInInProgressProvider)) return;
    _hideWindow();
  }

  @override
  void onWindowFocus() {
    _pullAndRefreshIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pullAndRefreshIfNeeded();
    }
  }

  /// Pull remote data and refresh UI providers. Debounced to avoid
  /// duplicate syncs when both onWindowFocus and resumed fire together.
  Future<void> _pullAndRefreshIfNeeded() async {
    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!).inSeconds < 30) {
      return;
    }
    _lastSyncAt = now;

    final sync = ref.read(syncServiceProvider);
    if (sync == null) return;

    // One-time: auto-clear watermarks after sync bug fix.
    if (!_syncInitialized) {
      await sync.init();
      _syncInitialized = true;
    }

    sync.syncSearchHistory();
    // syncReviewData updates review_cards / review_logs locally; drift's
    // table-watcher streams (wired into reviewSummaryProvider) re-emit
    // automatically, so no manual invalidate is needed here.
    sync.syncReviewData();
    sync.syncVocabularyData();
    sync.syncSpeakingData();
    // Settings sync stays pull-then-push: settings_sync uses dirty tracking
    // to avoid clobbering local edits, so pull-first is safe there.
    // Settings values (e.g. newCardsPerDay) aren't drift-watched, so we
    // still invalidate dependent providers when a pull actually changed
    // something.
    sync.pullSettings().then((pulled) {
      if (pulled > 0) {
        ref.invalidate(themeModeProvider);
        ref.invalidate(reviewFilterProvider);
        ref.invalidate(reviewSummaryProvider);
      }
      sync.pushDirtySettings();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      if (_registeredHotKey != null) {
        hotKeyManager.unregister(_registeredHotKey!);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      ref.listen(hotKeyChangeTrigger, (prev, next) async {
        final json = await ref.read(settingsDaoProvider).getQuickSearchHotKey();
        await _registerHotKey(json);
      });
      ref.listen(showTrayIconProvider, (prev, next) {
        next.whenData((show) {
          if (show) {
            _setupTrayIcon();
          } else {
            _removeTrayIcon();
          }
        });
      });
      ref.listen(showInDockProvider, (prev, next) {
        next.whenData((val) => _showInDock = val);
      });
    }

    // Open settings from overlay or normal mode (triggered by search bar icon).
    ref.listen(openSettingsTrigger, (_, _) => _openSettingsFromAnywhere());

    // Keep audio download provider alive across navigation.
    ref.listen(offlineAudioProvider, (_, _) {});

    final themeMode = ref
        .watch(themeModeProvider)
        .when(
          data: (mode) => mode,
          loading: () => ThemeMode.system,
          error: (_, _) => ThemeMode.system,
        );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Deckionary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0057A8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6AB0F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: Scaffold(
        body: ref.watch(isOverlayModeProvider)
            ? const DictionaryScreen()
            : IndexedStack(
                index: _currentTab,
                children: [
                  const DictionaryScreen(),
                  const ReviewHomeScreen(),
                  if (syncEnabled) const SpeakingHomeScreen(),
                ],
              ),
        bottomNavigationBar: ref.watch(isOverlayModeProvider)
            ? null
            : NavigationBar(
                selectedIndex: _currentTab,
                onDestinationSelected: (i) => setState(() => _currentTab = i),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.book_outlined),
                    selectedIcon: Icon(Icons.book),
                    label: 'Dictionary',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.school_outlined),
                    selectedIcon: Icon(Icons.school),
                    label: 'Review',
                  ),
                  if (syncEnabled)
                    const NavigationDestination(
                      icon: Icon(Icons.mic_outlined),
                      selectedIcon: Icon(Icons.mic),
                      label: 'Speaking',
                    ),
                ],
              ),
      ),
    );
  }
}
