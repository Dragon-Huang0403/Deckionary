import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_service.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  return service;
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
      Future.microtask(() => downloadAll());
    }

    return OfflineAudioState(cachedFiles: count, allPacksComplete: complete);
  }

  Future<void> downloadAll() async {
    final current =
        state.whenOrNull(data: (s) => s) ?? const OfflineAudioState();
    if (current.downloading) return;

    final audio = ref.read(audioServiceProvider);

    // Persist intent before starting
    await audio.markDownloadRequested();

    state = AsyncData(
      OfflineAudioState(
        cachedFiles: current.cachedFiles,
        allPacksComplete: current.allPacksComplete,
        downloading: true,
      ),
    );

    try {
      await audio.downloadAll(
        onProgress:
            (
              completedPacks,
              totalPacks,
              filesExtracted,
              bytes,
              retryRound,
              failedThisRound,
            ) {
              state = AsyncData(
                OfflineAudioState(
                  cachedFiles: current.cachedFiles + filesExtracted,
                  downloading: true,
                  completedPacks: completedPacks,
                  totalPacks: totalPacks,
                  filesExtracted: filesExtracted,
                  retryRound: retryRound,
                  failedPacks: failedThisRound,
                ),
              );
            },
        isCancelled: () {
          final s = state.whenOrNull(data: (s) => s);
          return s == null || !s.downloading;
        },
      );

      // If cancelled/cleared while running, don't overwrite state
      final postRun = state.whenOrNull(data: (s) => s);
      if (postRun != null && !postRun.downloading) return;

      // Success — clear the flag
      await audio.clearDownloadRequested();
      final count = await audio.getCachedFileCount();
      final complete = await audio.isDownloadComplete();
      state = AsyncData(
        OfflineAudioState(cachedFiles: count, allPacksComplete: complete),
      );
    } catch (e) {
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
  }

  Future<void> cancelDownload() async {
    final audio = ref.read(audioServiceProvider);
    audio.cancelDownload();
    await audio.clearDownloadRequested();
    final current =
        state.whenOrNull(data: (s) => s) ?? const OfflineAudioState();
    state = AsyncData(OfflineAudioState(cachedFiles: current.cachedFiles));
  }

  Future<void> clearCache() async {
    state = const AsyncData(OfflineAudioState(clearing: true));
    final audio = ref.read(audioServiceProvider);
    try {
      await audio.clearCache(); // increments generation + deletes all data
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
