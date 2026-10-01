// lib/screens/password_screen.dart
//
// Password manager (Oct 2026 redesign, group F). Logins for banks,
// portals and suppliers.
//  - Admins go straight in, can add / change / delete logins and
//    categories, and see "Who looked" and who has it open right now.
//  - Everyone else opens it with a code from an admin, in three steps:
//    ask for access → an admin approves (OTP approvals) and tells the
//    6-digit code by phone or WhatsApp → type the code. It then stays
//    open on this phone for 30 minutes (the SERVER checks this: the
//    access token is sent as x-password-token, kept on the phone only
//    until it runs out).
//  - The list never holds passwords. Show / Copy fetches one password
//    and the server notes who looked. A shown password hides again
//    after 20 seconds.
// Web counterpart: src/pages/PasswordManager.jsx.
// API: /passwords/access/me|close|open, /passwords/otp/request|status|verify,
//      /passwords/categories, /passwords/entries (+ /:id/secret), /passwords/views

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'admin/admin_common.dart';

const String _tokenKey = 'password_access_token';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  bool _loading = true;
  bool _admin = false;
  bool _open = false;
  String? _token;
  DateTime? _until;
  String? _error;
  String? _notice;

  // Gate
  String _stage = 'start'; // start | waiting | code
  int? _requestId;
  Timer? _poll;
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  // Vault
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _entries = [];
  int? _cat;
  String _search = '';
  Timer? _searchDebounce;
  Timer? _clock;
  final Map<int, String> _shown = {};
  final Map<int, Timer> _hideTimers = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _searchDebounce?.cancel();
    for (final t in _hideTimers.values) {
      t.cancel();
    }
    _code.dispose();
    super.dispose();
  }

  Map<String, String>? get _hdr => _token == null ? null : {'x-password-token': _token!};

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _admin = await ApiService.isAdmin();
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final me = await AdminApi.get('/passwords/access/me', headers: _hdr);
      if (me is Map && (me['admin'] == true || me['open'] == true)) {
        _admin = me['admin'] == true || _admin;
        _setOpen(me['seconds_left']);
        await _loadVault();
      } else {
        await _forgetToken();
        final r = me is Map ? me['request'] : null;
        if (r is Map && r['id'] != null) {
          _requestId = int.tryParse('${r['id']}');
          if (r['status'] == 'approved') {
            _stage = 'code';
          } else {
            _stage = 'waiting';
            _startPolling();
          }
        }
      }
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setOpen(dynamic secondsLeft) {
    _open = true;
    final s = int.tryParse('${secondsLeft ?? ''}');
    _until = _admin || s == null ? null : DateTime.now().add(Duration(seconds: s));
    _clock?.cancel();
    if (_until != null) {
      _clock = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!mounted) return;
        if (DateTime.now().isAfter(_until!)) {
          _lock('Your 30 minutes are up. Ask an admin for a new code.');
        } else {
          setState(() {});
        }
      });
    }
  }

  Future<void> _forgetToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> _lock(String message) async {
    _clock?.cancel();
    await _forgetToken();
    if (!mounted) return;
    setState(() {
      _open = false;
      _stage = 'start';
      _requestId = null;
      _entries = [];
      _shown.clear();
      _notice = message;
    });
  }

  // A 403 with needsOtp means the 30 minutes ran out or an admin closed it.
  Future<bool> _handleLocked(Object e) async {
    if (e is AdminApiError && e.status == 403 && e.data['needsOtp'] == true) {
      await _lock('The password manager closed. Ask an admin for a new code.');
      return true;
    }
    return false;
  }

  // ── Gate ────────────────────────────────────────────────────────────
  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await AdminApi.post('/passwords/otp/request', {});
      if (r is Map && r['skip'] == true) {
        await _start();
        return;
      }
      _requestId = int.tryParse('${r is Map ? (r['requestId'] ?? r['id']) : ''}');
      setState(() => _stage = 'waiting');
      _startPolling();
    } catch (e) {
      setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      final id = _requestId;
      if (id == null || !mounted) return;
      try {
        final r = await AdminApi.get('/passwords/otp/status/$id');
        final st = r is Map ? '${r['status']}' : '';
        if (!mounted) return;
        if (st == 'approved') {
          _poll?.cancel();
          setState(() => _stage = 'code');
        } else if (st == 'rejected' || st == 'expired' || st == 'used') {
          _poll?.cancel();
          setState(() {
            _stage = 'start';
            _requestId = null;
            _error = st == 'rejected' ? 'The admin said no to this request.' : 'The request ran out. Please ask again.';
          });
        }
      } catch (_) {/* try again on the next tick */}
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6 || _requestId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await AdminApi.post('/passwords/otp/verify', {'requestId': _requestId, 'code': code});
      final tok = r is Map ? r['sessionToken']?.toString() : null;
      if (tok == null) throw AdminApiError('Could not open it. Please try again.', 500, {});
      _token = tok;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, tok);
      _code.clear();
      _setOpen(r['seconds_left']);
      await _loadVault();
    } catch (e) {
      setState(() => _error = errText(e) == 'Invalid OTP code' ? 'That code is not right. Check it with the admin.' : errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Vault ───────────────────────────────────────────────────────────
  Future<void> _loadVault() async {
    try {
      final c = await AdminApi.get('/passwords/categories');
      final q = <String>[];
      if (_cat != null) q.add('category_id=$_cat');
      if (_search.trim().isNotEmpty) q.add('search=${Uri.encodeQueryComponent(_search.trim())}');
      final e = await AdminApi.get('/passwords/entries${q.isEmpty ? '' : '?${q.join('&')}'}', headers: _hdr);
      if (!mounted) return;
      setState(() {
        _cats = (c is List ? c : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _entries = (e is List ? e : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _error = null;
      });
    } catch (e) {
      if (await _handleLocked(e)) return;
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Future<String?> _secret(Map<String, dynamic> entry, String purpose) async {
    try {
      final r = await AdminApi.get('/passwords/entries/${entry['id']}/secret?for=$purpose', headers: _hdr);
      return r is Map ? '${r['password'] ?? ''}' : '';
    } catch (e) {
      if (await _handleLocked(e)) return null;
      if (mounted) showErr(context, errText(e));
      return null;
    }
  }

  Future<void> _show(Map<String, dynamic> entry) async {
    final id = int.tryParse('${entry['id']}') ?? 0;
    if (_shown.containsKey(id)) {
      _hideTimers.remove(id)?.cancel();
      setState(() => _shown.remove(id));
      return;
    }
    final pw = await _secret(entry, 'show');
    if (pw == null || !mounted) return;
    setState(() => _shown[id] = pw);
    _hideTimers[id]?.cancel();
    _hideTimers[id] = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _shown.remove(id));
    });
  }

  Future<void> _copyPassword(Map<String, dynamic> entry) async {
    final pw = await _secret(entry, 'copy');
    if (pw == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: pw));
    if (mounted) showOk(context, 'Password copied');
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showOk(context, '$what copied');
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _closeMine() async {
    try {
      await AdminApi.post('/passwords/access/close', {}, _hdr);
    } catch (_) {}
    await _lock('Closed. Ask an admin for a code to open it again.');
  }

  void _onSearch(String v) {
    _search = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadVault);
  }

  // ── Admin: entries and categories ───────────────────────────────────
  Future<void> _editEntry([Map<String, dynamic>? entry]) async {
    if (_cats.isEmpty) {
      showErr(context, 'Add a category first.');
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EntrySheet(entry: entry, cats: _cats, initialCat: _cat),
    );
    if (saved == true) {
      await _loadVault();
      if (mounted) showOk(context, 'Saved');
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    if (!await aConfirm(context, 'Delete this login?', '${entry['service_name']} will be removed for everyone.', yes: 'Delete', danger: true)) return;
    try {
      await AdminApi.delete('/passwords/entries/${entry['id']}');
      await _loadVault();
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    }
  }

  Future<void> _editCategory([Map<String, dynamic>? cat]) async {
    final ctrl = TextEditingController(text: cat?['name']?.toString() ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? 'New category' : 'Rename category'),
        content: TextField(controller: ctrl, autofocus: true, decoration: aInput('Name', hint: 'e.g. Banking')),
        actions: [
          if (cat != null)
            TextButton(onPressed: () => Navigator.pop(ctx, '\u0000delete'), child: const Text('Delete', style: TextStyle(color: aRed))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: aGreen), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      if (name == '\u0000delete' && cat != null) {
        await AdminApi.delete('/passwords/categories/${cat['id']}');
        if (_cat == int.tryParse('${cat['id']}')) _cat = null;
      } else if (cat == null) {
        await AdminApi.post('/passwords/categories', {'name': name});
      } else {
        await AdminApi.put('/passwords/categories/${cat['id']}', {'name': name});
      }
      await _loadVault();
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Password manager', actions: [
        if (_open && _admin)
          IconButton(
            tooltip: 'Who looked',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WhoLookedScreen())),
          ),
        if (_open && _admin)
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: 'Add',
            onSelected: (v) => v == 'cat' ? _editCategory() : _editEntry(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'entry', child: Text('Add password')),
              PopupMenuItem(value: 'cat', child: Text('Add category')),
            ],
          ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _open
              ? _vault()
              : _gate(),
    );
  }

  Widget _gate() {
    Widget step(int n, String title, String sub, {required bool done, required bool on, Widget? child}) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: done ? aSoftGreen : (on ? aGreen : aSoftGrey)),
              child: done
                  ? const Icon(Icons.check, size: 18, color: aGreenDark)
                  : Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : const Color(0xFF4A5643))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on || done ? aText : aMuted)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13, color: aMuted)),
                if (child != null) ...[const SizedBox(height: 10), child],
              ]),
            ),
          ]),
        );
    final s = _stage;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), children: [
      if (_notice != null) ...[ANote(_notice!, icon: Icons.lock_clock, warn: true), const SizedBox(height: 12)],
      ACard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock_outline, size: 24, color: aText),
            SizedBox(width: 10),
            Expanded(child: Text('Ask an admin to open it', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: aText))),
          ]),
          const SizedBox(height: 18),
          step(1, 'Ask for access', s == 'start' ? '' : 'Sent', done: s != 'start', on: s == 'start',
              child: s == 'start'
                  ? FilledButton(style: aPrimary(), onPressed: _busy ? null : _ask, child: Text(_busy ? 'Asking…' : 'Ask for access'))
                  : null),
          step(2, 'Admin approves', s == 'waiting' ? 'Waiting… The admin will tell you a 6-digit code by phone or WhatsApp.' : (s == 'code' ? 'Approved' : ''),
              done: s == 'code', on: s == 'waiting',
              child: s == 'waiting' ? const LinearProgressIndicator(minHeight: 3, color: aGreen, backgroundColor: aSoftGreen) : null),
          step(3, 'Type the code', '', done: false, on: s == 'code',
              child: s == 'code'
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _code,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _verify(),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                        decoration: aInput('6-digit code').copyWith(counterText: ''),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(style: aPrimary(), onPressed: _busy || _code.text.trim().length != 6 ? null : _verify, child: Text(_busy ? 'Opening…' : 'Open')),
                    ])
                  : null),
        ]),
      ),
      const SizedBox(height: 12),
      AErrorBox(_error),
      const SizedBox(height: 8),
      const Text('Once open, it stays open for 30 minutes on this phone.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: aMuted)),
    ]);
  }

  Widget _vault() {
    final left = _until?.difference(DateTime.now());
    final total = _cats.fold<int>(0, (s, c) => s + (int.tryParse('${c['entry_count']}') ?? 0));
    return RefreshIndicator(
      onRefresh: _loadVault,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
        if (!_admin && _until != null) ...[
          ACard(
            color: const Color(0xFFF3F8EE),
            border: const Color(0xFFCFE3C0),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              const Icon(Icons.lock_open, size: 18, color: Color(0xFF1F4A0E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Open until ${TimeOfDay.fromDateTime(_until!).format(context)} (${(left?.inMinutes ?? 0).clamp(0, 999)} min). Every password you open is noted for the admin.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1F4A0E)),
                ),
              ),
              TextButton(onPressed: _closeMine, child: const Text('Close')),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        TextField(onChanged: _onSearch, decoration: aInput('Search', hint: 'Service, company or username', suffix: const Icon(Icons.search))),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _catChip(null, 'All', total),
            for (final c in _cats) _catChip(c, '${c['name']}', int.tryParse('${c['entry_count']}') ?? 0),
          ]),
        ),
        if (_admin) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Long-press a category to rename or delete it.', style: TextStyle(fontSize: 12, color: aMuted))),
        const SizedBox(height: 10),
        AErrorBox(_error),
        if (_entries.isEmpty)
          const Padding(padding: EdgeInsets.all(30), child: Text('No logins here yet.', textAlign: TextAlign.center, style: TextStyle(color: aMuted)))
        else
          ACard(child: Column(children: [for (var i = 0; i < _entries.length; i++) _entryRow(_entries[i], i == 0)])),
        const SizedBox(height: 10),
        const Text('A shown password hides again after 20 seconds.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: aMuted)),
      ]),
    );
  }

  Widget _catChip(Map<String, dynamic>? c, String label, int count) {
    final id = c == null ? null : int.tryParse('${c['id']}');
    final on = _cat == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          setState(() => _cat = id);
          _loadVault();
        },
        onLongPress: _admin && c != null ? () => _editCategory(c) : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? aDark : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? aDark : const Color(0xFFD5DCCD)),
          ),
          child: Text('$label  $count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : const Color(0xFF34422D))),
        ),
      ),
    );
  }

  Widget _entryRow(Map<String, dynamic> e, bool first) {
    final id = int.tryParse('${e['id']}') ?? 0;
    final shown = _shown[id];
    final user = '${e['username'] ?? ''}';
    final url = '${e['url'] ?? ''}';
    final notes = '${e['remarks'] ?? ''}';
    final sub = [e['category_name'], e['company'] ?? e['provider']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    Widget line(String label, Widget value, List<Widget> actions) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 13, color: aMuted))),
            Expanded(child: value),
            ...actions,
          ]),
        );
    Widget iconBtn(IconData icon, String tip, VoidCallback onTap, {bool on = false}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 19, color: on ? aGreen : const Color(0xFF4A5643)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['service_name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: aText)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: aMuted)),
            ]),
          ),
          if (_admin)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'edit' ? _editEntry(e) : _deleteEntry(e),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Change')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: aRed))),
              ],
            ),
        ]),
        if (user.isNotEmpty)
          line('Username', Text(user, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)), [
            iconBtn(Icons.copy, 'Copy username', () => _copy(user, 'Username')),
          ]),
        if (e['has_password'] == true)
          line(
              'Password',
              SelectableText(shown ?? '••••••••••', maxLines: 1, style: TextStyle(fontSize: 14, fontFamily: 'monospace', letterSpacing: shown == null ? 2 : 0.5)),
              [
                iconBtn(shown == null ? Icons.visibility_outlined : Icons.visibility_off_outlined, shown == null ? 'Show password' : 'Hide password', () => _show(e), on: shown != null),
                iconBtn(Icons.copy, 'Copy password', () => _copyPassword(e)),
              ]),
        if (url.isNotEmpty)
          line(
              'Website',
              InkWell(
                onTap: () => _openUrl(url),
                child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFF3F6A23), decoration: TextDecoration.underline)),
              ),
              [iconBtn(Icons.copy, 'Copy website', () => _copy(url, 'Website'))]),
        if (notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, right: 10), child: Text(notes, style: const TextStyle(fontSize: 13, color: aMuted))),
      ]),
    );
  }
}

