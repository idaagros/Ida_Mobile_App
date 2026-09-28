// lib/screens/agronomy/agronomy_common.dart
//
// Shared pieces for the redesigned Agronomy setup (Sep 2026) and the
// crop calendar's "Mark done" screen — the same model as the web app:
//   - Products: one list, each with a kind, the unit doses are written
//     in and one preferred brand (/agri/products).
//   - Spray steps pick products (several = tank mix) with a dose per
//     acre (seasonal) or per tree (orchard).
//   - When recording, the preferred brand is filled in and can be
//     changed; recommended = dose x acres (or trees) sprayed, actual is
//     typed in.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

const Color agGreen = Color(0xFF3B7A28);
const Color agDark = Color(0xFF1E4012);
const Color agBg = Color(0xFFF4F7F2);
const Color agBorder = Color(0xFFE0E7D8);
const Color agMuted = Color(0xFF5F6A58);

// ── API ────────────────────────────────────────────────────────────────
class AgriApi {
  static const baseUrl = AppConfig.apiBaseUrl;

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
  }

  static dynamic _decode(http.Response res) {
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final msg = data is Map && data['error'] != null
        ? data['error'].toString()
        : 'Something went wrong (${res.statusCode})';
    throw AgriApiError(msg);
  }

  static Future<dynamic> get(String path) async =>
      _decode(await http.get(Uri.parse('$baseUrl$path'), headers: await _headers()));
  static Future<dynamic> post(String path, Map body) async => _decode(await http
      .post(Uri.parse('$baseUrl$path'), headers: await _headers(), body: jsonEncode(body)));
  static Future<dynamic> patch(String path, Map body) async => _decode(await http
      .patch(Uri.parse('$baseUrl$path'), headers: await _headers(), body: jsonEncode(body)));
  static Future<dynamic> delete(String path) async =>
      _decode(await http.delete(Uri.parse('$baseUrl$path'), headers: await _headers()));
}

class AgriApiError implements Exception {
  final String message;
  AgriApiError(this.message);
  @override
  String toString() => message;
}

// ── Kinds of product ───────────────────────────────────────────────────
class AgKind {
  final String label;
  final Color bg;
  final Color fg;
  final Color dot;
  const AgKind(this.label, this.bg, this.fg, this.dot);
}

const Map<String, AgKind> agKinds = {
  'fertilizer': AgKind('Fertiliser', Color(0xFFE3F0DA), Color(0xFF2C5E17), Color(0xFF5D9A37)),
  'pesticide': AgKind('Pesticide', Color(0xFFFDE6D2), Color(0xFF8C3F06), Color(0xFFF47D1E)),
  'fungicide': AgKind('Fungicide', Color(0xFFDDE9F7), Color(0xFF1D4D86), Color(0xFF3B73B9)),
  'weedicide': AgKind('Weedicide', Color(0xFFF1E4F6), Color(0xFF6B2C86), Color(0xFF8A4AA6)),
  'pruning': AgKind('Pruning', Color(0xFFECEEE8), Color(0xFF3A4833), Color(0xFF6B7566)),
};
const List<String> agKindKeys = ['fertilizer', 'pesticide', 'fungicide', 'weedicide'];
const List<String> agUnits = ['ml', 'L', 'g', 'kg'];
const List<String> agAgeBrackets = ['1-3', '4-6', '7-10', '10+'];

class KindChip extends StatelessWidget {
  final String? kind;
  const KindChip(this.kind, {super.key});
  @override
  Widget build(BuildContext context) {
    final k = agKinds[kind];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: k?.bg ?? const Color(0xFFFCEFD2), borderRadius: BorderRadius.circular(20)),
      child: Text(k?.label ?? 'Kind?',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: k?.fg ?? const Color(0xFF7A4D00))),
    );
  }
}

class SmallChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const SmallChip(this.text, {super.key, this.bg = Colors.white, this.fg = const Color(0xFF3A4833)});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: bg == Colors.white ? Border.all(color: const Color(0xFFD5DCCD)) : null),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

// ── Units and quantities ───────────────────────────────────────────────
bool _liquid(String u) => u == 'ml' || u == 'L';
double _toBase(String u) => (u == 'L' || u == 'kg') ? 1000 : 1;

double convertQty(double qty, String from, String to) {
  if (from == to || _liquid(from) != _liquid(to)) return qty;
  return qty * _toBase(from) / _toBase(to);
}

List<String> familyUnits(String unit) => _liquid(unit) ? ['ml', 'L'] : ['g', 'kg'];

