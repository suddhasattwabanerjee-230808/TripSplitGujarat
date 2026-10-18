import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Base URL for the TripSplit backend. Served through Tailscale Funnel,
/// which exposes the server's local port 8001 at a public HTTPS address —
/// works from any network (home WiFi, mobile data), not just devices on the
/// server's own tailnet.
const _baseUrl = 'https://nav-server.tail85596c.ts.net';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _tokenKey = 'trip_split.auth_token.v1';
  static const _userKey = 'trip_split.auth_user.v1';
  static const _lastTripKey = 'trip_split.last_trip_id.v1';

  final _preferences = SharedPreferencesAsync();
  String? _token;
  AppUser? _user;

  AppUser? get currentUser => _user;

  Future<bool> restoreSession() async {
    final token = await _preferences.getString(_tokenKey);
    final userJson = await _preferences.getString(_userKey);
    if (token == null || userJson == null) return false;
    _token = token;
    _user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    return true;
  }

  Future<void> _saveSession(String token, AppUser user) async {
    _token = token;
    _user = user;
    await _preferences.setString(_tokenKey, token);
    await _preferences.setString(_userKey, jsonEncode(user.toJson()));
  }

  /// The trip opened most recently — where quick-added UPI payments go by default.
  Future<void> rememberTrip(int tripId) => _preferences.setInt(_lastTripKey, tripId);

  Future<int?> lastTripId() => _preferences.getInt(_lastTripKey);

  /// Signing out is always the user's choice (or a session the server
  /// rejected and Google couldn't renew); the saved session never expires locally.
  Future<void> logOut() async {
    _token = null;
    _user = null;
    await _preferences.remove(_tokenKey);
    await _preferences.remove(_userKey);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Called when the server rejects the saved session and it can't be renewed
  /// silently — the only way the app ever signs someone out on its own.
  void Function()? onSessionExpired;

  Future<bool>? _renewing;

  dynamic _unwrap(http.Response response) {
    final body = response.body.isEmpty ? '{}' : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = body is Map && body['detail'] != null
          ? body['detail'].toString()
          : 'Request failed (${response.statusCode})';
      throw ApiException(message);
    }
    return body;
  }

  /// Sends [request] (re-run for a retry, so it re-reads [_headers]). A 401 on
  /// a signed-in session gets one silent renewal through Google before giving up,
  /// so a session the server dropped never bounces the user to the login screen.
  Future<dynamic> _send(Future<http.Response> Function() request, {bool renew = true}) async {
    http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 12));
      if (response.statusCode == 401 && _token != null && renew) {
        if (await _renewSession()) {
          response = await request().timeout(const Duration(seconds: 12));
        } else {
          await logOut();
          onSessionExpired?.call();
        }
      }
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
    try {
      return _unwrap(response);
    } on FormatException {
      throw ApiException('Unexpected reply from the server (${response.statusCode}).');
    }
  }

  /// Parallel requests that all hit a 401 share one renewal.
  Future<bool> _renewSession() =>
      _renewing ??= _renewWithGoogle().whenComplete(() => _renewing = null);

  Future<bool> _renewWithGoogle() async {
    // Accounts that never linked Google can't be renewed without the user.
    if (_user?.hasGoogle != true) return false;
    final idToken = await GoogleAuth.silentIdToken();
    if (idToken == null) return false;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/google'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return false;
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
      if (user.id != _user?.id) return false; // a different Google account; don't swap users silently
      await _saveSession(result['token'] as String, user);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _get(String path) =>
      _send(() => http.get(Uri.parse('$_baseUrl$path'), headers: _headers));

  Future<dynamic> _post(String path, Map<String, Object?> body, {bool renew = true}) => _send(
    () => http.post(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(body)),
    renew: renew,
  );

  Future<dynamic> _put(String path, Map<String, Object?> body) => _send(
    () => http.put(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(body)),
  );

  Future<dynamic> _patch(String path, Map<String, Object?> body) => _send(
    () => http.patch(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(body)),
  );

  Future<dynamic> _delete(String path) =>
      _send(() => http.delete(Uri.parse('$_baseUrl$path'), headers: _headers));

  // --- Auth -----------------------------------------------------------

  /// Exchanges a Google ID token for a TripSplit session. When someone is
  /// already signed in (an old phone account), the current session is sent
  /// too, and the server links Google to that account instead of making a new one.
  Future<AppUser> signInWithGoogle(String idToken) async {
    // A 401 here means Google's token was refused, not that the session died.
    final result = await _post('/auth/google', {'id_token': idToken}, renew: false);
    final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveSession(result['token'] as String, user);
    return user;
  }

  /// Re-reads the profile from the server (name/photo may have changed).
  Future<AppUser> refreshMe() async {
    final user = AppUser.fromJson(await _get('/me') as Map<String, dynamic>);
    await _saveSession(_token!, user);
    return user;
  }

  Future<AppUser> updateName(String name) async {
    final user = AppUser.fromJson(await _patch('/me', {'name': name}) as Map<String, dynamic>);
    await _saveSession(_token!, user);
    return user;
  }

  // --- Trips ------------------------------------------------------------

  Future<List<Trip>> listTrips() async {
    final result = await _get('/trips') as List<dynamic>;
    return result.map((item) => Trip.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Trip> createTrip({
    required String name,
    String? destination,
    String? startDate,
    String? endDate,
  }) async {
    final result = await _post('/trips', {
      'name': name,
      'destination': destination,
      'start_date': startDate,
      'end_date': endDate,
    });
    return Trip.fromJson(result as Map<String, dynamic>);
  }

  Future<Trip> joinTrip(String inviteCode) async {
    final result = await _post('/trips/join', {'invite_code': inviteCode});
    return Trip.fromJson(result as Map<String, dynamic>);
  }

  Future<Trip> getTrip(int tripId) async {
    final result = await _get('/trips/$tripId');
    return Trip.fromJson(result as Map<String, dynamic>);
  }

  // --- Expenses -----------------------------------------------------------

  Future<List<TripExpense>> listExpenses(int tripId) async {
    final result = await _get('/trips/$tripId/expenses') as List<dynamic>;
    return result
        .map((item) => TripExpense.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TripExpense> createExpense({
    required int tripId,
    required String description,
    required double amount,
    String? category,
    required String date,
    String? location,
  }) async {
    final result = await _post('/trips/$tripId/expenses', {
      'description': description,
      'amount': amount,
      'category': category,
      'date': date,
      'location': location,
      'split_type': 'equal',
    });
    return TripExpense.fromJson(result as Map<String, dynamic>);
  }

  Future<TripExpense> updateExpense({
    required int tripId,
    required int expenseId,
    required String description,
    required double amount,
    String? category,
    required String date,
    String? location,
  }) async {
    final result = await _put('/trips/$tripId/expenses/$expenseId', {
      'description': description,
      'amount': amount,
      'category': category,
      'date': date,
      'location': location,
    });
    return TripExpense.fromJson(result as Map<String, dynamic>);
  }

  Future<void> deleteExpense(int tripId, int expenseId) =>
      _delete('/trips/$tripId/expenses/$expenseId');

  // --- Balances & settlements ----------------------------------------------

  Future<List<Balance>> getBalances(int tripId) async {
    final result = await _get('/trips/$tripId/balances') as List<dynamic>;
    return result.map((item) => Balance.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<Settlement>> getSettlements(int tripId) async {
    final result = await _get('/trips/$tripId/settlements') as List<dynamic>;
    return result
        .map((item) => Settlement.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
