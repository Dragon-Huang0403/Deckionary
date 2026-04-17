import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../logging/logging_service.dart';
import '../network/http_retry.dart';
import 'audio_service.dart';
import 'download_dispatcher.dart';

/// Staging subdirectory under [getApplicationSupportDirectory] for downloaded
/// tar files awaiting extraction.
const _stagingDir = 'audio-staging';

/// Group name for all audio-pack download tasks.
const _group = 'audio-packs';

/// Orchestrates background download of audio tar packs via
/// [DownloadDispatcher] (backed by `background_downloader`).
///
/// Two-phase pipeline:
///   Phase 1 (native/background): download .tar packs to staging dir on disk.
///   Phase 2 (app-side): read tar → parse in isolate → insert into SQLite →
///     mark pack complete → delete tar.
class AudioDownloadManager {
  final AudioService _audioService;
  final AudioDb _audioDB;
  final DownloadDispatcher _dispatcher;

  /// HTTP client supplier for manifest fetching (injectable for tests).
  final http.Client Function() _clientFactory;

  /// Incremented on cancel/clear. Extraction checks this to stop when stale.
  int _generation = 0;

  /// Packs downloaded but not yet extracted.
  final _extractionQueue = <String>[];
  bool _extracting = false;

  /// Completes when the current extraction run finishes (for cancel to await).
  Completer<void>? _extractionDone;

  /// Completes when all enqueued tasks reach a final state.
  Completer<void>? _allDone;
  int _pendingTasks = 0;

  /// Tracking for progress, retry rounds, and circuit breaker.
  int _totalPacks = 0;
  int _packsCompleted = 0;
  int _totalFilesExtracted = 0;
  int _failedThisRound = 0;
  int _consecutiveFailures = 0;
  int _currentRound = 0;

  /// Progress callback — same signature consumed by OfflineAudioNotifier.
  void Function(
    int completedPacks,
    int totalPacks,
    int filesExtracted,
    int bytesDownloaded,
    int retryRound,
    int failedThisRound,
  )?
  onProgress;

  /// External cancellation check (from OfflineAudioNotifier).
  bool Function()? isCancelled;

