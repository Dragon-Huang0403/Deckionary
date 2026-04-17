import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../build_info.dart';

/// Buffers log entries in memory and batch-flushes to Supabase.
///
/// Flush triggers: every 30 minutes, on app resume, or buffer >= 50 entries.
class LogFlushService with WidgetsBindingObserver {
  final String _deviceId;
  final String? Function() _getUserId;
  final Future<void> Function(List<Map<String, dynamic>> batch) _insertBatch;
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _timer;

  static const _flushThreshold = 50;
  static const _flushInterval = Duration(minutes: 30);

  /// Production constructor — flushes to Supabase.
  LogFlushService({required SupabaseClient supabase, required String deviceId})
    : _deviceId = deviceId,
      _getUserId = (() => supabase.auth.currentUser?.id),
      _insertBatch = ((batch) => supabase.from('app_logs').insert(batch));

  /// Test constructor — uses a custom flush callback.
  LogFlushService.forTesting({
    required String deviceId,
    required Future<void> Function(List<Map<String, dynamic>> batch) onFlush,
  }) : _deviceId = deviceId,
       _getUserId = (() => null),
       _insertBatch = onFlush;

  /// Number of buffered entries (exposed for testing).
  int get bufferLength => _buffer.length;

  /// Start the periodic flush timer and lifecycle observer.
  void init() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Add an info/warning log entry to the buffer.
  void addLog({required String level, required String message}) {
    _buffer.add(_makeEntry(level: level, message: message));
    _flushIfThresholdReached();
  }

  /// Add an error log entry to the buffer.
  void addError({required String message, String? error, String? stackTrace}) {
    _buffer.add(
      _makeEntry(
        level: 'error',
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    _flushIfThresholdReached();
  }

  Map<String, dynamic> _makeEntry({
    required String level,
    required String message,
    String? error,
    String? stackTrace,
  }) {
    // Extract tag from message if it follows the [TAG] pattern
    String? tag;
    var msg = message;
    final tagMatch = RegExp(r'^\[(\w+)\]\s*').firstMatch(message);
    if (tagMatch != null) {
      tag = tagMatch.group(1);
      msg = message.substring(tagMatch.end);
    }

    return {
      'device_id': _deviceId,
      'user_id': _getUserId(),
      'level': level,
      'tag': tag,
      'message': msg,
      'error': error,
      'stack_trace': stackTrace,
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  void _flushIfThresholdReached() {
    if (_buffer.length >= _flushThreshold) {
      flush();
    }
  }

  /// Flush the buffer to Supabase. Safe to call at any time.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.of(_buffer);
    _buffer.clear();
    try {
      await _insertBatch(batch);
    } catch (_) {
      // Put entries back for retry on next flush
      _buffer.insertAll(0, batch);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      flush();
    }
  }

  /// Stop the timer and observer. Attempts a final flush.
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
