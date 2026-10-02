// lib/services/api_client.dart
//
// ONE place for every call from the phone to the server (Oct 2026).
// It adds the sign-in header, uses the server address in use on this
// phone, applies a timeout, and reacts to an expired sign-in the same
// way on every screen (signs out and opens Login with a message).
//
// Two ways to use it:
//   * Api.send(...)  - drop-in for http.get/post/put/patch/delete. Returns
//     the normal http.Response, so a screen can keep checking
//     res.statusCode and reading res.body as before.
//   * Api.json(...)  - returns the decoded JSON, or throws ApiException
//     with a plain message when the server says no.
// Errors shown to a person should go through Api.errorText(e) or
// Api.responseError(res) so they read the same everywhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'push_service.dart' show appNavigatorKey;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic> body;
  ApiException(this.message, [this.statusCode, this.body = const {}]);
  @override
  String toString() => message;
}

class Api {
  static const Duration defaultTimeout = Duration(seconds: 60);

  // Report / Excel / PDF downloads can take a while to build.
  static const Duration downloadTimeout = Duration(seconds: 180);
  static Duration _timeoutFor(String path) {
    final p = path.toLowerCase();
    if (p.contains('report') || p.contains('format=') || p.contains('xlsx') || p.contains('/generate')) return downloadTimeout;
    return defaultTimeout;
  }

  static String? _notice; // shown once on the Login screen
  static bool _expiring = false;

