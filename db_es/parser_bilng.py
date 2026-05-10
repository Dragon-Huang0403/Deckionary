"""Parser for the macOS-bundled Gran Diccionario Oxford Español-Inglés
(the "Spanish - English" bilingual bundle).

Extracts per-entry English glosses + bilingual examples for ES headwords.
EN→ES direction entries (id starts "e_b-en-es") are ignored — those are
not what we're presenting to the user.

Bundle's HTML uses these key class hooks:
  .hwg .hw                 headword
  .gramb                   POS section (multiple per entry: A, B, ...)
    .ps                    part-of-speech text ("intransitive verb")
    .semb                  semantic block (sense). Often nested:
                             top-level semb has sn = "1", "2", ...
                             nested semb has sn = "a", "b", ...
    .trg                   translation group
      .trans               English translation/gloss
      .lg .fld             field tag ("Sport", "Music")
      .cs                  collocate / context ("«atleta»")
      .ind                 sense indicator / disambiguator
    .exg                   example group
      .ex                  Spanish example sentence
      .trg .trans          English translation of the example
  .idmb                    idiom block (one per entry)
    .idm                   idiom text
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

from lxml import html as lxml_html


@dataclass
class BilngExample:
    text_es: str = ""
    text_en: str = ""


@dataclass
class BilngSense:
    sense_path: str = ""        # joined sense numbers, e.g. "A 1 a"
    pos: str = ""               # from .ps
    field_label: str = ""       # .fld text
    context: str = ""           # .cs collocate
    indicator: str = ""         # .ind text (e.g., "(apresurarse)")
    translation: str = ""       # .trans text — the EN gloss
    examples: List[BilngExample] = field(default_factory=list)


@dataclass
class BilngEntry:
    headword: str = ""
    pos: str = ""               # joined unique POSes
    senses: List[BilngSense] = field(default_factory=list)
    idioms: List[BilngExample] = field(default_factory=list)


def _classes(node) -> set[str]:
    return set((node.get("class") or "").split())


def _has_class(node, name: str) -> bool:
    return name in _classes(node)


def _text_clean(node) -> str:
    if node is None:
        return ""
    return " ".join(node.text_content().split()).strip()


def _headword_text(hw_node) -> str:
    """Extract headword text, skipping child .gp indicator spans."""
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


def _first_descendant_with_class(node, name: str):
    return next(
        (n for n in node.iterdescendants()
         if isinstance(n.tag, str) and _has_class(n, name)),
        None,
    )


def _direct_children_with_class(parent, *class_names: str):
    targets = set(class_names)
    for child in parent:
        if isinstance(child.tag, str) and _classes(child) & targets:
            yield child


def _is_es_entry(html: str) -> bool:
    """Filter: only ES headword entries have ids starting 's_b-es-en'."""
    return 's_b-es-en' in html[:300]


def _direct_text_in(node, target_class: str) -> str:
    """Return text of the FIRST descendant whose class contains target_class
    that doesn't itself contain a deeper one of the same class."""
    for n in node.iterdescendants():
        if isinstance(n.tag, str) and _has_class(n, target_class):
            return _text_clean(n)
    return ""


def _example_pair(exg) -> BilngExample:
    """An .exg contains .ex (Spanish) followed by .trg > .trans (English)."""
    ex_node = _first_descendant_with_class(exg, "ex")
    text_es = _text_clean(ex_node)

    text_en = ""
    trg = _first_descendant_with_class(exg, "trg")
    if trg is not None:
        # take all .trans inside this trg (multiple are possible — synonyms)
        trans_parts = []
        for t in trg.iterdescendants():
            if isinstance(t.tag, str) and _has_class(t, "trans"):
                txt = _text_clean(t)
                if txt:
                    trans_parts.append(txt)
        text_en = " / ".join(trans_parts)

    return BilngExample(text_es=text_es, text_en=text_en)


def _semb_translation(semb) -> tuple[str, str, str, str, list]:
    """Pull translation + context/field labels from a leaf .semb.

    Returns (translation, field_label, context, indicator, exg_nodes)."""
    translations: list[str] = []
    field_label = ""
    context = ""
    indicator = ""
    exgs: list = []

    # First .trg directly under semb; ignore .trg nested inside .exg
    for child in semb.iter():
        if not isinstance(child.tag, str):
            continue
        cls = _classes(child)
        if "exg" in cls:
            exgs.append(child)
            continue
        # skip nodes inside an exg (those belong to example translation)
        if any(_has_class(a, "exg") for a in child.iterancestors()
               if a is not semb):
            continue
        if "trans" in cls:
            t = _text_clean(child)
            if t and t not in translations:
                translations.append(t)
        elif "fld" in cls and not field_label:
            field_label = _text_clean(child)
        elif "cs" in cls and not context:
            # strip the ascii-art guillemets the dictionary wraps cs in
            context = _text_clean(child).strip("«» ")
        elif "ind" in cls and not indicator:
            indicator = _text_clean(child).strip("() ")

    return (
        " / ".join(translations),
        field_label,
        context,
        indicator,
        exgs,
    )


