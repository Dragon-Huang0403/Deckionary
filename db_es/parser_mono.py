"""Parser for the macOS-bundled Larousse Diccionario General de la Lengua
Española (the "Spanish" monolingual bundle).

Extracts a structured EntryData per <d:entry>:
    headword, pos, ipa, gender,
    sense_groups[] -> senses[] -> examples[]
    etymology, synonyms, xrefs, variants

The bundle's HTML uses these key class hooks:
  .hg .hw                   headword
  .sg .se1                  POS / sense-group container
    .posg .pos              part-of-speech text (one .se1 may have several)
    .msDict .df             top-level definition (no sense number)
    .se2 .hasSn .sn         numbered sense
      .msDict .df             definition text inside it
    .eg .ex                 example sentence
    .etym                   etymology
    .syn / .synGroup        synonyms
    .xrg .xr                cross-references
    .v                      variant headword
    .fg                     field/topic tag (e.g., "Botánica")
    .reg                    register marker (e.g., "coloq.")
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

from lxml import html as lxml_html


@dataclass
class Example:
    text_plain: str = ""
    text_html: str = ""


@dataclass
class Sense:
    sense_num: str = ""           # "1", "2"; empty for un-numbered senses
    labels: str = ""              # field/register tags joined by " "
    grammar: str = ""             # e.g., "transitivo"
    definition: str = ""
    examples: List[Example] = field(default_factory=list)


@dataclass
class SenseGroup:
    topic: str = ""               # POS string ("verbo intransitivo") or topic
    senses: List[Sense] = field(default_factory=list)


@dataclass
class MonoEntry:
    headword: str = ""
    pos: str = ""                 # joined unique POSes from all sense_groups
    gender: str = ""              # "m"/"f"/"mf" if noun
    ipa: str = ""                 # Larousse omits IPA, but reserve column
    sense_groups: List[SenseGroup] = field(default_factory=list)
    etymology: str = ""
    phrases: List[str] = field(default_factory=list)  # sub-entry locutions/idioms


def _classes(node) -> set[str]:
    return set((node.get("class") or "").split())


def _has_class(node, name: str) -> bool:
    return name in _classes(node)


def _text_clean(node) -> str:
    """Concatenated visible text; collapses whitespace and strips d:def
    self-closing markers Apple injects into the HTML."""
    txt = node.text_content() if node is not None else ""
    return " ".join(txt.split()).strip()


def _headword_text(hw_node) -> str:
    """Extract the headword text, ignoring inline indicator spans (.gp).

    The Larousse markup wraps homograph numbers like
        <span class="hw">ser<span class="gp ty_hom tg_hw"> 1 </span></span>
    so a naive text_content() pulls in "ser 1". This walker keeps every
    text node EXCEPT what's inside a .gp child."""
    if hw_node is None:
        return ""
    parts: list[str] = []
    if hw_node.text:
        parts.append(hw_node.text)
    for child in hw_node:
        if isinstance(child.tag, str):
            child_cls = set((child.get("class") or "").split())
            if "gp" not in child_cls:
                parts.append(child.text_content())
        if child.tail:
            parts.append(child.tail)
    return " ".join(" ".join(parts).split()).strip()


def _direct_children_with_class(parent, *class_names: str):
    """Yield direct children of `parent` whose class includes any of class_names."""
    targets = set(class_names)
    for child in parent:
        if not isinstance(child.tag, str):
            continue
        if _classes(child) & targets:
            yield child


def _first_descendant_with_class(node, name: str):
    return next(
        (n for n in node.iterdescendants() if _has_class(n, name)),
        None,
    )


def _all_descendants_with_class(node, *class_names: str):
    targets = set(class_names)
    out = []
    for n in node.iterdescendants():
        if isinstance(n.tag, str) and _classes(n) & targets:
            out.append(n)
    return out


_GENDER_MAP = {
    "nombre masculino": "m",
    "nombre femenino": "f",
    "nombre común": "mf",
    "nombre masculino y femenino": "mf",
}


def _infer_gender(pos_text: str) -> str:
    pl = pos_text.lower()
    for key, v in _GENDER_MAP.items():
        if key in pl:
            return v
    return ""


def _parse_examples(parent) -> list[Example]:
    """Find example sentences inside `parent`. Examples are <span class="ex">
    nested inside <span class="eg">. We dedup so we don't pick up nested
    ones twice."""
    examples = []
    seen: set[int] = set()
    for ex in _all_descendants_with_class(parent, "ex"):
        if id(ex) in seen:
            continue
        seen.add(id(ex))
        text = _text_clean(ex)
        if text:
            examples.append(Example(text_plain=text, text_html=lxml_html.tostring(ex, encoding="unicode")))
    return examples


