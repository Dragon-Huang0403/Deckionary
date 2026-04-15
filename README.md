<div align="center">

# Deckionary

**Your Oxford dictionary, your flashcards, one app.**

A dictionary and vocabulary learning app powered by the Oxford Advanced Learner's Dictionary (OALD10) with spaced repetition, instant search, and cross-device sync.

[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Android-blue)](#)
[![License](https://img.shields.io/badge/License-Private-lightgrey)](#)

[Download](#download) · [Features](#features) · [繁體中文](README.zh-TW.md)

</div>

---

<!-- Replace these placeholders with actual screenshots -->

<p align="center">
  <img src="docs/screenshots/dictionary.png" width="200" alt="Dictionary search" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/learning.png" width="200" alt="Spaced repetition review" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/review.png" width="200" alt="Reivew process" />
</p>

---

## Features

### Full Oxford Dictionary at Your Fingertips
Look up any word and get complete OALD10 entries — definitions, example sentences, pronunciations (US & GB), verb forms, collocations, synonyms, word families, and more. Oxford 3000/5000 and CEFR level badges help you focus on the words that matter.

### Learn with Spaced Repetition
<p align="center">
  <img src="docs/screenshots/spaced_repetition.png" width="600" alt="Hotkey instant search" />
</p>
Built-in FSRS flashcard system schedules your reviews at the optimal time. Rate each card (Again / Hard / Good / Easy) and the algorithm adapts to your memory. Set daily limits for new cards and reviews to match your pace.

### Instant Search on macOS
<p align="center">
  <img src="docs/screenshots/hotkey.png" width="600" alt="Hotkey instant search" />
</p>
Press **Cmd+Shift+D** from any app to pop up the dictionary — no need to switch windows. It even reads your clipboard so you can copy a word and look it up in one shortcut. Works across all desktops and displays.

### Sync Across Devices
Sign in with Google and your search history, flashcard progress, and settings follow you everywhere. Works offline first — everything syncs when you're back online.

### Listen and Pronounce
Tap to hear US or British pronunciation for headwords, verb forms, and example sentences. Enable auto-pronounce to hear every word as you search or review.

## Download

Get the latest release from [GitHub Releases](https://github.com/Dragon-Huang0403/Deckionary/releases):

- **macOS** — `.zip` (universal binary)
- **Android** — `.apk`
- **iOS** — coming soon

### macOS Installation

The app is not code-signed, so macOS will block it on first launch:

1. Download **Deckionary-macOS.zip** from the [latest release](https://github.com/Dragon-Huang0403/Deckionary/releases/latest)
2. Extract and move **Deckionary.app** to `/Applications`
3. Double-click to open — a warning will appear saying the app can't be opened. Click **Done** (do not move to Trash)
4. Go to **System Settings > Privacy & Security**, scroll down to find the blocked message for **Deckionary**, and click **Open Anyway**
5. A confirmation dialog will appear — click **Open**

You only need to do this once. Future launches will open normally.

---

## Development

### Prerequisites

Place `oald10.db` in `app/assets/` before building:

```bash
# Option A: Copy from project root (after running build_db.py)
cp oald10.db app/assets/oald10.db

# Option B: Download from R2
curl -o app/assets/oald10.db \
  https://r2.deckionary.com/db/oald10.db
```

The file is ~93 MB and not checked into git.

### Build & Run

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env.json
```

Without `env.json`, the app runs in local-only mode (no sync).

### Project Structure

```
app/
  lib/
    features/
      dictionary/       # Search, autocomplete, entry display
      review/           # FSRS spaced repetition
      settings/         # App configuration
    core/
      database/         # Drift ORM, DAOs
      audio/            # Pronunciation playback & caching
      sync/             # Supabase sync service
  macos/                # macOS-specific (hotkey, tray, window)
  ios/                  # iOS target
  android/              # Android target

db/                     # Python: SQLite schema, parser, importer
scripts/                # R2 export & upload
docs/                   # Guides
```

### Architecture

- **State management** — Riverpod
- **Database** — Drift (SQLite ORM). Two databases: read-only dictionary (`oald10.db`) + read-write user data
- **Spaced repetition** — FSRS-4.5 via the `fsrs` package
- **Audio** — just_audio with SQLite-backed offline cache
- **Sync** — Firebase Auth (Google Sign-in) + Supabase (data storage, RLS)
- **Routing** — go_router

<details>
<summary><strong>Firebase & Supabase Setup</strong> (required only for sync)</summary>

#### Firebase

```bash
dart pub global activate flutterfire_cli
cd app
flutterfire configure
```

This generates `lib/firebase_options.dart` (gitignored). Enable **Authentication > Google** in the [Firebase Console](https://console.firebase.google.com).

#### Google Sign-In (macOS)

Create an **iOS OAuth client ID** in [Google Cloud Console > Credentials](https://console.cloud.google.com/apis/credentials) with bundle ID `com.deckionary.deckionary`. Add the client ID to `macos/Runner/Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

#### Supabase

```bash
cp env.example.json env.json
```

Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from **Supabase Dashboard > Settings > API**.

Enable **Firebase** as a third-party auth provider in **Supabase Dashboard > Auth > Third-party providers**.

Apply migrations:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

#### macOS Signing

```bash
open macos/Runner.xcodeproj
```

In Xcode: **Runner target > Signing & Capabilities > Automatically manage signing > select Team**. Same for **RunnerTests**.

</details>

<details>
<summary><strong>Python Tools</strong></summary>

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install flask opencc-python-reimplemented

python build_db.py          # Build oald10.db from macOS dictionary bundle
python app.py --port 8000   # Web dictionary browser
```

See `docs/` for detailed guides on the database schema and R2 export.

</details>
