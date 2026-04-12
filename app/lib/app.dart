import 'dart:convert';
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

/// Whether the app is currently in overlay (Raycast-style) mode.
final isOverlayModeProvider = NotifierProvider<_OverlayModeNotifier, bool>(
  _OverlayModeNotifier.new,
);

class _OverlayModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// Check if clipboard text looks like a word/phrase worth searching.
bool _looksLikeSearchQuery(String text) {
  if (text.length > 50 || text.contains('\n')) return false;
  // Must start with a letter, allow letters/digits/spaces/hyphens/apostrophes
  return RegExp(r"^[a-zA-Z][a-zA-Z0-9 '\-]*$").hasMatch(text);
}

// ── HotKey serialization helpers ────────────────────────────────────────

HotKey deserializeHotKey(String jsonStr) {
  final map = jsonDecode(jsonStr) as Map<String, dynamic>;
  final keyCode = map['keyCode'] as int;
  final modifiers = (map['modifiers'] as List)
      .map((name) => HotKeyModifier.values.firstWhere((m) => m.name == name))
      .toList();
  return HotKey(
    key: PhysicalKeyboardKey(keyCode),
    modifiers: modifiers,
    scope: HotKeyScope.system,
  );
}

String serializeHotKey(HotKey hotKey) {
  // Capture debugName now — it's only available on predefined key constants,
  // not on keys reconstructed from usbHidUsage alone.
  final rawName = hotKey.physicalKey.debugName ?? '';
  final label = rawName.replaceFirst('Key ', '').replaceFirst('Digit ', '');
  return jsonEncode({
    'keyCode': hotKey.physicalKey.usbHidUsage,
    'modifiers': hotKey.modifiers?.map((m) => m.name).toList() ?? [],
    'label': label.isEmpty ? '?' : label,
  });
}

/// Derive a key label from USB HID usage code (fallback for old JSON without 'label').
String _labelFromUsbHid(int keyCode) {
  // Letters A-Z: USB HID 0x00070004 (458756) through 0x0007001D (458781)
  if (keyCode >= 458756 && keyCode <= 458781) {
    return String.fromCharCode('A'.codeUnitAt(0) + keyCode - 458756);
  }
  // Digits 1-9: USB HID 0x0007001E (458782) through 0x00070026 (458790)
  if (keyCode >= 458782 && keyCode <= 458790) {
    return String.fromCharCode('1'.codeUnitAt(0) + keyCode - 458782);
  }
  // Digit 0: USB HID 0x00070027 (458791)
  if (keyCode == 458791) return '0';
  return '?';
}

/// Display a hotkey from its JSON representation (e.g. "⌘⇧D").
String hotKeyDisplayString(String hotKeyJson) {
  final map = jsonDecode(hotKeyJson) as Map<String, dynamic>;
  final modifiers = (map['modifiers'] as List).cast<String>();
  // Use stored label, or derive from keyCode for old format without label
  var label = map['label'] as String?;
  if (label == null || label == '?') {
    final keyCode = map['keyCode'] as int?;
    label = keyCode != null ? _labelFromUsbHid(keyCode) : '?';
  }

  final buffer = StringBuffer();
  for (final mod in modifiers) {
    switch (mod) {
      case 'meta':
        buffer.write('\u2318');
      case 'shift':
        buffer.write('\u21E7');
      case 'alt':
        buffer.write('\u2325');
      case 'control':
        buffer.write('\u2303');
      default:
        buffer.write(mod);
    }
  }
  buffer.write(label);
  return buffer.toString();
}

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
        HardwareKeyboard.instance.isMetaPressed) {
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
    // Unregister ALL hotkeys — unregister(singleKey) doesn't reliably
    // remove the native listener on macOS.
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
        // Overlay visible → hide it
        await _hideWindow();
      } else if (isVisible) {
        // Normal mode visible → focus search bar + clipboard auto-fill
        setState(() => _currentTab = 0);
        _readClipboardAndFocusSearch();
      } else {
        // Hidden → show as overlay
        ref.read(isOverlayModeProvider.notifier).set(true);
        await _windowChannel.invokeMethod('setOverlayMode');
        await _windowChannel.invokeMethod('prepareForShow');
        await _positionOnMouseDisplay();
        await windowManager.show();
        await windowManager.focus();
        setState(() => _currentTab = 0);
        _readClipboardAndFocusSearch();
      }
    } finally {
      _windowTransitioning = false;
    }
  }

  void _readClipboardAndFocusSearch() async {
    String? clipText;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty && _looksLikeSearchQuery(text)) {
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
