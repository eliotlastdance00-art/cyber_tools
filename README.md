# VoiceReader

Private, on-device **PDF & text-to-speech** reader for Android — built with Flutter.
No cloud, no accounts, no tracking: your documents are read aloud by the OS speech engine, fully offline.

> **Status: Phase 0 — scaffold + CI.** Roadmap with acceptance criteria: [docs/ROADMAP.md](docs/ROADMAP.md) · Architecture (Clean Architecture, feature-first, Riverpod 3, drift): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · UI designs: [design/](design/)

## Build & test

Prerequisites: Flutter 3.47.9 (see `.fvmrc`) · Android SDK 36 · JDK 17 · Gradle 9.3.1 (auto-downloaded by the wrapper).

```bash
fvm install          # or use system Flutter 3.47.9
fvm flutter pub get
fvm flutter test
fvm flutter build apk --debug
fvm flutter run
```

> First `flutter build`/`flutter run` auto-injects `gradlew` + `gradle-wrapper.jar`
> (from the Flutter SDK cache) into `android/` — they are intentionally not committed.

CI (`.github/workflows/ci.yml`) runs on every push/PR: pinned Flutter via `.fvmrc`, `dart format` check, `flutter analyze --fatal-infos`, `flutter test --coverage`, and a debug APK build (artifact). Releases: tag `v*` → `release.yml` builds an App Bundle (see file for Play Console signing secrets).

## License

Proprietary — all rights reserved.
