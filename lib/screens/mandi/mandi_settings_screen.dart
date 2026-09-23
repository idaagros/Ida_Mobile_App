// lib/screens/mandi/mandi_settings_screen.dart
//
// Set-up for the mandi price tracker: data status (fetch now, load past
// years, area covered), tracked commodities with their exact Agmarknet
// names, markets included in averages, and MSP entries.
// Web counterpart: src/pages/MandiSettings.jsx — the web version also has
// file import (CSV/Excel), which isn't offered on the phone.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'mandi_common.dart';

class MandiSettingsScreen extends StatefulWidget {
  const MandiSettingsScreen({super.key});
  @override
  State<MandiSettingsScreen> createState() => _MandiSettingsScreenState();
}

class _MandiSettingsScreenState extends State<MandiSettingsScreen> {
  bool isAdmin = false, mayAdd = false, mayUpdate = false;

  @override
  void initState() {
    super.initState();
    _perms();
  }

  Future<void> _perms() async {
    final a = await ApiService.isAdmin();
    final add = await ApiService.canAdd('mandi_prices');
    final upd = await ApiService.canUpdate('mandi_prices');
    if (mounted) {
      setState(() {
        isAdmin = a;
        mayAdd = a || add;
        mayUpdate = a || upd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8F6),
        appBar: AppBar(
          title: const Text('Mandi Price Settings'),
          backgroundColor: mandiDark,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Color(0xFF88BA63),
            tabs: [Tab(text: 'Data'), Tab(text: 'Commodities'), Tab(text: 'Markets'), Tab(text: 'MSP')],
          ),
        ),
        body: TabBarView(children: [
          _DataTab(isAdmin: isAdmin, mayUpdate: mayUpdate),
          _CommoditiesTab(mayAdd: mayAdd, mayUpdate: mayUpdate),
          _MarketsTab(mayUpdate: mayUpdate),
          _MspTab(mayAdd: mayAdd, mayUpdate: mayUpdate),
        ]),
      ),
    );
  }
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : mandiGreen,
    duration: const Duration(seconds: 5),
  ));
}

