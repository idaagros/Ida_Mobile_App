// lib/screens/raw_material/rm_common.dart
//
// Shared bits for the Raw material screens (raw material received and money
// owed to suppliers, read from TallyPrime): one small API helper, number /
// date formatting, the period list, and a few small widgets.
// Web counterpart: src/pages/rawmaterial/rmUtils.jsx.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../services/api_client.dart';

const Color rmDark = Color(0xFF1E3313);
const Color rmAppBar = Color(0xFF1E4012);
const Color rmGreen = Color(0xFF3B7A28);
const Color rmBg = Color(0xFFF4F5F1);
const Color rmBorder = Color(0xFFE0E7D8);
const List<Color> rmAgeColors = [
  Color(0xFF88BA63),
  Color(0xFFD9B44A),
  Color(0xFFE08A3C),
  Color(0xFFC8483A),
];

class RmApiException implements Exception {
  final String message;
  final int status;
  RmApiException(this.message, this.status);
  @override
  String toString() => message;
}

class RmApi {
  static Future<dynamic> _call(String method, String path,
      {Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      Duration timeout = const Duration(seconds: 60)}) async {
    http.Response res;
    try {
      res = await Api.send(method, path, body: body, query: query, timeout: timeout);
    } catch (e) {
      throw RmApiException(Api.errorText(e), 0);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RmApiException(Api.responseError(res), res.statusCode);
    }
    return Api.decode(res);
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _call('GET', path, query: query);

  static Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _call('PUT', path, body: body);

  // Reading a year of vouchers from Tally can take a while.
  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _call('POST', path,
          body: body ?? <String, dynamic>{},
          timeout: const Duration(seconds: 180));
}

// ── Formatting ───────────────────────────────────────────────────────
double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

final NumberFormat _inrWhole = NumberFormat.decimalPattern('en_IN');
final NumberFormat _inrPaise = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
final NumberFormat _mtFmt = NumberFormat('#,##0.00#', 'en_IN');

// ₹1,23,456 (paise only when there are some); negatives with a real minus.
String inr(dynamic v) {
  if (v == null) return '—';
  final n = toD(v);
  final abs = n.abs();
  final whole = (abs - abs.roundToDouble()).abs() < 0.005;
  final body = whole ? _inrWhole.format(abs.round()) : _inrPaise.format(abs);
  return '${n < 0 ? '−' : ''}₹$body';
}

String mt(dynamic v) => v == null ? '—' : _mtFmt.format(toD(v));

DateTime? parseDay(dynamic s) {
  if (s == null) return null;
  final str = s.toString();
  if (str.length < 10) return null;
  return DateTime.tryParse(str.substring(0, 10));
}

String dmy(dynamic s) {
  final d = parseDay(s);
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

String dm(dynamic s) {
  final d = parseDay(s);
  return d == null ? '' : DateFormat('d MMM').format(d);
}

// "4:07 am" today, "19 Oct, 4:07 am" otherwise.
String whenText(dynamic ts) {
  if (ts == null) return '';
  final d = DateTime.tryParse(ts.toString())?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final time = DateFormat('h:mm a').format(d).toLowerCase();
  final today = d.year == now.year && d.month == now.month && d.day == now.day;
  return today ? time : '${DateFormat('d MMM').format(d)}, $time';
}

String isoDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

// ── Periods ──────────────────────────────────────────────────────────
class RmRange {
  final String key;
  final String label;
  const RmRange(this.key, this.label);
}

const List<RmRange> kRmRanges = [
  RmRange('season', 'This season'),
  RmRange('today', 'Today'),
  RmRange('week', 'Last 7 days'),
  RmRange('month', 'This month'),
  RmRange('30d', 'Last 30 days'),
  RmRange('fy', 'This financial year'),
  RmRange('custom', 'Pick dates…'),
];

class RmDates {
  final String from;
  final String to;
  const RmDates(this.from, this.to);
}

RmDates rangeDates(String key, {String? fyFrom, String? seasonFrom, String? customFrom, String? customTo}) {
  final now = DateTime.now();
  final today = isoDay(now);
  String back(int n) => isoDay(now.subtract(Duration(days: n)));
  switch (key) {
    case 'season':
      return RmDates(seasonFrom ?? '', today);
    case 'today':
      return RmDates(today, today);
    case 'week':
      return RmDates(back(6), today);
    case '30d':
      return RmDates(back(29), today);
    case 'fy':
      final y = now.month < 4 ? now.year - 1 : now.year;
      return RmDates(fyFrom ?? '$y-04-01', today);
    case 'custom':
      return RmDates(customFrom ?? today, customTo ?? today);
    default:
      return RmDates('${today.substring(0, 7)}-01', today);
  }
}

String rangeLabel(String key, RmDates r) {
  if (key == 'today') return 'today';
  if (key == 'season') return r.from.isEmpty ? 'this season' : 'season since ${dmy(r.from)}';
  if (key == 'month') {
    final d = parseDay(r.from);
    return d == null ? '' : DateFormat('MMMM yyyy').format(d);
  }
  return '${dm(r.from)} – ${dmy(r.to)}';
}

// Dropdown of periods; "Pick dates…" opens a date range picker.
class RmRangePicker extends StatelessWidget {
  final String range;
  final RmDates dates;
  final void Function(String range, RmDates dates) onChanged;
  const RmRangePicker({super.key, required this.range, required this.dates, required this.onChanged});

  Future<void> _pickCustom(BuildContext context) async {
    final first = DateTime(2020);
    final last = DateTime.now().add(const Duration(days: 366));
    final initialStart = parseDay(dates.from) ?? DateTime.now();
    final initialEnd = parseDay(dates.to) ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked != null) {
      onChanged('custom', RmDates(isoDay(picked.start), isoDay(picked.end)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rmBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: range,
          isExpanded: true,
          items: [
            for (final r in kRmRanges)
              DropdownMenuItem<String>(
                value: r.key,
                child: Text(r.key == 'custom' && range == 'custom' ? '${dm(dates.from)} – ${dmy(dates.to)}' : r.label),
              ),
          ],
          onChanged: (k) {
            if (k == null) return;
            if (k == 'custom') {
              _pickCustom(context);
            } else {
              onChanged(k, rangeDates(k));
            }
          },
        ),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────
class RmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  const RmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Colors.white,
    this.borderColor = rmBorder,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: child,
      );
}

class RmTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final bool dark;
  const RmTile({super.key, required this.label, required this.value, required this.sub, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : const Color(0xFF1E3313);
    final muted = dark ? const Color(0xFFC9D7BD) : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? rmDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? rmDark : rmBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 11.5, color: muted)),
      ]),
    );
  }
}

