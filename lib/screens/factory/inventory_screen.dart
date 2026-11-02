// lib/screens/factory/inventory_screen.dart — Inventory (stores): spares, consumables and wear-out alerts (Nov 2026)
//
// Everything is editable here: categories, items, units, minimum levels and wear-out rules (life in tonnes of pellets made,
// plant run hours, or days). "Fitted / changed" takes a part out of stock and restarts its life count; the ring shows how
// much of its life is used. Low stock and "change now" alerts are on top. Re-reads itself every 15 minutes.
// Who: admins, and users ticked for "Inventory" in Users & permissions (View, Add, Edit = use / fit / count, Delete).
// API: /inventory (routes/inventory.js).  Web counterpart: src/pages/Inventory.jsx.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_model.dart';
import '../../services/api_client.dart';

const _kKey = 'inventory';
const _green = Color(0xFF1E4012);

Color _stateColor(String s) {
  switch (s) {
    case 'due':
      return const Color(0xFFC62828);
    case 'soon':
      return const Color(0xFFE08A00);
    case 'ok':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF78909C);
  }
}

Color _hex(String? h, Color fallback) {
  if (h == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(h)) return fallback;
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}

double _d(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _nf(dynamic v) {
  if (v == null) return '–';
  final x = _d(v);
  return x == x.roundToDouble()
      ? x.round().toString()
      : x
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
}

String _dmy(dynamic iso) {
  final s = '${iso ?? ''}';
  return s.length >= 10
      ? '${s.substring(8, 10)}-${s.substring(5, 7)}-${s.substring(0, 4)}'
      : s;
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
const _basisUnit = {
  'tonnes': 't of pellets',
  'hours': 'run hours',
  'days': 'days'
};
const _basisShort = {'tonnes': 't', 'hours': 'h', 'days': 'days'};

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;
  String? _msg;
  String _q = '';
  String _cat = 'all';
  bool _onlyAlerts = false;
  bool _clean = false;
  final Set<int> _picked = {};
  bool _mayAdd = false, _mayEdit = false, _mayDelete = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _perms();
    _load();
    _timer =
        Timer.periodic(const Duration(minutes: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _perms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final admin =
          prefs.getBool('is_admin') ?? (prefs.getString('role') == 'admin');
      final perms =
          parsePermissions(jsonDecode(prefs.getString('permissions') ?? '[]'));
      if (mounted) {
        setState(() {
          _mayAdd = admin || hasAddAccess(perms, _kKey);
          _mayEdit = admin || hasUpdateAccess(perms, _kKey);
          _mayDelete = admin || hasDeleteAccess(perms, _kKey);
        });
      }
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _busy = true);
    try {
      final r = await Api.json('GET', '/inventory/overview');
      if (r is! Map || r['items'] == null)
        throw ApiException(
            'The server did not answer. Check that server.js has the /api/inventory line and restart it.');
      if (mounted)
        setState(() {
          _data = Map<String, dynamic>.from(r);
          if (!silent) _error = null;
        });
    } catch (e) {
      if (!silent && mounted) setState(() => _error = Api.errorText(e));
    } finally {
      if (mounted && !silent) setState(() => _busy = false);
    }
  }

  // run a change; the server answers with the fresh overview
  Future<bool> _run(Future<dynamic> Function() fn, [String? ok]) async {
    setState(() {
      _busy = true;
      _error = null;
      _msg = null;
    });
    try {
      final r = await fn();
      if (r is Map && r['items'] != null && mounted)
        _data = Map<String, dynamic>.from(r);
      if (mounted) setState(() => _msg = ok);
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _cats =>
      ((_data?['categories'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get _items =>
      ((_data?['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> _filtered() {
    final s = _q.trim().toLowerCase();
    final rank = {'due': 0, 'soon': 1, 'ok': 2};
    final order = <dynamic, int>{};
    final cats = _cats;
    for (var k = 0; k < cats.length; k++) {
      order[cats[k]['id']] = k;
    }
    final list = _items.where((i) {
      if (_cat != 'all' &&
          (_cat == 'none'
              ? i['category_id'] != null
              : '${i['category_id']}' != _cat)) return false;
      if (_onlyAlerts && i['state'] == 'ok') return false;
      if (s.isNotEmpty) {
        final hay =
            '${i['name']} ${i['used_on'] ?? ''} ${i['part_no'] ?? ''} ${i['make'] ?? ''} ${i['location'] ?? ''}'
                .toLowerCase();
        if (!hay.contains(s)) return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      final r =
          (rank['${a['state']}'] ?? 2).compareTo(rank['${b['state']}'] ?? 2);
      if (r != 0) return r;
      final c = (order[a['category_id']] ?? 99)
          .compareTo(order[b['category_id']] ?? 99);
      if (c != 0) return c;
      return '${a['name']}'.compareTo('${b['name']}');
    });
    return list;
  }

  // ── forms ──────────────────────────────────────────────────────────
  Future<Map<String, String>?> _form(
      String title, List<_Fld> fields, String button,
      {String? top}) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _FormSheet(title: title, fields: fields, button: button, top: top),
    );
  }

  Future<void> _stockIn(Map<String, dynamic> i) async {
    final r = await _form(
        '+ Stock: ${i['name']}',
        [
          _Fld('qty', 'Quantity bought (${i['unit']})', number: true),
          _Fld('date', 'Date (blank = today)', date: true),
          _Fld('note', 'Note (supplier, bill no…)'),
        ],
        'Add stock');
    if (r == null) return;
    await _run(
        () => Api.json('POST', '/inventory/items/${i['id']}/in',
            body: _cleanBody(r)),
        'Stock added.');
  }

  Future<void> _use(Map<String, dynamic> i) async {
    final r = await _form(
        'Use: ${i['name']}',
        [
          _Fld('qty', 'Quantity used (${i['unit']})', number: true),
          _Fld('date', 'Date (blank = today)', date: true),
          _Fld('note', 'Where / why (machine, tractor…)'),
        ],
        'Record use',
        top: 'In stock: ${_nf(i['qty'])} ${i['unit']}');
    if (r == null) return;
    await _run(
        () => Api.json('POST', '/inventory/items/${i['id']}/use',
            body: _cleanBody(r)),
        'Recorded.');
  }

  Future<void> _fit(Map<String, dynamic> i) async {
    final basis = '${i['life_basis']}';
    final r = await _form(
        'Fitted / changed: ${i['name']}',
        [
          _Fld('qty', 'How many (${i['unit']})', number: true, initial: '1'),
          _Fld('label', 'Name / position (optional), e.g. Die #2'),
          if (basis != 'none')
            _Fld('used_before',
                'Already used before fitting (${_basisShort[basis]}): blank for a new part',
                number: true),
          _Fld('date', 'Date fitted (blank = today)', date: true),
          _Fld('reason', 'Why the old one was changed (optional)',
              initial: 'Changed'),
        ],
        'Fitted',
        top:
            'In stock: ${_nf(i['qty'])} ${i['unit']}. The part fitted before (if any) is closed and this one starts counting${basis != 'none' ? ' its life of ${_nf(i['life_value'])} ${_basisUnit[basis]}' : ''}.');
    if (r == null) return;
    await _run(
        () => Api.json('POST', '/inventory/items/${i['id']}/fit',
            body: _cleanBody(r)),
        'Recorded. Its life is counting.');
  }

  Future<void> _count(Map<String, dynamic> i) async {
    final r = await _form(
        'Stock count: ${i['name']}',
        [
          _Fld('new_qty', 'Counted (${i['unit']})',
              number: true, initial: _nf(i['qty'])),
          _Fld('note', 'Note'),
        ],
        'Save count',
        top:
            'The app shows ${_nf(i['qty'])} ${i['unit']}. Enter what you actually counted.');
    if (r == null) return;
    final n = double.tryParse(r['new_qty'] ?? '');
    if (n == null) return;
    await _run(
        () => Api.json('POST', '/inventory/items/${i['id']}/adjust',
            body: {'new_qty': n, 'note': r['note'] ?? ''}),
        'Stock corrected.');
  }

  Map<String, dynamic> _cleanBody(Map<String, String> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v.trim().isEmpty) return;
      out[k] = (k == 'qty' || k == 'used_before')
          ? (double.tryParse(v) ?? v)
          : v.trim();
    });
    return out;
  }

  Future<void> _itemForm([Map<String, dynamic>? item]) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ItemSheet(item: item, cats: _cats),
    );
    if (r == null) return;
    if (item == null) {
      await _run(
          () => Api.json('POST', '/inventory/items', body: r), 'Item added.');
    } else {
      r.remove('qty');
      await _run(
          () => Api.json('PUT', '/inventory/items/${item['id']}', body: r),
          'Saved.');
    }
  }

  Future<void> _history(Map<String, dynamic> i) async {
    Map<String, dynamic> h = {};
    try {
      h = Map<String, dynamic>.from(
          await Api.json('GET', '/inventory/items/${i['id']}/history') as Map);
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
      return;
    }
    if (!mounted) return;
    final moves = ((h['moves'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final fits = ((h['fits'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    const kinds = {
      'in': 'Bought',
      'use': 'Used',
      'fit': 'Fitted',
      'adjust': 'Count'
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(16),
            children: [
              Text('History: ${i['name']}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (fits.isNotEmpty)
                const Text('Fitted parts',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              for (final f in fits)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF6F9F3),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${f['label'] ?? 'Part'} · fitted ${_dmy(f['fitted_on'])}'
                    '${f['status'] == 'removed' ? ' · out ${_dmy(f['removed_on'])}${f['final_used'] != null ? ' after ${_nf(f['final_used'])} ${_basisShort['${f['basis']}'] ?? ''}' : ''}${f['removed_reason'] != null ? ' (${f['removed_reason']})' : ''}' : ' · fitted now'}'
                    '${_d(f['used_before']) > 0 ? ' · started with ${_nf(f['used_before'])} used' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Movements',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              if (moves.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 6), child: Text('None yet.')),
              for (final m in moves)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${_dmy(m['move_date'])} · ${kinds['${m['kind']}'] ?? m['kind']} · ${_d(m['qty']) > 0 ? '+' : ''}${_nf(m['qty'])}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _d(m['qty']) < 0
                              ? const Color(0xFFC62828)
                              : const Color(0xFF2E7D32))),
                  subtitle: Text(
                      '${m['note'] ?? ''}${m['created_by'] != null ? '  · ${m['created_by']}' : ''}'),
                  trailing: _mayDelete
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final ok = await _confirm(
                                'Delete this entry? The stock goes back.');
                            if (ok != true) return;
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _run(
                                () => Api.json(
                                    'DELETE', '/inventory/moves/${m['id']}'),
                                'Entry deleted.');
                          })
                      : null,
                ),
            ]),
      ),
    );
  }

  Future<bool?> _confirm(String text, {String yes = 'Yes'}) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, true), child: Text(yes))
          ],
        ),
      );

  Future<void> _more(Map<String, dynamic> i) async {
    final fits = ((i['fits'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pick = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(14),
              child: Text('${i['name']}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
          ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History (bought, used, fitted)'),
              onTap: () => Navigator.pop(c, 'hist')),
          if (_mayEdit)
            ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Stock count (correct the quantity)'),
                onTap: () => Navigator.pop(c, 'count')),
          if (_mayEdit)
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit item, limits and life rule'),
                onTap: () => Navigator.pop(c, 'edit')),
          if (_mayEdit)
            for (final f in fits)
              ListTile(
                  leading: const Icon(Icons.output),
                  title: Text(
                      'Take out ${f['label'] ?? 'fitted part'} (nothing fitted in its place)'),
                  onTap: () => Navigator.pop(c, 'out:${f['id']}')),
          if (_mayDelete)
            ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                title: const Text('Delete this item'),
                onTap: () => Navigator.pop(c, 'del')),
        ]),
      ),
    );
    if (pick == null) return;
    if (pick == 'hist') return _history(i);
    if (pick == 'count') return _count(i);
    if (pick == 'edit') return _itemForm(i);
    if (pick == 'del') {
      if (await _confirm('Delete ${i['name']} with all its history?',
              yes: 'Delete') ==
          true) {
        await _run(
            () => Api.json('POST', '/inventory/items/bulk-delete', body: {
                  'ids': [i['id']]
                }),
            'Deleted.');
      }
      return;
    }
    if (pick.startsWith('out:')) {
      final id = pick.substring(4);
      if (await _confirm('Take it out without fitting a new one?') == true) {
        await _run(
            () => Api.json('POST', '/inventory/fits/$id/remove',
                body: {'reason': 'Removed'}),
            'Removed.');
      }
    }
  }

  Future<void> _categories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CategorySheet(
        cats: _cats,
        mayAdd: _mayAdd,
        mayEdit: _mayEdit,
        mayDelete: _mayDelete,
        onAdd: (n) => _run(
            () => Api.json('POST', '/inventory/categories', body: {'name': n}),
            'Category added.'),
        onRename: (id, n) => _run(
            () =>
                Api.json('PUT', '/inventory/categories/$id', body: {'name': n}),
            'Renamed.'),
        onDelete: (id) => _run(
            () => Api.json('DELETE', '/inventory/categories/$id'), 'Deleted.'),
      ),
    );
    if (mounted) setState(() {});
  }

  // ── build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Inventory',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_mayAdd)
            IconButton(
                tooltip: 'New item',
                icon: const Icon(Icons.add),
                onPressed: () => _itemForm()),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'cats') _categories();
              if (v == 'clean')
                setState(() {
                  _clean = !_clean;
                  _picked.clear();
                });
              if (v == 'refresh') _load();
            },
            itemBuilder: (_) => [
              if (_mayAdd || _mayEdit)
                const PopupMenuItem(value: 'cats', child: Text('Categories')),
              if (_mayDelete)
                PopupMenuItem(
                    value: 'clean',
                    child: Text(_clean
                        ? 'Finish clean up'
                        : 'Clean up (delete items)')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh now')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _clean
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  TextButton(
                      onPressed: () => setState(() {
                            _picked
                              ..clear()
                              ..addAll(_filtered()
                                  .where((i) => _d(i['qty']) == 0)
                                  .map((i) => i['id'] as int));
                          }),
                      child: const Text('Tick zero stock')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _picked.isEmpty || _busy
                        ? null
                        : () async {
                            if (await _confirm(
                                    'Delete ${_picked.length} item(s) with their history? This cannot be undone.',
                                    yes: 'Delete') !=
                                true) return;
                            final ids = _picked.toList();
                            if (await _run(
                                () => Api.json(
                                    'POST', '/inventory/items/bulk-delete',
                                    body: {'ids': ids}),
                                'Deleted.')) setState(() => _picked.clear());
                          },
                    child:
                        Text('Delete ${_picked.isEmpty ? '' : _picked.length}'),
                  ),
                ]),
              ),
            )
          : null,
      body: d == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_error!,
                          style: const TextStyle(color: Color(0xFF8A1C1C))))
                  : const CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _list(d)),
    );
  }

  Widget _list(Map<String, dynamic> d) {
    final totals = Map<String, dynamic>.from(d['totals'] as Map);
    final alerts = ((d['alerts'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final items = _filtered();
    final counts = <String, int>{};
    for (final i in _items) {
      counts['${i['category_id'] ?? 'none'}'] =
          (counts['${i['category_id'] ?? 'none'}'] ?? 0) + 1;
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        _banner(_error!, const Color(0xFFFDECEA), const Color(0xFF8A1C1C)),
      if (_msg != null)
        _banner(_msg!, const Color(0xFFF3F8EE), const Color(0xFF1F4A0E)),
      if (d['counting_ok'] == false)
        _banner(
            'Pellet production could not be read, so tonnes / hours life cannot be counted right now.',
            const Color(0xFFFFF8E6),
            const Color(0xFF6B4A00)),
      Row(children: [
        _tile('Items', '${totals['items']}', const Color(0xFF37474F), null),
        _tile('Change now', '${totals['due']}', const Color(0xFFC62828), 'due'),
        _tile(
            'Soon / low', '${totals['soon']}', const Color(0xFFE08A00), 'soon'),
        _tile(
            'Out', '${totals['out_of_stock']}', const Color(0xFF6A1B9A), null),
      ]),
      if (alerts.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: alerts.any((a) => a['level'] == 'due')
                      ? const Color(0xFFE7B4B0)
                      : const Color(0xFFECD9A4))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Needs attention',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in alerts)
                InkWell(
                  onTap: () => setState(() {
                    _q = '${a['name']}';
                    _cat = 'all';
                    _onlyAlerts = false;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _stateColor('${a['level']}').withOpacity(0.10),
                        border: Border.all(
                            color:
                                _stateColor('${a['level']}').withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${a['text']}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _stateColor('${a['level']}'))),
                  ),
                ),
            ]),
          ]),
        ),
      const SizedBox(height: 10),
      TextField(
        decoration: InputDecoration(
            hintText: 'Search item, machine, part number…',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            filled: true,
            fillColor: Colors.white),
        onChanged: (v) => setState(() => _q = v),
      ),
      SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Only needing attention',
              style: TextStyle(fontSize: 13)),
          value: _onlyAlerts,
          onChanged: (v) => setState(() => _onlyAlerts = v)),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip('All ${_items.length}', _cat == 'all', null,
              () => setState(() => _cat = 'all')),
          for (final c in _cats)
            _chip(
                '${c['name']} ${counts['${c['id']}'] ?? 0}',
                _cat == '${c['id']}',
                _hex('${c['colour']}', _green),
                () => setState(() => _cat = '${c['id']}')),
          if ((counts['none'] ?? 0) > 0)
            _chip('No category ${counts['none']}', _cat == 'none', null,
                () => setState(() => _cat = 'none')),
        ]),
      ),
      const SizedBox(height: 8),
      if (items.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('Nothing here for this filter.',
                    style: TextStyle(color: Colors.grey)))),
      for (final i in items) _card(i),
      Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
              child: Text('Updated ${d['as_of']} · refreshes every 15 min',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)))),
    ]);
  }

  Widget _banner(String t, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 13)),
      );

  Widget _tile(String l, String v, Color c, String? filter) => Expanded(
        child: InkWell(
          onTap:
              filter == null ? null : () => setState(() => _onlyAlerts = true),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E7D8))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Container(width: 3, color: c),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w600)),
                              Text(v,
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          v != '0' && l != 'Items' ? c : null)),
                            ]),
                      ),
                    ),
                  ])),
            ),
          ),
        ),
      );

  Widget _chip(String label, bool on, Color? col, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
            label: Text(label,
                style:
                    TextStyle(fontSize: 12.5, color: on ? Colors.white : null)),
            selected: on,
            selectedColor: col ?? _green,
            onSelected: (_) => tap(),
            visualDensity: VisualDensity.compact),
      );

  Widget _card(Map<String, dynamic> i) {
    final cat = _cats.where((c) => c['id'] == i['category_id']).toList();
    final col = _hex(
        cat.isEmpty ? null : '${cat.first['colour']}', const Color(0xFFCFD8C7));
    final fits = ((i['fits'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final f = fits.isEmpty ? null : fits.first;
    final state = '${i['state']}';
    final low = i['low'] == true;
    final qty = _d(i['qty']);
    final fitBad = fits.any((x) => x['status'] != 'ok');
    final sub = [
      if (cat.isNotEmpty) '${cat.first['name']}',
      if (i['used_on'] != null) '${i['used_on']}',
      if (i['part_no'] != null) '#${i['part_no']}',
      if (i['location'] != null) '📍 ${i['location']}'
    ].join(' · ');
    final picked = _picked.contains(i['id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: state == 'due'
                  ? const Color(0x55C62828)
                  : const Color(0xFFE0E7D8)),
          boxShadow: state == 'due'
              ? const [BoxShadow(color: Color(0x22C62828), blurRadius: 12)]
              : null),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: [
          Container(height: 3, color: col),
          Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_clean)
                  Checkbox(
                      value: picked,
                      onChanged: (v) => setState(() {
                            if (v == true) {
                              _picked.add(i['id'] as int);
                            } else {
                              _picked.remove(i['id']);
                            }
                          })),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i['name']}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        if (sub.isNotEmpty)
                          Text(sub,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_nf(i['qty']),
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      color: low
                                          ? const Color(0xFFC62828)
                                          : null)),
                              const SizedBox(width: 6),
                              Text('${i['unit']}',
                                  style: const TextStyle(color: Colors.grey)),
                              if (_d(i['min_qty']) > 0)
                                Text('  min ${_nf(i['min_qty'])}',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              const Spacer(),
                              if (state != 'ok')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color:
                                          _stateColor(state).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                      low && !fitBad
                                          ? (qty <= 0
                                              ? 'Out of stock'
                                              : 'Low stock')
                                          : (state == 'due'
                                              ? 'Change now'
                                              : 'Soon'),
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: _stateColor(state))),
                                ),
                            ]),
                      ]),
                ),
                if (f != null)
                  _Ring(
                      pct: f['pct'] is num ? (f['pct'] as num).toInt() : null,
                      status: '${f['status']}',
                      label: f['life'] != null
                          ? 'of ${_nf(f['life'])} ${_basisShort['${f['basis']}'] ?? ''}'
                          : ''),
              ]),
              if (f != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF6F9F3),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${f['label'] ?? 'Fitted part'} since ${_dmy(f['fitted_on'])}: ${_nf(f['used'])} of ${_nf(f['life'])} ${_basisUnit['${f['basis']}'] ?? ''} used'
                    '${f['days_left'] != null ? ' · about ${f['days_left']} day(s) left' : ''}${fits.length > 1 ? ' (+${fits.length - 1} more)' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                )
              else if (i['untracked'] == true)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F4),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      'Life ${_nf(i['life_value'])} ${_basisUnit['${i['life_basis']}'] ?? ''}. Not counting yet: press "Fitted / changed" when you put one on.',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              const SizedBox(height: 6),
              Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_mayAdd)
                      OutlinedButton(
                          onPressed: _busy ? null : () => _stockIn(i),
                          child: const Text('+ Stock')),
                    if (_mayEdit)
                      OutlinedButton(
                          onPressed: _busy ? null : () => _use(i),
                          child: const Text('Use')),
                    if (_mayEdit && i['track_fit'] == true)
                      FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B7A28)),
                          onPressed: _busy ? null : () => _fit(i),
                          child: const Text('Fitted / changed')),
                    IconButton(
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => _more(i)),
                  ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ring gauge: how much of the part's life is used
