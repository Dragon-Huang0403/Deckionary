<div align="center">

# Deckionary

**Your Oxford dictionary, your flashcards, one app.**

A dictionary and vocabulary learning app powered by the Oxford Advanced Learner's Dictionary (OALD10) with spaced repetition, instant search, and cross-device sync.

[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Android-blue)](#)
[![License](https://img.shields.io/badge/License-Private-lightgrey)](#)

[Download](#download) · [Features](#features) · [繁體中文](#繁體中文)

</div>

---

<!-- Replace these placeholders with actual screenshots -->

<p align="center">
  <img src="docs/screenshots/dictionary.png" width="260" alt="Dictionary search" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/review.png" width="260" alt="Spaced repetition review" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/quick-search.png" width="260" alt="macOS Quick Search" />
</p>

---

## Features

### Full Oxford Dictionary at Your Fingertips
Look up any word and get complete OALD10 entries — definitions, example sentences, pronunciations (US & GB), verb forms, collocations, synonyms, word families, and more. Oxford 3000/5000 and CEFR level badges help you focus on the words that matter.

### Learn with Spaced Repetition
Built-in FSRS flashcard system schedules your reviews at the optimal time. Rate each card (Again / Hard / Good / Easy) and the algorithm adapts to your memory. Set daily limits for new cards and reviews to match your pace.

### Instant Search on macOS
Press **Cmd+Shift+D** from any app to pop up the dictionary — no need to switch windows. It even reads your clipboard so you can copy a word and look it up in one shortcut. Works across all desktops and displays.

### Sync Across Devices
Sign in with Google and your search history, flashcard progress, and settings follow you everywhere. Works offline first — everything syncs when you're back online.

### Listen and Pronounce
Tap to hear US or British pronunciation for headwords, verb forms, and example sentences. Enable auto-pronounce to hear every word as you search or review.

## Download

Get the latest release from [GitHub Releases](https://github.com/XuanLongHuang/oxford-5000-to-anki/releases):

- **macOS** — `.zip` (universal binary)
- **Android** — `.apk`
- **iOS** — coming soon

---

## 繁體中文

<div align="center">

**你的牛津詞典，你的單字卡，一個 App 搞定。**

以《牛津高階英漢雙解詞典》第十版為基礎，結合間隔重複學習、即時查詢與跨裝置同步的詞典學習 App。

</div>

<!-- 請將以下替換為實際截圖 -->

<p align="center">
  <img src="docs/screenshots/dictionary.png" width="260" alt="詞典搜尋" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/review.png" width="260" alt="間隔重複複習" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/quick-search.png" width="260" alt="macOS 快速搜尋" />
</p>

### 完整牛津詞典，隨手可查
查詢任何單字，獲得完整的 OALD10 詞條——定義、例句、發音（美式與英式）、動詞變化、搭配詞、同義詞、詞彙家族等。Oxford 3000/5000 與 CEFR 等級標示幫助你專注在最重要的詞彙上。

### 間隔重複，高效記憶
內建 FSRS 演算法在最佳時機安排複習。每張卡片以「重來 / 困難 / 良好 / 簡單」評分，系統自動適應你的記憶曲線。可自訂每日新卡與複習數量上限，照自己的步調學習。

### macOS 即時查詢
在任何應用程式中按下 **Cmd+Shift+D** 即可彈出詞典視窗，無需切換畫面。支援剪貼簿自動搜尋——複製一個單字，按快捷鍵就能查詢。跨桌面、跨螢幕皆可使用。

### 跨裝置同步
使用 Google 帳號登入，搜尋紀錄、單字卡進度與設定在所有裝置間自動同步。離線優先架構——一切資料在恢復網路後自動同步。

### 聆聽與發音
點擊即可聽取美式或英式發音，支援詞條、動詞變化與例句音檔。開啟自動發音，搜尋或複習時每個單字都會自動朗讀。

### 下載

前往 [GitHub Releases](https://github.com/XuanLongHuang/oxford-5000-to-anki/releases) 取得最新版本：

- **macOS** — `.zip`（通用二進位）
- **Android** — `.apk`
- **iOS** — 即將推出

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
anki/                   # Python: Anki deck generator
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
pip install genanki flask opencc-python-reimplemented

python build_db.py          # Build oald10.db from macOS dictionary bundle
python app.py --port 8000   # Web dictionary browser
python anki/create_deck.py --5000  # Generate Anki deck
```

See `docs/` for detailed guides on the database schema, R2 export, and Anki generation.

</details>
