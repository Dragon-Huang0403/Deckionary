import 'dart:convert';

/// Defines which words the user wants to study.
/// Criteria combine with OR (union).
class ReviewFilter {
  final Set<String> cefrLevels; // e.g. {'a1', 'b2'}
  final bool ox3000;
  final bool ox5000;

  const ReviewFilter({
    this.cefrLevels = const {},
    this.ox3000 = false,
    this.ox5000 = false,
  });

  bool get isEmpty => cefrLevels.isEmpty && !ox3000 && !ox5000;

  String toJson() => jsonEncode({
    'cefr': cefrLevels.toList(),
    'ox3000': ox3000,
    'ox5000': ox5000,
  });

  factory ReviewFilter.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ReviewFilter(
      cefrLevels: ((map['cefr'] as List?) ?? []).cast<String>().toSet(),
      ox3000: map['ox3000'] as bool? ?? false,
      ox5000: map['ox5000'] as bool? ?? false,
    );
  }

  /// Deterministic hash including filter + review settings for queue invalidation.
  String queueHash({required int newCardsPerDay, required String cardOrder}) {
    final cefr = cefrLevels.toList()..sort();
    return '${cefr.join(",")}'
        '|ox3000=$ox3000|ox5000=$ox5000'
        '|new=$newCardsPerDay|order=$cardOrder';
  }

  ReviewFilter copyWith({Set<String>? cefrLevels, bool? ox3000, bool? ox5000}) {
    return ReviewFilter(
      cefrLevels: cefrLevels ?? this.cefrLevels,
      ox3000: ox3000 ?? this.ox3000,
      ox5000: ox5000 ?? this.ox5000,
    );
  }
}
