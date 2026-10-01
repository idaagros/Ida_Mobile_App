// lib/screens/owner_dashboard_screen.dart
//
// Owner's dashboard on the phone (Oct 2026) — the same three pages as the
// TV in the owner's room (website /tv), as tabs with cards:
//   Today   — factory yesterday, dispatch today, workers today, spray
//             weather, "needs a look" tiles, yesterday's readings,
//             approvals waiting, crop jobs due.
//   Factory — month so far vs the same days last month (in the first days
//             of a month: last month vs the month before).
//   Farms   — running crops, water stress by farm (satellite), mandi
//             prices today, workers last 7 days, farm cost changes.
// No rupee amounts of our own: costs are a % change only. Admins only.
// API: GET /dashboard (?fresh=1 on pull-to-refresh)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin/admin_common.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});
  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

const Color _red = Color(0xFFC0473A);
const Color _amber = Color(0xFFD98A1F);
final NumberFormat _nf1 = NumberFormat('#,##,##0.#', 'en_IN');
String n1(dynamic v) => v == null ? '—' : _nf1.format(num.tryParse('$v') ?? 0);
String n0(dynamic v) => v == null ? '—' : NumberFormat.decimalPattern('en_IN').format((num.tryParse('$v') ?? 0).round());
String shortDate(dynamic s) {
  final d = DateTime.tryParse('${s ?? ''}');
  return d == null ? '' : DateFormat('d MMM').format(d);
}

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => (v is List ? v : const []).whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _loading = true;
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AdminApi.get('/dashboard${fresh ? '?fresh=1' : ''}');
      if (!mounted) return;
      setState(() {
        _d = _m(d);
        _at = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: aBg,
        appBar: adminBar(
          "Owner's dashboard",
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : () => _load(fresh: true))],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFB9C7AE),
            indicatorColor: Color(0xFF88BA63),
            tabs: [Tab(text: 'Today'), Tab(text: 'Factory'), Tab(text: 'Farms')],
          ),
        ),
        body: _d == null
            ? Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Padding(padding: const EdgeInsets.all(20), child: AErrorBox(_error ?? 'Could not load the dashboard.')),
              )
            : TabBarView(children: [
                _page(_today()),
                _page(_factory()),
                _page(_farms()),
              ]),
      ),
    );
  }

  Widget _page(List<Widget> children) => RefreshIndicator(
        onRefresh: () => _load(fresh: true),
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
          if (_error != null) ...[AErrorBox(_error), const SizedBox(height: 10)],
          ...children,
          const SizedBox(height: 12),
          if (_at != null) Text('Updated ${DateFormat('h:mm a').format(_at!)} · pull down to refresh', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: aMuted)),
        ]),
      );

  // ── Small pieces ──────────────────────────────────────────────────────
  Widget _title(String t, {String? note}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
        child: Row(children: [
          Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: aMuted)),
          if (note != null) ...[const Spacer(), Flexible(child: Text(note, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: aMuted)))],
        ]),
      );

  Widget _change(dynamic pct, {bool goodUp = true, String text = ''}) {
    final p = pct is num ? pct : num.tryParse('${pct ?? ''}');
    if (p == null) return Text(text.isEmpty ? '—' : 'nothing to compare', style: const TextStyle(fontSize: 12, color: aMuted));
    final good = p == 0 || (p > 0) == goodUp;
    return Text.rich(TextSpan(children: [
      TextSpan(text: '${p > 0 ? '▲' : p < 0 ? '▼' : ''} ${p.abs()}%', style: TextStyle(fontWeight: FontWeight.w800, color: good ? aGreenDark : aRed)),
      if (text.isNotEmpty) TextSpan(text: ' $text', style: const TextStyle(color: aMuted)),
    ]), style: const TextStyle(fontSize: 12));
  }

  Widget _tile(String label, String value, Widget sub, {Color? dot}) => Expanded(
        child: ACard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: aMuted)),
            const SizedBox(height: 2),
            Row(children: [
              if (dot != null) Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: aText))),
            ]),
            const SizedBox(height: 2),
            sub,
          ]),
        ),
      );

  Widget _muted(String t) => Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: aMuted));

  // ── Today ─────────────────────────────────────────────────────────────
  List<Widget> _today() {
    final t = _m(_d!['today_page']);
    final f = _m(t['factory']);
    final disp = _m(t['dispatch']);
    final w = _m(t['workers']);
    final sp = _m(t['spray']);
    final alerts = _l(t['alerts']);
    final readings = _m(t['readings']);
    final ap = _m(t['approvals']);
    final jobs = _l(t['crop_jobs']);

    String fValue = '—';
    Color? fDot;
    String fSub = '';
    if (f.isNotEmpty) {
      if (f['closed'] == true) {
        fValue = 'Closed';
        fDot = Colors.grey;
        fSub = '${f['closed_reason'] ?? 'plant closed'}';
      } else if (f['entered'] != true) {
        fValue = 'Not entered';
        fDot = _amber;
        fSub = 'no run for ${shortDate(f['date'])} yet';
      } else {
        final h = num.tryParse('${f['run_h']}') ?? 0;
        fValue = '${n1(h)} h';
        fDot = h >= 20 ? aGreen : _amber;
        final top = _m(f['top_stop']);
        fSub = (f['stops'] ?? 0) == 0 ? 'no stops' : '${f['stops']} stop${f['stops'] == 1 ? '' : 's'}${top.isNotEmpty ? ' · ${'${top['reason']}'.toLowerCase()} ${n1(top['hours'])} h' : ''}';
      }
    }
    const spray = {'good': ('Good', aGreen), 'careful': ('Careful', _amber), 'avoid': ('Avoid', _red), 'night': ('Not now', Colors.grey)};
    final spv = spray[sp['status']] ?? ('—', Colors.grey);
    final past = readings['past_reminder'] == true;

    return [
      Row(children: [
        _tile('Factory yesterday · ${shortDate(f['date'])}', fValue, _muted(fSub), dot: fDot),
        const SizedBox(width: 10),
        _tile('Dispatch today', (disp['trucks_today'] ?? 0) == 0 ? 'None yet' : '${disp['trucks_today']} truck${disp['trucks_today'] == 1 ? '' : 's'}',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_muted('${n1(disp['mt_today'])} MT · month ${n0(disp['mt_month'])} MT'), _change(disp['pct'], text: 'vs last month')])),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _tile('Farm workers today', w['marked'] == true ? n0(w['present']) : 'Not marked',
            w['marked'] == true ? _muted('${n0(w['men'])} men · ${n0(w['women'])} women') : _muted(w['usual'] != null ? 'usual ${w['usual']}' : 'not marked yet'),
            dot: w['marked'] == true ? null : _amber),
        const SizedBox(width: 10),
        _tile('Spraying now${sp['farm_name'] != null ? ' · ${sp['farm_name']}' : ''}', spv.$1, _muted(sp['best_text'] != null ? 'best ${sp['best_text']}' : '${sp['text'] ?? ''}'), dot: spv.$2),
      ]),
      const SizedBox(height: 8),
      _title('Needs a look', note: alerts.isEmpty ? null : '${alerts.length} · red first'),
      if (alerts.isEmpty)
        const ACard(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.check_circle_outline, color: aGreen), SizedBox(width: 10), Text('All fine. Nothing needs a look.')]))
      else
        LayoutBuilder(builder: (ctx, c) {
          final w2 = (c.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final a in alerts) SizedBox(width: w2, child: _alertTile(a))]);
        }),
      const SizedBox(height: 8),
      _title('Readings for ${shortDate(readings['for_date'])}', note: readings['reminder_time'] != null ? 'reminder at ${readings['reminder_time']}' : null),
      ACard(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Column(children: [
          for (final r in _l(readings['items']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: r['in'] == true ? aGreen : past ? _red : Colors.grey)),
                const SizedBox(width: 10),
                Expanded(child: Text('${r['label']}', style: const TextStyle(fontSize: 14))),
                Text(r['in'] == true ? 'In' : 'Missing', style: TextStyle(fontWeight: FontWeight.w700, color: r['in'] == true ? aGreenDark : past ? aRed : aMuted)),
              ]),
            ),
          if (ap.isNotEmpty) ...[
            const Divider(height: 16),
            Row(children: [
              const Expanded(child: Text('Waiting for approval', style: TextStyle(fontSize: 14))),
              Text('${ap['total'] ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      _title('Crop jobs due'),
      ACard(
        child: jobs.isEmpty
            ? const Padding(padding: EdgeInsets.all(14), child: Text('Nothing due today or tomorrow.', style: TextStyle(color: aMuted)))
            : Column(children: [
                for (var i = 0; i < jobs.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${jobs[i]['crop']} · ${jobs[i]['farm']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${jobs[i]['label'] ?? (jobs[i]['kind'] == 'pruning' ? 'Pruning' : 'Job')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: aMuted)),
                        ]),
                      ),
                      Text(
                        jobs[i]['when'] == 'late' ? '${jobs[i]['days_late']} days late' : '${jobs[i]['when']}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: jobs[i]['when'] == 'late' ? aRed : jobs[i]['when'] == 'today' ? aAmber : aMuted),
                      ),
                    ]),
                  ),
              ]),
      ),
    ];
  }

  Widget _alertTile(Map<String, dynamic> a) {
    final red = a['level'] == 'red';
    final c = red ? _red : _amber;
    const icons = {'bolt': Icons.bolt, 'spray': Icons.water_drop_outlined, 'cal': Icons.event, 'water': Icons.opacity, 'drop': Icons.local_gas_station_outlined, 'gear': Icons.build_outlined, 'clock': Icons.schedule};
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: red ? const Color(0xFFFDF1EF) : const Color(0xFFFFF7EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: c, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Icon(icons[a['icon']] ?? Icons.warning_amber, size: 17, color: Colors.white)),
          const SizedBox(width: 8),
          Expanded(child: Text('${a['title']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Center(child: _visual(_m(a['visual']), c)),
        const SizedBox(height: 6),
        Text('${a['caption'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF3A4833))),
      ]),
    );
  }

  Widget _visual(Map<String, dynamic> v, Color c) {
    num? n(dynamic x) => x is num ? x : num.tryParse('${x ?? ''}');
    switch (v['type']) {
      case 'gauge':
        final min = n(v['min']) ?? 0.95;
        final max = n(v['max']) ?? 1;
        final val = n(v['value']) ?? min;
        final lim = n(v['limit']) ?? 0.99;
        return Column(children: [
          Text((val).toStringAsFixed(3), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (ctx, cc) {
            final w = cc.maxWidth;
            final span = (max - min) == 0 ? 1 : (max - min);
            final at = ((val - min) / span).clamp(0.0, 1.0).toDouble();
            final lv = ((lim - min) / span).clamp(0.0, 1.0).toDouble();
            return SizedBox(
              height: 12,
              child: Stack(children: [
                Row(children: [
                  Container(width: w * lv, height: 12, decoration: const BoxDecoration(color: Color(0xFFF0B9AE), borderRadius: BorderRadius.horizontal(left: Radius.circular(6)))),
                  Expanded(child: Container(height: 12, decoration: const BoxDecoration(color: Color(0xFFBFDDAA), borderRadius: BorderRadius.horizontal(right: Radius.circular(6))))),
                ]),
                Positioned(left: (w * at - 1.5).clamp(0.0, w - 3).toDouble(), top: 0, bottom: 0, child: Container(width: 3, color: aText)),
              ]),
            );
          }),
          Text('below $lim adds a charge', style: const TextStyle(fontSize: 10.5, color: aMuted)),
        ]);
      case 'count':
        return Column(children: [
          Text('${v['value']}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c, height: 1)),
          Text('${v['unit'] ?? ''}', style: const TextStyle(fontSize: 12)),
        ]);
      case 'drop':
        final val = n(v['value']);
        final fill = val == null ? 0.05 : (val / (n(v['max']) ?? 0.4)).clamp(0.05, 1.0).toDouble();
        return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            width: 30,
            height: 42,
            decoration: BoxDecoration(border: Border.all(color: c, width: 2), borderRadius: const BorderRadius.vertical(top: Radius.circular(18), bottom: Radius.circular(14))),
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(heightFactor: fill, widthFactor: 1, child: Container(color: c)),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(val == null ? '—' : val.toStringAsFixed(2), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c, height: 1)),
            const Text('leaf water', style: TextStyle(fontSize: 11, color: aMuted)),
          ]),
        ]);
      case 'bars':
        final val = n(v['value']) ?? 0;
        final norm = n(v['normal']) ?? 0;
        final mx = (val > norm ? val : norm) == 0 ? 1 : (val > norm ? val : norm);
        Widget bar(num x, Color col, String l) => Column(mainAxisSize: MainAxisSize.min, children: [
              Text(n1(x), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Container(width: 22, height: 40 * (x / mx).clamp(0.0, 1.0).toDouble(), color: col),
              Text(l, style: const TextStyle(fontSize: 10.5, color: aMuted)),
            ]);
        return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          bar(norm, const Color(0xFF9DB98A), 'normal'),
          const SizedBox(width: 12),
          bar(val, c, 'latest'),
          const SizedBox(width: 8),
          Text('${v['unit'] ?? ''}', style: const TextStyle(fontSize: 10.5, color: aMuted)),
        ]);
      case 'ring':
        final overdue = v['overdue'] == true;
        final days = n(v['days']) ?? 0;
        return SizedBox(
          width: 58,
          height: 58,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: overdue ? 1 : (1 - days * 0.1).clamp(0.08, 1.0).toDouble(), strokeWidth: 6, color: c, backgroundColor: const Color(0xFFE6E1D3)),
            Text(overdue ? 'Over\ndue' : '$days\n${days == 1 ? 'day' : 'days'}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1.1)),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Factory ───────────────────────────────────────────────────────────
  List<Widget> _factory() {
    final f = _m(_d!['factory_page']);
    if (f.isEmpty) return [const AErrorBox('Factory figures could not be loaded.')];
    final k = _m(f['kpis']);
    final vs = 'vs ${f['prev_label']}';
    final dk = _m(k['dispatch_mt']);
    final rh = _m(k['run_h_per_day']);
    final kw = _m(k['kwh_per_run_h']);
    final pf = _m(k['pf']);
    final dz = _m(k['diesel_l_per_h']);
    final dd = _l(f['dispatch_daily']);
    final rd = _l(f['run_daily']);
    final stops = _l(f['stops']);
    num mx = 1;
    for (final x in dd) {
      final a = num.tryParse('${x['now']}') ?? 0;
      final b = num.tryParse('${x['prev']}') ?? 0;
      if (a > mx) mx = a;
      if (b > mx) mx = b;
    }
    num smax = 1;
    for (final s in stops) {
      final h = num.tryParse('${s['hours']}') ?? 0;
      if (h > smax) smax = h;
    }
    return [
      Text('${f['label']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: aText)),
      Text('compared with ${f['prev_label']}', style: const TextStyle(fontSize: 12.5, color: aMuted)),
      const SizedBox(height: 10),
      Row(children: [
        _tile('Dispatched', '${n0(dk['now'])} MT', _change(dk['pct'], text: vs)),
        const SizedBox(width: 10),
        _tile('Run hours a day', '${n1(rh['now'])} h', _change(rh['pct'], text: vs)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _tile('kWh per run hour', n0(kw['now']), _change(kw['pct'], goodUp: false, text: vs)),
        const SizedBox(width: 10),
        _tile('Power factor', pf['avg'] == null ? '—' : (num.tryParse('${pf['avg']}') ?? 0).toStringAsFixed(3),
            Text((pf['days_below'] ?? 0) == 0 ? 'never below ${pf['limit']}' : '${pf['days_below']} days below ${pf['limit']}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: (pf['days_below'] ?? 0) == 0 ? aGreenDark : aRed))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _tile('Tractor diesel', dz['now'] == null ? '—' : '${(num.tryParse('${dz['now']}') ?? 0).toStringAsFixed(2)} L/h', _change(dz['pct'], goodUp: false, text: vs)),
        const SizedBox(width: 10),
        const Expanded(child: SizedBox()),
      ]),
      const SizedBox(height: 8),
      _title('Dispatch, MT a day', note: 'green ${f['label']} · grey ${f['prev_label']}'),
      ACard(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: SizedBox(
          height: 110,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final x in dd)
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Container(height: 100 * ((num.tryParse('${x['prev']}') ?? 0) / mx).clamp(0.0, 1.0).toDouble(), color: const Color(0xFFC9D6BE))),
                  Expanded(child: Container(height: 100 * ((num.tryParse('${x['now']}') ?? 0) / mx).clamp(0.0, 1.0).toDouble(), color: aGreen)),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      _title('Run hours a day', note: 'amber = under 20 h'),
      ACard(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: SizedBox(
          height: 80,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final x in rd)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: x['closed'] == true ? 4 : 76 * ((num.tryParse('${x['run_h'] ?? 0}') ?? 0) / 24).clamp(0.0, 1.0).toDouble(),
                    color: x['closed'] == true ? Colors.grey : ((num.tryParse('${x['run_h'] ?? 0}') ?? 0) >= 20 ? aGreen : _amber),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      _title('Why the plant stopped', note: '${n1(f['stops_total_h'])} h'),
      ACard(
        padding: const EdgeInsets.all(12),
        child: stops.isEmpty
            ? const Text('No stops.', style: TextStyle(color: aMuted))
            : Column(children: [
                for (var i = 0; i < stops.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 110, child: Text('${stops[i]['reason']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(minHeight: 9, value: ((num.tryParse('${stops[i]['hours']}') ?? 0) / smax).toDouble(), color: i == 0 ? _red : _amber, backgroundColor: aSoftGrey),
                        ),
                      ),
                      SizedBox(width: 52, child: Text('${n1(stops[i]['hours'])} h', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ),
              ]),
      ),
      const SizedBox(height: 8),
      _costs('Costs', 'vs ${f['prev_label']} · no ₹ shown', _l(f['costs'])),
      const SizedBox(height: 8),
      _title('Top buyers by MT'),
      ACard(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Column(children: [
          for (final b in _l(f['buyers']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [Expanded(child: Text('${b['party']}')), Text('${n0(b['mt'])} MT', style: const TextStyle(fontWeight: FontWeight.w700))]),
            ),
          if (_l(f['buyers']).isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No dispatch yet.', style: TextStyle(color: aMuted))),
        ]),
      ),
    ];
  }

  Widget _costs(String title, String note, List<Map<String, dynamic>> costs) => Column(children: [
        _title(title, note: note),
        ACard(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: Column(children: [
            for (var i = 0; i < costs.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
                child: Row(children: [
                  Expanded(child: Text('${costs[i]['label']}', style: const TextStyle(fontSize: 14))),
                  _change(costs[i]['pct'], goodUp: false),
                ]),
              ),
          ]),
        ),
      ]);

  // ── Farms ─────────────────────────────────────────────────────────────
  List<Widget> _farms() {
    final p = _m(_d!['farms_page']);
    final crops = _l(p['crops']);
    final water = _l(p['water']);
    final mandi = _l(p['mandi']);
    final w7 = _l(p['workers_7d']);
    num wmax = 1;
    for (final x in w7) {
      final v = num.tryParse('${x['present'] ?? 0}') ?? 0;
      if (v > wmax) wmax = v;
    }
    const st = {
      'stress': ('Water stress', AChip.bad),
      'watch': ('Watch', AChip.wait),
      'fine': ('Fine', AChip.ok),
    };
    const greyText = {'not_judged': 'Too young / near harvest', 'no_crop': 'No crop', 'clouds': 'Clouds', 'no_image': 'No image yet', 'no_boundary': 'Draw boundary'};
    final rule = _m(p['water_rule']);
    return [
      _title('Water stress by farm', note: 'satellite, about every 5 days'),
      ACard(
        child: Column(children: [
          for (var i = 0; i < water.length; i++)
            Builder(builder: (ctx) {
              final r = water[i];
              final s = st[r['status']];
              final chg = r['ndmi_change'] == null ? '' : ' (${(num.tryParse('${r['ndmi_change']}') ?? 0) > 0 ? '+' : ''}${r['ndmi_change']})';
              final img = r['status'] == 'clouds'
                  ? 'no clear image since ${shortDate(r['image_date'])}'
                  : r['image_date'] != null
                      ? 'image ${shortDate(r['image_date'])}${r['cloud_pct'] != null ? ' · ${r['cloud_pct']}% cloud' : ''}'
                      : r['status'] == 'no_boundary'
                          ? 'boundary not drawn'
                          : 'no image yet';
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${r['farm']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    if (s != null) s.$2(s.$1) else AChip(greyText[r['status']] ?? '${r['status']}'),
                  ]),
                  Text('${r['crops']}', style: const TextStyle(fontSize: 12.5, color: aMuted)),
                  const SizedBox(height: 3),
                  Text(
                    'Leaf water ${r['ndmi'] ?? '—'}$chg · vigour ${r['ndvi'] ?? '—'} · rain ${r['rain_mm'] == null ? '—' : '${n1(r['rain_mm'])} mm'} · sprinkler ${r['sprinkler'] == null ? '—' : r['sprinkler'] == true ? 'yes' : 'no'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(img, style: const TextStyle(fontSize: 11.5, color: aMuted)),
                ]),
              );
            }),
          if (water.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No active farm.', style: TextStyle(color: aMuted))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Text(
          'Leaf water (NDMI) below ${rule['stress_below'] ?? 0.1} = water stress, below ${rule['watch_below'] ?? 0.2} = watch, or a drop of ${rule['drop'] ?? 0.1} since the last image. Vigour (NDVI) = how green the crop is.',
          style: const TextStyle(fontSize: 11.5, color: aMuted),
        ),
      ),
      const SizedBox(height: 8),
      _title('Crops'),
      ACard(
        child: Column(children: [
          for (var i = 0; i < crops.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${crops[i]['crop']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  TextSpan(text: '  ${[crops[i]['farm'], crops[i]['size']].where((x) => x != null).join(' · ')}', style: const TextStyle(color: aMuted, fontSize: 12.5)),
                ])),
                Text('${crops[i]['stage'] ?? (crops[i]['cycle_type'] == 'orchard' ? 'Orchard' : 'Growing')}${crops[i]['day'] != null && crops[i]['days_to_harvest'] != null ? ' · day ${crops[i]['day']} of ${crops[i]['days_to_harvest']}' : ''}',
                    style: const TextStyle(fontSize: 13)),
                if (crops[i]['day'] != null && crops[i]['days_to_harvest'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: ((num.tryParse('${crops[i]['day']}') ?? 0) / (num.tryParse('${crops[i]['days_to_harvest']}') ?? 1)).clamp(0.0, 1.0).toDouble(),
                        color: aGreen,
                        backgroundColor: aSoftGrey,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Builder(builder: (ctx) {
                  final j = _m(crops[i]['next_job']);
                  final late = j['late'] == true;
                  final q = num.tryParse('${crops[i]['harvest_qtl'] ?? 0}') ?? 0;
                  return Row(children: [
                    Expanded(
                      child: Text(j.isEmpty ? 'No job due' : '${j['label'] ?? 'Job'} · ${late ? 'late' : shortDate(j['date'])}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: late ? aRed : aMuted)),
                    ),
                    if (q > 0) Text('${n1(q)} qtl', style: const TextStyle(fontSize: 12.5, color: aMuted)),
                  ]);
                }),
              ]),
            ),
          if (crops.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No crop is running.', style: TextStyle(color: aMuted))),
        ]),
      ),
      const SizedBox(height: 8),
      _title('Mandi today', note: 'best market · ₹ per quintal'),
      ACard(
        child: Column(children: [
          for (var i = 0; i < mandi.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: aLine))),
              child: Row(children: [
                SizedBox(width: 80, child: Text('${mandi[i]['crop']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 64, child: Text(n0(mandi[i]['modal']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                SizedBox(width: 58, child: _change(mandi[i]['change_7d_pct'])),
                Expanded(
                  child: Text(
                    '${mandi[i]['market']}${mandi[i]['msp'] != null ? ' · ${mandi[i]['above_msp'] == true ? 'above' : 'below'} MSP ${n0(mandi[i]['msp'])}' : ''}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11.5, color: aMuted),
                  ),
                ),
              ]),
            ),
          if (mandi.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No fresh mandi prices.', style: TextStyle(color: aMuted))),
        ]),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(2, 4, 2, 0), child: Text('change vs a week ago · market prices, not ours', style: TextStyle(fontSize: 11.5, color: aMuted))),
      const SizedBox(height: 8),
      _title('Farm workers, last 7 days'),
      ACard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: SizedBox(
          height: 96,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final x in w7)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(x['present'] == null ? '' : n0(x['present']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Container(width: 20, height: 56 * ((num.tryParse('${x['present'] ?? 0}') ?? 0) / wmax).clamp(0.0, 1.0).toDouble(), color: aGreen),
                  const SizedBox(height: 2),
                  Text(DateTime.tryParse('${x['date']}') == null ? '' : DateFormat('E').format(DateTime.parse('${x['date']}')), style: const TextStyle(fontSize: 10.5, color: aMuted)),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      _costs('Farm costs', '${p['costs_label'] ?? ''}', _l(p['costs'])),
    ];
  }
}