// ── Data ──────────────────────────────────────────────────────────────
class _DataTab extends StatefulWidget {
  final bool isAdmin, mayUpdate;
  const _DataTab({required this.isAdmin, required this.mayUpdate});
  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  Map<String, dynamic>? status;
  String? error;
  bool busy = false;
  int years = 5;
  Timer? _poll;
  final stateCtl = TextEditingController();
  final districtsCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    stateCtl.dispose();
    districtsCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = Map<String, dynamic>.from(await MandiApi.get('/mandi/status'));
      if (!mounted) return;
      setState(() {
        status = s;
        error = null;
      });
      if (stateCtl.text.isEmpty) {
        stateCtl.text = s['scope']['state'].toString();
        districtsCtl.text = List.from(s['scope']['districts']).join(', ');
      }
      _poll?.cancel();
      if (s['backfill'] != null) _poll = Timer(const Duration(seconds: 4), _load);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _run(Future<String> Function() fn) async {
    setState(() => busy = true);
    try {
      final msg = await fn();
      if (mounted) _snack(context, msg);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return error != null
          ? ListView(padding: const EdgeInsets.all(12), children: [ErrorBox(error!)])
          : const Center(child: CircularProgressIndicator());
    }
    final totals = Map<String, dynamic>.from(s['totals']);
    final keyOk = s['api_key_configured'] == true;
    final backfill = s['backfill'] as Map<String, dynamic>?;
    final log = List<Map<String, dynamic>>.from(s['log'] ?? []);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (!keyOk)
          MandiCard(
            color: Colors.amber.shade50,
            borderColor: Colors.amber.shade200,
            child: const Text(
              'Data.gov.in API key not set on the server. Automatic daily prices and loading past years are off until DATA_GOV_IN_KEY is added to the backend .env and the backend restarted.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        MandiCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Stored prices'),
            Row(children: [
              _kv('Rows', '${totals['rows_count']}'),
              _kv('From', shortDate(totals['first_date'])),
              _kv('Latest', shortDate(totals['last_date'])),
            ]),
            const SizedBox(height: 8),
            Text('Area: ${List.from(s['scope']['districts']).join(', ')}, ${s['scope']['state']}. Automatic fetch at ${s['schedule_ist']} IST.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (widget.mayUpdate) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: mandiGreen),
                onPressed: busy || !keyOk
                    ? null
                    : () => _run(() async {
                          final r = await MandiApi.post('/mandi/refresh');
                          if (r['skipped'] == true) return r['reason'].toString();
                          final problems = List.from(r['problems'] ?? []);
                          return 'Saved ${r['saved']} rows${problems.isNotEmpty ? ' (${problems.join('; ')})' : ''}';
                        }),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Fetch today\'s prices now'),
              ),
            ],
          ]),
        ),
        if (widget.isAdmin)
          MandiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Load past years'),
              Text('Pulls history for every active commodity. Needed once for "Best time to sell". Takes a few minutes; safe to run again.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              if (backfill != null) ...[
                Text('Loading: ${backfill['current'] ?? ''}  (${backfill['done']} / ${backfill['total']})', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (toD(backfill['total']) ?? 0) == 0 ? null : (toD(backfill['done'])! / toD(backfill['total'])!),
                  color: mandiGreen,
                  backgroundColor: Colors.grey.shade200,
                ),
              ] else
                Row(children: [
                  DropdownButton<int>(
                    value: years,
                    items: [3, 4, 5, 6, 8, 10].map((y) => DropdownMenuItem(value: y, child: Text('Last $y years'))).toList(),
                    onChanged: (v) => setState(() => years = v ?? 5),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: mandiGreen),
                    onPressed: busy || !keyOk
                        ? null
                        : () => _run(() async {
                              final r = await MandiApi.post('/mandi/backfill', {'years': years});
                              return 'Started: ${r['commodities']} commodities from ${shortDate(r['from'])}';
                            }),
                    child: const Text('Start'),
                  ),
                ]),
            ]),
          ),
        if (widget.isAdmin)
          MandiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Area covered'),
              TextField(controller: stateCtl, decoration: const InputDecoration(labelText: 'State', isDense: true)),
              const SizedBox(height: 6),
              TextField(controller: districtsCtl, decoration: const InputDecoration(labelText: 'Districts (comma separated)', isDense: true)),
              const SizedBox(height: 4),
              Text('Spell districts as Agmarknet does (Amravati, Akola, Yavatmal).', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          await MandiApi.put('/mandi/scope', {'state': stateCtl.text, 'districts': districtsCtl.text});
                          return 'Area saved';
                        }),
                child: const Text('Save area'),
              ),
            ]),
          ),
        const SectionLabel('Recent runs'),
        if (log.isEmpty) const MandiCard(child: Text('No runs yet')),
        ...log.map((l) {
          final st = l['status'].toString();
          final color = st == 'success' ? mandiGreen : st == 'failed' ? Colors.red.shade700 : mandiOrange;
          final when = DateTime.tryParse(l['started_at'].toString())?.toLocal();
          return MandiCard(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${l['run_type']}${l['started_by'] == null ? ' (auto)' : ''} · ${l['detail'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Text(st, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ]),
              Text('${when == null ? '' : '${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'} · saved ${l['rows_saved']}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if ((l['message'] ?? '').toString().isNotEmpty)
                Text(l['message'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 3, overflow: TextOverflow.ellipsis),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Commodities ───────────────────────────────────────────────────────
class _CommoditiesTab extends StatefulWidget {
  final bool mayAdd, mayUpdate;
  const _CommoditiesTab({required this.mayAdd, required this.mayUpdate});
  @override
  State<_CommoditiesTab> createState() => _CommoditiesTabState();
}

class _CommoditiesTabState extends State<_CommoditiesTab> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? sugg;
  List<Map<String, dynamic>> crops = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CommoditiesTab old) {
    super.didUpdateWidget(old);
    // Permissions arrive a moment after first build — reload suggestions then.
    if (old.mayAdd != widget.mayAdd) _load();
  }

  Future<void> _load() async {
    try {
      final r = await MandiApi.get('/mandi/commodities');
      Map<String, dynamic>? s;
      if (widget.mayAdd) s = Map<String, dynamic>.from(await MandiApi.get('/mandi/commodities/suggestions'));
      List<Map<String, dynamic>> c = [];
      try {
        c = List<Map<String, dynamic>>.from(await MandiApi.get('/agri/crops'));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(r);
        sugg = s;
        crops = c;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<String> get _nameOptions {
    final s = sugg;
    if (s == null) return [];
    final out = <String>{};
    for (final c in List.from(s['unlinked_crops'] ?? [])) {
      if (c['suggested_agmarknet_name'] != null) out.add(c['suggested_agmarknet_name'].toString());
    }
    for (final x in List.from(s['seen_in_data'] ?? [])) {
      out.add(x['commodity'].toString());
    }
    for (final n in List.from(s['known_names'] ?? [])) {
      out.add(n.toString());
    }
    return out.toList();
  }

  Future<void> _addAll() async {
    try {
      final r = await MandiApi.post('/mandi/commodities/from-crops');
      final added = List.from(r['added'] ?? []);
      final unmatched = List.from(r['unmatched'] ?? []);
      if (mounted) {
        _snack(context,
            'Added ${added.length}.${unmatched.isNotEmpty ? ' Couldn\'t match: ${unmatched.join(', ')} — add by hand.' : ''}');
      }
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final agCtl = TextEditingController(text: existing?['agmarknet_name']?.toString() ?? '');
    final dispCtl = TextEditingController(text: existing?['display_name']?.toString() ?? '');
    final aliasCtl = TextEditingController(text: existing?['aliases']?.toString() ?? '');
    int? cropId = existing?['crop_id'] as int?;
    final options = _nameOptions;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Add commodity' : 'Edit commodity'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: agCtl,
                decoration: const InputDecoration(labelText: 'Agmarknet name (exact spelling)', hintText: 'e.g. Soyabean'),
              ),
              if (options.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final o in options)
                    ActionChip(
                      label: Text(o, style: const TextStyle(fontSize: 11)),
                      onPressed: () => setD(() => agCtl.text = o),
                    ),
                ]),
              ],
              const SizedBox(height: 8),
              TextField(controller: dispCtl, decoration: const InputDecoration(labelText: 'Show as', hintText: 'e.g. Soybean')),
              const SizedBox(height: 8),
              TextField(
                controller: aliasCtl,
                decoration: const InputDecoration(
                  labelText: 'Other spellings (optional, comma separated)',
                  hintText: 'e.g. Red gram/Arhar/Tur(whole)',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: cropId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Our crop (optional)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('— none —')),
                  ...crops.map((c) => DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'].toString()))),
                ],
                onChanged: (v) => setD(() {
                  cropId = v;
                  if (dispCtl.text.isEmpty && v != null) {
                    dispCtl.text = crops.firstWhere((c) => c['id'] == v)['name'].toString();
                  }
                }),
              ),
              const SizedBox(height: 8),
              Text('The name must match Agmarknet exactly, or no prices will be found.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: mandiGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final body = {
      'agmarknet_name': agCtl.text.trim(),
      'display_name': dispCtl.text.trim().isEmpty ? agCtl.text.trim() : dispCtl.text.trim(),
      'aliases': aliasCtl.text.trim(),
      'crop_id': cropId,
    };
    try {
      if (existing == null) {
        await MandiApi.post('/mandi/commodities', body);
      } else {
        await MandiApi.patch('/mandi/commodities/${existing['id']}', body);
      }
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> c, bool v) async {
    try {
      await MandiApi.patch('/mandi/commodities/${c['id']}', {'is_active': v});
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final unlinked = List.from(sugg?['unlinked_crops'] ?? []);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) ErrorBox(error!),
        if (widget.mayAdd)
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: mandiGreen),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add commodity'),
            ),
            if (unlinked.isNotEmpty)
              OutlinedButton(onPressed: _addAll, child: Text('Add all my crops (${unlinked.length})')),
          ]),
        const SizedBox(height: 10),
        if (rows.isEmpty) const MandiCard(child: Text('Nothing tracked yet')),
        ...rows.map((c) {
          final active = c['is_active'] == 1 || c['is_active'] == true;
          final count = toD(c['row_count']) ?? 0;
          return MandiCard(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['display_name'].toString(),
                      style: TextStyle(fontWeight: FontWeight.w600, color: active ? mandiDark : Colors.grey)),
                  Text('Agmarknet: ${c['agmarknet_name']}${c['crop_name'] != null ? ' · crop: ${c['crop_name']}' : ''}${(c['aliases'] ?? '').toString().isNotEmpty ? '\nalso: ${c['aliases']}' : ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  Text(
                    count > 0 ? '${shortDate(c['first_date'])} → ${shortDate(c['last_date'])} (${count.round()} rows)' : 'No data yet',
                    style: TextStyle(fontSize: 11, color: count > 0 ? Colors.grey.shade500 : mandiOrange),
                  ),
                ]),
              ),
              if (widget.mayUpdate) IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(c)),
              Switch(value: active, activeColor: mandiGreen, onChanged: widget.mayUpdate ? (v) => _toggle(c, v) : null),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Markets ───────────────────────────────────────────────────────────
class _MarketsTab extends StatefulWidget {
  final bool mayUpdate;
  const _MarketsTab({required this.mayUpdate});
  @override
  State<_MarketsTab> createState() => _MarketsTabState();
}

class _MarketsTabState extends State<_MarketsTab> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await MandiApi.get('/mandi/markets');
      if (mounted) setState(() => rows = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _patch(Map<String, dynamic> m, Map<String, dynamic> body) async {
    try {
      await MandiApi.patch('/mandi/markets/${m['id']}', body);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  Future<void> _rename(Map<String, dynamic> m) async {
    final ctl = TextEditingController(text: m['display_name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m['market'].toString()),
        content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Short name (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await _patch(m, {'display_name': ctl.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) ErrorBox(error!),
        Text('Markets appear automatically once they report a price. Switch one off to leave it out of averages — its data is kept.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        if (rows.isEmpty) const MandiCard(child: Text('No markets yet — they appear after the first fetch')),
        ...rows.map((m) {
          final active = m['is_active'] == 1 || m['is_active'] == true;
          return MandiCard(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: widget.mayUpdate ? () => _rename(m) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(marketName(m), style: TextStyle(fontWeight: FontWeight.w600, color: active ? mandiDark : Colors.grey)),
                    Text('${m['market']} · ${m['district']} · last ${shortDate(m['last_date'])}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                ),
              ),
              Switch(value: active, activeColor: mandiGreen, onChanged: widget.mayUpdate ? (v) => _patch(m, {'is_active': v}) : null),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── MSP ───────────────────────────────────────────────────────────────
class _MspTab extends StatefulWidget {
  final bool mayAdd, mayUpdate;
  const _MspTab({required this.mayAdd, required this.mayUpdate});
  @override
  State<_MspTab> createState() => _MspTabState();
}

class _MspTabState extends State<_MspTab> {
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> commodities = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await MandiApi.get('/mandi/msp');
      final c = await MandiApi.get('/mandi/commodities');
      if (mounted) {
        setState(() {
          rows = List<Map<String, dynamic>>.from(m);
          commodities = List<Map<String, dynamic>>.from(c);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _add() async {
    int? commodityId;
    final seasonCtl = TextEditingController();
    final priceCtl = TextEditingController();
    DateTime? from;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add MSP'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: commodityId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Commodity'),
                items: commodities.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['display_name'].toString()))).toList(),
                onChanged: (v) => setD(() => commodityId = v),
              ),
              TextField(controller: seasonCtl, decoration: const InputDecoration(labelText: 'Season', hintText: '2025-26')),
              TextField(
                controller: priceCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'MSP ₹ per quintal'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(from == null ? 'Effective from: not set' : 'Effective from: ${shortDate(from!.toIso8601String())}')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setD(() => from = d);
                  },
                  child: const Text('Pick date'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: mandiGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (commodityId == null || seasonCtl.text.trim().isEmpty || double.tryParse(priceCtl.text) == null || from == null) {
      if (mounted) _snack(context, 'Fill in commodity, season, MSP and date', error: true);
      return;
    }
    final f = from!;
    try {
      await MandiApi.post('/mandi/msp', {
        'commodity_id': commodityId,
        'season_label': seasonCtl.text.trim(),
        'msp_price': double.parse(priceCtl.text),
        'effective_from': '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}',
      });
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete MSP?'),
        content: Text('${r['display_name']} ${r['season_label']}: ${rupees(r['msp_price'])}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MandiApi.delete('/mandi/msp/${r['id']}');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) ErrorBox(error!),
        Text('Minimum Support Price, entered once per season. Shown as a reference line on charts. Saving the same season again updates it.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        if (widget.mayAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: mandiGreen),
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add MSP'),
            ),
          ),
        const SizedBox(height: 10),
        if (rows.isEmpty) const MandiCard(child: Text('No MSP entered yet')),
        ...rows.map((r) => MandiCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['display_name']} · ${r['season_label']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('From ${shortDate(r['effective_from'])}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                ),
                Text(rupees(r['msp_price']), style: const TextStyle(fontWeight: FontWeight.w800, color: mandiDark)),
                if (widget.mayUpdate)
                  IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20), onPressed: () => _delete(r)),
              ]),
            )),
      ]),
    );
  }
}
