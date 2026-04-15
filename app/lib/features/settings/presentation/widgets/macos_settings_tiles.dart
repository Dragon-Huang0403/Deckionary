import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../../../../app.dart'
    show
        serializeHotKey,
        hotKeyDisplayString,
        hotKeyChangeTrigger,
        showTrayIconProvider,
        showInDockProvider;
import '../../../../core/database/database_provider.dart';
import '../../providers/settings_state.dart';

class HotKeyTile extends StatefulWidget {
  final String hotKeyJson;
  final WidgetRef ref;
  const HotKeyTile(this.hotKeyJson, this.ref, {super.key});

  @override
  State<HotKeyTile> createState() => _HotKeyTileState();
}

class _HotKeyTileState extends State<HotKeyTile> {
  bool _recording = false;

  /// Modifier-only USB HID codes -- ignore these until a real key is pressed.
  static const _modifierUsbHids = {
    0x000700E0, 0x000700E1, 0x000700E2, 0x000700E3, // L: Ctrl, Shift, Alt, Meta
    0x000700E4, 0x000700E5, 0x000700E6, 0x000700E7, // R: Ctrl, Shift, Alt, Meta
  };

  @override
  Widget build(BuildContext context) {
    final display = hotKeyDisplayString(widget.hotKeyJson);

    return ListTile(
      title: const Text('Global shortcut'),
      subtitle: Text(_recording ? 'Press modifier + key...' : display),
      trailing: _recording
          ? SizedBox(
              width: 200,
              child: HotKeyRecorder(
                onHotKeyRecorded: (newHotKey) async {
                  // Ignore modifier-only presses (user still building the combo)
                  if (_modifierUsbHids.contains(
                    newHotKey.physicalKey.usbHidUsage,
                  )) {
                    return;
                  }

                  final json = serializeHotKey(newHotKey);
                  await widget.ref
                      .read(settingsDaoProvider)
                      .setQuickSearchHotKey(json);
                  widget.ref.invalidate(settingsStateProvider);
                  // Directly trigger hotkey re-registration in app state
                  widget.ref.read(hotKeyChangeTrigger.notifier).fire();
                  if (mounted) setState(() => _recording = false);
                },
              ),
            )
          : TextButton(
              onPressed: () => setState(() => _recording = true),
              child: const Text('Change'),
            ),
    );
  }
}

class ShowOnScreenTile extends StatelessWidget {
  final String value;
  final WidgetRef ref;
  const ShowOnScreenTile(this.value, this.ref, {super.key});

  static const _options = {
    'mouse': 'Screen containing mouse',
    'activeWindow': 'Screen with active window',
    'primaryScreen': 'Primary screen',
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Show window on'),
      trailing: DropdownButton<String>(
        value: _options.containsKey(value) ? value : 'mouse',
        underline: const SizedBox.shrink(),
        onChanged: (val) async {
          if (val == null) return;
          await ref.read(settingsDaoProvider).setShowOnScreen(val);
          ref.invalidate(settingsStateProvider);
        },
        items: _options.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
      ),
    );
  }
}

class TrayIconTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const TrayIconTile(this.enabled, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Menu bar icon'),
      subtitle: const Text('Show icon in menu bar for quick access'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setShowTrayIcon(val);
        ref.invalidate(settingsStateProvider);
        ref.invalidate(showTrayIconProvider);
      },
    );
  }
}

class LaunchOnStartupTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const LaunchOnStartupTile(this.enabled, this.ref, {super.key});

  static const _channel = MethodChannel('com.deckionary/window');

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Launch on startup'),
      subtitle: const Text('Open Deckionary when you log in'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setLaunchOnStartup(val);
        ref.invalidate(settingsStateProvider);
        await _channel.invokeMethod('setLaunchOnStartup', val);
      },
    );
  }
}

class DockTile extends StatelessWidget {
  final bool enabled;
  final WidgetRef ref;
  const DockTile(this.enabled, this.ref, {super.key});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Show in Dock'),
      subtitle: const Text('Keep Dock icon visible when window is hidden'),
      value: enabled,
      onChanged: (val) async {
        await ref.read(settingsDaoProvider).setShowInDock(val);
        ref.invalidate(settingsStateProvider);
        ref.invalidate(showInDockProvider);
      },
    );
  }
}
