import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'core/database/database_provider.dart';
import 'core/sync/sync_provider.dart';
import 'features/dictionary/presentation/dictionary_screen.dart';
import 'features/review/presentation/review_home_screen.dart';

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
final searchBarFocusTrigger =
    NotifierProvider<_FocusTriggerNotifier, int>(_FocusTriggerNotifier.new);

class _FocusTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

/// Reads the hotkey setting from DB. Invalidate to reload after change.
final quickSearchHotKeyProvider = FutureProvider<String>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  return dao.getQuickSearchHotKey();
});

/// Reads the tray icon setting from DB. Invalidate to reload after change.
final showTrayIconProvider = FutureProvider<bool>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  return dao.getShowTrayIcon();
});

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
  return jsonEncode({
    'keyCode': hotKey.physicalKey.usbHidUsage,
    'modifiers': hotKey.modifiers?.map((m) => m.name).toList() ?? [],
  });
}

String hotKeyDisplayString(HotKey hotKey) {
  final buffer = StringBuffer();
  for (final mod in hotKey.modifiers ?? <HotKeyModifier>[]) {
    switch (mod) {
      case HotKeyModifier.meta:
        buffer.write('\u2318');
      case HotKeyModifier.shift:
        buffer.write('\u21E7');
      case HotKeyModifier.alt:
        buffer.write('\u2325');
      case HotKeyModifier.control:
        buffer.write('\u2303');
      default:
        buffer.write(mod.name);
    }
  }
  final keyName = hotKey.physicalKey.debugName ?? 'Unknown';
  final label = keyName.replaceFirst('Key ', '');
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
  int _currentTab = 0;
  HotKey? _registeredHotKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initMacOS();
    }
  }

  Future<void> _initMacOS() async {
    final dao = ref.read(settingsDaoProvider);
    final hotKeyJson = await dao.getQuickSearchHotKey();
    await _registerHotKey(hotKeyJson);

    final showTray = await dao.getShowTrayIcon();
    if (showTray) await _setupTrayIcon();
  }

  Future<void> _registerHotKey(String hotKeyJson) async {
    if (_registeredHotKey != null) {
      await hotKeyManager.unregister(_registeredHotKey!);
      _registeredHotKey = null;
    }
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
    final bytes = await rootBundle.load('assets/tray_icon.png');
    final tempDir = await getTemporaryDirectory();
    final iconFile = File('${tempDir.path}/tray_icon.png');
    await iconFile.writeAsBytes(bytes.buffer.asUint8List());

    await trayManager.setIcon(iconFile.path);
    await trayManager.setToolTip('Deckionary');

    final menu = Menu(items: [
      MenuItem(label: 'Show/Hide Deckionary'),
      MenuItem.separator(),
      MenuItem(label: 'Quit'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  Future<void> _removeTrayIcon() async {
    await trayManager.destroy();
  }

  Future<void> _toggleWindow() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
      setState(() => _currentTab = 0);
      ref.read(searchBarFocusTrigger.notifier).increment();
    }
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    _toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.label) {
      case 'Show/Hide Deckionary':
        _toggleWindow();
      case 'Quit':
        windowManager.setPreventClose(false);
        windowManager.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final sync = ref.read(syncServiceProvider);
      sync?.pullSearchHistory();
      sync?.syncReviewData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isMacOS) {
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
      ref.listen(quickSearchHotKeyProvider, (prev, next) {
        next.whenData((json) => _registerHotKey(json));
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
    }

    final themeMode = ref.watch(themeModeProvider).when(
      data: (mode) => mode,
      loading: () => ThemeMode.system,
      error: (_, _) => ThemeMode.system,
    );

    return MaterialApp(
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
        body: IndexedStack(
          index: _currentTab,
          children: const [
            DictionaryScreen(),
            ReviewHomeScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
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