String niceUnit(double qty, String unit) {
  if (unit == 'ml' && qty >= 1000) return 'L';
  if (unit == 'g' && qty >= 1000) return 'kg';
  if (unit == 'L' && qty > 0 && qty < 1) return 'ml';
  if (unit == 'kg' && qty > 0 && qty < 1) return 'g';
  return unit;
}

String trimNum(num? n, [int dp = 2]) {
  if (n == null) return '';
  final f = (n * _pow10(dp)).round() / _pow10(dp);
  return f == f.roundToDouble() ? f.toInt().toString() : f.toString();
}

double _pow10(int dp) {
  double r = 1;
  for (var i = 0; i < dp; i++) {
    r *= 10;
  }
  return r;
}

String fmtQty(num? qty, String unit) {
  if (qty == null) return '—';
  final u = niceUnit(qty.toDouble(), unit);
  return '${trimNum(convertQty(qty.toDouble(), unit, u))} $u';
}

double? toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? toI(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

// ── When a step happens ────────────────────────────────────────────────
const Map<String, String> anchorWords = {
  'DAS': 'sowing',
  'DAF': 'flowering starts',
  'DAP': 'pruning',
  'DAH': 'harvest',
  'DAPREV': 'another step is done',
};

List<String> anchorOptions(bool seasonal, {bool withPrev = true}) {
  final list = seasonal ? ['DAS'] : ['DAF', 'DAP', 'DAH'];
  return withPrev ? [...list, 'DAPREV'] : list;
}

String whenText(Map step, int no) {
  final d = toI(step['trigger_days']) ?? 0;
  final days = d == 1 ? 'day' : 'days';
  switch (step['trigger_type']) {
    case 'DAPREV':
      return '$d $days after step ${no - 1}';
    case 'DAS':
      return 'Day $d after sowing';
    case 'DAF':
      return 'Day $d after flowering';
    case 'DAP':
      return '$d $days after pruning';
    case 'DAH':
      return '$d $days after harvest';
  }
  return '$d $days';
}

// Steps in order, each with 'no' and an estimated day ('est') where one
// can be worked out.
List<Map> numberSteps(List steps) {
  final sorted = steps.map((s) => Map.from(s as Map)).toList()
    ..sort((a, b) {
      final c = (toI(a['sequence_order']) ?? 0).compareTo(toI(b['sequence_order']) ?? 0);
      return c != 0 ? c : (toI(a['id']) ?? 0).compareTo(toI(b['id']) ?? 0);
    });
  Map? prev;
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i];
    int? est;
    if (s['trigger_type'] == 'DAS' || s['trigger_type'] == 'DAF') {
      est = toI(s['trigger_days']);
    } else if (s['trigger_type'] == 'DAPREV' && prev != null && prev['est'] != null) {
      est = (prev['est'] as int) + (toI(s['trigger_days']) ?? 0);
    }
    s['no'] = i + 1;
    s['est'] = est;
    prev = s;
  }
  return sorted;
}

// Time order that keeps every "after step N" step right behind step N.
List<int> chainOrder(List<Map> numbered) {
  final chains = <List<Map>>[];
  for (final s in numbered) {
    if (s['trigger_type'] == 'DAPREV' && chains.isNotEmpty) {
      chains.last.add(s);
    } else {
      chains.add([s]);
    }
  }
  const rank = {'DAS': 0, 'DAF': 0, 'DAP': 1, 'DAH': 2};
  chains.sort((a, b) {
    final r = (rank[a.first['trigger_type']] ?? 3).compareTo(rank[b.first['trigger_type']] ?? 3);
    if (r != 0) return r;
    return (toI(a.first['trigger_days']) ?? 0).compareTo(toI(b.first['trigger_days']) ?? 0);
  });
  return [for (final c in chains) for (final s in c) toI(s['id'])!];
}

String mainKind(Map step) {
  if (step['activity_type'] == 'pruning') return 'pruning';
  final p = (step['products'] as List?) ?? [];
  if (p.isEmpty) return step['activity_type'] ?? 'pesticide';
  final counts = <String, int>{};
  for (final x in p) {
    final k = x['product_type'];
    if (k != null) counts[k] = (counts[k] ?? 0) + 1;
  }
  String best = p.first['product_type'] ?? 'pesticide';
  int n = 0;
  for (final x in p) {
    final k = x['product_type'];
    if (k != null && counts[k]! > n) {
      n = counts[k]!;
      best = k;
    }
  }
  return best;
}

// ── Common form bits ───────────────────────────────────────────────────
InputDecoration agInput(String label, {String? hint, String? helper, String? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      suffixText: suffix,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

Widget agLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF34422D))),
    );

void agSnack(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: isError ? Colors.red.shade700 : agGreen,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    margin: const EdgeInsets.all(16),
  ));
}