// Two tiles per row, any number of tiles.
class RmTileGrid extends StatelessWidget {
  final List<Widget> tiles;
  const RmTileGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class RmSectionLabel extends StatelessWidget {
  final String text;
  const RmSectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E3313))),
      );
}

class RmErrorBox extends StatelessWidget {
  final String message;
  const RmErrorBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B))),
      );
}

// Amber banner when the latest read of Tally failed (old data stays on screen).
class RmSyncBanner extends StatelessWidget {
  final Map<String, dynamic> status;
  const RmSyncBanner(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final last = status['last_attempt'];
    if (last is! Map || last['status'] != 'error') return const SizedBox.shrink();
    final msg = (last['message'] ?? '').toString();
    final okAt = status['last_ok_at'];
    final text = "Couldn't read Tally at ${whenText(last['at'])}${msg.isNotEmpty ? ': $msg' : ''}."
        "${okAt != null ? ' Showing what was read at ${whenText(okAt)}.' : ''}";
    return RmCard(
      color: const Color(0xFFFFF7EA),
      borderColor: const Color(0xFFF3D7A6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFF7A4D00), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFF6A4300)))),
      ]),
    );
  }
}

// "Matches Tally" / "Differs from Tally by ₹x".
class RmTallyChip extends StatelessWidget {
  final dynamic diff;
  final dynamic tally;
  const RmTallyChip({super.key, required this.diff, required this.tally});

  @override
  Widget build(BuildContext context) {
    if (diff == null) return const SizedBox.shrink();
    final d = toD(diff);
    final ok = d.abs() < 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE3F0DA) : const Color(0xFFFCEFD2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ok ? '✓ Matches Tally' : '⚠ Differs from Tally by ${inr(d.abs())}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ok ? const Color(0xFF2C5E17) : const Color(0xFF7A4D00)),
      ),
    );
  }
}

// One segmented bar for the ageing buckets of what is due.
class RmAgingBar extends StatelessWidget {
  final Map<String, dynamic> aging;
  final Map<String, dynamic> labels;
  final double total;
  const RmAgingBar({super.key, required this.aging, required this.labels, required this.total});