def _parse_sense(node) -> Sense:
    """Build a Sense from a node that contains .df / .eg children. Works for
    both top-level .msDict and numbered .se2 sub-senses."""
    df_node = _first_descendant_with_class(node, "df")
    definition = _text_clean(df_node) if df_node is not None else ""

    sn_node = _first_descendant_with_class(node, "sn")
    sense_num = _text_clean(sn_node) if sn_node is not None else ""

    label_nodes = _all_descendants_with_class(node, "fg", "reg", "lev", "fld")
    labels_parts = [_text_clean(n) for n in label_nodes]
    labels = " ".join(p for p in labels_parts if p)

    return Sense(
        sense_num=sense_num,
        labels=labels,
        definition=definition,
        examples=_parse_examples(node),
    )


def _parse_sense_group(se1_node) -> SenseGroup:
    """One .se1 → SenseGroup. POS becomes topic; numbered .se2 + un-numbered
    .msDict children become senses."""
    pos_nodes = _all_descendants_with_class(se1_node, "pos")
    pos_text = ", ".join(filter(None, (_text_clean(p) for p in pos_nodes)))

    sg = SenseGroup(topic=pos_text)

    # Two kinds of senses:
    #   (a) a top-level .msDict that's a direct descendant (un-numbered)
    #   (b) numbered .se2 children, each containing their own .msDict
    seen: set[int] = set()
    for child in se1_node.iter():
        if not isinstance(child.tag, str):
            continue
        cls = _classes(child)
        # un-numbered top-level sense — direct .msDict not inside a .se2
        if "msDict" in cls and not any(
            _has_class(a, "se2") for a in child.iterancestors()
            if a is not se1_node
        ):
            # skip if any ancestor is .se2 (we only want top-level msDict)
            if id(child) not in seen:
                seen.add(id(child))
                sg.senses.append(_parse_sense(child))
        elif "se2" in cls:
            if id(child) not in seen:
                seen.add(id(child))
                sg.senses.append(_parse_sense(child))

    return sg


def parse_entry(html: str) -> MonoEntry:
    """Parse one Larousse <d:entry>...</d:entry> HTML string."""
    root = lxml_html.fromstring(html)

    hw_node = _first_descendant_with_class(root, "hw")
    headword = _headword_text(hw_node)

    entry = MonoEntry(headword=headword)

    pos_set: list[str] = []
    for se1 in _all_descendants_with_class(root, "se1"):
        sg = _parse_sense_group(se1)
        if sg.topic and sg.topic not in pos_set:
            pos_set.append(sg.topic)
        if sg.senses or sg.topic:
            entry.sense_groups.append(sg)
    entry.pos = "; ".join(pos_set)

    if pos_set:
        entry.gender = _infer_gender(pos_set[0])

    etym_node = _first_descendant_with_class(root, "etym")
    if etym_node is not None:
        entry.etymology = _text_clean(etym_node)

    # subEntry blocks contain locutions/idioms; the phrase lemma sits in
    # `<span class="l">`. Variants of the phrase (in `<span class="v">`) are
    # ignored for now.
    seen_phrase: set[str] = set()
    for sub in _all_descendants_with_class(root, "subEntry"):
        head = _first_descendant_with_class(sub, "l")
        if head is None:
            head = _first_descendant_with_class(sub, "hw")
        phrase = _text_clean(head) if head is not None else ""
        if (
            phrase
            and phrase.lower() not in seen_phrase
            and phrase.lower() != headword.lower()
        ):
            seen_phrase.add(phrase.lower())
            entry.phrases.append(phrase)

    return entry


if __name__ == "__main__":
    import sys
    from db_es.importer import find_dictionary_bundles, BodyDataReader

    bundles = find_dictionary_bundles()
    reader = BodyDataReader(bundles["Spanish"])
    words = sys.argv[1:] or ["correr", "casa", "tiempo", "ser", "hablar"]
    for w in words:
        h = reader.get_html(w)
        if not h:
            print(f"{w}: not found")
            continue
        e = parse_entry(h)
        print(f"\n=== {w} ===")
        print(f"  headword: {e.headword}")
        print(f"  pos: {e.pos}")
        print(f"  gender: {e.gender or '-'}")
        print(f"  phrases ({len(e.phrases)}): {e.phrases[:5]}")
        print(f"  etymology: {e.etymology[:80]!r}")
        for i, sg in enumerate(e.sense_groups, 1):
            print(f"  sense_group {i}: topic={sg.topic!r}, {len(sg.senses)} senses")
            for j, s in enumerate(sg.senses[:3], 1):
                print(f"    sense {s.sense_num or '·'}: {s.definition[:70]!r}")
                for ex in s.examples[:2]:
                    print(f"      ex: {ex.text_plain[:70]!r}")
