"""Dataclass models for parsed dictionary entries."""

from dataclasses import dataclass, field


@dataclass
class ExampleData:
    text_plain: str
    text_html: str = ""
    text_zh: str = ""
    audio_gb: str = ""
    audio_us: str = ""


@dataclass
class SenseData:
    definition: str
    sense_num: int | None = None
    cefr_level: str = ""
    grammar: str = ""
    labels: str = ""
    variants: str = ""
    definition_zh: str = ""
    examples: list[ExampleData] = field(default_factory=list)


@dataclass
class SenseGroupData:
    topic_en: str = ""
    topic_zh: str = ""
    senses: list[SenseData] = field(default_factory=list)


@dataclass
class VerbFormData:
    form_label: str
    form_text: str
    audio_gb: str = ""
    audio_us: str = ""


@dataclass
class SynonymData:
    word: str
    group_title: str = ""
    definition: str = ""


@dataclass
class WordFamilyData:
    word: str
    pos: str = ""
    opposite: str = ""


@dataclass
class CollocationData:
    category: str
    words: list[str] = field(default_factory=list)


@dataclass
class XrefData:
    xref_type: str  # "see" or "cp"
    target_word: str


@dataclass
class ExtraExampleData:
    text_plain: str
    text_html: str = ""
    text_zh: str = ""


@dataclass
class EntryData:
    headword: str
    pos: str = ""
    ipa_gb: str = ""
    ipa_us: str = ""
    audio_gb: str = ""
    audio_us: str = ""
    cefr_level: str = ""
    ox3000: bool = False
    ox5000: bool = False
    groups: list[SenseGroupData] = field(default_factory=list)
    verb_forms: list[VerbFormData] = field(default_factory=list)
    card_type: str = "word"
    raw_html: str = ""
    synonyms: list[SynonymData] = field(default_factory=list)
    word_origin: str = ""
    word_origin_html: str = ""
    word_family: list[WordFamilyData] = field(default_factory=list)
    collocations: list[CollocationData] = field(default_factory=list)
    xrefs: list[XrefData] = field(default_factory=list)
    phrasal_verbs: list[str] = field(default_factory=list)
    extra_examples: list[ExtraExampleData] = field(default_factory=list)
