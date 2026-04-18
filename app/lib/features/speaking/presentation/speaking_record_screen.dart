import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/logging/logging_service.dart';
import '../providers/speaking_providers.dart';
import '../providers/speaking_session_notifier.dart';
import 'speaking_result_screen.dart';

class SpeakingRecordScreen extends ConsumerStatefulWidget {
  /// true when launched from the result screen's Try-again button — the
  /// result screen is already on the nav stack, so this screen just pops.
  final bool isRetry;

  const SpeakingRecordScreen({super.key, this.isRetry = false});

  @override
  ConsumerState<SpeakingRecordScreen> createState() =>
      _SpeakingRecordScreenState();
}

class _SpeakingRecordScreenState extends ConsumerState<SpeakingRecordScreen> {
  final _recorder = AudioRecorder();
  final _textController = TextEditingController();
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    // Safety net in case the widget is destroyed before PopScope runs
    // (e.g. platform back button without confirm). Fire-and-forget.
    _recorder
        .stop()
        .then((path) async {
          if (path != null) {
            try {
              await File(path).delete();
            } catch (_) {}
          }
        })
        .catchError((_) {});
    _recorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final status = ref.read(recordingStatusProvider);
    if (status == RecordingStatus.recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  /// Stop recording without analyzing. Deletes the temp WAV.
  Future<void> _cancelRecording() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) {
      ref.read(recordingStatusProvider.notifier).set(RecordingStatus.idle);
    }
  }

  Future<bool> _confirmStopDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop recording?'),
        content: const Text(
          'Recording is in progress. Leaving will discard the current recording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop & leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handlePopAttempt() async {
    final status = ref.read(recordingStatusProvider);
    if (status == RecordingStatus.processing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analysis in progress — please wait…')),
      );
      return;
    }
    if (status == RecordingStatus.recording) {
      final confirmed = await _confirmStopDialog();
      if (!confirmed) return;
      await _cancelRecording();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;

      final dir = await getApplicationDocumentsDirectory();
      final tempPath = '${dir.path}/_speaking_recording.wav';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: tempPath,
      );
      _elapsedSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });

      ref.read(recordingStatusProvider.notifier).set(RecordingStatus.recording);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path == null) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.processing);

    try {
      final audioBytes = await File(path).readAsBytes();
      final attempt = await ref
          .read(speakingSessionNotifierProvider.notifier)
          .addAttemptFromAudio(audioBytes);
      // Persist the recording for history replay: move temp -> permanent,
      // then fire-and-forget upload so the UI isn't blocked on network.
      final service = ref.read(speakingServiceProvider);
      if (service != null) {
        try {
          await service.attachLocalAudio(attemptId: attempt.id, tempPath: path);
        } catch (e, st) {
          globalTalker.handle(e, st, '[Speaking] attach local audio failed');
        }
        unawaited(
          service
              .uploadAttemptAudio(attemptId: attempt.id, bytes: audioBytes)
              .catchError((e, st) {
                globalTalker.handle(
                  e,
                  st as StackTrace,
                  '[Speaking] upload audio failed',
                );
                return '';
              }),
        );
      }
      _navigateOnSuccess();
    } catch (e, st) {
      _handleError(e, st);
    }
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.processing);

    try {
      await ref
          .read(speakingSessionNotifierProvider.notifier)
          .addAttemptFromText(text);
      _navigateOnSuccess();
    } catch (e, st) {
      _handleError(e, st);
    }
  }

  void _navigateOnSuccess() {
    if (!mounted) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.idle);
    if (widget.isRetry) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SpeakingResultScreen()),
      );
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    globalTalker.handle(error, stackTrace, '[Speaking] analysis failed');
    if (!mounted) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.idle);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Analysis failed: $error')));
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(speakingSessionNotifierProvider);
    final topicLabel = session?.topic ?? '';
    final inputMode = ref.watch(inputModeProvider);
    final recordingStatus = ref.watch(recordingStatusProvider);
    final cs = Theme.of(context).colorScheme;

    return PopScope<Object?>(
      canPop: recordingStatus == RecordingStatus.idle,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePopAttempt();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: Text(
            topicLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SegmentedButton<InputMode>(
                    segments: const [
                      ButtonSegment(
                        value: InputMode.speaking,
                        label: Text('Speak'),
                        icon: Icon(Icons.mic),
                      ),
                      ButtonSegment(
                        value: InputMode.typing,
                        label: Text('Type'),
                        icon: Icon(Icons.keyboard),
                      ),
                    ],
                    selected: {inputMode},
                    onSelectionChanged: recordingStatus != RecordingStatus.idle
                        ? null
                        : (modes) => ref
                              .read(inputModeProvider.notifier)
                              .set(modes.first),
                  ),
                ),
              ),
              Expanded(
                child: recordingStatus == RecordingStatus.processing
                    ? _buildProcessing()
                    : inputMode == InputMode.speaking
                    ? Center(child: _buildSpeakMode(cs, recordingStatus))
                    : _buildTypeMode(cs),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Analyzing your response...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSpeakMode(ColorScheme cs, RecordingStatus status) {
    final isRecording = status == RecordingStatus.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRecording) ...[
          Text(
            _formatDuration(_elapsedSeconds),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text('Recording...', style: TextStyle(color: cs.error, fontSize: 14)),
        ] else
          Text(
            'Tap to start recording',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
          ),
        const SizedBox(height: 40),
        SizedBox(
          width: 80,
          height: 80,
          child: FloatingActionButton.large(
            heroTag: 'mic_button',
            backgroundColor: isRecording ? cs.error : cs.primary,
            foregroundColor: isRecording ? cs.onError : cs.onPrimary,
            onPressed: _toggleRecording,
            child: Icon(isRecording ? Icons.stop : Icons.mic, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        if (isRecording)
          Text(
            'Tap to stop',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildTypeMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Type your response here...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Submit'),
              onPressed: _submitText,
            ),
          ),
        ],
      ),
    );
  }
}
