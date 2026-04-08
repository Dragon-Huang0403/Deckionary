#!/usr/bin/env python3
"""
Flask web app for browsing the OALD10 dictionary.

Usage:
    python app.py                  # start on port 8000
    python app.py --port 8080      # custom port
"""

import argparse

from flask import Flask, jsonify, render_template, request, Response

from db.query import connect, fuzzy_lookup, get_audio, search

app = Flask(__name__)

DB_PATH = "oald10.db"


def get_db():
    return connect(DB_PATH)


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/search")
def api_search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify([])

    db = get_db()

    # Try exact/fuzzy lookup first
    entries = fuzzy_lookup(db, q)

    # If no exact match, try FTS prefix search
    if not entries:
        entries = search(db, f"{q}*", limit=20)

    results = []
    for e in entries:
        groups = []
        for g in e.groups:
            senses = []
            for s in g.senses:
                examples = []
                for ex in s.examples:
                    examples.append({
                        "text_plain": ex.text_plain,
                        "text_html": ex.text_html,
                        "text_zh": ex.text_zh,
                        "audio_gb": ex.audio_gb,
                        "audio_us": ex.audio_us,
                    })
                senses.append({
                    "sense_num": s.sense_num,
                    "cefr_level": s.cefr_level,
                    "grammar": s.grammar,
                    "labels": s.labels,
                    "variants": s.variants,
                    "definition": s.definition,
                    "definition_zh": s.definition_zh,
                    "examples": examples,
                    "xrefs": [
                        {"xref_type": x.xref_type, "target_word": x.target_word}
                        for x in s.xrefs
                    ],
                })
            groups.append({
                "topic_en": g.topic_en,
                "topic_zh": g.topic_zh,
                "senses": senses,
                "xrefs": [
                    {"xref_type": x.xref_type, "target_word": x.target_word}
                    for x in g.xrefs
                ],
            })

        verb_forms = [
            {
                "form_label": vf.form_label,
                "form_text": vf.form_text,
                "audio_gb": vf.audio_gb,
                "audio_us": vf.audio_us,
            }
            for vf in e.verb_forms
        ]

        results.append({
            "headword": e.headword,
            "pos": e.pos,
            "ipa_gb": e.ipa_gb,
            "ipa_us": e.ipa_us,
            "audio_gb": e.audio_gb,
            "audio_us": e.audio_us,
            "cefr_level": e.cefr_level,
            "ox3000": e.ox3000,
            "ox5000": e.ox5000,
            "groups": groups,
            "verb_forms": verb_forms,
            "card_type": e.card_type,
            "synonyms": [
                {"word": s.word, "group_title": s.group_title, "definition": s.definition}
                for s in e.synonyms
            ],
            "word_origin": e.word_origin,
            "word_origin_html": e.word_origin_html,
            "word_family": [
                {"word": wf.word, "pos": wf.pos, "opposite": wf.opposite}
                for wf in e.word_family
            ],
            "collocations": [
                {"category": c.category, "words": c.words}
                for c in e.collocations
            ],
            "xrefs": [
                {"xref_type": x.xref_type, "target_word": x.target_word}
                for x in e.xrefs
            ],
            "phrasal_verbs": e.phrasal_verbs,
            "extra_examples": [
                {"text_plain": ex.text_plain, "text_html": ex.text_html, "text_zh": ex.text_zh}
                for ex in e.extra_examples
            ],
        })

    db.close()
    return jsonify(results)


@app.route("/api/audio/<path:filename>")
def api_audio(filename):
    db = get_db()
    data = get_audio(db, filename)
    db.close()
    if data is None:
        return Response("Not found", status=404)
    return Response(data, mimetype="audio/mpeg")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    app.run(port=args.port, debug=args.debug)
