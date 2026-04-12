import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/audio_provider.dart';
import '../../../../core/database/database_provider.dart';

const usAccentColor = Color(0xFF1565C0);
const gbAccentColor = Color(0xFFD84315);

class AudioButton extends ConsumerWidget {
  final String filename;
  final double size;
  final Color? color;

  const AudioButton(this.filename, {super.key, this.size = 28, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = color ?? usAccentColor;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: size * 0.55,
        style: IconButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.volume_up),
        onPressed: () => ref.read(audioServiceProvider).play(filename),
      ),
    );
  }
}

class EntryPhonetics extends ConsumerWidget {
  final List<Map<String, dynamic>> pronunciations;

  const EntryPhonetics(this.pronunciations, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = ref.watch(pronunciationDisplayProvider).value ?? 'both';
    final gb = pronunciations.where((p) => p['dialect'] == 'gb').firstOrNull;
    final us = pronunciations.where((p) => p['dialect'] == 'us').firstOrNull;
    final showUs = display != 'gb';
    final showGb = display != 'us';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Wrap(
        spacing: 16,
        children: [
          if (us != null && showUs)
            _phonGroup(
              'US',
              us['ipa'] as String? ?? '',
              us['audio_file'] as String? ?? '',
              usAccentColor,
            ),
          if (gb != null && showGb)
            _phonGroup(
              'GB',
              gb['ipa'] as String? ?? '',
              gb['audio_file'] as String? ?? '',
              gbAccentColor,
            ),
        ],
      ),
    );
  }

  Widget _phonGroup(String label, String ipa, String audioFile, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ipa,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        if (audioFile.isNotEmpty) ...[
          const SizedBox(width: 4),
          AudioButton(audioFile, color: color),
        ],
      ],
    );
  }
}