// ── Add / change a login (admins) ─────────────────────────────────────
class _EntrySheet extends StatefulWidget {
  final Map<String, dynamic>? entry;
  final List<Map<String, dynamic>> cats;
  final int? initialCat;
  const _EntrySheet({this.entry, required this.cats, this.initialCat});
  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late int? _cat;
  late final Map<String, TextEditingController> _c;
  bool _saving = false;
  String? _error;
  static const _fields = ['service_name', 'company', 'provider', 'username', 'password', 'url', 'remarks'];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _cat = int.tryParse('${e?['category_id'] ?? widget.initialCat ?? widget.cats.first['id']}');
    _c = {for (final f in _fields) f: TextEditingController(text: f == 'password' ? '' : '${e?[f] ?? ''}')};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final isNew = widget.entry == null;
    if (_c['service_name']!.text.trim().isEmpty) {
      setState(() => _error = 'Please give the service a name.');
      return;
    }
    if (isNew && _c['password']!.text.isEmpty) {
      setState(() => _error = 'Please type the password.');
      return;
    }
    final body = <String, dynamic>{'category_id': _cat};
    for (final f in _fields) {
      body[f] = _c[f]!.text.trim();
    }
    if (!isNew && _c['password']!.text.isEmpty) body.remove('password');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (isNew) {
        await AdminApi.post('/passwords/entries', body);
      } else {
        await AdminApi.put('/passwords/entries/${widget.entry!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry == null;
    const labels = {
      'service_name': 'Service',
      'company': 'Company',
      'provider': 'Provider',
      'username': 'Username',
      'password': 'Password',
      'url': 'Website',
      'remarks': 'Notes',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(isNew ? 'Add password' : 'Change login', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: _cat,
              decoration: aInput('Category'),
              items: [for (final c in widget.cats) DropdownMenuItem(value: int.tryParse('${c['id']}') ?? 0, child: Text('${c['name']}'))],
              onChanged: (v) => setState(() => _cat = v),
            ),
            for (final f in _fields) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _c[f],
                autocorrect: false,
                maxLines: f == 'remarks' ? 2 : 1,
                decoration: aInput(labels[f]!, hint: f == 'password' && !isNew ? 'Leave empty to keep the saved one' : null),
              ),
            ],
            const SizedBox(height: 12),
            AErrorBox(_error),
            const SizedBox(height: 12),
            FilledButton(style: aPrimary(), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          ]),
        ),
      ),
    );
  }
}

