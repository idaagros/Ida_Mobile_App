// lib/screens/mandi/mandi_commodity_screen.dart
//
// One commodity: price in each market today, the price trend (with MSP
// line), and "Best time to sell" — the seasonal pattern from the last
// few years, worked out on the backend (utils/mandiAnalysis.js).
// Web counterpart: src/pages/MandiCommodity.jsx.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'mandi_common.dart';

class MandiCommodityScreen extends StatefulWidget {
  final int commodityId;
  final String title;
  const MandiCommodityScreen({super.key, required this.commodityId, required this.title});
  @override
  State<MandiCommodityScreen> createState() => _MandiCommodityScreenState();
}

class _MandiCommodityScreenState extends State<MandiCommodityScreen> {
  List<Map<String, dynamic>> markets = [];
  List<Map<String, dynamic>> varieties = [];
  String market = 'all';
  String variety = 'all';

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    try {
      final m = await MandiApi.get('/mandi/markets');
      final v = await MandiApi.get('/mandi/commodities/${widget.commodityId}/varieties');
      if (!mounted) return;
      setState(() {
        markets = List<Map<String, dynamic>>.from(m).where((x) => x['is_active'] == 1 || x['is_active'] == true).toList();
        varieties = List<Map<String, dynamic>>.from(v);
      });
    } catch (_) {
      // Filters are optional — the tabs still work with "all".
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterKey = '$market|$variety';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8F6),
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: mandiDark,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Color(0xFF88BA63),
            tabs: [
              Tab(text: 'Markets'),
              Tab(text: 'Trend'),
              Tab(text: 'Best time'),
            ],
          ),
        ),
        body: Column(children: [
          _filters(),
          Expanded(
            child: TabBarView(children: [
              _MarketsTab(key: ValueKey('m$variety'), id: widget.commodityId, variety: variety),
              _TrendTab(key: ValueKey('t$filterKey'), id: widget.commodityId, market: market, variety: variety),
              _SeasonalTab(key: ValueKey('s$filterKey'), id: widget.commodityId, market: market, variety: variety),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: market,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Market', isDense: true, border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All markets (average)')),
              ...markets.map((m) => DropdownMenuItem(
                    value: m['market'].toString(),
                    child: Text(marketName(m), overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => market = v ?? 'all'),
          ),
        ),
        if (varieties.length > 1) ...[
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: variety,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Variety', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All varieties')),
                ...varieties.map((v) {
                  final name = (v['variety'] ?? '').toString();
                  return DropdownMenuItem(value: name, child: Text(name.isEmpty ? '(unspecified)' : name, overflow: TextOverflow.ellipsis));
                }),
              ],
              onChanged: (v) => setState(() => variety = v ?? 'all'),
            ),
          ),
        ],
      ]),
    );
  }
}

String _q(String s) => Uri.encodeQueryComponent(s);

// ── Markets today ─────────────────────────────────────────────────────
class _MarketsTab extends StatefulWidget {
  final int id;
  final String variety;
  const _MarketsTab({super.key, required this.id, required this.variety});
  @override
  State<_MarketsTab> createState() => _MarketsTabState();
}

class _MarketsTabState extends State<_MarketsTab> with AutomaticKeepAliveClientMixin {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = [];

  @override
  bool get wantKeepAlive => true;

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
      final d = await MandiApi.get('/mandi/commodities/${widget.id}/markets?variety=${_q(widget.variety)}');
      setState(() => rows = List<Map<String, dynamic>>.from(d['markets'] ?? []));
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    final latest = rows.fold<String>('', (m, r) => (r['date'] ?? '').toString().compareTo(m) > 0 ? r['date'].toString() : m);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (error != null) ErrorBox(error!),
        if (rows.isEmpty && error == null)
          const MandiCard(child: Text('No prices in the last 4 months for any active market.')),
        ...rows.map((r) {
          final old = (r['date'] ?? '').toString() != latest;
          final muted = old ? Colors.grey.shade500 : mandiDark;
          return MandiCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(marketName(r), style: TextStyle(fontWeight: FontWeight.w600, color: muted)),
                  const SizedBox(height: 2),
                  Text(
                    '${shortDate(r['date'])}${r['min'] != null ? ' · ${rupees(r['min'])} – ${rupees(r['max'])}' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, children: [
                    ChangeChip(value: r['change_1d_pct'], label: ' day'),
                    ChangeChip(value: r['change_7d_pct'], label: ' wk'),
                  ]),
                ]),
              ),
              Text(rupees(r['modal']), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: muted)),
            ]),
          );
        }),
        Text('Greyed markets haven\'t reported on the latest date. Prices in ₹ per quintal.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]),
    );
  }
}

