class SpeakingCorrection {
  final String original;
  final String natural;
  final String explanation;

  const SpeakingCorrection({
    required this.original,
    required this.natural,
    required this.explanation,
  });

  factory SpeakingCorrection.fromJson(Map<String, dynamic> json) =>
      SpeakingCorrection(
        original: json['original'] as String,
        natural: json['natural'] as String,
        explanation: json['explanation'] as String,
      );

  Map<String, dynamic> toJson() => {
    'original': original,
    'natural': natural,
    'explanation': explanation,
  };
}

class PronunciationIssue {
  final String word;
  final String heardAs;
  final String tip;

  const PronunciationIssue({
    required this.word,
    required this.heardAs,
    required this.tip,
  });

  factory PronunciationIssue.fromJson(Map<String, dynamic> json) =>
      PronunciationIssue(
        word: json['word'] as String,
        heardAs: json['heard_as'] as String? ?? '',
        tip: json['tip'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'word': word,
    'heard_as': heardAs,
    'tip': tip,
  };
}

class SpeakingResult {
  final String transcript;
  final List<SpeakingCorrection> corrections;
  final String naturalVersion;
  final String? overallNote;
  final List<PronunciationIssue>? pronunciationIssues;

  const SpeakingResult({
    required this.transcript,
    required this.corrections,
    required this.naturalVersion,
    this.overallNote,
    this.pronunciationIssues,
  });

  factory SpeakingResult.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['pronunciation_issues'];
    final issues = rawIssues is List
        ? rawIssues
              .map((e) => PronunciationIssue.fromJson(e as Map<String, dynamic>))
              .toList()
        : null;
    return SpeakingResult(
      transcript: json['transcript'] as String,
      corrections: (json['corrections'] as List)
          .map((e) => SpeakingCorrection.fromJson(e as Map<String, dynamic>))
          .toList(),
      naturalVersion: json['natural_version'] as String,
      overallNote: json['overall_note'] as String?,
      // Collapse [] → null so every consumer only needs a null check.
      // Kept in lockstep with saveAttempt in speaking_service.dart.
      pronunciationIssues: (issues != null && issues.isEmpty) ? null : issues,
    );
  }

  Map<String, dynamic> toJson() => {
    'transcript': transcript,
    'corrections': corrections.map((c) => c.toJson()).toList(),
    'natural_version': naturalVersion,
    'overall_note': overallNote,
    if (pronunciationIssues != null)
      'pronunciation_issues': pronunciationIssues!
          .map((p) => p.toJson())
          .toList(),
  };
}
