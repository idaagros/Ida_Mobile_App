// lib/screens/admin/user_form_screen.dart
//
// One person (Oct 2026 redesign, group F) — or a new one when `existing`
// is null. Same rules as the website's Users & permissions page:
//  - Can sign in / Admin switches, name, username (new only), password
//    (new) or a new password (leave empty to keep it).
//  - Access: a tab per group (Factory / Office / Farms / Dispatch &
//    sales); each area shows chips for the actions it has (View, Add,
//    Edit, Delete, Approve). Outward register and Farm attendance can
//    instead give Edit on single parts ("Or only these parts").
//  - Copy access from another person; View everything; Clear all.
//  - Face login: set it up or redo it here (needs the camera).
//  - A bar at the bottom says how many changes are not saved yet.
// Permission shape sent to the server: {module, level} per level, plus
// {module, scope, level:'update'} per part. The old combined 'edit'
// level reads as add + update + delete.
// Web counterpart: src/pages/Users.jsx.
// API: POST /admin/users, PUT /admin/users/:id

import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'admin_common.dart';
import 'user_face_enrollment_screen.dart';

// Same grouping and short names as the website (moduleDefinitions.js).
const List<(String, String, List<(String, String, String)>)> kPermGroups = [
  ('factory', 'Factory', [
    ('electricity', 'Electricity meter', ''),
    ('tractor', 'Factory tractor', 'hours & diesel'),
    ('machine', 'Machine hours', ''),
    ('machine_pf', 'Power factor', ''),
    ('factory', 'Factory run hours', ''),
    ('labour', 'Labour management', ''),
    ('machine_maintenance', 'Machine maintenance', ''),
    ('tractor_maintenance', 'Tractor maintenance', ''),
    ('daily_report', 'Daily reading report', ''),
  ]),
  ('office', 'Office', [
    ('reports_analytics', 'Reports & analytics', 'report tiles'),
    ('payroll', 'Payroll', 'not built yet'),
    ('passwords', 'Password manager', 'code from admin'),
  ]),
  ('farms', 'Farms', [
    ('farm_attendance', 'Farm attendance', ''),
    ('farm_masters', 'Farm masters', 'farms, workers, work types'),
    ('farm_tractor', 'Farm tractor', ''),
    ('agri', 'Crop planning', 'crops, cycles, sprays'),
    ('mandi_prices', 'Mandi prices', ''),
  ]),
  ('dispatch', 'Dispatch & sales', [
    ('outward_register', 'Outward register', ''),
    ('destinations', 'Destinations', ''),
    ('parties', 'Parties', ''),
    ('transport', 'Transport directory', ''),
  ]),
];

const List<String> kLevelOrder = ['view', 'add', 'update', 'delete', 'approve'];
const Map<String, String> kLevelLabels = {'view': 'View', 'add': 'Add', 'update': 'Edit', 'delete': 'Delete', 'approve': 'Approve'};

String _shortName(String module) {
  for (final g in kPermGroups) {
    for (final m in g.$3) {
      if (m.$1 == module) return m.$2;
    }
  }
  return module;
}

class UserFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> others;
  const UserFormScreen({super.key, this.existing, this.others = const []});
  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  late final bool _isNew = widget.existing == null;
  late final TextEditingController _name;
  late final TextEditingController _username;
  final TextEditingController _password = TextEditingController();
  bool _active = true;
  bool _admin = false;
  Map<String, Set<String>> _perms = {};
  Set<String> _parts = {};
  // What was loaded, to tell what changed.
  late final Set<String> _before;
  late final String _nameBefore;
  late final bool _activeBefore;
  late final bool _adminBefore;
  String _tab = 'factory';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final u = e == null ? null : AppUser.fromJson(e);
    _name = TextEditingController(text: u?.displayName ?? '');
    _username = TextEditingController(text: u?.username ?? '');
    _active = u?.isActive ?? true;
    _admin = u?.isAdmin ?? false;
    _readPerms(u?.permissions ?? const []);
    _before = _flatKeys();
    _nameBefore = _name.text;
    _activeBefore = _active;
    _adminBefore = _admin;
    // Open on the first group that has something ticked.
    for (final g in kPermGroups) {
      if (g.$3.any((m) => (_perms[m.$1] ?? const <String>{}).isNotEmpty || _parts.any((p) => p.startsWith('${m.$1}::')))) {
        _tab = g.$1;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _readPerms(List<PermissionEntry> list) {
    final p = <String, Set<String>>{};
    final s = <String>{};
    for (final e in list) {
      if (e.scope != null) {
        s.add('${e.module}::${e.scope}');
        continue;
      }
      final levels = e.level == 'edit' ? const ['add', 'update', 'delete'] : [e.level];
      (p[e.module] ??= <String>{}).addAll(levels);
    }
    _perms = p;
    _parts = s;
  }

  Set<String> _flatKeys() => {
        for (final e in _perms.entries)
          for (final l in e.value) '${e.key}:$l',
        for (final s in _parts) 'part:$s',
      };

  List<Map<String, String>> _flatten() => [
        for (final e in _perms.entries)
          for (final l in e.value) {'module': e.key, 'level': l},
        for (final s in _parts) {'module': s.split('::')[0], 'scope': s.split('::')[1], 'level': 'update'},
      ];

  int get _changes {
    final now = _flatKeys();
    var n = now.difference(_before).length + _before.difference(now).length;
    if (_name.text.trim() != _nameBefore.trim()) n++;
    if (_active != _activeBefore) n++;
    if (_admin != _adminBefore) n++;
    if (_password.text.isNotEmpty) n++;
    if (_isNew && _username.text.trim().isNotEmpty) n++;
    return n;
  }

  void _toggle(String module, String level) {
    setState(() {
      final set = _perms[module] ?? <String>{};
      if (set.contains(level)) {
        set.remove(level);
      } else {
        set.add(level);
      }
      if (set.isEmpty) {
        _perms.remove(module);
      } else {
        _perms[module] = set;
      }
    });
  }

  void _togglePart(String module, String part) {
    final k = '$module::$part';
    setState(() {
      if (!_parts.remove(k)) _parts.add(k);
    });
  }

  void _viewEverything() {
    setState(() {
      for (final m in kModuleDefinitions) {
        (_perms[m['key']!] ??= <String>{}).add('view');
      }
    });
  }

  Future<void> _copyFrom() async {
    final others = widget.others;
    if (others.isEmpty) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Copy access from…', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Their ticks replace the ones here. You can still change them before saving.', style: TextStyle(fontSize: 13, color: aMuted)),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final o in others)
                  ListTile(
                    leading: AAvatar('${o['display_name'] ?? o['username'] ?? ''}', orange: o['is_admin'] == true, size: 36),
                    title: Text('${o['display_name'] ?? o['username'] ?? ''}'),
                    subtitle: Text(o['is_admin'] == true ? 'Admin' : '@${o['username'] ?? ''}'),
                    onTap: () => Navigator.pop(ctx, o),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    final src = AppUser.fromJson(picked);
    setState(() {
      if (src.isAdmin) {
        _admin = true;
      } else {
        _readPerms(src.permissions);
      }
    });
  }

  Future<void> _face() async {
    final e = widget.existing;
    if (e == null) return;
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UserFaceEnrollmentScreen(userId: '${e['id']}', userName: '${e['display_name'] ?? e['username'] ?? ''}')),
    );
    if (done == true && mounted) showOk(context, 'Face login saved');
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _name.text.trim();
    final username = _username.text.trim();
    final pw = _password.text;
    String? err;
    if (name.isEmpty) {
      err = 'Please give a name.';
    } else if (_isNew && username.isEmpty) {
      err = 'Please give a username.';
    } else if (_isNew && RegExp(r'\s').hasMatch(username)) {
      err = 'A username can’t have spaces.';
    } else if (_isNew && pw.isEmpty) {
      err = 'Please set a password.';
    } else if (pw.isNotEmpty && pw.length < 4) {
      err = 'The password needs at least 4 characters.';
    } else if (!_admin && _flatKeys().isEmpty) {
      err = 'Tick at least one thing this person can do, or make them admin.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final body = <String, dynamic>{
      'display_name': name,
      'is_active': _active,
      'is_admin': _admin,
      'permissions': _flatten(),
      if (pw.isNotEmpty) 'password': pw,
    };
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await AdminApi.post('/admin/users', {...body, 'username': username.toLowerCase()});
      } else {
        await AdminApi.put('/admin/users/${widget.existing!['id']}', body);
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
    final changes = _changes;
    final e = widget.existing;
    final title = _isNew ? 'New user' : (_name.text.trim().isEmpty ? '${e?['username'] ?? ''}' : _name.text.trim());
    final faceAt = e?['face_enrolled_at'];
    String faceText = 'No face login yet';
    if (faceAt != null) {
      final d = DateTime.tryParse('$faceAt');
      faceText = d == null ? 'Face login set up' : 'Face login set up on ${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
    }

    return PopScope(
      canPop: changes == 0 || _saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await aConfirm(context, 'Leave without saving?', 'Your $changes change${changes == 1 ? '' : 's'} will be lost.', yes: 'Leave', danger: true);
        if (leave && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: aBg,
        appBar: adminBar(title),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            ACard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  AAvatar(_name.text.isEmpty ? '?' : _name.text, orange: _admin, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: aText)),
                      Text(_isNew ? 'They sign in with the username and password you set here.' : '@${e?['username'] ?? ''} · $faceText',
                          style: const TextStyle(fontSize: 12.5, color: aMuted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can sign in', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _active,
                  activeTrackColor: aGreen,
                  onChanged: (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Admin', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Can do everything', style: TextStyle(fontSize: 12.5)),
                  value: _admin,
                  activeTrackColor: const Color(0xFFD9650F),
                  onChanged: (v) => setState(() => _admin = v),
                ),
                const SizedBox(height: 6),
                TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: aInput('Name', hint: 'e.g. Ramesh Patil')),
                const SizedBox(height: 10),
                TextField(
                  controller: _username,
                  enabled: _isNew,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: aInput('Username', hint: 'e.g. ramesh', helper: _isNew ? null : 'A username can’t be changed'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: aInput(_isNew ? 'Password' : 'New password',
                      hint: _isNew ? 'At least 4 characters' : 'Leave empty to keep the current one'),
                ),
                if (!_isNew) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: aSecondary(),
                    onPressed: _face,
                    icon: const Icon(Icons.face_outlined, size: 19),
                    label: Text(faceAt == null ? 'Set up face login' : 'Redo face login'),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Access', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: aText)),
              const Spacer(),
              if (widget.others.isNotEmpty)
                TextButton.icon(onPressed: _copyFrom, icon: const Icon(Icons.copy_all_outlined, size: 18), label: const Text('Copy from…')),
            ]),
            if (_admin)
              const ANote('An admin can see and do everything, so there is nothing to tick.')
            else ...[
              const Text('Tick what this person may do. Only the actions an area has are shown.', style: TextStyle(fontSize: 13, color: aMuted)),
              const SizedBox(height: 10),
              AFilterChips<String>(
                value: _tab,
                onChanged: (v) => setState(() => _tab = v),
                options: [
                  for (final g in kPermGroups)
                    (g.$1, g.$2, g.$3.where((m) => (_perms[m.$1] ?? const <String>{}).isNotEmpty || _parts.any((p) => p.startsWith('${m.$1}::'))).length),
                ],
              ),
              const SizedBox(height: 10),
              ACard(
                child: Column(children: [
                  for (final g in kPermGroups)
                    if (g.$1 == _tab)
                      for (var i = 0; i < g.$3.length; i++) _area(g.$3[i], i == 0),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: _viewEverything, child: const Text('View everything')),
                TextButton(
                  onPressed: () => setState(() {
                    _perms = {};
                    _parts = {};
                  }),
                  child: const Text('Clear all', style: TextStyle(color: aRed)),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            AErrorBox(_error),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E6DC)))),
            child: Row(children: [
              if (changes > 0) AChip.wait('$changes change${changes == 1 ? '' : 's'}') else const Text('No changes', style: TextStyle(color: aMuted, fontSize: 13)),
              const Spacer(),
              FilledButton.icon(
                style: aPrimary(height: 46),
                onPressed: _saving || changes == 0 ? null : _save,
                icon: Icon(_isNew ? Icons.person_add_alt_1 : Icons.check, size: 19),
                label: Text(_saving ? 'Saving…' : (_isNew ? 'Add user' : 'Save')),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _area((String, String, String) m, bool first) {
    final module = m.$1;
    final supported = moduleSupportedLevels(module);
    final got = _perms[module] ?? const <String>{};
    final parts = kSectionedModules[module];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: m.$2, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: aText)),
          if (m.$3.isNotEmpty) TextSpan(text: '  · ${m.$3}', style: const TextStyle(fontSize: 12, color: aMuted)),
        ])),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in kLevelOrder)
            if (supported.contains(l)) _levelChip(module, l, got.contains(l)),
        ]),
        if (parts != null) ...[
          const SizedBox(height: 8),
          const Text('Or Edit only these parts:', style: TextStyle(fontSize: 12.5, color: aMuted)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in parts) _partChip(module, p['key']!, _partLabel(p['label']!), _parts.contains('$module::${p['key']}')),
          ]),
        ],
      ]),
    );
  }

  String _partLabel(String l) => l.replaceFirst('Stage A: ', '').replaceFirst('Stage B: ', '');

  Widget _levelChip(String module, String level, bool on) {
    final color = level == 'approve' ? aBlue : (level == 'delete' ? const Color(0xFFB3392B) : aGreen);
    return Semantics(
      checked: on,
      label: '${_shortName(module)}: ${kLevelLabels[level]}',
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => _toggle(module, level),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: on ? color : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? color : const Color(0xFFC3CCB9)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 15, color: Colors.white)),
            Text(kLevelLabels[level]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF3A4833))),
          ]),
        ),
      ),
    );
  }

  Widget _partChip(String module, String key, String label, bool on) => InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => _togglePart(module, key),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFEEF5E8) : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? const Color(0xFF9CC27D) : const Color(0xFFD5DCCD)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 14, color: Color(0xFF1F4A0E))),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? const Color(0xFF1F4A0E) : const Color(0xFF3A4833))),
          ]),
        ),
      );
}
