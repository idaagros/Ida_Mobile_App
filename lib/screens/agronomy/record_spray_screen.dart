// lib/screens/agronomy/record_spray_screen.dart
//
// Crop calendar › "Mark done" for a spray step that has products (Sep
// 2026, same as the web). Per product: the brand actually used (the
// preferred brand is filled in; it can be changed or another brand
// typed), the recommended quantity (dose in the plan × acres or trees
// sprayed) and what was actually used — which starts EMPTY on purpose,
// so it is really entered rather than accepted from the plan.
// Pops `true` when saved.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'agronomy_common.dart';

class RecordSprayScreen extends StatefulWidget {
  final Map item;
  final int? stepNo;
  final String cycleType;
  final int cycleId;
  final List workers;
  const RecordSprayScreen(
      {super.key, required this.item, this.stepNo, required this.cycleType, required this.cycleId, this.workers = const []});
  @override
  State<RecordSprayScreen> createState() => _RecordSprayScreenState();
}

class _Line {
  String brand; // brand id as text, or 'other'
  final TextEditingController other = TextEditingController();
  final TextEditingController actual = TextEditingController();
  String unit;
  _Line(this.brand, this.unit);
}

class _RecordSprayScreenState extends State<RecordSprayScreen> {
  late List products;
  late bool perTree;
  double? basisQty;
  DateTime date = DateTime.now();
  final areaCtrl = TextEditingController();
  final costCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();
  int? workerId;
  late List<_Line> lines;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    products = (widget.item['products'] as List?) ?? [];
    perTree = widget.item['basis'] == 'tree';
    basisQty = toD(widget.item['basis_qty']);
    if (basisQty != null) areaCtrl.text = trimNum(basisQty);
    lines = [
      for (final p in products)
        _Line(
          p['preferred_brand_id'] != null
              ? '${p['preferred_brand_id']}'
              : (((p['brands'] as List?) ?? []).isNotEmpty ? '${p['brands'][0]['id']}' : 'other'),
          _startUnit(p),
        )
    ];
    areaCtrl.addListener(() => setState(() {}));
    for (final l in lines) {
      l.actual.addListener(() => setState(() {}));
    }
  }

  String _startUnit(Map p) {
    final dose = toD(p['dose']);
    final u = p['unit'] as String? ?? 'ml';
    if (dose == null || basisQty == null) return u;
    return niceUnit(dose * basisQty!, u);
  }

  double? get covered => double.tryParse(areaCtrl.text.trim());

  double? recommended(Map p) {
    final dose = toD(p['dose']);
    final c = covered;
    if (dose == null || c == null) return null;
    return dose * c;
  }

  // Difference text and colour, or null.
  (String, Color, Color, bool)? diff(int i) {
    final p = products[i];
    final rec = recommended(p);
    final a = double.tryParse(lines[i].actual.text.trim());
    if (rec == null || a == null) return null;
    final unit = p['unit'] as String? ?? 'ml';
    final actualBase = convertQty(a, lines[i].unit, unit);
    final d = actualBase - rec;
    final pct = rec > 0 ? d / rec * 100 : 0.0;
    if (pct.abs() < 0.5) return ('Same', const Color(0xFFE3F0DA), const Color(0xFF2C5E17), false);
    final more = d > 0;
    return (
      '${more ? '+' : '−'}${fmtQty(d.abs(), unit)} · ${pct.abs().round()}% ${more ? 'more' : 'less'}',
      more ? const Color(0xFFFDE6D2) : const Color(0xFFDDE9F7),
      more ? const Color(0xFF8C3F06) : const Color(0xFF1D4D86),
      pct.abs() > 10,
    );
  }

  void _useRecommended() {
    setState(() {
      for (var i = 0; i < products.length; i++) {
        final rec = recommended(products[i]);
        if (rec == null) continue;
        final u = niceUnit(rec, products[i]['unit'] ?? 'ml');
        lines[i].unit = u;
        lines[i].actual.text = trimNum(convertQty(rec, products[i]['unit'] ?? 'ml', u), 3);
      }
    });
  }

  Future<void> _save() async {
    final c = covered;
    if (c == null || c <= 0) {
      setState(() => error = perTree ? 'Write how many trees were sprayed.' : 'Write how many acres were sprayed.');
      return;
    }
    if (basisQty != null && c > basisQty!) {
      setState(() => error = perTree ? 'The block has ${trimNum(basisQty)} trees.' : 'Only ${trimNum(basisQty)} acres are sown in this plan.');
      return;
    }
    for (var i = 0; i < products.length; i++) {
      if (double.tryParse(lines[i].actual.text.trim()) == null) {
        setState(() => error = 'Write how much ${products[i]['name']} was actually used.');
        return;
      }
      final hasBrands = ((products[i]['brands'] as List?) ?? []).isNotEmpty;
      if (lines[i].brand == 'other' && hasBrands && lines[i].other.text.trim().isEmpty) {
        setState(() => error = 'Write the brand of ${products[i]['name']} that was used.');
        return;
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final res = await AgriApi.post('/agri/actual-operations', {
        'cycle_type': widget.cycleType,
        'cycle_id': widget.cycleId,
        'schedule_item_id': widget.item['id'],
        'operation_date': DateFormat('yyyy-MM-dd').format(date),
        if (perTree) 'trees_covered': c.round() else 'area_covered_acre': c,
        'cost': double.tryParse(costCtrl.text.trim()),
        'worker_id': workerId,
        'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
        'products': [
          for (var i = 0; i < products.length; i++)
            {
              'product_id': products[i]['product_id'],
              if (lines[i].brand == 'other')
                'brand_name': lines[i].other.text.trim().isEmpty ? null : lines[i].other.text.trim()
              else
                'brand_id': int.tryParse(lines[i].brand),
              'actual_qty': double.parse(lines[i].actual.text.trim()),
              'unit': lines[i].unit,
            }
        ],
      });
      if (!mounted) return;
      if (res is Map && res['warning'] != null) agSnack(context, res['warning'].toString(), isError: true);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final offCount = [for (var i = 0; i < products.length; i++) diff(i)].where((d) => d != null && d.$4).length;
    final planned = widget.item['planned_date'] != null
        ? 'Planned for ${DateFormat('d MMM').format(DateTime.parse(widget.item['planned_date']))}'
        : 'No date planned yet';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mark step ${widget.stepNo ?? ''} done', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('$planned${products.length > 1 ? ' · tank mix of ${products.length}' : ''}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) setState(() => date = picked);
              },
              child: InputDecorator(decoration: agInput('Date done'), child: Text(DateFormat('dd MMM yyyy').format(date))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: areaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: agInput(perTree ? 'Trees sprayed' : 'Area sprayed',
                  suffix: basisQty != null ? '/ ${trimNum(basisQty)} ${perTree ? 'trees' : 'ac'}' : (perTree ? 'trees' : 'ac')),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          basisQty != null
              ? '${perTree ? 'Trees come from the orchard block' : 'Area comes from this crop’s sown area'}. Lower it if only part was sprayed — the recommended amounts change with it.'
              : 'The ${perTree ? 'number of trees isn’t set on the orchard block' : 'area sown isn’t set on this sowing plan'} — write it here.',
          style: const TextStyle(fontSize: 12, color: agMuted),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _useRecommended, child: const Text('Use recommended for all')),
        const SizedBox(height: 12),
        for (var i = 0; i < products.length; i++) _productCard(i),
        if (offCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF7EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF3D7A6))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB8660B)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('$offCount product${offCount == 1 ? '' : 's'} differ${offCount == 1 ? 's' : ''} from the plan by more than 10%. A short remark helps later.',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7A4D00)))),
            ]),
          ),
        TextField(
            controller: costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: agInput('Cost (₹, optional)')),
        const SizedBox(height: 12),
        if (widget.workers.isNotEmpty) ...[
          DropdownButtonFormField<int>(
            value: workerId,
            isExpanded: true,
            decoration: agInput('Done by (optional)'),
            items: [for (final w in widget.workers) DropdownMenuItem(value: toI(w['id']), child: Text('${w['name']}'))],
            onChanged: (v) => setState(() => workerId = v),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
            controller: remarksCtrl,
            decoration: agInput(offCount > 0 ? 'Remarks' : 'Remarks (optional)',
                hint: offCount > 0 ? 'Why more or less was used' : 'e.g. brand changed — shop out of stock')),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: Text(error!, style: TextStyle(color: Colors.red.shade900)),
          ),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: agBorder))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(saving ? 'Saving…' : 'Mark done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _productCard(int i) {
    final p = products[i];
    final l = lines[i];
    final unit = p['unit'] as String? ?? 'ml';
    final brands = (p['brands'] as List?) ?? [];
    final pref = p['preferred_brand_id'] == null ? '' : '${p['preferred_brand_id']}';
    final notPref = pref.isNotEmpty && l.brand != pref;
    final rec = recommended(p);
    final d = diff(i);
    final c = covered;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(p['name'] ?? '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          KindChip(p['product_type']),
        ]),
        Text(
            toD(p['dose']) != null
                ? '${trimNum(toD(p['dose']), 3)} $unit/${perTree ? 'tree' : 'acre'}${c != null ? ' × ${trimNum(c)} ${perTree ? 'trees' : 'acres'}' : ''}'
                : 'No dose in the plan',
            style: const TextStyle(fontSize: 12, color: agMuted)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: l.brand,
          isExpanded: true,
          decoration: agInput('Brand used').copyWith(
            fillColor: notPref ? const Color(0xFFFFFCF3) : Colors.white,
            enabledBorder: notPref
                ? OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEEC46B)))
                : null,
          ),
          items: [
            for (final b in brands)
              DropdownMenuItem(value: '${b['id']}', child: Text('${b['brand_name']}${'${b['id']}' == pref ? ' (preferred)' : ''}')),
            DropdownMenuItem(value: 'other', child: Text(brands.isEmpty ? 'Write the brand…' : 'Other brand…')),
          ],
          onChanged: (v) => setState(() => l.brand = v ?? 'other'),
        ),
        if (l.brand == 'other') ...[
          const SizedBox(height: 8),
          TextField(controller: l.other, decoration: agInput('Brand name')),
        ],
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recommended', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF34422D))),
              const SizedBox(height: 4),
              Text(rec != null ? fmtQty(rec, unit) : '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: l.actual,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: agInput('Actually used'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 72,
                child: DropdownButtonFormField<String>(
                  value: l.unit,
                  decoration: agInput(''),
                  items: [for (final u in familyUnits(unit)) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => setState(() => l.unit = v ?? l.unit),
                ),
              ),
            ]),
          ),
        ]),
        if (d != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: d.$2, borderRadius: BorderRadius.circular(20)),
            child: Text(d.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: d.$3)),
          ),
        ],
      ]),
    );
  }
}