  /// Full address for a path like '/electricity?x=1'. A full http(s)
  /// address is returned unchanged.
  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = path.startsWith('http') ? path : '${AppConfig.apiBaseUrl}${path.startsWith('/') ? '' : '/'}$path';
    final u = Uri.parse(base);
    if (query == null || query.isEmpty) return u;
    final q = <String, String>{...u.queryParameters};
    query.forEach((k, v) {
      if (v != null) q[k] = v.toString();
    });
    return u.replace(queryParameters: q);
  }

  static Future<String?> _token() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('token');
    } catch (_) {
      return null;
    }
  }

  /// Headers every call needs. [extra] wins over the defaults (for example
  /// the password manager's x-password-token).
  static Future<Map<String, String>> headers({Map<String, String>? extra, bool json = true, bool auth = true}) async {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    if (auth) {
      final t = await _token();
      if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Sends one request. [body] may be a Map/List (sent as JSON) or a String
  /// (sent as is). Returns the http.Response whatever the status; only a
  /// network failure or timeout throws. [auth]: false for calls made before
  /// signing in (login, face login, health check).
  static Future<http.Response> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? query,
    Duration? timeout,
    bool auth = true,
  }) async {
    final h = await Api.headers(extra: headers, auth: auth);
    final u = uri(path, query);
    final limit = timeout ?? _timeoutFor(path);
    final b = body == null ? null : (body is String ? body : jsonEncode(body));
    http.Response res;
    switch (method.toUpperCase()) {
      case 'POST':
        res = await http.post(u, headers: h, body: b ?? '{}').timeout(limit);
        break;
      case 'PUT':
        res = await http.put(u, headers: h, body: b ?? '{}').timeout(limit);
        break;
      case 'PATCH':
        res = await http.patch(u, headers: h, body: b ?? '{}').timeout(limit);
        break;
      case 'DELETE':
        res = await http.delete(u, headers: h, body: b).timeout(limit);
        break;
      default:
        res = await http.get(u, headers: h).timeout(limit);
    }
    if (auth) await _checkExpired(res);
    return res;
  }

  static Future<http.Response> get(String path, {Map<String, String>? headers, Map<String, dynamic>? query, Duration? timeout, bool auth = true}) =>
      send('GET', path, headers: headers, query: query, timeout: timeout, auth: auth);
  static Future<http.Response> post(String path, {Object? body, Map<String, String>? headers, Duration? timeout, bool auth = true}) =>
      send('POST', path, body: body, headers: headers, timeout: timeout, auth: auth);
  static Future<http.Response> put(String path, {Object? body, Map<String, String>? headers, Duration? timeout}) =>
      send('PUT', path, body: body, headers: headers, timeout: timeout);
  static Future<http.Response> patch(String path, {Object? body, Map<String, String>? headers, Duration? timeout}) =>
      send('PATCH', path, body: body, headers: headers, timeout: timeout);
  static Future<http.Response> delete(String path, {Object? body, Map<String, String>? headers, Duration? timeout}) =>
      send('DELETE', path, body: body, headers: headers, timeout: timeout);

  /// For file uploads: build the http.MultipartRequest as before, then send
  /// it here. The sign-in header is added; other headers you set are kept.
  static Future<http.Response> sendMultipart(http.MultipartRequest req, {Duration timeout = const Duration(seconds: 120), bool auth = true}) async {
    final h = await Api.headers(json: false, auth: auth);
    h.forEach((k, v) => req.headers.putIfAbsent(k, () => v));
    final streamed = await req.send().timeout(timeout);
    final res = await http.Response.fromStream(streamed);
    if (auth) await _checkExpired(res);
    return res;
  }

  /// Decoded JSON (Map / List) or null for an empty body. Throws
  /// [ApiException] with a plain message when the status is not 2xx.
  static Future<dynamic> json(String method, String path, {Object? body, Map<String, String>? headers, Map<String, dynamic>? query, Duration? timeout, bool auth = true}) async {
    http.Response res;
    try {
      res = await send(method, path, body: body, headers: headers, query: query, timeout: timeout, auth: auth);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(errorText(e));
    }
    final data = decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(responseError(res), res.statusCode, data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
    }
    return data;
  }

  /// Decoded body or null (never throws).
  static dynamic decode(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  // ── Plain messages ─────────────────────────────────────────────────

  /// The text to show for a failed response: the server's own words if it
  /// sent any (for example "You need approve access to ..."), else a plain line.
  static String responseError(http.Response res) {
    final d = decode(res);
    if (d is Map && d['error'] != null && d['error'].toString().trim().isNotEmpty) {
      return d['error'].toString();
    }
    if (d is Map && d['message'] != null && d['message'].toString().trim().isNotEmpty && res.statusCode >= 400) {
      return d['message'].toString();
    }
    if (res.statusCode == 401) return 'Your session has expired. Sign in again.';
    if (res.statusCode == 403) return 'You do not have permission to do this.';
    if (res.statusCode == 404) return 'Not found. It may have been removed.';
    if (res.statusCode >= 500) return 'The server had a problem. Try again in a moment.';
    return 'Something went wrong (${res.statusCode}).';
  }

  /// The text to show for anything thrown by a call.
  static String errorText(Object e) {
    if (e is ApiException) return e.message;
    if (e is TimeoutException) return 'The server is slow to answer. Try again in a moment.';
    if (e is SocketException || e is HandshakeException || e is http.ClientException) {
      return 'No signal, or the server cannot be reached. Check the internet and try again.';
    }
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  // ── Expired sign-in ────────────────────────────────────────────────

  static Future<void> _checkExpired(http.Response res) async {
    if (res.statusCode != 401 || _expiring) return;
    // The background notification check has no screen to send anyone to:
    // never end the session from there (the next time the app is opened
    // in front, the first call handles it).
    if (appNavigatorKey.currentState == null) return;
    final d = decode(res);
    final msg = (d is Map ? (d['error'] ?? '') : '').toString().toLowerCase();
    // Only the "no / bad token" answers mean the sign-in is gone.
    if (!msg.contains('token')) return;
    if ((await _token()) == null) return;
    _expiring = true;
    try {
      await endSession();
      _notice = 'Your session has expired. Sign in again.';
      final nav = appNavigatorKey.currentState;
      if (nav != null) nav.pushNamedAndRemoveUntil('/login', (r) => false);
    } finally {
      // let the next sign-in work normally
      Future.delayed(const Duration(seconds: 2), () => _expiring = false);
    }
  }

  /// Forgets the saved sign-in on this phone but keeps the server address
  /// an admin saved (a plain prefs.clear() used to lose it).
  static Future<void> endSession() async {
    final p = await SharedPreferences.getInstance();
    final host = p.getString('server_host');
    await p.clear();
    if (host != null && host.isNotEmpty) await p.setString('server_host', host);
  }

  /// The one-time message for the Login screen (null if none).
  static String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// Shows [takeNotice] as a snackbar; call from Login's initState.
  static void showNoticeIfAny(BuildContext context) {
    final n = takeNotice();
    if (n == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n)));
    });
  }
}
