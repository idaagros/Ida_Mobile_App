// lib/screens/raw_material/rm_vehicles_screen.dart
//
// Trucks seen in the period: trips, tonnes, the truck's usual load and loads
// that are far from it (more than the set % from the truck's usual; a new truck is
// compared with the supplier's usual load). Tap a truck to see its trips.
// API: GET /raw-material/vehicles, GET /raw-material/vehicle?no=
// Web counterpart: src/pages/rawmaterial/RmVehicles.jsx.

import 'package:flutter/material.dart';
import 'rm_common.dart';
import 'rm_party_screen.dart';

class RmVehiclesScreen extends StatefulWidget {
  final Map<String, dynamic> query;
  final String label;
  const RmVehiclesScreen({super.key, required this.query, required this.label});
  @override
  State<RmVehiclesScreen> createState() => _RmVehiclesScreenState();
}

class _RmVehiclesScreenState extends State<RmVehiclesScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> data = {};
  String search = '';
  String? open;
  Map<String, dynamic>? trips;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await RmApi.get('/raw-material/vehicles', query: widget.query);
      if (!mounted) return;
      setState(() {
        data = Map<String, dynamic>.from(d as Map);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> _toggle(String key) async {
    if (open == key) {
      setState(() => open = null);
      return;
    }
    setState(() {
      open = key;
      trips = null;
    });
    try {
      final d = await RmApi.get('/raw-material/vehicle', query: {...widget.query, 'no': key});
      if (mounted && open == key) setState(() => trips = Map<String, dynamic>.from(d as Map));
    } catch (e) {
      if (mounted && open == key) setState(() => trips = {'trips': []});
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = search.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final all = ((data['vehicles'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final list = all.where((v) => k.isEmpty || v['key'].toString().contains(k)).toList();
    final flagged = all.fold<int>(0, (s, v) => s + toD(v['flags']).round());
    return Scaffold(
      backgroundColor: rmBg,
      appBar: AppBar(title: const Text('Vehicles'), backgroundColor: rmAppBar, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (loading && data.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (error != null) RmCard(color: const Color(0xFFFDECEA), child: Text(error!)),
          if (data.isNotEmpty) ...[
            Text(_intro(all.length, flagged), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Find a truck', filled: true, fillColor: Colors.white, border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 10),
            if (list.isEmpty) const RmCard(child: Text('No truck matches.', textAlign: TextAlign.center)),
            for (final v in list) _card(v),
          ],
        ]),
      ),
    );
  }

  String _intro(int count, int flagged) {
    final noVeh = toD(data['no_vehicle']).round();
    final pct = toD(data['pct']).round();
    final b = StringBuffer('${widget.label}: $count truck${count == 1 ? "" : "s"}');
    if (flagged > 0) b.write(" · $flagged load${flagged == 1 ? "" : "s"} far from the truck's usual");
    if (noVeh > 0) b.write(' · $noVeh with no vehicle number');
    b.write(".\nA load is flagged when it is more than $pct% above or below what that truck usually brings ");
    b.write("(after 3 trips; a new truck is compared with the supplier's usual load).");
    return b.toString();
  }

  String _flagText(Map f) {
    final lead = f['acked'] == true ? '✓ checked: ' : '⚑ ';
    final usual = mt(f['usual']);
    return f['basis'] == 'supplier' ? '${lead}new truck; supplier usually $usual MT' : '${lead}truck usually $usual MT';
  }

  Widget _card(Map<String, dynamic> v) {
    final key = v['key'].toString();
    final flags = toD(v['flags']).round();
    final isOpen = open == key;
    return RmCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => _toggle(key),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(v['vehicle'].toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                if (flags > 0) Text('⚑ $flags', style: const TextStyle(color: Color(0xFF9E2419), fontWeight: FontWeight.w800)),
                Icon(isOpen ? Icons.expand_less : Icons.expand_more),
              ]),
              const SizedBox(height: 2),
              Text(
                '${toD(v['trips']).round()} trip${toD(v['trips']) == 1 ? '' : 's'} · ${mt(v['qty_mt'])} MT · usual ${mt(v['usual_mt'])} MT (${mt(v['min_mt'])} – ${mt(v['max_mt'])})\n'
                'last ${dm(v['last_date'])} · ${v['last_party']}${toD(v['suppliers']) > 1 ? ' +${toD(v['suppliers']).round() - 1}' : ''}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ),
        if (isOpen)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: rmBorder))),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: trips == null
                ? const Padding(padding: EdgeInsets.all(8), child: Text('Loading…'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final t in ((trips!['trips'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)))
                      InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RmPartyScreen(name: t['party'].toString()))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${dm(t['date'])} · ${t['party']} · ${t['label']} · ${mt(t['qty_mt'])} MT', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            if (t['flag'] is Map)
                              Text(
                                _flagText(t['flag'] as Map),
                                style: TextStyle(fontSize: 12.5, color: (t['flag'] as Map)['acked'] == true ? Colors.grey.shade600 : const Color(0xFF9E2419), fontWeight: FontWeight.w600),
                              ),
                          ]),
                        ),
                      ),
                  ]),
          ),
      ]),
    );
  }
}
