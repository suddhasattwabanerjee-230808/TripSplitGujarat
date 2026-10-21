import 'package:google_sign_in/google_sign_in.dart';

import 'env.dart';

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message, {this.canceled = false});
  final String message;

  /// The user backed out of the account picker; not worth an error message.
  final bool canceled;

  @override
  String toString() => message;
}

/// Thin wrapper over google_sign_in that only hands back Google ID tokens.
/// The backend verifies the token once and issues its own session token, which
/// is what keeps the user signed in; Google is only asked again if that
/// session is ever rejected.
abstract final class GoogleAuth {
  static Future<void>? _initialized;

  static bool get isConfigured => googleWebClientId.isNotEmpty;

  static Future<void> _ensureInitialized() => _initialized ??= GoogleSignIn.instance
      .initialize(serverClientId: googleWebClientId)
      .catchError((Object error) {
        _initialized = null; // let the next attempt retry
        throw error;
      });

  /// Shows the Google account picker and returns an ID token for the chosen account.
  static Future<String> signIn() async {
    if (!isConfigured) {
      throw GoogleAuthException('Google sign-in isn\'t set up in this build yet.');
    }
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email', 'profile']);
      final idToken = account.authentication.idToken;
      if (idToken == null) throw GoogleAuthException('Google didn\'t return a sign-in token. Try again.');
      return idToken;
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          throw GoogleAuthException('Sign-in canceled.', canceled: true);
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw GoogleAuthException(
            'Google sign-in is misconfigured for this build (check the OAuth client IDs and SHA-1).',
          );
        default:
          throw GoogleAuthException(e.description ?? 'Google sign-in failed. Try again.');
      }
    }
  }

  /// A fresh ID token for the account already used on this phone, without
  /// showing the picker. Null if there isn't one or Google can't provide it.
  static Future<String?> silentIdToken() async {
    if (!isConfigured) return null;
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return account?.authentication.idToken;
    } on Exception {
      return null;
    }
  }

  /// Removes TripSplit's access from the user's Google account (it drops
  /// off "Apps with access" in their Google settings) and signs out.
  static Future<void> disconnect() async {
    if (!isConfigured) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.disconnect();
    } on Exception {
      await signOut();
    }
  }

  static Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } on Exception {
      // Local sign-out still happens; Google just offers the same account next time.
    }
  }
}