// ── Who looked + open right now (admins) ──────────────────────────────
class _WhoLookedScreen extends StatefulWidget {
  const _WhoLookedScreen();
  @override
  State<_WhoLookedScreen> createState() => _WhoLookedScreenState();
}

class _WhoLookedScreenState extends State<_WhoLookedScreen> {
  List<Map<String, dynamic>> _views = [];
  List<Map<String, dynamic>> _open = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await AdminApi.get('/passwords/views?days=30');
      final o = await AdminApi.get('/passwords/access/open');
      if (!mounted) return;
      setState(() {
        _views = (v is List ? v : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _open = (o is List ? o : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _close(Map<String, dynamic> a) async {
    if (!await aConfirm(context, 'Close it now?', 'The password manager closes for ${a['user_name']} on every device.', yes: 'Close now', danger: true)) return;
    try {
      await AdminApi.post('/passwords/access/${a['id']}/close', {});
      await _load();
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    }
  }

  String _when(String s) {
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (d == null) return s;
    final now = DateTime.now();
    final t = TimeOfDay.fromDateTime(d).format(context);
    if (d.year == now.year && d.month == now.month && d.day == now.day) return t;
    final y = now.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday $t';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    const word = {'show': 'saw', 'copy': 'copied', 'edit': 'opened'};
    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Who looked'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
                AErrorBox(_error),
                const Text('OPEN RIGHT NOW', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: aMuted)),
                const SizedBox(height: 6),
                ACard(
                  child: _open.isEmpty
                      ? const Padding(padding: EdgeInsets.all(14), child: Text('Nobody.', style: TextStyle(color: aMuted)))
                      : Column(children: [
                          for (final a in _open)
                            ListTile(
                              leading: AAvatar('${a['user_name']}', size: 36),
                              title: Text('${a['user_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('closes at ${a['closes_at']} · ${((int.tryParse('${a['seconds_left']}') ?? 0) / 60).round()} min left'
                                  '${(int.tryParse('${a['devices']}') ?? 1) > 1 ? ' · ${a['devices']} devices' : ''}'),
                              trailing: OutlinedButton(style: aSecondary(height: 36, fg: aRed), onPressed: () => _close(a), child: const Text('Close')),
                            ),
                        ]),
                ),
                const SizedBox(height: 16),
                const Text('LAST 30 DAYS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: aMuted)),
                const SizedBox(height: 6),
                ACard(
                  child: _views.isEmpty
                      ? const Padding(padding: EdgeInsets.all(14), child: Text('Nobody has opened a password yet.', style: TextStyle(color: aMuted)))
                      : Column(children: [
                          for (var i = 0; i < _views.length; i++)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text.rich(TextSpan(style: const TextStyle(fontSize: 14, color: aText), children: [
                                  TextSpan(text: '${_views[i]['user_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(text: ' ${word[_views[i]['action']] ?? 'saw'} '),
                                  TextSpan(text: '${_views[i]['service_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ])),
                                Text(_when('${_views[i]['viewed_at']}'), style: const TextStyle(fontSize: 12, color: aMuted)),
                              ]),
                            ),
                        ]),
                ),
              ]),
            ),
    );
  }
}
