# Changelog

All notable changes to this project are documented here. Versions follow
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`); the build
number after `+` in `pubspec.yaml` increments on every release.

## [1.2.0] - 2026-10-14

### Added
- Over-the-air updates: the app checks the TripSplit backend
  (`/releases/latest`) on launch and lets you download + install a newer
  build directly, without going through the Play Store. A manual "check for
  updates" button also lives next to the logout icon on the trips list. The
  release workflow now pushes each tagged build straight to the server after
  creating the GitHub Release.

### Changed
- Location search now calls Google's Places API (New) directly over REST
  (`places:autocomplete` + place details), with the `X-Android-Package`/
  `X-Android-Cert` headers that let an Android-app-restricted key work from
  plain HTTP. Replaces an earlier attempt via the `flutter_google_places_sdk`
  plugin, which only supports the legacy Places API — not enabled (and no
  longer offered) on newer Google Cloud projects.
- Selected search results now show as "Place name, City" (e.g. "Hotel Aditya
  Mansingh, Veraval"), built from the place's own name and address
  components, matching Ola/Uber-style pickers.

### Fixed
- Picking a search result or tapping "recenter" could show the correct
  place/name label for a moment, then have it silently overwritten by a
  plain reverse-geocoded city name — the programmatic camera move those
  actions trigger was firing the same `onCameraIdle` handler used for manual
  map dragging, which re-resolved the label from scratch. Now suppressed for
  camera moves the app itself initiates.

## [1.1.0] - 2026-10-14

### Changed
- Location picker now uses the native Google Maps widget (`google_maps_flutter`)
  instead of OpenStreetMap tiles, for a true Google Maps look and feel —
  same interaction (pin-centered pan-to-select).

### Infrastructure
- Release workflow now writes the Google Maps API key (from a
  `GOOGLE_MAPS_API_KEY` repository secret) into `local.properties` before
  building, so release APKs actually have a working map.
- Debug signing is pinned to a committed `app/debug.keystore` instead of each
  machine's own `~/.android/debug.keystore`, so local and CI builds share one
  signing identity — the SHA-1 the Maps API key is restricted to.

## [1.0.0] - 2026-10-14

First tagged release. Previous history (demo stage) is summarized here
rather than split into pre-1.0 versions.

### Added
- Phone + OTP login, with accounts and sessions backed by a FastAPI server
  (`tripsplit_backend` on the `nav` server, reachable via Tailscale Funnel).
- Trips: create a trip, get a 6-character invite code, others join with it.
  Any number of members per trip (not fixed to 3).
- Expenses: add/edit/delete, always recorded under the logged-in account as
  payer; editing and deleting are restricted to the expense's own creator
  (enforced both client-side and by the backend).
- Each expense carries a category, a pickable date/time, and a location —
  chosen from a full-screen map (OpenStreetMap tiles, pin-centered pan-to-
  select, plus free-text search via Nominatim) or defaulted from GPS.
- Overview screen groups expenses by category and by city, with subtotal
  strips and colored icon badges.
- Balances and suggested settlements, computed server-side per trip.

### Infrastructure
- GitHub Actions CI: `flutter analyze`, `flutter test`, `flutter build apk
  --debug` on every push/PR to `main`.
- GitHub Actions release workflow: pushing a `vX.Y.Z` tag builds a release
  APK and publishes it as a GitHub Release with this changelog's matching
  section as the release notes.
