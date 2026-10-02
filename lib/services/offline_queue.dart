// lib/services/offline_queue.dart
//
// Offline entry (Oct 2026). Two small jobs, both on this phone:
//
//  1. SAVED ANSWERS (read cache). When a screen asks the server for
//     something it will need again offline (workers, farms, work types, a
//     day's attendance), the last good answer is kept in a file. With no
//     signal the screen gets that saved answer instead of an error.
//
//  2. SEND-LATER QUEUE (write queue). When a person saves an entry and
//     there is no signal, the entry is kept in a file and sent by itself
//     once the server can be reached again. Each entry carries a random id
//     (X-Request-Id) so that if a try reached the server but the answer
//     was lost, sending it again does not save it twice (the server
//     remembers the first answer - backend src/middleware/idempotency.js).
//
// Rules the app follows:
//   * An entry the server REFUSES (for example "today's attendance is
//     already approved") is not retried forever. It stays on the phone as
//     "Not sent", with the server's words, until the person discards it or
//     fixes and saves again. Nothing is lost or overwritten silently.
//   * Entries are sent oldest first, one at a time, and sending stops at
//     the first "no signal" so the order is kept.
//   * Entries belong to the person who made them; they are only sent while
//     that same person is signed in. Signing out keeps them on the phone.
//   * Web is not offline (phone only).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'push_service.dart' show appMessengerKey;

class OfflineEntry {
  final String id; // also sent as X-Request-Id
  final String method;
  final String path;
  final String body; // JSON text ('' = none)
  final String label; // what the person sees, e.g. "Attendance 02 Oct"
  final String key; // same key = replaces the older waiting entry
  final String user; // username that made it
  final int createdAt; // ms since epoch
  // Entries with photos: text fields + files kept in offline/files.
  final Map<String, String> fields; // empty for JSON entries
  final List<Map<String, String>> files; // {field, name, type, file}
  String status; // 'pending' | 'failed'
  String error;
  int tries;

  OfflineEntry({
    required this.id,
    required this.method,
    required this.path,
    required this.body,
    required this.label,
    required this.key,
    required this.user,
    required this.createdAt,
    this.fields = const {},
    this.files = const [],
    this.status = 'pending',
    this.error = '',
    this.tries = 0,
  });