class _Ring extends StatelessWidget {
  final int? pct;
  final String status;
  final String label;
  const _Ring({required this.pct, required this.status, required this.label});
  @override
  Widget build(BuildContext context) {
    final c = _stateColor(status);
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ((pct ?? 0).clamp(0, 100)) / 100),
          duration: const Duration(milliseconds: 700),
          builder: (_, v, __) => CustomPaint(
              size: const Size(74, 74), painter: _RingPainter(v, c)),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(pct == null ? '–' : '$pct%',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: c)),
          if (label.isNotEmpty)
            Text(label,
                style: const TextStyle(fontSize: 8.5, color: Colors.grey),
                textAlign: TextAlign.center),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color c;
  _RingPainter(this.v, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final r = (s.width - 10) / 2;
    final center = Offset(s.width / 2, s.height / 2);
    final base = Paint()
      ..color = const Color(0xFFE6EBE1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final glow = Paint()
      ..color = c.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, r, base);
    if (v > 0) {
      if (v >= 0.8)
        canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2,
            2 * math.pi * v, false, glow);
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2,
          2 * math.pi * v, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}

// ── a simple form sheet ───────────────────────────────────────────────
class _Fld {
  final String key;
  final String label;
  final bool number;
  final bool date;
  final String initial;
  _Fld(this.key, this.label,
      {this.number = false, this.date = false, this.initial = ''});
}

