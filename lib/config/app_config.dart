// lib/config/app_config.dart
//
// Single source of truth for the backend's address. Every screen reads
// AppConfig.apiBaseUrl / AppConfig.apiHost - no screen has its own copy.
//
// Two ways to change the server (e.g. when moving to Cloudflare):
//   1. For new builds: change [defaultApiHost] below and build a new APK.
//   2. For phones already in use: an admin opens App settings -> Server
//      address (or taps the server line at the bottom of the login
//      screen), types the new address and taps Test & save. It is only
//      saved if the new address answers as the Ida AgriCo server.
//      This is stored on that phone only.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // The built-in server address - no trailing slash, no '/api' suffix.
  // Change ONLY this line when switching hosting for new builds.
  static const String defaultApiHost = 'https://ida.idaagrico.com';

  static const String _prefKey = 'server_host';
  static String _host = defaultApiHost;

  // The backend's root address in use on this phone (default, or the
  // one an admin saved). Used for /uploads/... photos.
  static String get apiHost => _host;

  // What almost every screen actually wants for its HTTP calls.
  static String get apiBaseUrl => '$_host/api';

  // True when this phone uses an address other than the built-in one.
  static bool get isCustomHost => _host != defaultApiHost;

  // Just the domain, for display (e.g. "ida.idaagrico.com").
  static String get displayHost => Uri.tryParse(_host)?.host ?? _host;

  // Call once in main() before runApp.
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_prefKey);
      if (saved != null && saved.isNotEmpty) _host = saved;
    } catch (_) {
      // keep the default
    }
  }

  // Turns what a person types into a clean root address:
  // "app.example.in" -> "https://app.example.in";
  // "https://app.example.in/api/" -> "https://app.example.in".
  // Returns null if it can't be a web address.
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    if (s.endsWith('/api')) s = s.substring(0, s.length - 4);
    s = s.replaceAll(RegExp(r'/+$'), '');
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !u.host.contains('.')) return null;
    return s;
  }

  // Checks that [host] answers as the Ida AgriCo server. Returns null
  // when fine, otherwise a short reason to show the person.
  static Future<String?> test(String host) async {
    try {
      final res = await http
          .get(Uri.parse('$host/api/health'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['app'] == 'idaagrico') return null;
      }
      return 'That address answered, but it is not the Ida AgriCo server '
          '(${res.statusCode}).';
    } catch (_) {
      return 'Could not reach that address. Check the spelling and that '
          'the server is running.';
    }
  }

  // Saves a new address for this phone (already tested by the caller).
  // Passing null or the default goes back to the built-in address.
  static Future<void> setHost(String? host) async {
    final p = await SharedPreferences.getInstance();
    if (host == null || host == defaultApiHost) {
      await p.remove(_prefKey);
      _host = defaultApiHost;
    } else {
      await p.setString(_prefKey, host);
      _host = host;
    }
  }
}
