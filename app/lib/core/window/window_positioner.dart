import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Where to show the hotkey overlay window.
enum ShowOnScreen {
  mouse,
  activeWindow,
  primaryScreen;

  static ShowOnScreen fromString(String value) => switch (value) {
    'activeWindow' => ShowOnScreen.activeWindow,
    'primaryScreen' => ShowOnScreen.primaryScreen,
    _ => ShowOnScreen.mouse,
  };
}

/// A display's visible area in screen coordinates (top-left origin).
class DisplayFrame {
  final double x, y, width, height;
  const DisplayFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Compute overlay window position + size for a given display frame.
///
/// Window is 800px wide, 70% of display height (clamped 400–900),
/// centered horizontally and placed at 35% from the top.
({Size size, Offset position}) computeWindowGeometry(DisplayFrame display) {
  const winW = 800.0;
  final winH = (display.height * 0.7).clamp(400.0, 900.0);
  final x = display.x + (display.width - winW) / 2;
  final y = display.y + (display.height - winH) * 0.35;
  return (size: Size(winW, winH), position: Offset(x, y));
}

/// Resolves which display to target based on the [ShowOnScreen] setting.
///
/// Dependencies are injected as callbacks so the logic is testable
/// without platform plugins.
class DisplayResolver {
  final Future<DisplayFrame?> Function() getMouseDisplay;
  final Future<DisplayFrame?> Function() getActiveWindowDisplay;
  final Future<DisplayFrame?> Function() getPrimaryDisplay;

  const DisplayResolver({
    required this.getMouseDisplay,
    required this.getActiveWindowDisplay,
    required this.getPrimaryDisplay,
  });

  /// Resolves the target display for [mode], falling back to mouse → primary
  /// if the selected mode returns null (e.g. no active window).
  Future<DisplayFrame?> resolve(ShowOnScreen mode) async {
    final primary = switch (mode) {
      ShowOnScreen.mouse => await getMouseDisplay(),
      ShowOnScreen.activeWindow => await getActiveWindowDisplay(),
      ShowOnScreen.primaryScreen => await getPrimaryDisplay(),
    };
    if (primary != null) return primary;
    // Fallback: try mouse display, then primary display.
    return await getMouseDisplay() ?? await getPrimaryDisplay();
  }
}

/// Bridges platform APIs (screen_retriever, windowManager, MethodChannel) to
/// [DisplayResolver] and applies the resulting geometry.
class PlatformDisplayAdapter {
  final MethodChannel _windowChannel;

  const PlatformDisplayAdapter(this._windowChannel);

  Future<DisplayFrame?> getMouseDisplay() async {
    final cursorPos = await screenRetriever.getCursorScreenPoint();
    final displays = await screenRetriever.getAllDisplays();
    for (final display in displays) {
      final pos = display.visiblePosition ?? Offset.zero;
      final sz = display.visibleSize ?? display.size;
      final bounds = Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
      if (bounds.contains(Offset(cursorPos.dx, cursorPos.dy))) {
        return DisplayFrame(
          x: pos.dx,
          y: pos.dy,
          width: sz.width,
          height: sz.height,
        );
      }
    }
    return null;
  }

  Future<DisplayFrame?> getActiveWindowDisplay() async {
    final result =
        await _windowChannel.invokeMethod<Map>('getActiveWindowScreenFrame');
    if (result == null) return null;
    return DisplayFrame(
      x: (result['x'] as num).toDouble(),
      y: (result['y'] as num).toDouble(),
      width: (result['width'] as num).toDouble(),
      height: (result['height'] as num).toDouble(),
    );
  }

  Future<DisplayFrame?> getPrimaryDisplay() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final pos = display.visiblePosition ?? Offset.zero;
    final sz = display.visibleSize ?? display.size;
    return DisplayFrame(
      x: pos.dx,
      y: pos.dy,
      width: sz.width,
      height: sz.height,
    );
  }

  /// Resolves the target display for [settingValue] and positions the window.
  Future<void> positionWindow(String settingValue) async {
    try {
      final mode = ShowOnScreen.fromString(settingValue);
      final resolver = DisplayResolver(
        getMouseDisplay: getMouseDisplay,
        getActiveWindowDisplay: getActiveWindowDisplay,
        getPrimaryDisplay: getPrimaryDisplay,
      );
      final frame = await resolver.resolve(mode);
      if (frame != null) {
        final geom = computeWindowGeometry(frame);
        await windowManager.setSize(geom.size);
        await windowManager.setPosition(geom.position);
      }
    } catch (e) {
      debugPrint('Could not position window: $e');
    }
  }
}
