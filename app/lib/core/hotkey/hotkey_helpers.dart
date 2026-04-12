import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// Check if clipboard text looks like a word/phrase worth searching.
bool looksLikeSearchQuery(String text) {
  if (text.length > 50 || text.contains('\n')) return false;
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
  final rawName = hotKey.physicalKey.debugName ?? '';
  final label = rawName.replaceFirst('Key ', '').replaceFirst('Digit ', '');
  return jsonEncode({
    'keyCode': hotKey.physicalKey.usbHidUsage,
    'modifiers': hotKey.modifiers?.map((m) => m.name).toList() ?? [],
    'label': label.isEmpty ? '?' : label,
  });
}

String _labelFromUsbHid(int keyCode) {
  if (keyCode >= 458756 && keyCode <= 458781) {
    return String.fromCharCode('A'.codeUnitAt(0) + keyCode - 458756);
  }
  if (keyCode >= 458782 && keyCode <= 458790) {
    return String.fromCharCode('1'.codeUnitAt(0) + keyCode - 458782);
  }
  if (keyCode == 458791) return '0';
  return '?';
}

/// Display a hotkey from its JSON representation (e.g. "⌘⇧D").
String hotKeyDisplayString(String hotKeyJson) {
  final map = jsonDecode(hotKeyJson) as Map<String, dynamic>;
  final modifiers = (map['modifiers'] as List).cast<String>();
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
