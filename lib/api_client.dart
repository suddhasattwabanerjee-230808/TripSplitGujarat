import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<dynamic> _get(String path) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      return _unwrap(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  Future<dynamic> _post(String path, Map<String, Object?> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      return _unwrap(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  Future<dynamic> _delete(String path) async {
    try {
      final response = await http
          .delete(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      return _unwrap(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  // --- Auth -----------------------------------------------------------

  /// Returns the mock OTP code (the backend hands it back directly since no
  /// real SMS provider is wired up yet).
  Future<String> requestOtp(String phone) async {
    final result = await _post('/auth/request-otp', {'phone': phone});
    return result['otp'] as String;
  }

  Future<AppUser> verifyOtp(String phone, String code, {String? name}) async {
    final result = await _post('/auth/verify-otp', {
      'phone': phone,
      'code': code,
      if (name != null) 'name': name,
    });
    final user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveSession(result['token'] as String, user);
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
    required int paidBy,
    String? category,
  }) async {
    final result = await _post('/trips/$tripId/expenses', {
      'description': description,
      'amount': amount,
      'paid_by': paidBy,
      'category': category,
      'split_type': 'equal',
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
