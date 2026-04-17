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

class SpeakingResult {
  final String transcript;
  final List<SpeakingCorrection> corrections;
  final String naturalVersion;
  final String? overallNote;

  const SpeakingResult({
    required this.transcript,
    required this.corrections,
    required this.naturalVersion,
    this.overallNote,
  });

  factory SpeakingResult.fromJson(Map<String, dynamic> json) => SpeakingResult(
    transcript: json['transcript'] as String,
    corrections: (json['corrections'] as List)
        .map((e) => SpeakingCorrection.fromJson(e as Map<String, dynamic>))
        .toList(),
    naturalVersion: json['natural_version'] as String,
    overallNote: json['overall_note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'transcript': transcript,
    'corrections': corrections.map((c) => c.toJson()).toList(),
    'natural_version': naturalVersion,
    'overall_note': overallNote,
  };
}