// ── Price trend ───────────────────────────────────────────────────────
class _TrendTab extends StatefulWidget {
  final int id;
  final String market;
  final String variety;
  const _TrendTab({super.key, required this.id, required this.market, required this.variety});
  @override
  State<_TrendTab> createState() => _TrendTabState();
}

class _TrendTabState extends State<_TrendTab> with AutomaticKeepAliveClientMixin {
  static const ranges = [(90, '3M'), (365, '1Y'), (1095, '3Y'), (1825, '5Y')];
  int days = 365;
  bool loading = true;
  String? error;
  Map<String, dynamic>? data;

  @override
  bool get wantKeepAlive => true;

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
      final d = await MandiApi.get(
          '/mandi/commodities/${widget.id}/trend?days=$days&market=${_q(widget.market)}&variety=${_q(widget.variety)}');
      setState(() => data = Map<String, dynamic>.from(d));
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final series = List<Map<String, dynamic>>.from(data?['series'] ?? []);
    final summary = data?['summary'] as Map<String, dynamic>?;
    final range = data?['range'] as Map<String, dynamic>?;
    final mspList = List<Map<String, dynamic>>.from(data?['msp'] ?? []);
    final msp = mspList.isEmpty ? null : mspList.last;

    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 6, children: [
        for (final r in ranges)
          ChoiceChip(
            label: Text(r.$2),
            selected: days == r.$1,
            selectedColor: mandiTint,
            onSelected: (_) {
              setState(() => days = r.$1);
              _load();
            },
          ),
      ]),
      const SizedBox(height: 10),
      if (error != null) ErrorBox(error!),
      if (loading)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (series.isEmpty)
        const MandiCard(child: Text('No prices in this period.'))
      else ...[
        Row(children: [
          _stat('Latest', rupees(summary?['modal']), shortDate(summary?['date'])),
          _stat('High', rupees(range?['high']), shortDate(range?['high_date'])),
        ]),
        Row(children: [
          _stat('Low', rupees(range?['low']), shortDate(range?['low_date'])),
          _stat(
            msp != null ? 'MSP ${msp['season_label']}' : 'MSP',
            msp != null ? rupees(msp['msp_price']) : '—',
            msp != null && summary != null
                ? '${(toD(summary['modal']) ?? 0) >= (toD(msp['msp_price']) ?? 0) ? 'above' : 'below'} by ${rupees(((toD(summary['modal']) ?? 0) - (toD(msp['msp_price']) ?? 0)).abs())}'
                : 'not set',
          ),
        ]),
        MandiCard(
          padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
          child: SizedBox(height: 260, child: _chart(series, msp)),
        ),
        Text('Dark line: modal price. Light lines: min and max.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    ]);
  }

  Widget _stat(String label, String value, String sub) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: MandiCard(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionLabel(label),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: mandiDark)),
              Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );

  Widget _chart(List<Map<String, dynamic>> series, Map<String, dynamic>? msp) {
    List<FlSpot> spots(String key) => [
          for (var i = 0; i < series.length; i++)
            if (toD(series[i][key]) != null) FlSpot(i.toDouble(), toD(series[i][key])!)
        ];
    final modal = spots('modal');
    final all = [...modal, ...spots('min'), ...spots('max')].map((s) => s.y).toList();
    final mspV = toD(msp?['msp_price']);
    if (mspV != null) all.add(mspV);
    var minY = all.reduce((a, b) => a < b ? a : b);
    var maxY = all.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) == 0 ? 100.0 : (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;
    final step = (series.length / 4).ceilToDouble().clamp(1, double.infinity).toDouble();

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            getTitlesWidget: (v, meta) => Text(rupeesK(v), style: const TextStyle(fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: step,
            reservedSize: 22,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i < 0 || i >= series.length || v != i.toDouble()) return const SizedBox.shrink();
              final d = series[i]['date'];
              return Text(days > 400 ? (d?.toString() ?? '').substring(0, 7) : dayMonth(d), style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
      extraLinesData: mspV == null
          ? null
          : ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: mspV,
                color: mandiOrange,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(fontSize: 10, color: mandiOrange, fontWeight: FontWeight.w600),
                  labelResolver: (_) => 'MSP ${rupees(mspV)}',
                ),
              ),
            ]),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touched) => touched.map((t) {
            if (t.barIndex != 2) return null;
            final i = t.x.round();
            return LineTooltipItem('${shortDate(series[i]['date'])}\n${rupees(t.y)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600));
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(spots: spots('max'), color: const Color(0xFFC9D6BF), barWidth: 1, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: spots('min'), color: const Color(0xFFC9D6BF), barWidth: 1, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: modal, color: mandiGreen, barWidth: 2, dotData: const FlDotData(show: false)),
      ],
    ));
  }
}

