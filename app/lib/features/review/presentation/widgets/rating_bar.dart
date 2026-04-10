import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

/// Row of 4 rating buttons: Again / Hard / Good / Easy with interval previews.
class RatingBar extends StatelessWidget {
  final Map<fsrs.Rating, String> intervals;
  final ValueChanged<fsrs.Rating> onRate;

  const RatingBar({
    super.key,
    required this.intervals,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _RatingButton(
              label: 'Again',
              interval: intervals[fsrs.Rating.again] ?? '',
              color: const Color(0xFFE53935),
              onTap: () => onRate(fsrs.Rating.again),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Hard',
              interval: intervals[fsrs.Rating.hard] ?? '',
              color: const Color(0xFFFF9800),
              onTap: () => onRate(fsrs.Rating.hard),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Good',
              interval: intervals[fsrs.Rating.good] ?? '',
              color: const Color(0xFF4CAF50),
              onTap: () => onRate(fsrs.Rating.good),
            ),
            const SizedBox(width: 8),
            _RatingButton(
              label: 'Easy',
              interval: intervals[fsrs.Rating.easy] ?? '',
              color: const Color(0xFF2196F3),
              onTap: () => onRate(fsrs.Rating.easy),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String interval;
  final Color color;
  final VoidCallback onTap;

  const _RatingButton({
    required this.label,
    required this.interval,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            if (interval.isNotEmpty)
              Text(interval,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
