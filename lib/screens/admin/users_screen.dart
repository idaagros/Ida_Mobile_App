// lib/screens/admin/users_screen.dart
//
// Users & permissions (Oct 2026 redesign, group F): everyone who can
// sign in, with a search and All / Can sign in / Admins / Off filters.
// Tap a person to open them (user_form_screen.dart), + to add someone.
// The server leaves out the signed-in admin, so an admin can never
// switch off their own admin by mistake.
// Web counterpart: src/pages/Users.jsx.
// API: GET /admin/users

import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'admin_common.dart';
import 'user_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _raw = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AdminApi.get('/admin/users');
      final list = d is List ? d : const [];
      if (!mounted) return;
      setState(() => _raw = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AppUser> get _users => _raw.map((m) => AppUser.fromJson(m)).toList();

  Future<void> _open(Map<String, dynamic>? raw) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UserFormScreen(existing: raw, others: _raw.where((m) => m != raw).toList())),
    );
    if (saved == true) {
      await _load();
      if (mounted) showOk(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _users;
    final counts = {
      'all': all.length,
      'active': all.where((u) => u.isActive).length,
      'admin': all.where((u) => u.isAdmin).length,
      'off': all.where((u) => !u.isActive).length,
    };
    final q = _search.trim().toLowerCase();
    final shown = <int>[];
    for (var i = 0; i < all.length; i++) {
      final u = all[i];
      if (_filter == 'active' && !u.isActive) continue;
      if (_filter == 'admin' && !u.isAdmin) continue;
      if (_filter == 'off' && u.isActive) continue;
      if (q.isNotEmpty && !u.displayName.toLowerCase().contains(q) && !u.username.toLowerCase().contains(q)) continue;
      shown.add(i);
    }

    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Users & permissions', actions: [
        IconButton(tooltip: 'Add user', icon: const Icon(Icons.person_add_alt_1), onPressed: () => _open(null)),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: aInput('Search', hint: 'Name or username', suffix: const Icon(Icons.search)),
            ),
            const SizedBox(height: 10),
            AFilterChips<String>(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
              options: [
                ('all', 'All', counts['all']),
                ('active', 'Can sign in', counts['active']),
                ('admin', 'Admins', counts['admin']),
                ('off', 'Off', counts['off']),
              ],
            ),
            const SizedBox(height: 10),
            AErrorBox(_error),
            if (_loading && _raw.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (!_loading && shown.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Text('Nobody here.', textAlign: TextAlign.center, style: TextStyle(color: aMuted)),
              ),
            if (shown.isNotEmpty)
              ACard(
                child: Column(children: [
                  for (var k = 0; k < shown.length; k++) _row(all[shown[k]], _raw[shown[k]], k == 0),
                ]),
              ),
            const SizedBox(height: 12),
            const Text('You are not in this list, so you can’t switch off your own admin by mistake.',
                style: TextStyle(fontSize: 12.5, color: aMuted)),
          ],
        ),
      ),
    );
  }

  Widget _row(AppUser u, Map<String, dynamic> raw, bool first) {
    final areas = u.isAdmin ? 'Everything' : _areasText(u.permissions);
    final face = raw['face_enrolled_at'] != null;
    return InkWell(
      onTap: () => _open(raw),
      child: Opacity(
        opacity: u.isActive ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
          child: Row(children: [
            AAvatar(u.displayName, orange: u.isAdmin),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: aText)),
                const SizedBox(height: 2),
                Text('@${u.username}${face ? ' · face login' : ''} · $areas',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: aMuted)),
              ]),
            ),
            const SizedBox(width: 8),
            if (u.isAdmin)
              const AChip('Admin', bg: Color(0xFFFDE6D2), fg: Color(0xFF8C3F06))
            else if (!u.isActive)
              const AChip('Off'),
            const Icon(Icons.chevron_right, color: aMuted),
          ]),
        ),
      ),
    );
  }
}

String _areasText(List<PermissionEntry> perms) {
  final mods = perms.where((p) => p.scope == null).map((p) => p.module).toSet();
  final parts = perms.where((p) => p.scope != null).length;
  final a = mods.length;
  final s = '$a area${a == 1 ? '' : 's'}';
  return parts > 0 ? '$s + $parts part${parts == 1 ? '' : 's'}' : s;
}