class _FormSheet extends StatefulWidget {
  final String title;
  final List<_Fld> fields;
  final String button;
  final String? top;
  const _FormSheet(
      {required this.title,
      required this.fields,
      required this.button,
      this.top});
  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial)
  };
  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context))
              ]),
              if (widget.top != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.top!,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.grey))),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _c[f.key],
                    readOnly: f.date,
                    keyboardType: f.number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                        labelText: f.label,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: f.date
                            ? const Icon(Icons.calendar_today, size: 18)
                            : null),
                    onTap: f.date
                        ? () async {
                            final r = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2024),
                                lastDate: DateTime.now());
                            if (r != null)
                              setState(() => _c[f.key]!.text = _iso(r));
                          }
                        : null,
                  ),
                ),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.pop(context,
                          {for (final e in _c.entries) e.key: e.value.text}),
                      child: Text(widget.button))),
            ]),
      ),
    );
  }
}

// ── new / edit item ───────────────────────────────────────────────────
class _ItemSheet extends StatefulWidget {
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> cats;
  const _ItemSheet({required this.item, required this.cats});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final Map<String, TextEditingController> _c;
  int? _cat;
  String _basis = 'none';
  bool _track = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    String t(String k) =>
        i == null || i[k] == null ? '' : (i[k] is num ? _nf(i[k]) : '${i[k]}');
    _c = {
      'name': TextEditingController(text: t('name')),
      'unit': TextEditingController(text: i == null ? 'pcs' : t('unit')),
      'qty': TextEditingController(),
      'min_qty': TextEditingController(
          text: i != null && _d(i['min_qty']) > 0 ? t('min_qty') : ''),
      'used_on': TextEditingController(text: t('used_on')),
      'part_no': TextEditingController(text: t('part_no')),
      'make': TextEditingController(text: t('make')),
      'location': TextEditingController(text: t('location')),
      'notes': TextEditingController(text: t('notes')),
      'life_value': TextEditingController(text: t('life_value')),
      'warn_pct': TextEditingController(text: i == null ? '80' : t('warn_pct')),
    };
    _cat = i == null
        ? (widget.cats.isEmpty ? null : widget.cats.first['id'] as int?)
        : i['category_id'] as int?;
    _basis = i == null ? 'none' : '${i['life_basis']}';
    _track = i != null && i['track_fit'] == true;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _tf(String k, String label, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
            controller: _c[k],
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true)),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(editing ? 'Edit item' : 'New item',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800))),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context))
          ]),
          _tf('name', 'Name'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<int?>(
              value: _cat,
              decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('No category')),
                for (final c in widget.cats)
                  DropdownMenuItem<int?>(
                      value: c['id'] as int?, child: Text('${c['name']}'))
              ],
              onChanged: (v) => setState(() => _cat = v),
            ),
          ),
          _tf('unit', 'Unit (pcs, litre, kg, set, m…)'),
          if (!editing) _tf('qty', 'Stock now (opening)', number: true),
          _tf('min_qty', 'Alert when stock is at or below (blank = no alert)',
              number: true),
          _tf('used_on', 'Used on (machine / area)'),
          _tf('part_no', 'Part number'),
          _tf('make', 'Make / supplier'),
          _tf('location', 'Where it is kept'),
          _tf('notes', 'Notes'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFAFCF8),
                border: Border.all(color: const Color(0xFFE0E7D8)),
                borderRadius: BorderRadius.circular(10)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Wear-out rule (optional)',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _basis,
                decoration: const InputDecoration(
                    labelText: 'Life is counted in',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No life rule')),
                  DropdownMenuItem(
                      value: 'tonnes', child: Text('Tonnes of pellets made')),
                  DropdownMenuItem(
                      value: 'hours', child: Text('Plant run hours')),
                  DropdownMenuItem(value: 'days', child: Text('Calendar days')),
                ],
                onChanged: (v) => setState(() => _basis = v ?? 'none'),
              ),
              if (_basis != 'none') ...[
                const SizedBox(height: 10),
                _tf('life_value', 'Life (${_basisShort[_basis]})',
                    number: true),
                _tf('warn_pct', 'Warn at (%)', number: true),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _track || _basis != 'none',
                onChanged: _basis != 'none'
                    ? null
                    : (v) => setState(() => _track = v ?? false),
                title: const Text('Show the "Fitted / changed" button',
                    style: TextStyle(fontSize: 13)),
              ),
              const Text(
                  'The life of a part already fitted keeps the value it had when it was fitted.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final name = _c['name']!.text.trim();
                if (name.isEmpty) return;
                String? s(String k) =>
                    _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
                Navigator.pop(context, <String, dynamic>{
                  'name': name,
                  'category_id': _cat,
                  'unit': s('unit') ?? 'pcs',
                  'qty': double.tryParse(_c['qty']!.text) ?? 0,
                  'min_qty': double.tryParse(_c['min_qty']!.text) ?? 0,
                  'used_on': s('used_on'),
                  'part_no': s('part_no'),
                  'make': s('make'),
                  'location': s('location'),
                  'notes': s('notes'),
                  'life_basis': _basis,
                  'life_value': _basis == 'none'
                      ? null
                      : double.tryParse(_c['life_value']!.text),
                  'warn_pct': int.tryParse(_c['warn_pct']!.text) ?? 80,
                  'track_fit': _track || _basis != 'none',
                });
              },
              child: Text(editing ? 'Save' : 'Add item'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── categories ────────────────────────────────────────────────────────
class _CategorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> cats;
  final bool mayAdd, mayEdit, mayDelete;
  final Future<bool> Function(String) onAdd;
  final Future<bool> Function(int, String) onRename;
  final Future<bool> Function(int) onDelete;
  const _CategorySheet(
      {required this.cats,
      required this.mayAdd,
      required this.mayEdit,
      required this.mayDelete,
      required this.onAdd,
      required this.onRename,
      required this.onDelete});
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late List<Map<String, dynamic>> _cats = widget.cats;
  final _new = TextEditingController();
  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final r = await Api.json('GET', '/inventory/overview');
      if (r is Map && mounted)
        setState(() => _cats = ((r['categories'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('Categories',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context))
              ]),
              for (final c in _cats)
                Row(children: [
                  Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                          color: _hex('${c['colour']}', _green),
                          shape: BoxShape.circle)),
                  Expanded(
                    child: TextFormField(
                      initialValue: '${c['name']}',
                      enabled: widget.mayEdit,
                      decoration: const InputDecoration(
                          isDense: true, border: InputBorder.none),
                      onFieldSubmitted: (v) async {
                        if (v.trim().isNotEmpty &&
                            v.trim() != '${c['name']}' &&
                            await widget.onRename(c['id'] as int, v.trim()))
                          _reload();
                      },
                    ),
                  ),
                  if (widget.mayDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        if (await widget.onDelete(c['id'] as int)) _reload();
                      },
                    ),
                ]),
              if (widget.mayAdd) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _new,
                          decoration: const InputDecoration(
                              hintText: 'New category, e.g. Dryer',
                              border: OutlineInputBorder(),
                              isDense: true))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final n = _new.text.trim();
                      if (n.isEmpty) return;
                      if (await widget.onAdd(n)) {
                        _new.clear();
                        _reload();
                      }
                    },
                    child: const Text('Add'),
                  ),
                ]),
              ],
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Press enter after renaming. A category with items cannot be deleted: move or delete its items first.',
                      style: TextStyle(fontSize: 12, color: Colors.grey))),
            ]),
      ),
    );
  }
}
