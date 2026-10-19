/// Passed at build time via `--dart-define=GOOGLE_MAPS_API_KEY=...` so the
/// literal key never lands in source control. The same key is also embedded
/// in the Android manifest (via android/local.properties) for the native
/// Maps SDK — this constant is what the Places Autocomplete plugin needs on
/// the Dart side to talk to the native Places SDK layer.
const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// The *Web application* OAuth client ID from Google Cloud Console (APIs &
/// Services → Credentials), ending in `.apps.googleusercontent.com`. Android's
/// Credential Manager needs it to mint an ID token the backend can verify; it
/// is a public identifier, not a secret. The Android OAuth client (package +
/// signing SHA-1) must exist in the same Cloud project, but isn't referenced here.
const googleWebClientId = '482908381478-kof6tms8k9r787fqnktmu5td6hpr1gnc.apps.googleusercontent.com';
