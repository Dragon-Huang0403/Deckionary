import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../providers/speaking_providers.dart';
import '../../providers/speaking_session_notifier.dart';

/// Natural-version playback + local shadow recording controls for a single
/// attempt. Shadow audio is stored on the session notifier and deleted on
/// session end.
class ShadowBlock extends ConsumerStatefulWidget {
  final String attemptId;
  final String naturalVersion;
  final String? shadowAudioPath;

  const ShadowBlock({
    super.key,
    required this.attemptId,
    required this.naturalVersion,
    required this.shadowAudioPath,
  });

  @override
  ConsumerState<ShadowBlock> createState() => _ShadowBlockState();
}

class _ShadowBlockState extends ConsumerState<ShadowBlock> {
  final _recorder = AudioRecorder();
  bool _loadingModel = false;
  bool _isRecording = false;
  bool _isPlayingShadow = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _playModel() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _loadingModel = true);
    try {
      await tts.play(widget.naturalVersion);
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        ref
            .read(speakingSessionNotifierProvider.notifier)
            .setShadowAudio(attemptId: widget.attemptId, path: path);
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final shadowDir = Directory('${dir.path}/speaking_shadow');
    if (!shadowDir.existsSync()) shadowDir.createSync(recursive: true);
    final path = '${shadowDir.path}/${const Uuid().v4()}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: path,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _playShadow() async {
    final path = widget.shadowAudioPath;
    if (path == null || !File(path).existsSync()) return;
    setState(() => _isPlayingShadow = true);
    try {
      final tts = ref.read(ttsCacheServiceProvider);
      await tts?.playLocalFile(path);
    } finally {
      if (mounted) setState(() => _isPlayingShadow = false);
    }
  }

  Future<void> _clearShadow() async {
    await ref
        .read(speakingSessionNotifierProvider.notifier)
        .clearShadowAudio(widget.attemptId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasShadow =
        widget.shadowAudioPath != null &&
        File(widget.shadowAudioPath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Shadow practice',
              style: textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_loadingModel)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: 'Play model',
                onPressed: _playModel,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            FilledButton.tonalIcon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop' : 'Record'),
              onPressed: _toggleRecord,
            ),
            const SizedBox(width: 8),
            if (hasShadow) ...[
              IconButton(
                icon: Icon(
                  _isPlayingShadow ? Icons.graphic_eq : Icons.play_arrow,
                ),
                tooltip: 'Play your shadow',
                onPressed: _isPlayingShadow ? null : _playShadow,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-record',
                onPressed: _clearShadow,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
