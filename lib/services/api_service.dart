// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_locale.dart';
import '../models/user_model.dart';

class ApiService {
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev';

  // ── Session ────────────────────────────────────────────────────────────────

  /// Call this right after a successful login response.
  /// Stores everything the app needs without another API call.
  static Future<void> saveSession(Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    final user = result['user'] as Map<String, dynamic>;

    await prefs.setString('token', result['token']);
    await prefs.setString('username', user['username'] ?? '');
    await prefs.setString('display_name', user['display_name'] ?? '');
    await prefs.setBool('is_admin', user['is_admin'] ?? false);
    await prefs.setString('permissions', jsonEncode(user['permissions'] ?? []));

    // The account's OWN language preference is authoritative — applies
    // even on a brand new device, so "log in as user2, see Marathi"
    // works regardless of what this device last showed.
    await AppLocale.apply(user['preferred_language'] ?? 'en');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username') ?? '';
  }

  static Future<String> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('display_name') ?? '';
  }

  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
  }

  /// Returns the parsed permission entries the logged-in user has.
  /// For admin, this returns an empty list — use isAdmin() to gate instead.
  static Future<List<PermissionEntry>> getPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('permissions') ?? '[]';
    return parsePermissions(jsonDecode(raw));
  }

  /// Check if the current user can access (view) a given module key.
  static Future<bool> canAccess(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasModuleAccess(perms, moduleKey);
  }

  /// Check if the current user has EDIT-level access to a module —
  /// i.e. can add/edit master data there, not just view it.
  static Future<bool> canEdit(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasEditAccess(perms, moduleKey);
  }

  /// The three granular mutation checks — use these instead of canEdit
  /// when a specific action (not "any edit right at all") is what
  /// actually gates a button, e.g. a Delete icon should check
  /// canDelete, not the broader canEdit.
  static Future<bool> canAdd(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasAddAccess(perms, moduleKey);
  }

  static Future<bool> canUpdate(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasUpdateAccess(perms, moduleKey);
  }

  static Future<bool> canDelete(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasDeleteAccess(perms, moduleKey);
  }

  /// A deliberately distinct privilege from the mutation checks above -
  /// for modules with an approval workflow (e.g. daily entries needing
  /// admin sign-off), so someone can be granted the ability to approve
  /// without also being able to add/edit/delete regular records.
  static Future<bool> canApprove(String moduleKey) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return hasApproveAccess(perms, moduleKey);
  }

  /// Section-scoped approve check, for the same sectioned modules as
  /// canUpdateSection (e.g. farm_attendance's two stages) - matches the
  /// backend's requireFixedSection(module, scope, 'approve') exactly.
  static Future<bool> canApproveSection(String moduleKey, String scope) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return perms.any((p) =>
        p.module == moduleKey &&
        (p.level == 'approve' || p.level == 'edit') &&
        (p.scope == null || p.scope == scope));
  }

  /// Section-scoped check, for workflow modules with independently
  /// grantable sections (see kSectionedModules in user_model.dart) -
  /// e.g. canUpdateSection('outward_register', 'bhada'). An unscoped
  /// module-level grant still passes this for every section, matching
  /// the backend's _hasScopedLevel exactly.
  static Future<bool> canUpdateSection(String moduleKey, String scope) async {
    if (await isAdmin()) return true;
    final perms = await getPermissions();
    return perms.any((p) =>
        p.module == moduleKey &&
        (p.level == 'update' || p.level == 'edit') &&
        (p.scope == null || p.scope == scope));
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Changes the logged-in user's language preference — persisted on
  /// their account (so it follows them to any device), and applied
  /// immediately in this session.
  static Future<bool> setLanguage(String code) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/users/me/language'),
        headers: await _authHeaders(),
        body: jsonEncode({'language': code}),
      );
      if (res.statusCode == 200) {
        await AppLocale.apply(code);
        return true;
      }
      // ignore: avoid_print
      print('setLanguage failed: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('setLanguage error: $e');
      return false;
    }
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getReports() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/reports'),
      headers: await _authHeaders(),
    );
    return jsonDecode(res.body);
  }

  static Future<bool> submitReport(
      String title, String description, String date) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/reports'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'title': title,
        'description': description,
        'report_date': date,
      }),
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }

  // ── Attendance ─────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getRegisters() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/registers'),
      headers: await _authHeaders(),
    );
    return jsonDecode(res.body);
  }

  static Future<bool> checkIn(double lat, double lng) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/registers/checkin'),
      headers: await _authHeaders(),
      body: jsonEncode({'latitude': lat, 'longitude': lng}),
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }

  static Future<bool> checkOut() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/registers/checkout'),
      headers: await _authHeaders(),
    );
    return res.statusCode == 200;
  }
}
