# VoiceReader — Flutter App Architecture

> Status: **PROPOSAL — not approved yet. No code will be written until this document and the designs in `design/` are accepted.**
> Author: engineering proposal · Date: 2026-11-10 · Product: VoiceReader (native Android/iOS reader that speaks PDF & text; successor to the `voicereader/` web MVP)

---

## 1. Goals and non-goals

**Goals**
- Native Flutter app, Android-first, iOS-ready. Fast (60fps lists, lazy sentence rendering), advanced engineering (typed everything, CI-gated), and **not a toy**.
- Offline-first and privacy-first: documents and audio never leave the device; TTS uses the OS engine.
- One-time-payment Pro entitlement via **Google Play Billing** (non-consumable), with `Restore purchase`.
- Test-driven from Phase 1; every PR merges only with green CI.

**Non-goals (v1)**
- No cloud OCR, no server, no account system, no subscriptions.
- No audiobook download/store, no social features.
- Windows/desktop builds (pdfrx can do it, but release signing/testing is out of scope until Android is stable).

**Honesty box**
- The Flutter SDK is **not installed in this working sandbox** (and the sandbox cannot reach Google's SDK hosts). All build/test verification will happen in **GitHub Actions** on your GitHub repo (this is precisely why we use Actions from day one). I will not claim "it compiles" without a green CI run.
- Google Play does **not permit Gumroad checkout for digital goods consumed in-app**. Play Billing is mandatory for the in-app Pro unlock on Play distribution. Gumroad stays only for the web version.
- TTS voice quality depends on the device OEM engine; we cannot ship custom voices without huge cost — we pick the best available system voice automatically.

---

## 2. Research summary (why this stack)

2026 community consensus (see sources at the bottom):

| Decision | Choice | Why |
|---|---|---|
| State / DI | **Riverpod 3 + `riverpod_generator`** | Compile-safe, context-free DI, de-facto standard; no `get_it` needed |
| Routing | **go_router + `go_router_builder`** (typed routes) | Official recommendation; type-safe, deep links, testable redirects |
| Models | **freezed 3 + json_serializable** | Sealed classes, `copyWith`, pattern matching — no hand-written boilerplate |
| Local DB | **drift** (SQLite) | Typed SQL, migrations, in-memory test DB; beats Hive for relations/progress queries |
| i18n | **slang** (type-safe) | Compile-time checked keys vs. fragile intl strings |
| PDF | **pdfrx** (PDFium, MIT) — text + render | 2025–2026 community top pick; Syncfusion rejected (commercial license at scale) |
| PDF fallback | `syncfusion_flutter_pdf` text extractor | Only if pdfrx text quality fails on real files (community license free < $1M rev, ≤5 devs) |
| Speech | **flutter_tts** | Wraps Android TextToSpeech / iOS AVSpeechSynthesizer; offline, zero API cost |
| Purchases | **in_app_purchase** (Play Billing) | Policy-required for digital goods on Play; `PurchaseStatus.purchased`, non-consumable |
| Lints | **very_good_analysis** + strict casts/inference | Machine-enforceable strictness |
| Testing | **flutter_test + mocktail + integration_test** | Widget tests for UI, unit tests for logic, emulator job in CI |
| CI | **GitHub Actions** (`subosito/flutter-action` + `.fvmrc`) | Reproducible SDK pin, coverage gate ≥ 80% domain+data |
| SDK pin | **fvm** (`.fvmrc` committed) | "Works on my machine" is not acceptable |

Alternatives considered and rejected: BLoC (heavier for solo dev, Riverpod chosen), Hive (weaker queries/migrations; drift used instead), get_it (riverpod already does DI), WebView wrapper of the web MVP (not "advanced", poor UX), commercial PDF SDKs (cost), Stripe/Gumroad in-app (Play policy violation).

---

## 3. Repository layout (proposal — pending your decision Q2)

```
cyber_tools/
├─ tts_chunks.py, tests/, requirements.txt …   # existing Python CLI — untouched
├─ voicereader/
│   ├─ web/            # current web MVP moved here (landing + web reader) — archive, not deleted
│   ├─ app/            # ⬅️ NEW: Flutter package (the product)
│   ├─ design/         # UI mockups (01_library_home.png … 04_settings.png)
│   ├─ docs/           # THIS FILE + ROADMAP.md
│   ├─ SELL.md         # web sales playbook (unchanged)
│   └─ tools/          # release-zip script for the web version
└─ .github/workflows/  # ci.yml (PR gates) + release.yml (tag → AAB)
```

Nothing is deleted until you approve. The web MVP keeps working unchanged at its current URLs.

---

## 4. Architecture: feature-first Clean Architecture

Dependency rule (strict, enforced by review + custom_lint later):

```
presentation  ─┐
               ▼
data ────────► domain ◄── (domain imports NOTHING from Flutter/plugins)
               ▲
core (Result, Failures, constants) — shared by all layers
```

```
lib/
├─ main.dart                    # ProviderScope, error zone, runApp
├─ app.dart                     # MaterialApp.router + theme + l10n
├─ core/
│   ├─ error/failure.dart       # sealed AppFailure: Storage, Pdf, Tts, Purchase, Validation, Permission
│   ├─ result/result.dart       # sealed Result<T> = Ok<T> | Err<AppFailure>
│   ├─ platform/file_service.dart # copy import → app docs dir (path_provider)
│   ├─ theme/                   # ColorScheme (navy/coral/teal), ThemeExtension, typography
│   └─ utils/                   # debounce, formatters, ulid
├─ features/
│   ├─ library/
│   │   ├─ domain/   entities/document.dart · repositories/document_repository.dart · usecases/…
│   │   ├─ data/     datasources/document_local_datasource.dart (drift) · models/document_dto.dart · repositories/document_repository_impl.dart
│   │   └─ presentation/ library_screen.dart · widgets/document_list_tile.dart · providers/library_provider.dart
│   ├─ reader/                  # same 3 layers: ReaderScreen, SentenceText (highlight), providers
│   ├─ playback/                # domain: TtsEngine interface + PlaybackController; data: FlutterTtsEngine; presentation: PlaybackBar widget + provider
│   ├─ pro/                     # domain: ProEntitlement entity, PurchaseRepository iface, usecases (CheckPro, PurchasePro, RestorePurchases);
│   │                           # data: PlayBillingPurchaseDataSource (in_app_purchase); presentation: ProScreen (paywall), restore button
│   └─ settings/                # voice, rate, pitch, highlight-on, text-scale — drift settings KV; SettingsScreen
└─ shared/widgets/              # ProgressRing, EmptyState, AppButton, etc.
```

**Rules**
- Domain = pure Dart. No `package:flutter`, no plugins. Entities are freezed; failures are sealed.
- Data depends on domain interfaces; repositories catch all exceptions → `Result<T>`; never throw across layers.
- Presentation = widgets + Riverpod notifiers only. No business logic in widgets.
- Navigation = typed routes only (`go_router_builder`): `LibraryRoute`, `ReaderRoute(docId)`, `ProRoute`, `SettingsRoute`.
- Every I/O behind an interface (`DocumentRepository`, `TtsEngine`, `PurchaseDataSource`) → swappable fakes in tests.

---

## 5. Domain model (freezed sketch)

```dart
@freezed sealed class DocumentSource with _$DocumentSource {
  const factory DocumentSource.pdf(String relativePath, {String? sha256}) = PdfSource;
  const factory DocumentSource.text(String storageKey) = TextSource;
}

@freezed sealed class ReadingDocument with _$ReadingDocument {
  const factory ReadingDocument({
    required String id,                 // ULID
    required String title,
    required DocumentSource source,
    required int charCount,
    required DateTime addedAt,
    required DateTime lastOpenedAt,
    int? lastSentenceIndex,             // reading position
    double get progress => …            // derived
  }) = _ReadingDocument;
}

@freezed sealed class Sentence with _$Sentence {
  const factory Sentence({required int index, required String text,
                          required int startChar, required int endChar}) = _Sentence;
}

@freezed sealed class VoiceProfile with _$VoiceProfile {
  const factory VoiceProfile({required String id, required String language,
    required String name, required bool isLocalEngine}) = _VoiceProfile;
}

@freezed sealed class ProEntitlement with _$ProEntitlement {
  const factory ProEntitlement.free() = Free;
  const factory ProEntitlement.pro({required EntitlementSource source, DateTime? purchasedAt}) = Pro;
}

enum PlaybackStatus { idle, playing, paused, completed, error }

@freezed sealed class ReaderSession with _$ReaderSession {
  const factory ReaderSession({required String documentId,
    @Default(0) int currentSentenceIndex,
    @Default(PlaybackStatus.idle) PlaybackStatus status,
    @Default(1.0) double rate,
    @Default(1.0) double pitch,
    String? voiceId}) = _ReaderSession;
}
```

---

## 6. Use cases (all return `Result<T>`; unit-tested)

**library/** — `ImportPdfUseCase` (copy→app dir, extract text via pdfrx, insert row, return doc) · `ImportTextUseCase` · `GetLibraryUseCase` (stream + search filter) · `DeleteDocumentUseCase` (row + files) · `GetReaderDocumentUseCase`
**reader/** — `SplitIntoSentencesUseCase` (port of `tts_chunks.py`: sentence regex, abbreviation guards, ellipses, quotes, CJK punctuation; keeps paragraphs) · `UpdateReadingPositionUseCase` (debounced, writes only on change ≥ 1 sentence)
**playback/** — `GetVoicesUseCase` · `StartPlaybackUseCase(docId, fromSentence?)` · `PausePlaybackUseCase` · `ResumePlaybackUseCase` · `StopPlaybackUseCase` · `SkipToSentenceUseCase(index)` — controller drives `TtsEngine` and emits `ReaderSession` stream; `onStart(sentence)`/`onComplete` wire highlight
**pro/** — `CheckProEntitlementUseCase` (drift cache + Billing query) · `PurchaseProUseCase` (launchBillingFlow, verify purchase, mark owned) · `RestorePurchasesUseCase` · `ConsumePendingPurchasesUseCase`
**settings/** — `GetSettingsUseCase` · `SaveVoiceSettingsUseCase` · `SaveAppearanceUseCase`

---

## 7. Data layer details

**drift tables**
```sql
documents(id TEXT PK, title TEXT, source_type TEXT, source_ref TEXT, char_count INT,
          added_at INT, last_opened_at INT, last_sentence_index INT NULL);
document_text(doc_id TEXT PK REFERENCES documents, plain_text TEXT);   -- cached extraction
settings(key TEXT PK, value TEXT);                                      -- JSON values
purchase_state(key TEXT PK, value TEXT);                                -- cached entitlement
```
- Migrations via drift `MigrationStrategy` from v1; `SchemaVerifier` in tests; in-memory `NativeDatabase.memory()` for repo tests.
- Imported files copied under `path_provider` app-docs/`books/` with ULID filenames; SHA-256 for dedupe on import (re-import of same file → opens existing doc, no duplicates).
- Reading position written with debounce 500 ms; flushed on `AppLifecycleState.paused`.

---

## 8. Presentation layer & design system

- Screens (mapped 1:1 to `design/` mockups): `LibraryScreen` (search + list + FAB import + progress ring on tile), `ReaderScreen` (text with tappable, highlighted sentences + `PlaybackBar`), `ProScreen` (lifetime paywall, `Restore purchase`), `SettingsScreen` (voice/speed/pitch/highlight/appearance).
- Material 3, dark-navy first: `ColorScheme.fromSeed` overridden with brand tokens — `navy #0b1b33`, `coral #ff6b4a`, `teal #2dd4bf`; `ThemeExtension<AppTokens>` for spacing/radii; Inter/system text; dynamic color disabled.
- Accessibility: `Semantics` labels on all controls, min 48dp targets, TalkBack verified, text-scale clamped 0.8–1.3.
- Performance: `ListView.builder` + `RepaintBoundary` per sentence span is NOT possible for RichText — instead: chunked paragraph widgets, `TextSpan` highlight via `SelectableText.rich` rebuilt only on sentence index change; long docs (>2M chars) stream paragraphs lazily.

---

## 9. Testing strategy (gates on every PR)

| Layer | Tool | Examples / gate |
|---|---|---|
| Domain | flutter_test + mocktail | Sentence splitter: ≥20 cases (EN/TK/RU/TR, «…», quotes, newlines, decimals "3.5", "e.g."); position debounce; entitlement transitions |
| Data | drift in-memory + mocktail | Repo CRUD, migration v1→n, dedupe by sha256, file-copy failure → typed `StorageFailure` |
| Playback | FakeTtsEngine | Play→highlight seq, pause/resume, skip mid-utterance, error recovery, completion event |
| Widget | flutter_test | Empty library, tile rendering, paywall locked/unlocked, settings toggles |
| Golden | matchesGoldenFile | PlaybackBar (phone + large text) |
| Integration | integration_test (Android emulator job, manual trigger) | import → play → pause → restore-purchase flow |

**Gates:** `very_good_analysis` with `strict-casts`/`strict-inference`, `dart format` check, `flutter analyze --fatal-infos`, coverage of `lib/domain`+`lib/data` ≥ **80%** (`very_good_coverage`), zero failing tests. Emulator job optional v1.

---

## 10. CI/CD — `.github/workflows/`

**ci.yml** (on PR + push to `main`/`arena/**`):
1. checkout → `subosito/flutter-action@v2` with `flutter-version-file: voicereader/app/.fvmrc` (channel stable, exact pin committed)
2. cache `~/.pub-cache` keyed on pubspec.lock; `flutter pub get`
3. `dart run build_runner build --delete-conflicting-outputs` (drift/freezed/riverpod codegen must be reproducible)
4. `dart format . --output=none --set-exit-if-changed`
5. `flutter analyze --fatal-infos`
6. `flutter test --coverage` → upload to Codecov-or-artifact; `very_good_coverage --min-coverage 80` on domain+data
7. `flutter build apk --debug` → artifact `voicereader-debug-apk` (proves the app actually builds)

**release.yml** (on tag `v*`): `flutter build appbundle --release`, AAB + SHA-256 artifact, changelog from tag; Play upload is a commented-out step you enable with `PLAY_SERVICE_ACCOUNT_JSON` secret (supply via fastlane or `r0adkll/upload-google-play`). Never commit keystores; `android/key.properties` → `.gitignore`d, injected via CI secrets.

Plus: Dependabot (pub ecosystem, weekly), PR template (checklist: tests added? screenshots? changelog?), branch protection on `main` (1 review + green CI).

**Pending decisions that affect CI:** repo root for Flutter package (Q2), bundle id (`com.voicereader.app` proposed), min SDK 23 / target SDK 35, iOS left unbuilt.

---

## 11. Sources

- DEV Community, "Modern Flutter Best Practices for 2026" (Riverpod 3, go_router typed routes, freezed 3, fvm, strict lint) — dev.to/hamberluo/modern-flutter-best-practices-for-2026-56o3
- LobeHub agents-opencode Flutter rules (feature-first, sealed Result, Riverpod codegen, widgets-only-in-UI)
- pub.dev / fluttertrends.dev — pdfrx v2.5.0 (MIT, PDFium, ~15K downloads/day, Aug–Sep 2026); pdfx #5
- r/FlutterDev + desarrollolibre PDF comparison (2025-11): pdfrx recommended; Syncfusion license caveat
- GitHub community clean-architecture templates (heygourab/flutter_clean_architecture, sgaabdu4/building-flutter-apps)
- RevenueCat State of Subscription Apps 2026 (category economics — carried over into product pricing decision)
- Google Play Payments policy + Play Billing for digital goods (Subscriptions/IAP) — Gumroad in-app rejected

---

## 12. Explicit open questions (need YOUR answers — see ROADMAP §0)

1. Platform scope: Android-only v1 / Android+iOS / +desktop later
2. Repo tidy-up: option A/B/C in Q2 (what gets moved/deleted)
3. Monetization: Play Billing non-consumable $19 (recommended) vs subscription vs free+ads
4. Bundle id & app name ("VoiceReader" is fine?) and min Android version (23?)
5. Do you approve the 4 designs in `design/` and this architecture? (approval gate before Phase 0)
