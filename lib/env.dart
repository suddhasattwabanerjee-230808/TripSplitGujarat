/// Passed at build time via `--dart-define=GOOGLE_MAPS_API_KEY=...` so the
/// literal key never lands in source control. The same key is also embedded
/// in the Android manifest (via android/local.properties) for the native
/// Maps SDK — this constant is what the Places Autocomplete plugin needs on
/// the Dart side to talk to the native Places SDK layer.
const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
