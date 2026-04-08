import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  String? _localAudioDir;
  bool _localPathResolved = false;

  AudioService() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Reset for next play
      }
    });
  }

  Future<String?> _getLocalAudioDir() async {
    if (_localPathResolved) return _localAudioDir;
    _localPathResolved = true;

    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/personal/oxford-5000-to-anki/oxford.dictionary/Contents',
      'oxford.dictionary/Contents',
      '../oxford.dictionary/Contents',
    ];
    for (final p in candidates) {
      try {
        if (await Directory(p).exists()) {
          _localAudioDir = Directory(p).absolute.path;
          debugPrint('AudioService: local audio dir = $_localAudioDir');
          return _localAudioDir;
        }
      } catch (_) {}
    }
    debugPrint('AudioService: no local audio directory found');
    return null;
  }

  Future<void> play(String filename) async {
    if (filename.isEmpty) return;

    try {
      // 1. Try local cache (previously downloaded from CDN)
      final cacheDir = await getApplicationDocumentsDirectory();
      final cachedFile = File('${cacheDir.path}/audio/$filename');
      if (cachedFile.existsSync()) {
        debugPrint('AudioService: playing from cache: ${cachedFile.path}');
        await _player.setFilePath(cachedFile.path);
        await _player.play();
        return;
      }

      // 2. Try local filesystem (dev mode)
      final localDir = await _getLocalAudioDir();
      if (localDir != null) {
        final localFile = File('$localDir/$filename');
        if (localFile.existsSync()) {
          debugPrint('AudioService: playing from local: ${localFile.path}');
          await _player.setFilePath(localFile.path);
          await _player.play();
          return;
        } else {
          debugPrint('AudioService: local file not found: ${localFile.path}');
        }
      }

      // 3. Fall back to remote URL (Flask dev server or CDN)
      const baseUrl = 'http://localhost:8000/api/audio';
      final url = '$baseUrl/$filename';
      debugPrint('AudioService: playing from URL: $url');
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('AudioService: error playing $filename: $e');
    }
  }

  Future<void> playPronunciation(
    List<Map<String, dynamic>> pronunciations, {
    String dialect = 'us',
  }) async {
    if (pronunciations.isEmpty) return;

    final pron = pronunciations.where((p) => p['dialect'] == dialect).firstOrNull ??
        pronunciations.first;

    final audioFile = pron['audio_file'] as String? ?? '';
    if (audioFile.isNotEmpty) {
      await play(audioFile);
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