  AudioDownloadManager(
    this._audioService,
    this._audioDB,
    this._dispatcher, {
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  /// Lazily resolved staging directory path.
  String? _stagingPath;

  /// Override the staging directory path (for tests).
  @visibleForTesting
  set stagingPathOverride(String path) => _stagingPath = path;

  Future<String> _getStagingPath() async {
    if (_stagingPath != null) return _stagingPath!;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/$_stagingDir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _stagingPath = dir.path;
    return _stagingPath!;
  }

  /// Initialise the dispatcher (call once at app start).
  Future<void> initialize() async {
    await _dispatcher.configure(maxConcurrent: 3);
    _dispatcher.configureGroupNotification(
      group: _group,
      running: const TaskNotification(
        'Downloading audio',
        '{numFinished}/{numTotal} packs',
      ),
      complete: const TaskNotification(
        'Audio download complete',
        'All packs downloaded',
      ),
      error: const TaskNotification(
        'Audio download error',
        '{numFailed} packs failed',
      ),
      progressBar: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Start (or resume) downloading all audio packs.
  ///
  /// Fetches manifest, skips already-completed packs, enqueues remaining via
  /// [DownloadDispatcher], and processes completed downloads through the
  /// extraction pipeline. Retries failed packs across multiple rounds.
  Future<void> startDownload() async {
    final gen = ++_generation;
    bool stale() => _generation != gen || (isCancelled?.call() ?? false);

    final manifest = await _fetchManifest(stale);
    if (stale()) return;

    _totalPacks = manifest.length;
    final completed = await _audioDB.getCompletedPacks();
    _packsCompleted = completed.length;
    _totalFilesExtracted = 0;

    globalTalker.info(
      '[AudioDL] manifest: ${manifest.length} packs, '
      '${completed.length} already completed',
    );

    // Fire initial progress so UI shows total packs immediately.
    _fireProgress(0);

    const maxRounds = 10;
    const roundDelays = [0, 10, 30, 60, 120]; // seconds

    for (var round = 0; round < maxRounds; round++) {
      if (stale()) return;

      _currentRound = round;
      _failedThisRound = 0;
      _consecutiveFailures = 0;
      _extractionQueue.clear();

      final alreadyDone = await _audioDB.getCompletedPacks();
      _packsCompleted = alreadyDone.length;
      final remaining = manifest
          .where((p) => !alreadyDone.contains(p['name']))
          .toList();

      globalTalker.info(
        '[AudioDL] round $round: ${remaining.length} remaining, '
        '$_packsCompleted completed',
      );

      if (remaining.isEmpty) {
        _fireProgress(0);
        return;
      }

      // Backoff between retry rounds.
      if (round > 0) {
        final delay = roundDelays[round.clamp(0, roundDelays.length - 1)];
        globalTalker.info(
          '[AudioDL] waiting ${delay}s before retry round $round',
        );
        await Future.delayed(Duration(seconds: delay));
        if (stale()) return;
      }

      // Register callbacks before enqueueing.
      _registerCallbacks(gen);

      await _enqueuePacks(remaining, gen);
      if (stale()) {
        _dispatcher.unregisterCallbacks(_group);
        return;
      }

      // Wait for all tasks in this round to reach a final state.
      await _allDone?.future;
      _dispatcher.unregisterCallbacks(_group);

      // Wait for any trailing extraction to finish before next round.
      if (_extracting) await _extractionDone?.future;

      if (stale()) return;
      if (_failedThisRound == 0) {
        globalTalker.info('[AudioDL] round $round: all packs succeeded');
        return;
      }
      globalTalker.info(
        '[AudioDL] round $round done: $_failedThisRound failed, '
        '$_packsCompleted/$_totalPacks total completed',
      );
    }

    // Still incomplete after all rounds.
    final finalCompleted = await _audioDB.getCompletedPacks();
    final leftover = manifest.length - finalCompleted.length;
    if (leftover > 0) {
      throw Exception('$leftover packs failed after $maxRounds retry rounds');
    }
  }

  /// Cancel any active downloads and clean up staging directory.
  ///
  /// Waits for any in-progress extraction isolate to finish before returning,
  /// so callers can safely touch the database after this resolves.
  Future<void> cancelDownload() async {
    _generation++;
    globalTalker.info('[AudioDL] cancel requested, generation=$_generation');
    _extractionQueue.clear();
    _pendingTasks = 0;
    // Register a no-op callback so the native side doesn't warn about
    // missing listeners while it fires cancellation status updates.
    _dispatcher.registerStatusCallback(_group, (_) {});
    _completeAllDone();
    await _dispatcher.reset(_group);
    _dispatcher.unregisterCallbacks(_group);
    // Wait for any in-progress extraction to finish — the isolate can't be
    // interrupted, but the stale check prevents DB writes after it returns.
    if (_extracting) await _extractionDone?.future;
    await _cleanStagingDir();
  }

  /// Recover incomplete work on app restart.
  ///
  /// 1. Extract any staged tar files that weren't processed before app kill.
  /// 2. Re-attach to in-flight background downloads if any.
  /// 3. Re-enqueue missing packs if downloads were lost.
  Future<void> recoverPendingWork() async {
    final gen = ++_generation;
    bool stale() => _generation != gen;

    // 1. Extract staged tars.
    final stagingPath = await _getStagingPath();
    final stagingDir = Directory(stagingPath);
    if (stagingDir.existsSync()) {
      final completed = await _audioDB.getCompletedPacks();
      final tarFiles = stagingDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.tar'),
      );

      for (final file in tarFiles) {
        if (stale()) return;
        final packName = file.uri.pathSegments.last;
        if (!completed.contains(packName)) {
          globalTalker.info('[AudioDL] recovery: extracting staged $packName');
          await _extractPack(packName, file.path, gen);
        } else {
          file.deleteSync();
        }
      }
    }

    // 2. Check for in-flight tasks from a previous session.
    final activeTasks = await _dispatcher.allTasks(_group);
    if (activeTasks.isNotEmpty) {
      globalTalker.info(
        '[AudioDL] recovery: ${activeTasks.length} tasks still active',
      );
      _pendingTasks = activeTasks.length;
      _allDone = Completer<void>();
      _registerCallbacks(gen);
      await _allDone?.future;
      _dispatcher.unregisterCallbacks(_group);
      if (_extracting) await _extractionDone?.future;
    }

    // 3. Re-enqueue remaining packs if needed.
    final isComplete = await _audioDB.isDownloadComplete();
    if (!isComplete) {
      globalTalker.info('[AudioDL] recovery: re-enqueuing remaining packs');
      await startDownload();
    }
  }

  void dispose() {
    _dispatcher.unregisterCallbacks(_group);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _fetchManifest(
    bool Function() stale,
  ) async {
    const packsUrl = '$r2BaseUrl/audio-packs';
    final client = _clientFactory();
    try {
      final res = await httpGetWithRetry(
        client,
        Uri.parse('$packsUrl/manifest.json'),
        maxAttempts: 3,
        timeout: const Duration(seconds: 15),
        isCancelled: stale,
      );
      if (res.statusCode != 200) {
        throw Exception('Failed to fetch manifest: ${res.statusCode}');
      }
      final manifest = (jsonDecode(res.body) as List)
          .cast<Map<String, dynamic>>();
      await _audioDB.setMeta('total_packs', manifest.length.toString());
      return manifest;
    } finally {
      client.close();
    }
  }

  Future<void> _enqueuePacks(List<Map<String, dynamic>> packs, int gen) async {
    final stagingPath = await _getStagingPath();
    _pendingTasks = packs.length;
    _allDone = Completer<void>();

    for (final pack in packs) {
      if (_generation != gen) return;
      final packName = pack['name'] as String;
      final task = DownloadTask(
        url: '$r2BaseUrl/audio-packs/$packName',
        filename: packName,
        directory: stagingPath,
        baseDirectory: BaseDirectory.root,
        group: _group,
        retries: 3,
        updates: Updates.status,
      );
      await _dispatcher.enqueue(task);
    }
  }

  void _registerCallbacks(int gen) {
    _dispatcher.registerStatusCallback(_group, (update) {
      if (_generation != gen) return;
      _handleStatusUpdate(update, gen);
    });
  }

  void _handleStatusUpdate(TaskStatusUpdate update, int gen) {
    if (!update.status.isFinalState) return;

    final packName = update.task.filename;

    if (update.status == TaskStatus.complete) {
      globalTalker.info('[AudioDL] downloaded $packName, queuing extraction');
      _consecutiveFailures = 0;
      _extractionQueue.add(packName);
      _processExtractionQueue(gen);
    } else {
      globalTalker.warning('[AudioDL] $packName failed: ${update.status}');
      _failedThisRound++;
      _consecutiveFailures++;

      if (_consecutiveFailures >= 5) {
        globalTalker.warning(
          '[AudioDL] circuit breaker: $_consecutiveFailures consecutive '
          'failures, cancelling remaining',
        );
        _dispatcher.reset(_group);
        // reset() silently drops tasks without emitting status updates.
        // Account for remaining pending tasks so _allDone completes.
        _pendingTasks = 0;
        _fireProgress(_failedThisRound);
        _completeAllDone();
        return;
      }

      _pendingTasks--;
      _fireProgress(_failedThisRound);
      _completeAllDone();
    }
  }

  Future<void> _processExtractionQueue(int gen) async {
    if (_extracting) return;
    _extracting = true;
    _extractionDone = Completer<void>();

    try {
      while (_extractionQueue.isNotEmpty) {
        if (_generation != gen) {
          // Stale — drain remaining as failed so _pendingTasks stays accurate.
          final dropped = _extractionQueue.length;
          _extractionQueue.clear();
          _pendingTasks -= dropped;
          _completeAllDone();
          return;
        }
        final packName = _extractionQueue.removeAt(0);
        final stagingPath = await _getStagingPath();
        final tarPath = '$stagingPath/$packName';

        if (!File(tarPath).existsSync()) {
          globalTalker.warning(
            '[AudioDL] $packName: tar file missing, skipping',
          );
          _failedThisRound++;
          _pendingTasks--;
          _fireProgress(_failedThisRound);
          _completeAllDone();
          continue;
        }

        final extracted = await _extractPack(packName, tarPath, gen);
        if (_generation != gen) {
          _pendingTasks--;
          _completeAllDone();
          return;
        }

        if (extracted > 0) {
          _packsCompleted++;
          _totalFilesExtracted += extracted;
        } else {
          _failedThisRound++;
        }

        _pendingTasks--;
        _fireProgress(_failedThisRound);
        _completeAllDone();
      }
    } finally {
      _extracting = false;
      _extractionDone?.complete();
      _extractionDone = null;
    }
  }

  /// Extract a single tar pack. Returns file count or 0 on failure.
  Future<int> _extractPack(String packName, String tarPath, int gen) async {
    try {
      final extracted = await _audioService.extractTarFile(tarPath);
      if (_generation != gen) return 0;
      if (extracted == 0) {
        globalTalker.warning('[AudioDL] $packName: extracted 0 files');
        return 0;
      }
      await _audioDB.markPackComplete(packName);
      globalTalker.info('[AudioDL] $packName: extracted $extracted files');
      return extracted;
    } catch (e) {
      globalTalker.error('[AudioDL] $packName: extraction error: $e');
      return 0;
    }
  }

  void _fireProgress(int failedThisRound) {
    onProgress?.call(
      _packsCompleted,
      _totalPacks,
      _totalFilesExtracted,
      0, // bytes — no longer tracked per-pack
      _currentRound,
      failedThisRound,
    );
  }

  /// Complete [_allDone] if pending tasks are done, guarding against double-complete.
  void _completeAllDone() {
    if (_pendingTasks <= 0 && _allDone != null && !_allDone!.isCompleted) {
      _allDone!.complete();
    }
  }

  Future<void> _cleanStagingDir() async {
    final stagingPath = await _getStagingPath();
    final dir = Directory(stagingPath);
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        f.deleteSync();
      }
    }
  }
}
