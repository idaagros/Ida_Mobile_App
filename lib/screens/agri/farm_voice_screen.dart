// lib/screens/agri/farm_voice_screen.dart
//
// Sprays and harvests by voice (or typed): say it, check the card, tap Save.
//   "Choufuli soybean imidacloprid 200 ml yesterday"   -> ticks off that planned spray step in the crop calendar
//   "Choufuli tur harvest 12 quintal"                    -> a harvest record (kept in kg, shown in quintals)
// Each sentence becomes a card. Anything orange must be fixed before Save works. Nothing is saved before Save.
// Dose: "100 ml per acre" (the app multiplies by the acres sprayed) or the total ("2 litre").
// "as per plan" uses the planned quantity. Several entries: say "next" between them.
// Admins only. Web counterpart: src/pages/FarmVoice.jsx (typed; the microphone is phone only).
// API: /farm-voice (routes/farmVoice.js).

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/voice_allocation_sheet.dart';
import '../agronomy/agronomy_common.dart';

Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Map<String, dynamic>> _ml(dynamic v) => ((v as List?) ?? const []).map((e) => _m(e)).toList();
String _num(dynamic v) {
  final d = toD(v);
  return d == null ? '' : trimNum(d, 3);
}

double? _parse(String t) {
  final s = t.replaceAll(',', '').trim();
  return s.isEmpty ? null : double.tryParse(s);
}

class _Item {
  final int key;
  Map<String, dynamic> input;
  Map<String, dynamic> card;
  Map<String, dynamic>? result;
  final Map<String, TextEditingController> ctl = {};
  final Set<String> touched = {};
  Timer? timer;
  _Item(this.key, this.input, this.card);

  TextEditingController c(String k) => ctl.putIfAbsent(k, () => TextEditingController());
  bool get saved => result != null && result!['ok'] == true;
  List<Map<String, dynamic>> get warnings => _ml(card['warnings']);
  List<String> get blockers => ((card['blockers'] as List?) ?? const []).map((e) => e.toString()).toList();

  void dispose() {
    timer?.cancel();
    for (final x in ctl.values) {
      x.dispose();
    }
  }
}

class FarmVoiceScreen extends StatefulWidget {
  const FarmVoiceScreen({super.key});
  @override
  State<FarmVoiceScreen> createState() => _FarmVoiceScreenState();
}