// ── Best time to sell (seasonal) ──────────────────────────────────────
class _SeasonalTab extends StatefulWidget {
  final int id;
  final String market;
  final String variety;
  const _SeasonalTab({super.key, required this.id, required this.market, required this.variety});
  @override
  State<_SeasonalTab> createState() => _SeasonalTabState();
}

class _SeasonalTabState extends State<_SeasonalTab> with AutomaticKeepAliveClientMixin {
  static const monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
  static const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const yearColors = [Color(0xFFC9D6BF), Color(0xFFB0C69F), Color(0xFF94B47F), Color(0xFF7AA262), Color(0xFF5F8A47), Color(0xFF4B7236), Color(0xFF3A5A2A)];
  int years = 5;
  bool loading = true;
  String? error;
  Map<String, dynamic>? data;

  @override
  bool get wantKeepAlive => true;

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
      final d = await MandiApi.get(
          '/mandi/commodities/${widget.id}/seasonal?years=$years&market=${_q(widget.market)}&variety=${_q(widget.variety)}');
      setState(() => data = Map<String, dynamic>.from(d));
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Text('Based on the last ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        for (final y in [3, 4, 5])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$y yrs'),
              selected: years == y,
              selectedColor: mandiTint,
              onSelected: (_) {
                setState(() => years = y);
                _load();
              },
            ),
          ),
      ]),
      const SizedBox(height: 8),
      if (error != null) ErrorBox(error!),
      if (loading)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (data != null && data!['insufficient'] == true)
        MandiCard(child: Text((data!['message'] ?? 'Not enough data yet').toString()))
      else if (data != null)
        ..._body(data!),
    ]);
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final peak = Map<String, dynamic>.from(d['peak']);
    final low = Map<String, dynamic>.from(d['low']);
    final current = Map<String, dynamic>.from(d['current']);
    final yearsUsed = List.from(d['years_used'] ?? []);
    final insights = List<String>.from((d['insights'] ?? []).map((e) => e.toString()));
    final msp = d['latest_msp'] as Map<String, dynamic>?;

    return [
      _windowCard('Usually highest', peak, true, 'Above average in ${peak['above_average_years']} of ${yearsUsed.length} years'),
      _windowCard('Usually lowest', low, false, 'Below average in ${low['below_average_years']} of ${yearsUsed.length} years'),
      MandiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel('Now (${current['label']})'),
          Text(rupees(current['latest_price']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: mandiDark)),
          Text(
            current['typical_price'] != null ? 'Typical for now: ${rupees(current['typical_price'])}' : 'Usually little trading at this time',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            ChangeChip(value: current['vs_typical_pct'], label: ' vs typical'),
            ChangeChip(value: current['vs_last_year_pct'], label: ' vs last yr'),
          ]),
        ]),
      ),
      MandiCard(
        color: const Color(0xFFF3F7EF),
        borderColor: const Color(0xFFDBE6D2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What the last ${yearsUsed.length} years show',
              style: const TextStyle(fontWeight: FontWeight.w700, color: mandiDark)),
          const SizedBox(height: 6),
          ...insights.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  ', style: TextStyle(color: Color(0xFF2F4A1F))),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 13, color: Color(0xFF2F4A1F)))),
                ]),
              )),
          if (msp != null)
            Text('MSP ${msp['season_label']}: ${rupees(msp['msp_price'])} per quintal.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            'A pattern from past years, not a forecast — monsoon, exports, government procurement and stock limits can override it in any given year.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ]),
      ),
      MandiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Price vs yearly average, by fortnight', style: TextStyle(fontWeight: FontWeight.w700, color: mandiDark)),
          Text('Green = usual peak, orange = usual low', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          SizedBox(height: 200, child: _barChart(d)),
        ]),
      ),
      MandiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Each year, fortnight by fortnight', style: TextStyle(fontWeight: FontWeight.w700, color: mandiDark)),
          Text('Lighter = older years. Orange = this year so far.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          SizedBox(height: 220, child: _overlayChart(d)),
          const SizedBox(height: 6),
          _legend(d),
        ]),
      ),
    ];
  }

  Widget _windowCard(String title, Map<String, dynamic> w, bool good, String foot) {
    final pct = toD(w['vs_average_pct']) ?? 0;
    return MandiCard(
      color: good ? mandiTint : mandiOrangeTint,
      borderColor: good ? const Color(0xFFC9D6BF) : const Color(0xFFECD0BB),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(title),
        Text(w['label'].toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: mandiDark)),
        Text('${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}% vs yearly average · about ${rupees(w['typical_price_now'])} at recent levels',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        Text(foot, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]),
    );
  }

  Widget _barChart(Map<String, dynamic> d) {
    final fns = List<Map<String, dynamic>>.from(d['fortnights']);
    final peakSet = Set<int>.from(List.from(d['peak']['fortnights']).map((e) => e as int));
    final lowSet = Set<int>.from(List.from(d['low']['fortnights']).map((e) => e as int));
    final nowFn = d['current']['fn'] as int;
    final vals = fns.map((f) => toD(f['vs_average_pct']) ?? 0).toList();
    final maxAbs = vals.fold<double>(1, (m, v) => v.abs() > m ? v.abs() : m) * 1.15;

    return BarChart(BarChartData(
      minY: -maxAbs,
      maxY: maxAbs,
      alignment: BarChartAlignment.spaceBetween,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? Colors.grey.shade500 : Colors.grey.shade200, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) => Text('${v.round()}%', style: const TextStyle(fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 18,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i % 2 != 0 || i < 0 || i > 23) return const SizedBox.shrink();
              return Text(monthLetters[i ~/ 2], style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, gi, rod, ri) {
            final f = fns[group.x];
            final v = toD(f['vs_average_pct']);
            return BarTooltipItem('${f['label']}\n${v == null ? 'no data' : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%'}',
                const TextStyle(color: Colors.white, fontSize: 11));
          },
        ),
      ),
      barGroups: [
        for (var i = 0; i < 24; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: vals[i],
              width: 7,
              borderRadius: BorderRadius.zero,
              color: peakSet.contains(i)
                  ? mandiGreen
                  : lowSet.contains(i)
                      ? mandiOrange
                      : i == nowFn
                          ? mandiDark
                          : const Color(0xFFB8CFA6),
            ),
          ]),
      ],
    ));
  }

  List<Map<String, dynamic>> _overlay(Map<String, dynamic> d) => List<Map<String, dynamic>>.from(d['overlay'] ?? []);

  Color _yearColor(int indexInPast, int pastCount) {
    final idx = (indexInPast + yearColors.length - pastCount).clamp(0, yearColors.length - 1);
    return yearColors[idx];
  }

  Widget _overlayChart(Map<String, dynamic> d) {
    final overlay = _overlay(d);
    final past = overlay.where((y) => y['is_current'] != true).toList();
    final allVals = <double>[];
    for (final y in overlay) {
      for (final v in List.from(y['values'])) {
        final dv = toD(v);
        if (dv != null) allVals.add(dv);
      }
    }
    if (allVals.isEmpty) return const SizedBox.shrink();
    var minY = allVals.reduce((a, b) => a < b ? a : b);
    var maxY = allVals.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) == 0 ? 100.0 : (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    // FlSpot.nullSpot leaves a real gap (e.g. cotton's Jun–Sep off-season)
    // instead of drawing a straight line across months with no trading.
    List<FlSpot> spots(Map<String, dynamic> y) {
      final vals = List.from(y['values']);
      return [for (var i = 0; i < 24; i++) toD(vals[i]) == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), toD(vals[i])!)];
    }

    return LineChart(LineChartData(
      minX: 0,
      maxX: 23,
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            getTitlesWidget: (v, meta) => Text(rupeesK(v), style: const TextStyle(fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 2,
            reservedSize: 18,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i % 4 != 0 || i < 0 || i > 23) return const SizedBox.shrink();
              return Text(monthShort[i ~/ 2], style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
      lineBarsData: [
        for (var i = 0; i < past.length; i++)
          LineChartBarData(spots: spots(past[i]), color: _yearColor(i, past.length), barWidth: 1.5, dotData: const FlDotData(show: false)),
        for (final y in overlay.where((y) => y['is_current'] == true))
          LineChartBarData(spots: spots(y), color: mandiOrange, barWidth: 2.5, dotData: const FlDotData(show: false)),
      ],
    ));
  }

  Widget _legend(Map<String, dynamic> d) {
    final overlay = _overlay(d);
    final past = overlay.where((y) => y['is_current'] != true).toList();
    return Wrap(spacing: 10, runSpacing: 4, children: [
      for (var i = 0; i < past.length; i++) _legendItem('${past[i]['year']}', _yearColor(i, past.length)),
      for (final y in overlay.where((y) => y['is_current'] == true)) _legendItem('${y['year']} (so far)', mandiOrange),
    ]);
  }

  Widget _legendItem(String text, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 3, color: c),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ]);
}
