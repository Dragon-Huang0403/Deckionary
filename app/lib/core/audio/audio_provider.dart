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
  final String? error;

  const OfflineAudioState({
    this.cachedFiles = 0,
    this.downloading = false,
    this.completedPacks = 0,
    this.totalPacks = 0,
    this.filesExtracted = 0,
    this.allPacksComplete = false,
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
    return OfflineAudioState(
      cachedFiles: count,
      allPacksComplete: complete,
    );
  }

  Future<void> downloadAll() async {
    final current = state.when(
      data: (s) => s,
      loading: () => const OfflineAudioState(),
      error: (_, _) => const OfflineAudioState(),
    );
    if (current.downloading) return;

    state = AsyncData(
      OfflineAudioState(
        cachedFiles: current.cachedFiles,
        allPacksComplete: current.allPacksComplete,
        downloading: true,
      ),
    );

    final audio = ref.read(audioServiceProvider);
    try {
      await audio.downloadAll(
        onProgress: (completedPacks, totalPacks, filesExtracted, bytes) {
          state = AsyncData(
            OfflineAudioState(
              cachedFiles: current.cachedFiles + filesExtracted,
              allPacksComplete: current.allPacksComplete,
              downloading: true,
              completedPacks: completedPacks,
              totalPacks: totalPacks,
              filesExtracted: filesExtracted,
            ),
          );
        },
      );
      final count = await audio.getCachedFileCount();
      state = AsyncData(
        OfflineAudioState(cachedFiles: count, allPacksComplete: true),
      );
    } catch (e) {
      final count = await audio.getCachedFileCount();
      state = AsyncData(
        OfflineAudioState(
          cachedFiles: count,
          allPacksComplete: current.allPacksComplete,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> clearCache() async {
    final audio = ref.read(audioServiceProvider);
    await audio.clearCache();
    state = const AsyncData(OfflineAudioState());
  }
}

final offlineAudioProvider =
    AsyncNotifierProvider<OfflineAudioNotifier, OfflineAudioState>(
      OfflineAudioNotifier.new,
    );
