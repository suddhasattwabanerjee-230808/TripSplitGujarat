# TripSplit

A Flutter expense splitter for trips with any number of people. Each person
logs in with their own phone number, creates or joins a trip with a short
invite code, and everyone on that trip sees the same shared expenses,
balances, and settlement suggestions — synced through a small FastAPI
backend, not just stored on one device.

See [CHANGELOG.md](CHANGELOG.md) for what's in each release.

## Run

Install Flutter and the Android toolchain, connect an Android device or start an
emulator, then run:

```powershell
flutter pub get
flutter run
```

The iOS project is included for builds from macOS with Xcode.

## Releases

Versions follow [Semantic Versioning](https://semver.org/). To cut a release:

1. Bump `version:` in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`).
2. Add a matching `## [MAJOR.MINOR.PATCH] - YYYY-MM-DD` section to
   [CHANGELOG.md](CHANGELOG.md) describing what changed.
3. Commit, then tag and push:
   ```powershell
   git tag vMAJOR.MINOR.PATCH
   git push origin vMAJOR.MINOR.PATCH
   ```
4. The `Release` GitHub Actions workflow builds a release APK and publishes
   it under [Releases](../../releases), with the changelog section as the
   release notes.