def _walk_sembs(parent, parent_path: str = ""):
    """Yield (semb_node, sense_path) for every leaf .semb under parent.

    A leaf .semb is one that contains a .trans NOT inside a child .semb.
    """
    for semb in _direct_children_with_class(parent, "semb"):
        sn = ""
        # Find direct sn (top-of-semb numbering)
        for c in semb:
            if isinstance(c.tag, str) and _has_class(c, "sn"):
                sn = _text_clean(c)
                break
            inner = _first_descendant_with_class(c, "sn")
            if inner is not None and not any(
                _has_class(a, "semb") for a in inner.iterancestors() if a is not semb
            ):
                sn = _text_clean(inner)
                break
        path = (parent_path + " " + sn).strip() if sn else parent_path

        # Does this semb contain any nested semb? If so, recurse; otherwise
        # treat it as a leaf.
        nested = list(_direct_children_with_class(semb, "semb"))
        if nested:
            yield from _walk_sembs(semb, path)
        else:
            yield semb, path


def parse_entry(html: str) -> BilngEntry | None:
    """Parse one bilingual <d:entry>; returns None if it's an EN→ES entry."""
    if not _is_es_entry(html):
        return None
    root = lxml_html.fromstring(html)

    hw = _first_descendant_with_class(root, "hw")
    headword = _headword_text(hw)
    entry = BilngEntry(headword=headword)

    pos_set: list[str] = []
    for gramb in root.iterdescendants():
        if not isinstance(gramb.tag, str) or not _has_class(gramb, "gramb"):
            continue
        pos_node = _first_descendant_with_class(gramb, "ps")
        pos_text = _text_clean(pos_node)
        if pos_text and pos_text not in pos_set:
            pos_set.append(pos_text)

        # gramb may have a top-level letter-label sn ("A", "B")
        gramb_sn = ""
        for c in gramb:
            if isinstance(c.tag, str) and _has_class(c, "sn"):
                gramb_sn = _text_clean(c)
                break
            inner = _first_descendant_with_class(c, "sn")
            if inner is not None and not any(
                _has_class(a, "semb") for a in inner.iterancestors()
            ):
                gramb_sn = _text_clean(inner)
                break

        for semb, path in _walk_sembs(gramb, gramb_sn):
            translation, field_label, context, indicator, exgs = _semb_translation(semb)
            sense = BilngSense(
                sense_path=path,
                pos=pos_text,
                field_label=field_label,
                context=context,
                indicator=indicator,
                translation=translation,
                examples=[_example_pair(e) for e in exgs],
            )
            entry.senses.append(sense)
    entry.pos = "; ".join(pos_set)

    # Idioms: each .idmsec is one idiom (with .idm + translation + examples)
    for idmsec in root.iterdescendants():
        if not isinstance(idmsec.tag, str) or not _has_class(idmsec, "idmsec"):
            continue
        idm_node = _first_descendant_with_class(idmsec, "idm")
        idiom_es = _text_clean(idm_node)
        translation, _, _, _, _ = _semb_translation(idmsec)
        if idiom_es:
            entry.idioms.append(BilngExample(text_es=idiom_es, text_en=translation))

    return entry


if __name__ == "__main__":
    import sys
    from db_es.importer import find_dictionary_bundles, BodyDataReader

    bundles = find_dictionary_bundles()
    reader = BodyDataReader(bundles["Spanish - English"])
    words = sys.argv[1:] or ["correr", "casa", "tiempo", "ser", "hablar"]
    for w in words:
        h = reader.get_html(w)
        if not h:
            print(f"{w}: not found")
            continue
        e = parse_entry(h)
        if e is None:
            print(f"{w}: not a Spanish entry (skipped)")
            continue
        print(f"\n=== {w} ===")
        print(f"  headword: {e.headword}")
        print(f"  pos: {e.pos}")
        print(f"  senses: {len(e.senses)}")
        for s in e.senses[:6]:
            tag_parts = [p for p in [s.field_label, s.context, s.indicator] if p]
            tag = f"  [{', '.join(tag_parts)}]" if tag_parts else ""
            print(f"    {s.sense_path:8s} → {s.translation!r}{tag}")
            for ex in s.examples[:1]:
                print(f"             ex: {ex.text_es[:50]!r} → {ex.text_en[:50]!r}")
        if e.idioms:
            print(f"  idioms ({len(e.idioms)}):")
            for idm in e.idioms[:3]:
                print(f"    {idm.text_es!r} → {idm.text_en[:60]!r}")
