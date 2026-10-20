# TripSplit

A Flutter expense splitter for trips with any number of people. Each person
signs in with Google, creates or joins a trip with a short invite code, and
everyone on that trip sees the same shared expenses, balances, and settlement
suggestions — synced live through Firebase (Auth + Firestore), with offline
writes, not just stored on one device.

See [CHANGELOG.md](CHANGELOG.md) for what's in each release.

## Run

Install Flutter and the Android toolchain, connect an Android device or start an
emulator, then run:

```powershell
flutter pub get
flutter run
```

Sign-in needs `android/app/google-services.json` from the Firebase console.

The iOS project is included for builds from macOS with Xcode.

## Firebase

Security rules and indexes live in `firestore.rules` and
`firestore.indexes.json`. Deploy them with the Firebase CLI:

```powershell
firebase deploy --only firestore
```

The rules have emulator tests in `firestore-tests/` (`npm install && npm test`,
needs Java); CI runs them on every push to `main`.

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
   release notes. It also publishes `TripSplit.apk` and `latest.json` to the
   public `TripSplit-releases` repo, where the in-app updater looks (needs the
   `RELEASES_TOKEN` secret).
