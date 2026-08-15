# CHERIFLIX

CHERIFLIX is a Windows-first Flutter streaming app scaffold built around a TV-style focus model, TMDb metadata, a rotating multi-provider embed playback system, and a separate .NET 8 updater.

> **Beta build:** Android and Android TV packages from this repository install as **Cheriflix Beta**. Completed implementation builds are published locally as `ready to install apk/Cheriflix-Beta.apk`.

## Current scope

This repository currently contains:

- a Flutter package scaffold with app-shell navigation and focus-first screen structure
- core playback provider logic for 15 embed services with configurable priority and fallback
- SQLite-backed repositories for profiles, app session TTL, and per-title last-good provider tracking
- a Windows updater console app in .NET 8 for staged binary replacement and relaunch
- unit tests covering provider URL construction, fallback sequencing, and 24-hour session gate logic

## Missing generated platform runners

Flutter is not installed in this environment, so the generated `windows/`, `android/`, and other platform runner folders are not included yet. After installing Flutter, generate them from the workspace root:

```powershell
flutter create . --platforms=windows,android
```

That command should be run after reviewing the existing `pubspec.yaml` and before attempting a build.

## Configuration

Compile-time defines:

- `CHERIFLIX_TMDB_API_KEY`
- `CHERIFLIX_UPDATE_MANIFEST_URL`
- `CHERIFLIX_PROVIDER_CONFIG_PATH`
- `CHERIFLIX_SOURCE_RESOLVER_URL`

Example:

```powershell
flutter run -d windows `
  --dart-define=CHERIFLIX_TMDB_API_KEY=your_tmdb_key `
  --dart-define=CHERIFLIX_UPDATE_MANIFEST_URL=https://updates.example.com/cheriflix/manifest.json `
  --dart-define=CHERIFLIX_SOURCE_RESOLVER_URL=http://127.0.0.1:8082 `
  --dart-define=CHERIFLIX_PROVIDER_CONFIG_PATH=config/provider_config.example.json
```

Local example JSON files are in [config/provider_config.example.json](/C:/Users/WATER/Documents/Codex/CHERIFLIX/config/provider_config.example.json) and [config/update_manifest.example.json](/C:/Users/WATER/Documents/Codex/CHERIFLIX/config/update_manifest.example.json).

The playback resolver service lives in `backend/source_resolver_service/` and is optional at runtime. If `CHERIFLIX_SOURCE_RESOLVER_URL` is unset or unreachable, the app falls back to the existing local embed resolver path.

On desktop, the packaged app also reads these values from normal process environment variables at launch time, so you do not need to rebuild the executable just to change `CHERIFLIX_SOURCE_RESOLVER_URL` or the other runtime endpoints.

## Android TV release workflow

Build a TV-compatible release APK (arm32 + arm64 + x64), regenerate TV launcher assets from `branding/icon HQ.png`, and validate ABI/runtime libraries:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_android_tv_release.ps1
```

The script enforces:

- release build target platforms: `android-arm`, `android-arm64`, `android-x64`
- APK ABI validation for `libapp.so` and `libflutter.so` in every packaged ABI
- mandatory badging checks for the beta app label (`Cheriflix Beta`), launchable activity, and TV banner presence
- replacement of any obsolete APKs in `ready to install apk`
- final signed output copied to `ready to install apk/Cheriflix-Beta.apk`

If you only want to regenerate Android launcher + TV banner assets:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/generate_android_tv_branding.ps1
```

To run the resolver locally:

```powershell
cd backend/source_resolver_service
dart run bin/server.dart
```

The resolver binds to `127.0.0.1:8082` by default. Set `PORT` if you want a different port.

## Layout

```text
lib/
  app/                    bootstrap and app shell
  core/
    data/                 SQLite-backed repositories
    models/               domain models and config contracts
    services/             playback, session, TMDb, updates
  features/
    home/
    player/
    profile/
    search/
    settings/
    splash/
test/
updater/CheriflixUpdater/ .NET 8 self-updater
config/                   local example config files
```
