enum SpeakingTopicCategory {
  work,
  travel,
  opinions,
  dailyLife,
  technology,
  culture,
  education,
  health;

  String get displayName {
    switch (this) {
      case work:
        return 'Work & Career';
      case travel:
        return 'Travel & Places';
      case opinions:
        return 'Opinions & Debate';
      case dailyLife:
        return 'Daily Life';
      case technology:
        return 'Technology';
      case culture:
        return 'Culture & Society';
      case education:
        return 'Education & Learning';
      case health:
        return 'Health & Wellbeing';
    }
  }
}

class SpeakingTopic {
  final String id;
  final String title;
  final SpeakingTopicCategory category;
  final bool isCustom;

  const SpeakingTopic({
    required this.id,
    required this.title,
    required this.category,
    this.isCustom = false,
  });
}
