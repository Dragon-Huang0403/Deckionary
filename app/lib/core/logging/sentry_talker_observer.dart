import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../config.dart';
import 'log_flush_service.dart';

/// Routes Talker log events to Sentry and the log flush buffer.
class SentryTalkerObserver extends TalkerObserver {
  final LogFlushService? _flushService;

  const SentryTalkerObserver({LogFlushService? flushService})
    : _flushService = flushService;

  bool get _sentryEnabled => sentryDsn.isNotEmpty;

  @override
  void onError(TalkerError err) {
    if (_sentryEnabled) {
      Sentry.captureException(err.error, stackTrace: err.stackTrace);
    }
    _flushService?.addError(
      message: err.message ?? err.error.toString(),
      error: err.error.toString(),
      stackTrace: err.stackTrace?.toString(),
    );
  }

  @override
  void onException(TalkerException err) {
    if (_sentryEnabled) {
      Sentry.captureException(err.exception, stackTrace: err.stackTrace);
    }
    _flushService?.addError(
      message: err.message ?? err.exception.toString(),
      error: err.exception.toString(),
      stackTrace: err.stackTrace?.toString(),
    );
  }

  @override
  void onLog(TalkerData log) {
    final logLevel = log.logLevel ?? LogLevel.debug;

    if (_sentryEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: log.message,
          level: _mapLevel(logLevel),
          timestamp: DateTime.now(),
        ),
      );
    }
    // Only buffer non-debug logs for Supabase flush
    if (logLevel != LogLevel.debug) {
      _flushService?.addLog(level: logLevel.name, message: log.message ?? '');
    }
  }

  SentryLevel _mapLevel(LogLevel level) {
    return switch (level) {
      LogLevel.error => SentryLevel.error,
      LogLevel.warning => SentryLevel.warning,
      LogLevel.info => SentryLevel.info,
      _ => SentryLevel.debug,
    };
  }
}