// Two-to-four option segmented control in the app's style.
class AgSeg<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T>? onChanged;
  const AgSeg({super.key, required this.values, required this.labels, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFEEF1EA), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(values[i]),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: values[i] == value ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: values[i] == value
                      ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 2, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: values[i] == value ? FontWeight.w700 : FontWeight.w600,
                        color: values[i] == value ? const Color(0xFF1F2D17) : const Color(0xFF56614F))),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Product picker (bottom sheet) ──────────────────────────────────────
// Returns the picked product (Map) — an existing one, or a new one
// created on the spot.
Future<Map?> pickProduct(BuildContext context, List products, {List<int> exclude = const [], bool canAdd = true}) {
  return showModalBottomSheet<Map>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ProductPickerSheet(products: products, exclude: exclude, canAdd: canAdd),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  final List products;
  final List<int> exclude;
  final bool canAdd;
  const _ProductPickerSheet({required this.products, required this.exclude, required this.canAdd});
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String q = '';
  bool adding = false;
  final nameCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  String? kind;
  String unit = 'ml';
  bool unitTouched = false;
  bool busy = false;
  String? error;

  List get list {
    final s = q.trim().toLowerCase();
    return widget.products.where((p) {
      if (p['is_active'] == false || p['is_active'] == 0) return false;
      if (widget.exclude.contains(toI(p['id']))) return false;
      if (s.isEmpty) return true;
      final brands = (p['brands'] as List?) ?? [];
      return p['name'].toString().toLowerCase().contains(s) ||
          brands.any((b) => b['brand_name'].toString().toLowerCase().contains(s));
    }).take(30).toList();
  }

  Future<void> _create() async {
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => error = 'Write the product name.');
      return;
    }
    if (kind == null) {
      setState(() => error = 'Choose what kind of product it is.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final p = await AgriApi.post('/agri/products', {
        'name': nameCtrl.text.trim(),
        'product_type': kind,
        'unit': unit,
        'brands': brandCtrl.text.trim().isEmpty ? [] : [brandCtrl.text.trim()],
      });
      if (mounted) Navigator.pop(context, p as Map);
    } catch (e) {
      setState(() {
        busy = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: adding ? _addForm() : _search(),
        ),
      ),
    );
  }

  Widget _search() {
    final items = list;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              autofocus: true,
              decoration: agInput('Find a product or brand').copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          for (final p in items)
            ListTile(
              title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${p['unit']} · ${p['preferred_brand_name'] != null ? 'brand ${p['preferred_brand_name']}' : 'no brand yet'}'),
              trailing: KindChip(p['product_type']),
              onTap: () => Navigator.pop(context, p as Map),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No product matches “$q”.', style: const TextStyle(color: agMuted)),
            ),
          if (widget.canAdd)
            ListTile(
              leading: const Icon(Icons.add, color: agGreen),
              title: Text(q.trim().isEmpty ? 'New product — add it to Products' : 'New product “${q.trim()}” — add it to Products',
                  style: const TextStyle(color: agGreen, fontWeight: FontWeight.w700)),
              onTap: () => setState(() {
                adding = true;
                nameCtrl.text = q.trim();
              }),
            ),
        ]),
      ),
    ]);
  }

  Widget _addForm() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => adding = false), icon: const Icon(Icons.arrow_back)),
        const Text('New product', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      TextField(controller: nameCtrl, decoration: agInput('Product name', hint: 'e.g. Carbendazim 50% WP')),
      const SizedBox(height: 14),
      agLabel('Kind'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in agKindKeys)
          ChoiceChip(
            label: Text(agKinds[k]!.label),
            selected: kind == k,
            selectedColor: agDark,
            labelStyle: TextStyle(color: kind == k ? Colors.white : const Color(0xFF3A4833), fontWeight: FontWeight.w600),
            onSelected: (_) => setState(() {
              kind = k;
              if (!unitTouched) unit = k == 'fertilizer' ? 'kg' : 'ml';
            }),
          ),
      ]),
      const SizedBox(height: 14),
      agLabel('Doses are written in'),
      AgSeg<String>(
          values: agUnits,
          labels: agUnits,
          value: unit,
          onChanged: (u) => setState(() {
                unit = u;
                unitTouched = true;
              })),
      const SizedBox(height: 14),
      TextField(controller: brandCtrl, decoration: agInput('Preferred brand (optional)')),
      if (error != null) ...[
        const SizedBox(height: 10),
        Text(error!, style: TextStyle(color: Colors.red.shade800)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white),
          onPressed: busy ? null : _create,
          icon: const Icon(Icons.add),
          label: Text(busy ? 'Adding…' : 'Add product'),
        ),
      ),
    ]);
  }
}
