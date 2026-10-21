/// Passed at build time via `--dart-define=GOOGLE_MAPS_API_KEY=...` so the
/// literal key never lands in source control. The same key is also embedded
/// in the Android manifest (via android/local.properties) for the native
/// Maps SDK — this constant is what the Places Autocomplete plugin needs on
/// the Dart side to talk to the native Places SDK layer.
const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// The *Web application* OAuth client ID of the `tripsplit-237a5` Firebase
/// project (the `client_type: 3` entry in android/app/google-services.json).
/// Android's Credential Manager needs it to mint the Google ID token that
/// Firebase Auth signs in with; it is a public identifier, not a secret. The
/// app's release SHA-1 must be registered on the Firebase Android app.
const googleWebClientId = '442536622738-q17cm7jj8fqlb40os36qc2n722hbmmlv.apps.googleusercontent.com';

/// The push relay (push-worker/worker.js, a free Cloudflare Worker) that sends
/// tripmates an instant notification when someone adds an expense. Empty
/// until it's deployed: then only the in-app and 15-minute checks notify.
const pushRelayUrl = '';
