"""
Enhanced OALD10 HTML parser.

Extracted from create_deck.py with these enhancements:
- Examples: returns both text_plain and text_html (preserving highlighting spans)
- Example audio: extracts both GB and US audio
- Verb forms: extracts both GB and US audio + form_label attribute
- CEFR: extracts cefr attribute from <li class="sense">
- Oxford levels: extracts ox3000/ox5000 from headword <h1> attributes
- Returns dataclass models instead of raw dicts
"""

import re

from .models import (
    CollocationData, EntryData, ExampleData, ExtraExampleData,
    SenseData, SenseGroupData, SynonymData, VerbFormData,
    WordFamilyData, XrefData,
)


def strip_tags(html: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()


def extract_span(html: str, class_name: str) -> str | None:
    """Extract the full inner content of the first <span class="{class_name}">,
    correctly handling nested <span> tags."""
    marker = f'class="{class_name}"'
    idx = html.find(marker)
    if idx == -1:
        return None
    tag_start = html.rfind("<", 0, idx)
    content_start = html.find(">", tag_start) + 1
    depth, pos = 1, content_start
    while pos < len(html) and depth > 0:
        open_next = html.find("<span", pos)
        close_next = html.find("</span>", pos)
        if close_next == -1:
            break
        if open_next != -1 and open_next < close_next:
            depth += 1
            pos = open_next + 5
        else:
            depth -= 1
            if depth == 0:
                return html[content_start:close_next]
            pos = close_next + 7
    return None


def _find_examples(block: str) -> list[tuple[str, str]]:
    """Find all (ex_text_html, ex_tail) pairs, correctly handling nested spans."""
    results = []
    pos = 0
    marker = '<span class="x">'
    while True:
        start = block.find(marker, pos)
        if start == -1:
            break
        content_start = start + len(marker)
        depth, p = 1, content_start
        while p < len(block) and depth > 0:
            open_next = block.find("<span", p)
            close_next = block.find("</span>", p)
            if close_next == -1:
                break
            if open_next != -1 and open_next < close_next:
                depth += 1
                p = open_next + 5
            else:
                depth -= 1
                if depth == 0:
                    ex_text_html = block[content_start:close_next]
                    span_end = p + len("</span>")
                    li_end = block.find("</li>", span_end)
                    ex_tail = block[span_end:li_end] if li_end != -1 else ""
                    results.append((ex_text_html, ex_tail))
                    pos = li_end + 5 if li_end != -1 else span_end
                    break
                p = close_next + 7
        else:
            break
    return results


def _parse_senses(html: str) -> list[SenseData]:
    """Extract a flat list of senses from any HTML fragment."""
    senses = []
    for block in re.split(r'(?=<li\s[^>]*class="sense")', html):
        if 'class="sense"' not in block:
            continue

        m = re.search(r'sensenum="(\d+)"', block)
        sense_num = int(m.group(1)) if m else None

        # Sense-level CEFR
        m = re.search(r'cefr="(\w+)"', block)
        cefr_level = m.group(1) if m else ""

        m = re.search(r'<span class="grammar"[^>]*>(.*?)</span>', block, re.DOTALL)
        grammar = strip_tags(m.group(1)) if m else ""

        labels = re.findall(r'<span class="labels"[^>]*>(.*?)</span>', block, re.DOTALL)
        labels_text = " ".join(strip_tags(l) for l in labels)

        m = re.search(r'<div class="variants"[^>]*>(.*?)</div>', block, re.DOTALL)
        variants = strip_tags(m.group(1)) if m else ""

        def_inner = extract_span(block, "def")
        definition = strip_tags(def_inner) if def_inner else ""
        if not definition:
            continue

        m = re.search(r'<deft>.*?<chn>(.*?)</chn>.*?</deft>', block, re.DOTALL)
        definition_zh = strip_tags(m.group(1)) if m else ""

        examples = []
        for ex_text_html, ex_tail in _find_examples(block):
            text_plain = strip_tags(ex_text_html)
            if not text_plain:
                continue

            m = re.search(r'<chn>(.*?)</chn>', ex_tail, re.DOTALL)
            text_zh = strip_tags(m.group(1)) if m else ""

            ex_audio = re.findall(r'new Audio\("([^"]+)"\)', ex_tail)
            audio_gb = next((a for a in ex_audio if "_gbs_" in a or "_brs_" in a), "")
            audio_us = next((a for a in ex_audio if "_uss_" in a or "_ams_" in a), "")

            examples.append(ExampleData(
                text_plain=text_plain,
                text_html=ex_text_html,
                text_zh=text_zh,
                audio_gb=audio_gb,
                audio_us=audio_us,
            ))

        senses.append(SenseData(
            sense_num=sense_num,
            cefr_level=cefr_level,
            grammar=grammar,
            labels=labels_text,
            variants=variants,
            definition=definition,
            definition_zh=definition_zh,
            examples=examples,
        ))
    return senses


def _parse_verb_forms(block: str) -> list[VerbFormData]:
    """Extract verb conjugation rows from <table class="verb_forms_table">."""
    forms = []
    for form_attr, content in re.findall(
        r'<tr\b[^>]*\bform="([^"]+)"[^>]*>(.*?)</tr>', block, re.DOTALL
    ):
        td = re.search(r'<td\b[^>]*\bclass="verb_form"[^>]*>(.*?)</td>', content, re.DOTALL)
        label_word = strip_tags(td.group(1)) if td else ""

        m = re.search(r'class="phons_br".*?new Audio\("([^"]+)"\)', content, re.DOTALL)
        audio_gb = m.group(1) if m else ""

        m = re.search(r'class="phons_n_am".*?new Audio\("([^"]+)"\)', content, re.DOTALL)
        audio_us = m.group(1) if m else ""

        if label_word:
            forms.append(VerbFormData(
                form_label=form_attr,
                form_text=label_word,
                audio_gb=audio_gb,
                audio_us=audio_us,
            ))
    return forms


def _extract_unbox(block: str, unbox_type: str) -> list[str]:
    """Extract all unbox sections of a given type from a block."""
    sections = []
    pattern = f'<span class="unbox"[^>]*unbox="{unbox_type}"[^>]*>'
    for m in re.finditer(pattern, block):
        start = m.start()
        # Find matching closing by tracking span depth
        depth, pos = 1, m.end()
        while pos < len(block) and depth > 0:
            open_next = block.find("<span", pos)
            close_next = block.find("</span>", pos)
            if close_next == -1:
                break
            if open_next != -1 and open_next < close_next:
                depth += 1
                pos = open_next + 5
            else:
                depth -= 1
                if depth == 0:
                    sections.append(block[m.end():close_next])
                    break
                pos = close_next + 7
    return sections


def _parse_synonyms(block: str) -> list[SynonymData]:
    """Parse synonym boxes (unbox="synonyms")."""
    results = []
    for section in _extract_unbox(block, "synonyms"):
        # Group title from <span class="closed">...</span>
        m = re.search(r'<span class="closed">([^<]+)</span>', section)
        group_title = m.group(1).strip() if m else ""

        # Synonym words from <ul class="inline"><li class="li">WORD</li>
        for li in re.findall(r'<ul class="inline"[^>]*>(.*?)</ul>', section, re.DOTALL):
            for word_m in re.finditer(r'<li class="li"[^>]*>([^<]+)</li>', li):
                results.append(SynonymData(
                    word=word_m.group(1).strip(),
                    group_title=group_title,
                ))

        # Per-word definitions from deflist
        for li in re.findall(r'<li class="li"[^>]*>\s*<span class="dt">(.*?)</span>\s*<span class="dd">(.*?)</span>', section, re.DOTALL):
            word = strip_tags(li[0]).strip()
            definition = strip_tags(li[1]).strip()
            # Update existing synonym with definition
            for syn in results:
                if syn.word == word and not syn.definition:
                    syn.definition = definition
                    break

    return results


def _parse_word_origin(block: str) -> tuple[str, str]:
    """Parse word origin (unbox="wordorigin"). Returns (text_plain, text_html)."""
    for section in _extract_unbox(block, "wordorigin"):
        # Content is in <span class="body"><span class="p">...</span></span>
        body_m = re.search(r'<span class="body"[^>]*>(.*)', section, re.DOTALL)
        if not body_m:
            continue
        body = body_m.group(1)
        # Extract inner <span class="p"> content
        p_m = re.search(r'<span class="p"[^>]*>(.*?)</span>', body, re.DOTALL)
        if p_m:
            text_html = p_m.group(1).strip()
        else:
            text_html = body.strip()
        text_plain = strip_tags(text_html)
        return text_plain, text_html
    return "", ""


def _parse_word_family(block: str) -> list[WordFamilyData]:
    """Parse word family (unbox="wordfamily")."""
    results = []
    for section in _extract_unbox(block, "wordfamily"):
        for li in re.finditer(r'<span class="p"[^>]*>(.*?)</span>\s*</li>', section, re.DOTALL):
            content = li.group(1)
            wfw = re.search(r'<span class="wfw"[^>]*>([^<]+)</span>', content)
            wfp = re.search(r'<span class="wfp"[^>]*>([^<]+)</span>', content)
            wfo = re.search(r'<span class="wfo"[^>]*>([^<]+)</span>', content)
            if wfw:
                results.append(WordFamilyData(
                    word=wfw.group(1).strip(),
                    pos=wfp.group(1).strip() if wfp else "",
                    opposite=wfo.group(1).strip() if wfo else "",
                ))
    return results


def _parse_collocations(block: str) -> list[CollocationData]:
    """Parse Oxford Collocations Dictionary snippets (unbox="snippet")."""
    results = []
    for section in _extract_unbox(block, "snippet"):
        # Split by inner <span class="unbox"> category headers
        # Skip the first "Oxford Collocations Dictionary" title
        parts = re.split(r'<span class="unbox"[^>]*>', section)
        for part in parts:
            # Category name is the text before the first tag
            cat_m = re.match(r'([^<]+)<', part)
            if not cat_m:
                continue
            category = cat_m.group(1).strip()
            if not category or category.startswith("Oxford") or category.startswith("See"):
                continue
            # Words from <ul class="collocs_list"><li>
            words = []
            for li_m in re.finditer(r'<li class="li"[^>]*>([^<]+)</li>', part):
                w = li_m.group(1).strip()
                if w and w != "…":
                    words.append(w)
            if words:
                results.append(CollocationData(category=category, words=words))
    return results


def _parse_xrefs(block: str) -> list[XrefData]:
    """Parse cross-references (see also, compare)."""
    results = []
    for m in re.finditer(r'<span class="xrefs"[^>]*xt="(\w+)"[^>]*>(.*?)</span>\s*</span>', block, re.DOTALL):
        xref_type = m.group(1)
        content = m.group(2)
        for xh in re.finditer(r'<span class="xh"[^>]*>([^<]+)</span>', content):
            results.append(XrefData(xref_type=xref_type, target_word=xh.group(1).strip()))
    return results


def _parse_phrasal_verbs(block: str) -> list[str]:
    """Parse phrasal verb links from <aside class="phrasal_verb_links">."""
    results = []
    m = re.search(r'<aside class="phrasal_verb_links"[^>]*>(.*?)</aside>', block, re.DOTALL)
    if m:
        for xh in re.finditer(r'<span class="xh"[^>]*>([^<]+)</span>', m.group(1)):
            results.append(xh.group(1).strip())
    return results


def _parse_extra_examples(block: str) -> list[ExtraExampleData]:
    """Parse extra examples (unbox="extra_examples")."""
    results = []
    for section in _extract_unbox(block, "extra_examples"):
        for li in re.finditer(r'<li[^>]*>(.*?)</li>', section, re.DOTALL):
            content = li.group(1)
            # Text from <span class="unx">
            unx = re.search(r'<span class="unx"[^>]*>(.*?)</span>', content, re.DOTALL)
            if not unx:
                continue
            text_html = unx.group(1).strip()
            text_plain = strip_tags(text_html)
            if not text_plain:
                continue
            # Chinese from <chn>
            chn = re.search(r'<chn>(.*?)</chn>', content, re.DOTALL)
            text_zh = strip_tags(chn.group(1)) if chn else ""
            results.append(ExtraExampleData(
                text_plain=text_plain,
                text_html=text_html,
                text_zh=text_zh,
            ))
    return results


def _parse_pos_block(block: str, fallback_headword: str) -> EntryData | None:
    """Parse one <div class="entry"> block."""
    m = re.search(r'<h1\s[^>]*class="headword"[^>]*>([^<]+)</h1>', block)
    headword = m.group(1).strip() if m else fallback_headword

    # Oxford levels from headword <h1> attributes
    h1_tag = re.search(r'<h1\s[^>]*class="headword"[^>]*>', block)
    h1_attrs = h1_tag.group(0) if h1_tag else ""
    ox3000 = 'ox3000="y"' in h1_attrs
    ox5000 = 'ox5000="y"' in h1_attrs

    m = re.search(r'<span class="pos"[^>]*>([^<]+)</span>', block)
    pos = m.group(1).strip() if m else ""

    m = re.search(r'class="phons_br"[^>]*>.*?<span class="phon">([^<]+)</span>', block, re.DOTALL)
    ipa_gb = m.group(1).strip() if m else ""

    m = re.search(r'class="phons_n_am"[^>]*>.*?<span class="phon">([^<]+)</span>', block, re.DOTALL)
    ipa_us = m.group(1).strip() if m else ""

    # Entry-level CEFR from symbols div
    m = re.search(r'<div class="symbols"[^>]*>.*?</div>', block, re.DOTALL)
    cefr_level = ""
    if m:
        cefr_m = re.search(r'data-cefr="(\w+)"', m.group(0))
        if not cefr_m:
            # Fallback: try to find cefr from first sense
            cefr_m = re.search(r'cefr="(\w+)"', block)
        if cefr_m:
            cefr_level = cefr_m.group(1)

    sense_start = min(
        (block.find(t) for t in ('<ol class="sense', '<li class="sense') if block.find(t) != -1),
        default=2000,
    )
    phon_section = block[:sense_start]
    all_audio = re.findall(r'new Audio\("([^"]+)"\)', phon_section)
    audio_gb = next((a for a in all_audio if re.match(r"[^_].*__gb_", a)), "")
    audio_us = next((a for a in all_audio if re.match(r"[^_].*__us_", a)), "")

    groups = []

    # Senses before any shcut-g / idm-g section
    first_section = min(
        (block.find(t) for t in ('<span class="shcut-g"', '<span class="idm-g"') if block.find(t) != -1),
        default=len(block),
    )
    pre_senses = _parse_senses(block[:first_section])
    if pre_senses:
        groups.append(SenseGroupData(senses=pre_senses))

    # Senses grouped under topic headers (shcut-g)
    for shcut in re.findall(
        r'<span class="shcut-g".*?(?=<span class="shcut-g"|<span class="idm-g"|$)',
        block, re.DOTALL,
    ):
        topic_en, topic_zh = "", ""
        h2 = re.search(r'<h2 class="shcut"[^>]*>(.*?)</h2>', shcut, re.DOTALL)
        if h2:
            raw = h2.group(1)
            topic_en = strip_tags(re.sub(r'<shcutt>.*?</shcutt>', '', raw, flags=re.DOTALL))
            chn = re.search(r'<chn>(.*?)</chn>', raw, re.DOTALL)
            topic_zh = chn.group(1).strip() if chn else ""
        senses = _parse_senses(shcut)
        if senses:
            groups.append(SenseGroupData(topic_en=topic_en, topic_zh=topic_zh, senses=senses))

    if not groups:
        return None

    verb_forms = _parse_verb_forms(block) if pos == "verb" else []

    # New fields
    synonyms = _parse_synonyms(block)
    word_origin_plain, word_origin_html = _parse_word_origin(block)
    word_family = _parse_word_family(block)
    collocations = _parse_collocations(block)
    xrefs = _parse_xrefs(block)
    phrasal_verbs = _parse_phrasal_verbs(block)
    extra_examples = _parse_extra_examples(block)

    return EntryData(
        headword=headword,
        pos=pos,
        ipa_gb=ipa_gb,
        ipa_us=ipa_us,
        audio_gb=audio_gb,
        audio_us=audio_us,
        cefr_level=cefr_level,
        ox3000=ox3000,
        ox5000=ox5000,
        groups=groups,
        verb_forms=verb_forms,
        card_type="word",
        synonyms=synonyms,
        word_origin=word_origin_plain,
        word_origin_html=word_origin_html,
        word_family=word_family,
        collocations=collocations,
        xrefs=xrefs,
        phrasal_verbs=phrasal_verbs,
        extra_examples=extra_examples,
    )


def _parse_idioms(block: str) -> list[tuple[EntryData, str]]:
    """One (EntryData, idiom_html) per idiom found in a PoS block."""
    idioms = []
    for idm in re.findall(
        r'<span class="idm-g".*?(?=<span class="idm-g"|$)',
        block, re.DOTALL,
    ):
        m = re.search(r'<span class="idm"[^>]*>(.*?)</span>', idm)
        phrase = strip_tags(m.group(1)) if m else ""
        if not phrase:
            continue
        senses = _parse_senses(idm)
        if not senses:
            continue
        idioms.append((
            EntryData(
                headword=phrase,
                pos="idiom",
                groups=[SenseGroupData(senses=senses)],
                card_type="idiom",
            ),
            idm,  # only the idiom snippet, not the full block
        ))
    return idioms


def parse_entry(html: str) -> list[EntryData]:
    """Return one EntryData per PoS block + one per idiom."""
    m = re.search(r'd:title="([^"]+)"', html)
    fallback = m.group(1) if m else ""

    results = []
    for block in re.split(r'(?=<div class="entry")', html):
        if 'class="entry"' not in block:
            continue
        parsed = _parse_pos_block(block, fallback)
        if parsed:
            parsed.raw_html = block
            results.append(parsed)
        for idiom, idiom_html in _parse_idioms(block):
            idiom.raw_html = idiom_html
            results.append(idiom)
    return results
