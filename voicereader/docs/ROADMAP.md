# VoiceReader — Flutter App Roadmap (step-by-step, one phase per PR)

> Rule: **no phase starts before the previous one is merged with green CI.** Each phase ends with something you can demo. Code is written only after you approve `ARCHITECTURE.md` + `design/`.

## Phase 0 — Repo tidy + scaffold + CI gate (PR #1)
- [ ] Move web MVP → `voicereader/web/` (per Q2 decision); keep `tts_chunks.py` untouched
- [ ] `flutter create voicereader/app --org com.voicereader --platforms android` (iOS folder kept)
- [ ] `.fvmrc` pin latest stable; `.gitignore` for Flutter; dependabot for pub
- [ ] `analysis_options.yaml` (very_good_analysis, strict-casts/inference), `build.yaml`
- [ ] `.github/workflows/ci.yml` + `release.yml` (see ARCHITECTURE §10) — **CI green on empty app**
- [ ] Bundle id `com.voicereader.app` (Q4), minSdk 23, targetSdk 35
- **DoD:** PR merged; Actions tab shows green lint+test+debug-APK build.

## Phase 1 — Core domain + failures + sentence splitter (PR #2)
- [ ] `core/result`, `core/error` (sealed `AppFailure`), `core/utils` (ULID, debounce)
- [ ] `SplitIntoSentencesUseCase` — port of `tts_chunks.py` rules; ≥20 unit tests PASS (EN/TK/RU/TR, ellipses, abbreviations, quotes, decimals, newlines, CRLF, Turkmen "·" separators)
- [ ] Crash-free test harness: `ProviderScope` overrides helper
- **DoD:** coverage domain ≥ 80%; splitter outputs verified against Python implementation on identical inputs (golden test vectors).

## Phase 2 — Data layer: drift DB + document repository (PR #3)
- [ ] drift schema v1 (`documents`, `document_text`, `settings`, `purchase_state`) + migrations + in-memory test DB
- [ ] `platform/file_service.dart` — import copy, SHA-256, path management
- [ ] `DocumentLocalDatasource`, `DocumentRepositoryImpl` → `Result<T>`; dedupe-on-import test
- [ ] `ImportPdfUseCase` / `ImportTextUseCase` wired to pdfrx text extraction (behind `PdfTextExtractor` interface + fake for tests)
- **DoD:** repo tests green incl. migration test; files persist across restarts (integration smoke in debug APK).

## Phase 3 — Playback engine (PR #4)
- [ ] `TtsEngine` interface; `FlutterTtsEngine` (flutter_tts): voices list, setVoice/rate/pitch/volume, speak, pause, stop, handlers → highlight events
- [ ] `PlaybackController` (Riverpod `Notifier<ReaderSession>`): start/pause/resume/stop/skipTo; sentence stream; completion → next sentence; error skip policy
- [ ] `FakeTtsEngine` for deterministic tests (playback order, pause mid-sentence, completion cascade)
- **DoD:** playback unit tests green; manual checklist on device: voice quality sweep, rate 0.5–2.0

## Phase 4 — Library UI (PR #5)
- [ ] Theme system (§8) + app shell + typed routes (go_router_builder)
- [ ] `LibraryScreen`: search, empty state, `DocumentListTile` with progress, swipe-to-delete + confirm, FAB → file picker (PDF/TXT/MD), import feedback + open
- **DoD:** widget tests (empty/list/delete) green; import→appears-in-list flow works on device.

## Phase 5 — Reader UI + highlighting (PR #6)
- [ ] `ReaderScreen`: `SelectableText.rich`, per-sentence spans, tap-to-jump, coral highlight on active sentence, auto-scroll (nearest, respects manual scroll)
- [ ] `PlaybackBar`: play/pause/stop, ±1 sentence, rate chip cycling 0.8/1.0/1.2/1.5/2.0, voice label
- [ ] Reading position persisted (debounced) and restored on open; progress shown in Library
- **DoD:** highlight stays ≤16ms behind TTS on mid-range Android; 2M-char document scrolls at 60fps.

## Phase 6 — Pro paywall (PR #7)
- [ ] `ProScreen` exactly per `design/03_pro_paywall.png`; `purchases`/backend-less `in_app_purchase` integration: query, buy (non-consumable "pro_lifetime" $19), verify, `restorePurchases`, pending-purchase consumption
- [ ] Entitlement cached in drift + checked on app start & on resume; gate: free tier 1,500 chars/doc + library save locked (same rules as web MVP)
- [ ] License-testing: Play license testers list; RTDN not needed for one-time product (note in docs)
- **DoD:** purchase flow succeeds on internal-testing track with a license tester account; "restore" works after reinstall.

## Phase 7 — Settings + voices + appearance (PR #8)
- [ ] `SettingsScreen` per mockup: voice picker (grouped by locale, local-engine first), speed/pitch sliders, highlight toggle, text-size, dark theme (forced), About/privacy/licenses pages
- [ ] Settings persisted via drift KV; applied app-wide via provider
- **DoD:** settings survive restart; TalkBack pass on both screens.

## Phase 8 — Polish + release prep (PR #9)
- [ ] App icon (adapt icon.png), splash, Play Store assets (feature graphic 1024×500, phone screenshots of the 4 screens, privacy policy page — host on GitHub Pages)
- [ ] Crash reporting: Firebase Crashlytics behind `--dart-define=ENABLE_CRASHLYTICS=true` (optional, default off)
- [ ] `release.yml` tag build → AAB; internal testing track
- [ ] Beta: 10 testers (you + friends) → 2 weeks bug bash → production staged rollout (10% → 100%)
- **DoD:** v1.0.0 live on Play internal/production track.

## Backlog (post-v1, DO NOT START YET)
iOS build + TestFlight · background/lock-screen playback (audio_service + notification controls) · sleep timer · auto-scroll pacing modes · export highlights · 10-language marketing landing refresh · short-drama/TTS Pro tier

---

## 0. Questions blocking Phase 0 (answer in chat)
1. **Platform scope** — Android-only v1 / Android+iOS / (+desktop later)?
2. **Repo tidy-up** — A) `voicereader/web/` archive + Flutter in `voicereader/app/` (recommended) · B) Flutter replaces `voicereader/` entirely, web deleted · C) new `voicereader_flutter/`, web untouched
3. **Monetization** — Play Billing one-time $19 (recommended, policy-compliant) · subscription $4.99/mo · free + ads (AdMob)
4. **Identity** — bundle id `com.voicereader.app`? min SDK 23? App name "VoiceReader"?
5. **Approval** — architecture (ARCHITECTURE.md) + 4 designs OK? Changes requested?