  bool get isMultipart => fields.isNotEmpty || files.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'path': path,
        'body': body,
        'label': label,
        'key': key,
        'user': user,
        'createdAt': createdAt,
        'fields': fields,
        'files': files,
        'status': status,
        'error': error,
        'tries': tries,
      };

  static OfflineEntry? fromJson(dynamic j) {
    try {
      if (j is! Map) return null;
      return OfflineEntry(
        id: j['id'].toString(),
        method: j['method'].toString(),
        path: j['path'].toString(),
        body: (j['body'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        key: (j['key'] ?? '').toString(),
        user: (j['user'] ?? '').toString(),
        createdAt: (j['createdAt'] is int) ? j['createdAt'] as int : int.tryParse('${j['createdAt']}') ?? 0,
        fields: (j['fields'] is Map) ? Map<String, String>.from((j['fields'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))) : <String, String>{},
        files: (j['files'] is List) ? (j['files'] as List).whereType<Map>().map((m) => Map<String, String>.from(m.map((k, v) => MapEntry(k.toString(), v.toString())))).toList() : <Map<String, String>>[],
        status: (j['status'] ?? 'pending').toString(),
        error: (j['error'] ?? '').toString(),
        tries: (j['tries'] is int) ? j['tries'] as int : 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A file (photo) to keep with a save made without signal.
class QueuedFile {
  final String field;
  final String filename;
  final String contentType; // e.g. image/jpeg
  final List<int> bytes;
  const QueuedFile({required this.field, required this.filename, required this.bytes, this.contentType = 'image/jpeg'});
}

class Offline {
  Offline._();

  // ── What can be saved for offline reading ─────────────────────────
  // Only lists and day views the offline screens need. Keep this short:
  // every saved answer is a file on the phone.
  static const List<String> cacheablePrefixes = [
    '/farm-workers',
    '/farms',
    '/work-types',
    '/attendance/day/',
    '/agri/cycles/on-farm',
    // step 2: reading screens (previous reading, month calendar, lists)
    '/electricity',
    '/tractor',
    '/machine',
    '/machine-pf',
    '/factory',
    '/farm-tractor',
    '/maintenance',
    '/machine-maintenance',
  ];

  // Never saved: downloads and big reports (not JSON lists).
  static const List<String> _neverSaved = ['report', 'format=', 'xlsx', 'csv', 'pdf', 'download', '/uploads/', 'projection'];

  static bool isCacheable(String path) {
    final p = path.startsWith('http') ? Uri.parse(path).path + (Uri.parse(path).hasQuery ? '?${Uri.parse(path).query}' : '') : path;
    final norm = p.startsWith('/api/') ? p.substring(4) : p;
    final low = norm.toLowerCase();
    if (_neverSaved.any((x) => low.contains(x))) return false;
    return cacheablePrefixes.any((x) => norm == x || norm.startsWith(x));
  }

  // ── State other widgets can watch ─────────────────────────────────
  /// Entries of the signed-in person waiting to be sent.
  static final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Entries of the signed-in person the server refused.
  static final ValueNotifier<int> failedCount = ValueNotifier<int>(0);

  /// True while the screen in front is showing saved (older) answers.
  static final ValueNotifier<bool> showingSaved = ValueNotifier<bool>(false);

  /// Bumped every time entries were sent; screens can listen and reload.
  static final ValueNotifier<int> sentTick = ValueNotifier<int>(0);

  static List<OfflineEntry> _entries = [];
  static bool _loaded = false;
  static bool _flushing = false;
  static Timer? _timer;
  static String _user = '';
  static final _rng = Random.secure();

  // ── Files ─────────────────────────────────────────────────────────
  static Future<Directory> _dir([String sub = '']) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline${sub.isEmpty ? '' : '/$sub'}');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _queueFile() async => File('${(await _dir()).path}/queue.json');

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _queueFile();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        if (data is List) {
          _entries = data.map(OfflineEntry.fromJson).whereType<OfflineEntry>().toList();
        }
      }
    } catch (_) {
      _entries = [];
    }
  }

  static Future<void> _save() async {
    try {
      final f = await _queueFile();
      await f.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()), flush: true);
    } catch (_) {/* the entry stays in memory; next save retries */}
    _refreshCounts();
  }

  static Future<String> _currentUser() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('username') ?? '';
    } catch (_) {
      return '';
    }
  }

  static void _refreshCounts() {
    final mine = _entries.where((e) => e.user == _user).toList();
    pendingCount.value = mine.where((e) => e.status == 'pending').length;
    failedCount.value = mine.where((e) => e.status == 'failed').length;
  }

  // ── Start-up ──────────────────────────────────────────────────────
  /// Call once from main() (safe to call again). Loads waiting entries and
  /// starts the 40-second "try to send" timer.
  static Future<void> init() async {
    await _load();
    _user = await _currentUser();
    _refreshCounts();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (_entries.any((e) => e.status == 'pending')) flush();
    });
    if (_entries.any((e) => e.status == 'pending')) {
      // do not hold up the first screen
      Future.delayed(const Duration(seconds: 3), flush);
    }
  }

  /// Call after a successful sign-in (the signed-in person may have changed).
  static Future<void> onSignedIn() async {
    await _load();
    _user = await _currentUser();
    _refreshCounts();
    if (pendingCount.value > 0) flush();
  }

  /// Call when the app comes back to the front.
  static void onResume() {
    if (_entries.any((e) => e.status == 'pending')) flush();
  }

  // ── Which failures mean "no signal" ───────────────────────────────
  static bool isNetworkError(Object e) =>
      e is TimeoutException || e is SocketException || e is HandshakeException || e is http.ClientException;

  /// Answers a tunnel / proxy gives when the real server cannot be reached.
  static bool isUnreachableStatus(int s) => s == 502 || s == 503 || s == 504 || (s >= 520 && s <= 530);

  // ── Saved answers (read cache) ────────────────────────────────────
  static String _cacheName(String path) {
    // simple stable name from the path
    var h = 5381;
    for (final c in path.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return '${h.toRadixString(16)}_${path.length}.json';
  }

  static Future<void> saveAnswer(String path, String body) async {
    try {
      final d = await _dir('cache');
      final f = File('${d.path}/${_cacheName(path)}');
      await f.writeAsString(jsonEncode({'path': path, 'savedAt': DateTime.now().millisecondsSinceEpoch, 'body': body}), flush: true);
    } catch (_) {}
  }

  /// The last good answer for [path], or null.
  static Future<http.Response?> savedAnswer(String path) async {
    try {
      final d = await _dir('cache');
      final f = File('${d.path}/${_cacheName(path)}');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['path'] != path) return null;
      return http.Response(j['body'].toString(), 200, headers: {'content-type': 'application/json; charset=utf-8', 'x-from-saved': '1'});
    } catch (_) {
      return null;
    }
  }

  /// Forget saved answers (used when somebody signs out: the next person
  /// must not see them). Waiting entries are NOT touched.
  static Future<void> clearSavedAnswers() async {
    try {
      final d = await _dir('cache');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    showingSaved.value = false;
  }

  // ── Send-later queue ──────────────────────────────────────────────
  static String newRequestId() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Keeps an entry for later. An older WAITING entry with the same [key]
  /// (same day, same screen) is replaced, because the server replaces the
  /// whole day on every save too. A "Not sent" entry with the same key is
  /// replaced as well (the person has fixed it and saved again).
  static Future<OfflineEntry> enqueue({
    required String id,
    required String method,
    required String path,
    required String body,
    required String label,
    required String key,
    Map<String, String> fields = const {},
    List<QueuedFile> files = const [],
  }) async {
    await _load();
    _user = await _currentUser();
    final old = _entries.where((e) => e.key == key && e.user == _user).toList();
    _entries.removeWhere((e) => e.key == key && e.user == _user);
    for (final o in old) {
      await _dropFiles(o);
    }
    // photos go to their own files so queue.json stays small
    final saved = <Map<String, String>>[];
    var n = 0;
    for (final f in files) {
      try {
        final d = await _dir('files');
        final file = File('${d.path}/${id}_${n++}');
        await file.writeAsBytes(f.bytes, flush: true);
        saved.add({'field': f.field, 'name': f.filename, 'type': f.contentType, 'file': file.path});
      } catch (_) {/* a photo that cannot be kept is left out; the entry still is */}
    }
    final e = OfflineEntry(
      id: id,
      method: method.toUpperCase(),
      path: path,
      body: body,
      label: label,
      key: key,
      user: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      fields: fields,
      files: saved,
    );
    _entries.add(e);
    await _save();
    return e;
  }

  static Future<void> _dropFiles(OfflineEntry e) async {
    for (final f in e.files) {
      try {
        final file = File(f['file'] ?? '');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Is something waiting (or refused) under [key]?
  static OfflineEntry? waitingFor(String key) {
    for (final e in _entries) {
      if (e.key == key && e.user == _user) return e;
    }
    return null;
  }

  static List<OfflineEntry> mine() => _entries.where((e) => e.user == _user).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  static Future<void> discard(String id) async {
    await _load();
    for (final e in _entries.where((e) => e.id == id).toList()) {
      await _dropFiles(e);
    }
    _entries.removeWhere((e) => e.id == id);
    await _save();
    sentTick.value++; // screens re-read what is waiting
  }

  /// Removes the waiting / "Not sent" entry under [key] of the signed-in
  /// person. Called when the same save has just gone through online, so an
  /// older copy can never be sent afterwards and overwrite the newer one.
  static Future<void> dropKey(String key) async {
    await _load();
    _user = await _currentUser();
    final before = _entries.length;
    for (final e in _entries.where((e) => e.key == key && e.user == _user).toList()) {
      await _dropFiles(e);
    }
    _entries.removeWhere((e) => e.key == key && e.user == _user);
    if (_entries.length != before) {
      await _save();
      sentTick.value++;
    }
  }

  /// Puts a "Not sent" entry back in line to be tried again.
  static Future<void> retry(String id) async {
    await _load();
    for (final e in _entries) {
      if (e.id == id) {
        e.status = 'pending';
        e.error = '';
      }
    }
    await _save();
    flush();
  }

  /// Sends what is waiting, oldest first. Safe to call any time.
  /// Returns how many were sent.
  static Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true; // set before any await so two calls cannot both send
    int sent = 0, refused = 0;
    try {
      await _load();
      _user = await _currentUser();
      if (_user.isEmpty) return 0;
      final token = await _token();
      if (token == null || token.isEmpty) return 0;
      final todo = _entries.where((e) => e.user == _user && e.status == 'pending').toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final e in todo) {
        final r = await _sendOne(e, token);
        if (r == _R.sent) {
          sent++;
          await _dropFiles(e);
          _entries.removeWhere((x) => x.id == e.id);
          await _save();
        } else if (r == _R.refused) {
          refused++;
          await _save();
        } else {
          // no signal / server busy / sign-in problem: stop, keep the order
          await _save();
          break;
        }
      }
    } finally {
      _flushing = false;
      _refreshCounts();
    }
    if (sent > 0) sentTick.value++;
    if (sent > 0 || refused > 0) _tell(sent, refused);
    return sent;
  }

  static Future<String?> _token() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('token');
    } catch (_) {
      return null;
    }
  }

  static Future<_R> _sendOne(OfflineEntry e, String token) async {
    try {
      final h = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'X-Request-Id': e.id,
      };
      final u = Uri.parse(_full(e.path));
      final b = e.body.isEmpty ? '{}' : e.body;
      const limit = Duration(seconds: 40);
      http.Response res;
      if (e.isMultipart) {
        final req = http.MultipartRequest(e.method, u);
        req.headers['Authorization'] = 'Bearer $token';
        req.headers['X-Request-Id'] = e.id;
        req.fields.addAll(e.fields);
        for (final f in e.files) {
          final file = File(f['file'] ?? '');
          if (!await file.exists()) continue; // photo lost: send the rest
          final parts = (f['type'] ?? 'image/jpeg').split('/');
          req.files.add(http.MultipartFile.fromBytes(f['field'] ?? 'photo', await file.readAsBytes(),
              filename: f['name'] ?? 'photo.jpg', contentType: MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg')));
        }
        final streamed = await req.send().timeout(const Duration(seconds: 120));
        res = await http.Response.fromStream(streamed);
      } else {
      switch (e.method) {
        case 'PUT':
          res = await http.put(u, headers: h, body: b).timeout(limit);
          break;
        case 'PATCH':
          res = await http.patch(u, headers: h, body: b).timeout(limit);
          break;
        case 'DELETE':
          res = await http.delete(u, headers: h, body: e.body.isEmpty ? null : e.body).timeout(limit);
          break;
        default:
          res = await http.post(u, headers: h, body: b).timeout(limit);
      }
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return _R.sent;
      if (isUnreachableStatus(res.statusCode)) return _R.later;
      if (res.statusCode == 401) {
        // sign-in problem: leave it waiting; the normal screens will ask to sign in again
        return _R.later;
      }
      if (res.statusCode >= 500) {
        e.tries++;
        e.error = _msg(res);
        if (e.tries >= 5) {
          e.status = 'failed';
          return _R.refused;
        }
        return _R.later;
      }
      // 4xx: the server said no. Keep it, show why.
      e.status = 'failed';
      e.error = _msg(res);
      return _R.refused;
    } catch (err) {
      if (isNetworkError(err)) return _R.later;
      e.tries++;
      e.error = err.toString();
      if (e.tries >= 5) {
        e.status = 'failed';
        return _R.refused;
      }
      return _R.later;
    }
  }

  static String _full(String path) {
    if (path.startsWith('http')) return path;
    return '${AppConfig.apiBaseUrl}${path.startsWith('/') ? '' : '/'}$path';
  }

  static String _msg(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      if (d is Map && d['error'] != null && d['error'].toString().trim().isNotEmpty) return d['error'].toString();
      if (d is Map && d['message'] != null && d['message'].toString().trim().isNotEmpty) return d['message'].toString();
    } catch (_) {}
    if (res.statusCode == 403) return 'You do not have permission to do this.';
    if (res.statusCode == 404) return 'Not found. It may have been removed.';
    return 'The server could not accept this (${res.statusCode}).';
  }

  static void _tell(int sent, int refused) {
    try {
      final m = appMessengerKey.currentState;
      if (m == null) return;
      final parts = <String>[];
      if (sent > 0) parts.add(sent == 1 ? '1 saved entry was sent' : '$sent saved entries were sent');
      if (refused > 0) parts.add(refused == 1 ? '1 entry could not be sent - open "Not sent" to see why' : '$refused entries could not be sent - open "Not sent" to see why');
      m.showSnackBar(SnackBar(
        content: Text(parts.join('. ')),
        backgroundColor: refused > 0 ? const Color(0xFFB45309) : const Color(0xFF3B7A28),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {}
  }
}

enum _R { sent, later, refused }
