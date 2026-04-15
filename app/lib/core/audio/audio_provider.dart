import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_download_manager.dart';
import 'audio_service.dart';
import 'download_dispatcher.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  return service;
});

final audioDownloadManagerProvider = Provider<AudioDownloadManager>((ref) {
  final audio = ref.read(audioServiceProvider);
  final dispatcher = BackgroundDownloaderDispatcher();
  final manager = AudioDownloadManager(audio, audio.audioDB, dispatcher);
  // Initialization is fire-and-forget — configures max concurrency and
  // notification templates. Safe to proceed before it completes since
  // startDownload awaits its own enqueue calls.
  manager.initialize();
  ref.onDispose(manager.dispose);
  return manager;
});

/// Single source of truth for offline audio state
class OfflineAudioState {
  final int cachedFiles;
  final bool downloading;
  final int completedPacks;
  final int totalPacks;
  final int filesExtracted;
  final bool allPacksComplete;
  final int retryRound;
  final int failedPacks;
  final bool clearing;
  final String? error;

  const OfflineAudioState({
    this.cachedFiles = 0,
    this.clearing = false,
    this.downloading = false,
    this.completedPacks = 0,
    this.totalPacks = 0,
    this.filesExtracted = 0,
    this.allPacksComplete = false,
    this.retryRound = 0,
    this.failedPacks = 0,
    this.error,
  });

  bool get isFullyDownloaded => allPacksComplete && cachedFiles > 0;
  double get progress => totalPacks > 0 ? completedPacks / totalPacks : 0;
}

class OfflineAudioNotifier extends AsyncNotifier<OfflineAudioState> {
  @override
  Future<OfflineAudioState> build() async {
    final audio = ref.read(audioServiceProvider);
    final count = await audio.getCachedFileCount();
    final complete = await audio.isDownloadComplete();

    // Auto-resume if user previously requested download and it's not done
    if (!complete && await audio.wasDownloadRequested()) {
      Future.microtask(() => _recoverOrDownload());
    }

    return OfflineAudioState(cachedFiles: count, allPacksComplete: complete);
  }

  /// Recover pending work from a previous session, then continue downloading.
  Future<void> _recoverOrDownload() async {
    final current =
        state.whenOrNull(data: (s) => s) ?? const OfflineAudioState();
    if (current.downloading) return;

    final audio = ref.read(audioServiceProvider);
    final manager = ref.read(audioDownloadManagerProvider);

    state = AsyncData(
      OfflineAudioState(
        cachedFiles: current.cachedFiles,
        allPacksComplete: current.allPacksComplete,
        downloading: true,
      ),
    );

    _attachProgressCallback(manager, current.cachedFiles);

    try {
      await manager.recoverPendingWork();
      await _onDownloadSuccess(audio);
    } catch (e) {
      await _onDownloadError(audio, e);
    }
  }

  Future<void> downloadAll() async {
    final current =
        state.whenOrNull(data: (s) => s) ?? const OfflineAudioState();
    if (current.downloading) return;

    final audio = ref.read(audioServiceProvider);
    final manager = ref.read(audioDownloadManagerProvider);

    // Persist intent before starting
    await audio.markDownloadRequested();

    state = AsyncData(
      OfflineAudioState(
        cachedFiles: current.cachedFiles,
        allPacksComplete: current.allPacksComplete,
        downloading: true,
      ),
    );

    _attachProgressCallback(manager, current.cachedFiles);

    try {
      await manager.startDownload();
      await _onDownloadSuccess(audio);
    } catch (e) {
      await _onDownloadError(audio, e);
    }
  }

  void _attachProgressCallback(AudioDownloadManager manager, int baseCached) {
    manager.onProgress =
        (
          completedPacks,
          totalPacks,
          filesExtracted,
          _,
          retryRound,
          failedThisRound,
        ) {
          state = AsyncData(
            OfflineAudioState(
              cachedFiles: baseCached + filesExtracted,
              downloading: true,
              completedPacks: completedPacks,
              totalPacks: totalPacks,
              filesExtracted: filesExtracted,
              retryRound: retryRound,
              failedPacks: failedThisRound,
            ),
          );
        };

    manager.isCancelled = () {
      final s = state.whenOrNull(data: (s) => s);
      return s == null || !s.downloading;
    };
  }

  Future<void> _onDownloadSuccess(AudioService audio) async {
    // If cancelled/cleared while running, don't overwrite state
    final postRun = state.whenOrNull(data: (s) => s);
    if (postRun != null && !postRun.downloading) return;

    await audio.clearDownloadRequested();
    final count = await audio.getCachedFileCount();
    final complete = await audio.isDownloadComplete();
    state = AsyncData(
      OfflineAudioState(cachedFiles: count, allPacksComplete: complete),
    );
  }

  Future<void> _onDownloadError(AudioService audio, Object e) async {
    // If cancelled/cleared while running, don't overwrite state
    final postRun = state.whenOrNull(data: (s) => s);
    if (postRun != null && !postRun.downloading) return;

    // Don't clear download_requested — will auto-resume next launch
    debugPrint('OfflineAudioNotifier: download failed: $e');
    final count = await audio.getCachedFileCount();
    final completed = await audio.getCompletedPackCount();
    state = AsyncData(
      OfflineAudioState(
        cachedFiles: count,
        completedPacks: completed,
        totalPacks: AudioDb.totalPacks,
        error: e.toString(),
      ),
    );
  }

  Future<void> cancelDownload() async {
    final audio = ref.read(audioServiceProvider);
    final manager = ref.read(audioDownloadManagerProvider);
    await manager.cancelDownload();
    await audio.clearDownloadRequested();
    final current =
        state.whenOrNull(data: (s) => s) ?? const OfflineAudioState();
    state = AsyncData(OfflineAudioState(cachedFiles: current.cachedFiles));
  }

  Future<void> clearCache() async {
    state = const AsyncData(OfflineAudioState(clearing: true));
    final audio = ref.read(audioServiceProvider);
    final manager = ref.read(audioDownloadManagerProvider);
    try {
      await manager.cancelDownload();
      await audio.clearCache();
    } catch (e) {
      debugPrint('OfflineAudioNotifier: clearCache failed: $e');
      state = AsyncData(OfflineAudioState(error: 'Failed to clear cache: $e'));
      return;
    }
    state = const AsyncData(OfflineAudioState());
  }
}

final offlineAudioProvider =
    AsyncNotifierProvider<OfflineAudioNotifier, OfflineAudioState>(
      OfflineAudioNotifier.new,
    );
