import 'package:drift/drift.dart';

// ── Dictionary tables (read-only, from dictionary.db) ────────────────────────

class DictEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId => integer().named('source_id')();
  TextColumn get headword => text()();
  TextColumn get pos => text().withDefault(const Constant(''))();
  IntColumn get entryIndex => integer().named('entry_index').withDefault(const Constant(0))();
  TextColumn get ipaGb => text().named('ipa_gb').withDefault(const Constant(''))();
  TextColumn get ipaUs => text().named('ipa_us').withDefault(const Constant(''))();
  TextColumn get cefrLevel => text().named('cefr_level').withDefault(const Constant(''))();
  IntColumn get ox3000 => integer().withDefault(const Constant(0))();
  IntColumn get ox5000 => integer().withDefault(const Constant(0))();
  BlobColumn get rawHtml => blob().named('raw_html').nullable()();
  TextColumn get createdAt => text().named('created_at').withDefault(Constant(DateTime.now().toIso8601String()))();

  @override
  String get tableName => 'entries';
}

class DictPronunciations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get dialect => text()();
  TextColumn get ipa => text().withDefault(const Constant(''))();
  TextColumn get audioFile => text().named('audio_file').withDefault(const Constant(''))();

  @override
  String get tableName => 'pronunciations';
}

class DictVerbForms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get formLabel => text().named('form_label').withDefault(const Constant(''))();
  TextColumn get formText => text().named('form_text')();
  TextColumn get audioGb => text().named('audio_gb').withDefault(const Constant(''))();
  TextColumn get audioUs => text().named('audio_us').withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'verb_forms';
}

class DictSenseGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get topicEn => text().named('topic_en').withDefault(const Constant(''))();
  TextColumn get topicZh => text().named('topic_zh').withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'sense_groups';
}

class DictSenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get senseGroupId => integer().named('sense_group_id')();
  IntColumn get entryId => integer().named('entry_id')();
  IntColumn get senseNum => integer().named('sense_num').nullable()();
  TextColumn get cefrLevel => text().named('cefr_level').withDefault(const Constant(''))();
  TextColumn get grammar => text().withDefault(const Constant(''))();
  TextColumn get labels => text().withDefault(const Constant(''))();
  TextColumn get variants => text().withDefault(const Constant(''))();
  TextColumn get definition => text()();
  TextColumn get definitionZh => text().named('definition_zh').withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'senses';
}

class DictExamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get senseId => integer().named('sense_id')();
  TextColumn get textPlain => text().named('text_plain')();
  TextColumn get textHtml => text().named('text_html').withDefault(const Constant(''))();
  TextColumn get textZh => text().named('text_zh').withDefault(const Constant(''))();
  TextColumn get audioGb => text().named('audio_gb').withDefault(const Constant(''))();
  TextColumn get audioUs => text().named('audio_us').withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'examples';
}

class DictExtraExamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  IntColumn get senseNum => integer().named('sense_num').nullable()();
  TextColumn get textPlain => text().named('text_plain')();
  TextColumn get textHtml => text().named('text_html').withDefault(const Constant(''))();
  TextColumn get textZh => text().named('text_zh').withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'extra_examples';
}

class DictSynonyms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get groupTitle => text().named('group_title').withDefault(const Constant(''))();
  TextColumn get word => text()();
  TextColumn get definition => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'synonyms';
}

class DictWordOrigins extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get textHtml => text().named('text_html').withDefault(const Constant(''))();
  TextColumn get textPlain => text().named('text_plain').withDefault(const Constant(''))();

  @override
  String get tableName => 'word_origins';
}

class DictWordFamily extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get word => text()();
  TextColumn get pos => text().withDefault(const Constant(''))();
  TextColumn get opposite => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'word_family';
}

class DictCollocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get category => text()();
  TextColumn get words => text()();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'collocations';
}

class DictXrefs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  IntColumn get senseGroupId => integer().named('sense_group_id').nullable()();
  IntColumn get senseId => integer().named('sense_id').nullable()();
  TextColumn get xrefType => text().named('xref_type')();
  TextColumn get targetWord => text().named('target_word')();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'xrefs';
}

class DictPhrasalVerbs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get phrase => text()();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  String get tableName => 'phrasal_verbs';
}

class DictVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get variant => text()();

  @override
  String get tableName => 'variants';
}