class _FarmVoiceScreenState extends State<FarmVoiceScreen> {
  List<Map<String, dynamic>> farms = [];
  final List<_Item> items = [];
  final typeCtrl = TextEditingController();
  String heard = '';
  String? error;
  bool loading = true;
  bool busy = false;
  bool forbidden = false;
  int _keyN = 1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    typeCtrl.dispose();
    for (final i in items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final c = _m(await AgriApi.get('/farm-voice/context'));
      farms = _ml(c['farms']);
    } catch (e) {
      final t = e.toString();
      if (RegExp(r'admin|403|forbidden', caseSensitive: false).hasMatch(t)) {
        forbidden = true;
      } else {
        error = t;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  // ── what was said ──────────────────────────────────────────────────
  Future<void> _speak() async {
    final res = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VoiceAllocationSheet(
        dateStr: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        idaGreen: agGreen,
        endpoint: '/farm-voice/parse',
        title: 'Say the spray or harvest',
        hint: 'Say the farm, the crop, then the product and quantity, or what was harvested. '
            'Example: "Choufuli soybean imidacloprid 200 ml yesterday" or "Choufuli tur harvest 12 quintal". '
            'Say "next" between entries.',
      ),
    );
    if (res == null || !mounted) return;
    _applyParsed(_m(res));
  }

  Future<void> _typed() async {
    final t = typeCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = _m(await AgriApi.post('/farm-voice/parse', {'transcript': t}));
      _applyParsed(r);
      typeCtrl.clear();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  void _applyParsed(Map<String, dynamic> r) {
    setState(() {
      heard = (r['heard'] ?? '').toString();
      items.removeWhere((i) {
        if (i.saved) return false;
        i.dispose();
        return true;
      });
      for (final x in _ml(r['items'])) {
        final it = _Item(_keyN++, _m(x['input']), _m(x['card']));
        _sync(it, reset: true);
        items.add(it);
      }
      error = null;
    });
  }

  // put the server's figures into the boxes the person has not typed in
  void _sync(_Item it, {bool reset = false}) {
    if (reset) it.touched.clear();
    final card = it.card;
    void put(String k, String v) {
      if (!it.touched.contains(k)) it.c(k).text = v;
    }

    final tree = card['basis'] == 'tree';
    put('area', _num(tree ? card['trees_covered'] : card['area_covered']));
    put('kg', _num(card['quantity_kg']));
    put('remarks', (card['remarks'] ?? '').toString());
    for (final p in _ml(card['products'])) {
      put('q${p['product_id']}', _num(p['actual_qty']));
    }
  }

  // ── keep the card in step with what the person edits ───────────────
  void _recheck(_Item it, {bool soon = false}) {
    it.timer?.cancel();
    Future<void> go() async {
      try {
        final c = _m(await AgriApi.post('/farm-voice/check', {'input': it.input}));
        if (!mounted) return;
        setState(() {
          it.card = c;
          _sync(it);
        });
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      }
    }

    if (soon) {
      it.timer = Timer(const Duration(milliseconds: 500), go);
    } else {
      go();
    }
  }

  // change what the card is based on; `drop` = fields that no longer make sense
  void _change(_Item it, Map<String, dynamic> patch, {List<String> drop = const [], bool reset = false, bool soon = false}) {
    setState(() {
      it.input = {...it.input, ...patch};
      for (final k in drop) {
        it.input.remove(k);
      }
      if (reset) it.touched.clear();
    });
    _recheck(it, soon: soon);
  }

  List<Map<String, dynamic>> _lines(_Item it, {String? brandFor, int? brandId}) {
    final out = <Map<String, dynamic>>[];
    for (final p in _ml(it.card['products'])) {
      final pid = toI(p['product_id']);
      final text = it.ctl['q$pid']?.text ?? '';
      final n = _parse(text);
      final bid = (brandFor != null && '$pid' == brandFor) ? brandId : toI(p['brand_id']);
      out.add(n == null
          ? {'product_id': pid, 'cleared': true, 'brand_id': bid}
          : {'product_id': pid, 'actual_qty': n, 'unit': p['unit'], 'brand_id': bid});
    }
    return out;
  }

  void _qtyChanged(_Item it, String pid) {
    it.touched.add('q$pid');
    it.input = {...it.input, 'products': _lines(it)};
    _recheck(it, soon: true);
  }

  void _brandChanged(_Item it, int pid, int bid) {
    it.input = {...it.input, 'products': _lines(it, brandFor: '$pid', brandId: bid)};
    _recheck(it);
  }

  Future<void> _pickDate(_Item it) async {
    final cur = DateTime.tryParse((it.card['date'] ?? '').toString()) ?? DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime.now().subtract(const Duration(days: 400)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (p == null) return;
    _change(it, {'date': DateFormat('yyyy-MM-dd').format(p), 'date_said': true});
  }

  // ── save ───────────────────────────────────────────────────────────
  List<_Item> get open => items.where((i) => !i.saved).toList();
  bool get ready => open.isNotEmpty && open.every((i) => i.blockers.isEmpty) && !busy;

  Future<void> _saveAll() async {
    final todo = open;
    final strong = <String>[
      for (final i in todo)
        for (final w in i.warnings)
          if (w['level'] == 'warn') '${w['text']}'
    ];
    if (strong.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Please check'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final t in strong) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• $t')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = _m(await AgriApi.post('/farm-voice/save', {'items': [for (final i in todo) i.input]}));
      final results = _ml(r['results']);
      setState(() {
        for (var n = 0; n < todo.length && n < results.length; n++) {
          todo[n].result = results[n];
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  // ── screen ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: agBg,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        title: const Text('Spray and harvest entry', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: (!kIsWeb && !forbidden && !loading)
          ? FloatingActionButton.extended(
              backgroundColor: agGreen,
              onPressed: busy ? null : _speak,
              icon: const Icon(Icons.mic, color: Colors.white),
              label: const Text('Say it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: agGreen))
          : forbidden
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Only admins can use this screen.')))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                  children: [
                    if (error != null) _banner(error!, const Color(0xFFFDECEA), const Color(0xFFF1B9B3), const Color(0xFF8A1F13)),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: typeCtrl,
                          minLines: 1,
                          maxLines: 3,
                          decoration: agInput('Or type it', hint: 'Choufuli tur harvest 12 quintal'),
                          onSubmitted: (_) => _typed(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: agGreen),
                        onPressed: busy ? null : _typed,
                        child: const Text('Make card'),
                      ),
                    ]),
                    if (heard.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Read as: "$heard"', style: const TextStyle(fontSize: 12, color: agMuted))),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Tap "Say it" and speak, for example:\n'
                          '"Choufuli soybean imidacloprid 200 ml yesterday"\n'
                          '"Choufuli tur harvest 12 quintal"\n\n'
                          'You can say the dose per acre ("100 ml per acre") or the total, or "as per plan".',
                          style: TextStyle(color: agMuted, height: 1.4),
                        ),
                      ),
                    for (final it in items) _card(it),
                    if (open.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: agGreen, minimumSize: const Size.fromHeight(50)),
                        onPressed: ready ? _saveAll : null,
                        child: Text(busy ? 'Please wait…' : 'Save ${open.length} ${open.length == 1 ? 'entry' : 'entries'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      if (!ready && !busy && open.any((i) => i.blockers.isNotEmpty))
                        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Fix the orange items first.', style: TextStyle(fontSize: 12.5, color: Color(0xFF7A4D00)))),
                    ],
                  ],
                ),
    );
  }

  Widget _banner(String text, Color bg, Color border, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 13.5)),
      );

  Widget _card(_Item it) {
    final c = it.card;
    if (it.saved) {
      return _banner('✓ ${it.result!['message']}${it.result!['warning'] != null ? '\n${it.result!['warning']}' : ''}',
          const Color(0xFFF3F8EE), const Color(0xFFCFE3C0), const Color(0xFF1F4A0E));
    }
    final failed = it.result != null && it.result!['ok'] != true;
    final kind = (c['kind'] ?? '').toString();
    final spray = kind == 'spray';
    final harvest = kind == 'harvest';
    final cycleOpts = _ml(c['cycle_options']);
    final cycle = c['cycle'] is Map ? _m(c['cycle']) : null;
    final farm = c['farm'] is Map ? _m(c['farm']) : null;
    final cycleVal = cycle == null ? null : '${cycle['cycle_type']}:${cycle['cycle_id']}';
    final steps = _ml(c['step_options']);
    final stepId = toI(c['step_id']);
    final tree = c['basis'] == 'tree';
    final kgNum = _parse(it.c('kg').text);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: agBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 190,
            child: AgSeg<String>(
              values: const ['spray', 'harvest'],
              labels: const ['Spray', 'Harvest'],
              value: spray ? 'spray' : 'harvest',
              onChanged: (v) => _change(it, {'kind': v}, drop: const ['products'], reset: true),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              items.remove(it);
              it.dispose();
            }),
            child: const Text('Remove'),
          ),
        ]),
        if ((c['heard'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('"${c['heard']}"', style: const TextStyle(fontSize: 12, color: agMuted))),
        if (failed) _banner('Not saved: ${it.result!['message']}', const Color(0xFFFDECEA), const Color(0xFFF1B9B3), const Color(0xFF8A1F13)),
        DropdownButtonFormField<int>(
          value: farm == null ? null : toI(farm['id']),
          isExpanded: true,
          decoration: _orange(agInput('Farm'), farm == null),
          items: [for (final f in farms) DropdownMenuItem(value: toI(f['id']), child: Text('${f['name']}'))],
          onChanged: (v) {
            if (v == null) return;
            _change(it, {'farm_id': v},
                drop: const ['cycle_type', 'cycle_id', 'cycle_scope', 'step_id', 'products', 'area_covered', 'trees_covered'], reset: true);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: cycleOpts.any((o) => '${o['cycle_type']}:${o['cycle_id']}' == cycleVal) ? cycleVal : null,
          isExpanded: true,
          decoration: _orange(agInput('Crop', hint: farm == null ? 'Choose the farm first' : 'Choose the crop'), cycle == null),
          items: [
            for (final o in cycleOpts)
              DropdownMenuItem(
                value: '${o['cycle_type']}:${o['cycle_id']}',
                child: Text('${o['label']}${o['state'] == 'finished' ? ' (finished)' : ''}', overflow: TextOverflow.ellipsis),
              )
          ],
          onChanged: (v) {
            if (v == null) return;
            final parts = v.split(':');
            _change(it, {'cycle_type': parts[0], 'cycle_id': int.tryParse(parts[1])},
                drop: const ['step_id', 'products', 'area_covered', 'trees_covered'], reset: true);
          },
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _pickDate(it),
          child: InputDecorator(
            decoration: agInput('Date'),
            child: Row(children: [
              Expanded(child: Text(_dmy((c['date'] ?? '').toString()), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              const Icon(Icons.calendar_today, size: 18, color: agMuted),
            ]),
          ),
        ),
        if (spray && cycle != null) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: stepId != null && steps.any((s) => toI(s['id']) == stepId) ? stepId : 0,
            isExpanded: true,
            decoration: agInput('Which planned step'),
            items: [
              for (final s in steps)
                DropdownMenuItem(
                  value: toI(s['id']),
                  child: Text(
                    '${s['label'] ?? 'Spray'}${s['planned_date'] != null ? ' · planned ${_dmy('${s['planned_date']}')}' : ''}${s['status'] == 'overdue' ? ' · overdue' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const DropdownMenuItem(value: 0, child: Text('An extra spray (not in the plan)')),
            ],
            onChanged: (v) => _change(it, {'step_id': v == 0 ? null : v}, drop: const ['products']),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: it.c('area'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: agInput(tree ? 'Trees sprayed' : 'Acres sprayed', helper: c['basis_qty'] != null ? (tree ? '${_num(c['basis_qty'])} trees in the block' : '${_num(c['basis_qty'])} acres sown') : null),
            onChanged: (t) {
              it.touched.add('area');
              _change(it, tree ? {'trees_covered': _parse(t)} : {'area_covered': _parse(t)}, soon: true);
            },
          ),
          const SizedBox(height: 10),
          for (final p in _ml(c['products'])) _productRow(it, p),
        ],
        if (harvest) ...[
          const SizedBox(height: 10),
          TextField(
            controller: it.c('kg'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            decoration: _orange(
                agInput('Harvested (kg)',
                    helper: (kgNum != null && kgNum > 0) ? '= ${trimNum(kgNum / 100, 2)} quintal' : ((c['said_qty'] ?? '').toString().isNotEmpty ? 'You said: ${c['said_qty']}' : null)),
                !(kgNum != null && kgNum > 0)),
            onChanged: (t) {
              it.touched.add('kg');
              _change(it, {'quantity_kg': _parse(t), 'unconvertible_unit': null}, soon: true);
            },
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: it.c('remarks'),
          maxLength: 250,
          decoration: agInput('Remarks (optional)').copyWith(counterText: ''),
          onChanged: (t) {
            it.touched.add('remarks');
            _change(it, {'remarks': t}, soon: true);
          },
        ),
        for (final b in it.blockers)
          Padding(padding: const EdgeInsets.only(top: 6), child: _banner('✕ $b', const Color(0xFFFDECEA), const Color(0xFFF1B9B3), const Color(0xFF8A1F13))),
        for (final w in it.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: w['level'] == 'warn'
                ? _banner('⚠ ${w['text']}', const Color(0xFFFFF7EA), const Color(0xFFF3D7A6), const Color(0xFF6A4300))
                : _banner('ℹ ${w['text']}', const Color(0xFFF3F8EE), const Color(0xFFCFE3C0), const Color(0xFF1F4A0E)),
          ),
      ]),
    );
  }

  Widget _productRow(_Item it, Map<String, dynamic> p) {
    final pid = toI(p['product_id']) ?? 0;
    final brands = _ml(p['brands']);
    final brandId = toI(p['brand_id']);
    final rec = toD(p['recommended']);
    final unit = '${p['unit'] ?? ''}';
    final diff = toI(p['diff_pct']);
    final missing = p['actual_qty'] == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: missing ? const Color(0xFFE08A3C) : agBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
          Text(rec != null ? 'Plan: ${trimNum(rec, 3)} $unit' : (p['in_plan'] == true ? '' : 'Not in this step'), style: const TextStyle(fontSize: 12, color: agMuted)),
        ]),
        if (brands.isNotEmpty) ...[
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: brands.any((b) => toI(b['id']) == brandId) ? brandId : null,
            isExpanded: true,
            decoration: agInput('Brand'),
            items: [for (final b in brands) DropdownMenuItem(value: toI(b['id']), child: Text('${b['brand_name']}'))],
            onChanged: (v) {
              if (v != null) _brandChanged(it, pid, v);
            },
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: it.c('q$pid'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: agInput('Used', suffix: unit),
              onChanged: (_) => _qtyChanged(it, '$pid'),
            ),
          ),
          if (diff != null && diff.abs() >= 1) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: diff.abs() > 25 ? const Color(0xFFFDE6D2) : const Color(0xFFE3F0DA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${diff > 0 ? '+' : '−'}${diff.abs()}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        if ((p['said'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('said: ${p['said']}', style: const TextStyle(fontSize: 12, color: agMuted))),
      ]),
    );
  }

  InputDecoration _orange(InputDecoration d, bool bad) => bad
      ? d.copyWith(enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE08A3C), width: 1.6)))
      : d;

  String _dmy(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMM yyyy').format(d);
  }
}
