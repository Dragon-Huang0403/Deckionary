"""FastAPI preview server for the Spanish dictionary.

Run from repo root:
    uvicorn preview_web.server:app --reload

Goal: render the Spanish dictionary data faithfully so we can judge
content quality before committing to Flutter integration. Pretty UI
is not the point.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from db_es import commons_audio, tts

REPO_ROOT = Path(__file__).resolve().parents[1]
VOX_DB = REPO_ROOT / "vox_es.db"
AUDIO_DIR = REPO_ROOT / "audio_es"
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
STATIC_DIR = Path(__file__).resolve().parent / "static"

app = FastAPI(title="Deckionary ES preview")
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


def _open_db() -> sqlite3.Connection | None:
    if not VOX_DB.exists():
        return None
    db = sqlite3.connect(f"file:{VOX_DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    return db


def _entry_payload(db: sqlite3.Connection, headword: str) -> dict | None:
    row = db.execute(
        "SELECT id, headword, pos, gender, ipa, frequency_tier FROM entries "
        "WHERE LOWER(headword) = LOWER(?) ORDER BY entry_index LIMIT 1",
        (headword,),
    ).fetchone()
    if row is None:
        return None

    entry_id = row["id"]
    sense_groups = []
    for sg in db.execute(
        "SELECT id, topic, topic_en FROM sense_groups "
        "WHERE entry_id = ? ORDER BY sort_order",
        (entry_id,),
    ).fetchall():
        senses = []
        for s in db.execute(
            "SELECT id, sense_num, grammar, labels, definition, definition_en "
            "FROM senses WHERE sense_group_id = ? ORDER BY sort_order",
            (sg["id"],),
        ).fetchall():
            examples = db.execute(
                "SELECT text_plain, text_html, text_en FROM examples "
                "WHERE sense_id = ? ORDER BY sort_order",
                (s["id"],),
            ).fetchall()
            senses.append({**dict(s), "examples": [dict(e) for e in examples]})
        sense_groups.append({**dict(sg), "senses": senses})

    summary_en: list[str] = []
    seen_en: set[str] = set()
    for sg in sense_groups:
        if sg.get("topic") == "English meanings":
            continue
        for t in (sg.get("topic_en") or "").split(";"):
            t = t.strip()
            if t and t.lower() not in seen_en:
                seen_en.add(t.lower())
                summary_en.append(t)
                if len(summary_en) >= 8:
                    break
        if len(summary_en) >= 8:
            break

    seen_pos: set[str] = set()
    pos_parts: list[str] = []
    for raw in (row["pos"] or "").replace(";", ",").split(","):
        p = raw.strip()
        if p and p.lower() not in seen_pos:
            seen_pos.add(p.lower())
            pos_parts.append(p)
    pos_clean = ", ".join(pos_parts)

    return {
        "headword": row["headword"],
        "pos": pos_clean,
        "gender": row["gender"],
        "ipa": row["ipa"],
        "frequency_tier": row["frequency_tier"],
        "summary_en": ", ".join(summary_en),
        "sense_groups": sense_groups,
    }


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    db = _open_db()
    sample = []
    if db is not None:
        sample = [
            r["headword"]
            for r in db.execute(
                "SELECT headword FROM entries ORDER BY RANDOM() LIMIT 12"
            ).fetchall()
        ]
        db.close()
    return templates.TemplateResponse(
        request,
        "index.html",
        {"sample": sample, "db_exists": VOX_DB.exists()},
    )


@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = ""):
    db = _open_db()
    results: list[str] = []
    if db is not None and q.strip():
        results = [
            r["headword"]
            for r in db.execute(
                "SELECT headword FROM entries WHERE headword LIKE ? "
                "ORDER BY LENGTH(headword), headword LIMIT 30",
                (q.strip() + "%",),
            ).fetchall()
        ]
        db.close()
    return templates.TemplateResponse(
        request,
        "search.html",
        {"q": q, "results": results, "db_exists": VOX_DB.exists()},
    )


@app.get("/entry/{headword}", response_class=HTMLResponse)
async def entry(request: Request, headword: str):
    db = _open_db()
    if db is None:
        raise HTTPException(404, f"vox_es.db not built yet — run build_es_db.py first")
    payload = _entry_payload(db, headword)
    db.close()
    if payload is None:
        raise HTTPException(404, f"No entry for '{headword}'")
    return templates.TemplateResponse(
        request, "entry.html", payload
    )


@app.get("/audio/{word}")
async def audio(word: str):
    """Two-tier audio: prefer Wikimedia Commons (real human voice), fall
    back to pre-generated Piper TTS. Sets ``X-Audio-Source`` so the UI
    can mark synthetic audio.
    """
    path = commons_audio.fetch(word)
    source = "wikimedia-commons"
    if path is None:
        path = tts.lookup(word)
        source = "piper-tts"
    if path is None:
        raise HTTPException(404, f"No Spanish audio available for '{word}'")
    media_type = {
        ".wav": "audio/wav",
        ".ogg": "audio/ogg",
        ".oga": "audio/ogg",
        ".mp3": "audio/mpeg",
    }.get(path.suffix.lower(), "application/octet-stream")
    return FileResponse(
        path, media_type=media_type,
        headers={"X-Audio-Source": source},
    )


@app.get("/health")
async def health():
    db = _open_db()
    n_entries = 0
    if db is not None:
        n_entries = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        db.close()
    return {
        "db_path": str(VOX_DB),
        "db_exists": VOX_DB.exists(),
        "entry_count": n_entries,
        "audio_dir": str(AUDIO_DIR),
    }