  @override
  Widget build(BuildContext context) {
    final keys = labels.keys.toList();
    if (keys.isEmpty || total <= 0) return const SizedBox.shrink();
    final segments = <Widget>[];
    for (var i = 0; i < keys.length; i++) {
      final v = toD(aging[keys[i]]);
      if (v > 0) {
        segments.add(Expanded(
          flex: (v / total * 1000).round().clamp(1, 1000).toInt(),
          child: Container(color: rmAgeColors[i % rmAgeColors.length]),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(height: 12, child: Row(children: segments)),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (var i = 0; i < keys.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: rmAgeColors[i % rmAgeColors.length], borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 5),
            Text('${labels[keys[i]]} ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            Text(inr(aging[keys[i]]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
      ]),
    ]);
  }
}

// ── Rate / deduction / weight alerts (the server learns each supplier's usual values) ──
// kind: 'one-off' | 'new?' (latest purchase, not yet confirmed) | 'unusual' (weight)
//       | 'changed' (information) | 'explained' (narration gives a quality reason; information).
bool isInfoAlert(Map a) => a['kind'] == 'changed' || a['kind'] == 'explained';

String alertText(Map a, {bool withParty = true}) {
  final who = withParty ? '${a['party']}: ' : '';
  final when = '${a['label']} on ${dm(a['date'])}';
  final usual = toD(a['usual']);
  final value = toD(a['value']);
  final kind = a['kind'];
  if (a['field'] == 'weight') return "$who$when was ${mt(value)} MT; this supplier's usual load is about ${mt(usual)} MT.";
  if (a['field'] == 'vehicle') {
    final pct = usual > 0 ? ((value - usual).abs() / usual * 100).round() : 0;
    final dir = value > usual ? 'more' : 'less';
    final veh = (a['vehicle'] ?? '').toString();
    if (a['basis'] == 'supplier') return "$who$when: truck $veh is new to us and carried ${mt(value)} MT, $pct% $dir than this supplier's usual load of ${mt(usual)} MT.";
    return '$who$when: truck $veh carried ${mt(value)} MT, $pct% $dir than its usual ${mt(usual)} MT (last ${toD(a['trips']).round()} trips). A different vehicle, or a wrong number?';
  }
  final why = kind == 'explained' && a['note'] != null ? ' Narration: "${a['note']}".' : '';
  if (a['field'] == 'rate') {
    if (kind == 'changed') return '${who}rate changed from ${inr(usual)} to ${inr(value)} per MT from $when. Treated as the usual rate from now on.';
    return '$who$when was at ${inr(value)} per MT; usual is ${inr(usual)}${kind == 'new?' ? ' (latest purchase: a new rate, or a mistake?)' : ''}.$why';
  }
  if (kind == 'changed') return '${who}deduction changed from ${inr(usual)} to ${inr(value)} from $when. Treated as the usual from now on.';
  if (usual == 0) return '$who$when has a deduction of ${inr(value)}; usually none.$why';
  if (value == 0) return '$who$when has no deduction; usually ${inr(usual)}.$why';
  return '$who$when has a deduction of ${inr(value)}; usually ${inr(usual)}.$why';
}

String alertShort(Map a) {
  final usual = toD(a['usual']);
  if (a['field'] == 'weight') return 'load usually about ${mt(usual)} MT';
  if (a['field'] == 'vehicle') {
    final veh = (a['vehicle'] ?? '').toString();
    return a['basis'] == 'supplier'
        ? "new truck $veh: ${toD(a['value']) > usual ? 'heavier' : 'lighter'} than this supplier's usual ${mt(usual)} MT"
        : 'truck $veh usually carries ${mt(usual)} MT';
  }
  if (a['field'] == 'rate') {
    if (a['kind'] == 'changed') return 'rate changed from ${inr(usual)}';
    return a['kind'] == 'explained' ? 'rate usually ${inr(usual)} (quality cut in narration)' : 'rate usually ${inr(usual)}';
  }
  if (a['kind'] == 'changed') return 'deduction changed from ${inr(usual)}';
  return (usual == 0 ? 'usually no deduction' : 'deduction usually ${inr(usual)}') + (a['kind'] == 'explained' ? ' (quality cut in narration)' : '');
}
