import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/database/database_provider.dart';
import 'core/sync/sync_provider.dart';
import 'core/update/update_provider.dart';
import 'core/update/update_service.dart';
import 'features/dictionary/presentation/dictionary_screen.dart';
import 'features/review/presentation/review_home_screen.dart';
import 'features/review/providers/review_providers.dart';
import 'features/settings/presentation/settings_screen.dart';

export 'app_providers.dart';
export 'core/hotkey/hotkey_helpers.dart';

import 'app_providers.dart';
import 'core/hotkey/hotkey_helpers.dart';

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
  bool _settingsOpen = false;
  bool _showInDock = true;
  bool _windowTransitioning = false;

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

    // Listen for native-to-Flutter calls (dock icon click)
    _windowChannel.setMethodCallHandler((call) async {
      if (call.method == 'dockClicked') {
        await _showNormalMode();
      }
    });

    // Show window in normal mode on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _windowChannel.invokeMethod('setNormalMode');
      await windowManager.show();
      await windowManager.focus();
    });
  }

  void _checkForUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await ref.read(updateInfoProvider.future);
      if (info == null || !mounted) return;

      final dao = ref.read(settingsDaoProvider);
      final skipped = await dao.getSkippedVersion();
      if (skipped == info.latestVersion) return;

      if (mounted) _showUpdateDialog(info);
    });
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

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.comma &&
        HardwareKeyboard.instance.isMetaPressed &&
        !ref.read(isOverlayModeProvider)) {
      _openSettings();
      return true;
    }
    return false;
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
    } catch (e) {
      debugPrint('Failed to register hotkey: $e');
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
    } catch (e) {
      debugPrint('Failed to setup tray icon: $e');
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
    // 1. Configure overlay + space-jump BEFORE showing (same as original)
    await _windowChannel.invokeMethod('setOverlayMode');
    await _windowChannel.invokeMethod('prepareForShow');
    await _positionOnMouseDisplay();

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
      if (text != null && text.isNotEmpty && looksLikeSearchQuery(text)) {
        clipText = text;
      }
    } catch (_) {}
    ref.read(clipboardSearchText.notifier).set(clipText);
    ref.read(searchBarFocusTrigger.notifier).increment();
  }

  Future<void> _hideWindow() async {
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

  Future<void> _positionOnMouseDisplay() async {
    try {
      final cursorPos = await screenRetriever.getCursorScreenPoint();
      final displays = await screenRetriever.getAllDisplays();

      Display? targetDisplay;
      for (final display in displays) {
        final pos = display.visiblePosition ?? Offset.zero;
        final sz = display.visibleSize ?? display.size;
        final bounds = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
        if (bounds.contains(Offset(cursorPos.dx, cursorPos.dy))) {
          targetDisplay = display;
          break;
        }
      }

      if (targetDisplay != null) {
        final dpos = targetDisplay.visiblePosition ?? Offset.zero;
        final dsz = targetDisplay.visibleSize ?? targetDisplay.size;
        final winW = 800.0;
        final winH = (dsz.height * 0.7).clamp(400.0, 900.0);
        final x = dpos.dx + (dsz.width - winW) / 2;
        final y = dpos.dy + (dsz.height - winH) * 0.35;
        await windowManager.setSize(Size(winW, winH));
        await windowManager.setPosition(Offset(x, y));
      }
    } catch (e) {
      debugPrint('Could not position window: $e');
    }
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

  @override
  void onWindowBlur() {
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
  void _pullAndRefreshIfNeeded() {
    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!).inSeconds < 30) {
      return;
    }
    _lastSyncAt = now;

    final sync = ref.read(syncServiceProvider);
    if (sync == null) return;

    sync.pullSearchHistory();
    sync.syncReviewData().then((_) {
      ref.invalidate(reviewSummaryProvider);
    });
    // Push any settings that failed to sync while offline, then pull
    sync.pushDirtySettings().then((_) {
      sync.pullSettings().then((pulled) {
        if (pulled > 0) {
          ref.invalidate(themeModeProvider);
          ref.invalidate(reviewFilterProvider);
          ref.invalidate(reviewSummaryProvider);
        }
      });
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
                children: const [DictionaryScreen(), ReviewHomeScreen()],
              ),
        bottomNavigationBar: ref.watch(isOverlayModeProvider)
            ? null
            : NavigationBar(
                selectedIndex: _currentTab,
                onDestinationSelected: (i) => setState(() => _currentTab = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.book_outlined),
                    selectedIcon: Icon(Icons.book),
                    label: 'Dictionary',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.school_outlined),
                    selectedIcon: Icon(Icons.school),
                    label: 'Review',
                  ),
                ],
              ),
      ),
    );
  }
}
