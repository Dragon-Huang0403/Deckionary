import 'dart:async';
import 'package:background_downloader/background_downloader.dart';

/// Thin abstraction over [FileDownloader] for testability.
///
/// Tests inject a mock that emits controlled [TaskUpdate] events instead of
/// performing real network I/O.
abstract class DownloadDispatcher {
  /// Enqueue a [DownloadTask]. Returns true if successfully enqueued.
  Future<bool> enqueue(DownloadTask task);

  /// Cancel all tasks in [group] and return the number cancelled.
  Future<int> reset(String group);

  /// Return all active tasks (enqueued, running, waiting to retry) in [group].
  Future<List<Task>> allTasks(String group);

  /// Stream of [TaskUpdate]s for tasks that don't have a registered callback.
  Stream<TaskUpdate> get updates;

  /// Configure max concurrent downloads and notifications.
  Future<void> configure({int maxConcurrent = 3});

  /// Configure group-level notification (Android notification bar).
  void configureGroupNotification({
    required String group,
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar = false,
  });
}

/// Real implementation backed by [FileDownloader].
class BackgroundDownloaderDispatcher implements DownloadDispatcher {
  @override
  Future<bool> enqueue(DownloadTask task) => FileDownloader().enqueue(task);

  @override
  Future<int> reset(String group) => FileDownloader().reset(group: group);

  @override
  Future<List<Task>> allTasks(String group) =>
      FileDownloader().allTasks(group: group);

  @override
  Stream<TaskUpdate> get updates => FileDownloader().updates;

  @override
  Future<void> configure({int maxConcurrent = 3}) async {
    await FileDownloader().configure(
      globalConfig: [(Config.holdingQueue, (maxConcurrent, null, null))],
    );
  }

  @override
  void configureGroupNotification({
    required String group,
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar = false,
  }) {
    FileDownloader().configureNotificationForGroup(
      group,
      running: running,
      complete: complete,
      error: error,
      progressBar: progressBar,
    );
  }
}
