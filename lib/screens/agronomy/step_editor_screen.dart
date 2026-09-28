// lib/screens/agronomy/step_editor_screen.dart
//
// Full-screen editor for one spray / fertiliser step of a crop plan
// (Agronomy setup redesign, Sep 2026). Same rules as the web:
//   When: N days after sowing (seasonal) or flowering / pruning /
//         harvest (orchard), or N days after another step is done.
//   What: apply products (picked from Products; several = tank mix,
//         each with a dose per acre or per tree) or pruning.
// After saving, steps are put back in time order, keeping every
// "after step N" step right behind step N.
// Pops `true` when something was saved or deleted.

import 'package:flutter/material.dart';
import 'agronomy_common.dart';

class StepEditorScreen extends StatefulWidget {
  final Map variety;
  final List<Map> steps; // numbered steps of this variety
  final Map? step; // null = new
  final List products;
  final bool canEdit;
  const StepEditorScreen(
      {super.key, required this.variety, required this.steps, this.step, required this.products, required this.canEdit});
  @override
  State<StepEditorScreen> createState() => _StepEditorScreenState();
}

class _StepEditorScreenState extends State<StepEditorScreen> {
  late bool seasonal;
  late String trigger;
  final daysCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  int? afterId;
  String kind = 'products';
  String age = '';
  List<Map> items = []; // {product_id, ctrl}
  late List products;
  bool saving = false;
  String? error;

  String get perUnit => seasonal ? 'acre' : 'tree';

  @override
  void initState() {
    super.initState();
    products = List.from(widget.products);
    seasonal = widget.variety['crop_type'] != 'perennial';
    final s = widget.step;
    if (s == null) {
      trigger = seasonal ? 'DAS' : 'DAF';
    } else {
      trigger = s['trigger_type'] ?? (seasonal ? 'DAS' : 'DAF');
      daysCtrl.text = '${s['trigger_days'] ?? ''}';
      notesCtrl.text = s['notes'] ?? '';
      kind = s['activity_type'] == 'pruning' ? 'pruning' : 'products';
      age = s['tree_age_bracket'] ?? '';
      if (trigger == 'DAPREV') {
        final prev = widget.steps.where((x) => x['no'] == (s['no'] as int) - 1);
        if (prev.isNotEmpty) afterId = toI(prev.first['id']);
      }
      for (final p in (s['products'] as List? ?? [])) {
        items.add({'product_id': toI(p['product_id']), 'ctrl': TextEditingController(text: trimNum(toD(p['dose']), 3))});
      }
    }
  }

  Map? productById(int? id) {
    for (final p in products) {
      if (toI(p['id']) == id) return p as Map;
    }
    return null;
  }

  List<Map> get followOptions => widget.steps.where((x) => toI(x['id']) != toI(widget.step?['id'])).toList();

  bool takenAfter(Map s) => widget.steps.any((x) =>
      x['no'] == (s['no'] as int) + 1 && x['trigger_type'] == 'DAPREV' && toI(x['id']) != toI(widget.step?['id']));

  Future<void> _addProduct() async {
    final p = await pickProduct(context, products,
        exclude: items.map((i) => i['product_id'] as int).toList(), canAdd: widget.canEdit);
    if (p == null) return;
    setState(() {
      if (!products.any((x) => toI(x['id']) == toI(p['id']))) products.add(p);
      items.add({'product_id': toI(p['id']), 'ctrl': TextEditingController()});
    });
  }

  Future<void> _save() async {
    final days = int.tryParse(daysCtrl.text.trim());
    if (days == null || days < 0) { setState(() => error = 'Write the number of days (a whole number).'); return; }
    if (trigger == 'DAPREV' && afterId == null) { setState(() => error = 'Choose which step this one follows.'); return; }
    if (kind == 'products') {
      if (items.isEmpty) { setState(() => error = 'Add at least one product to this step.'); return; }
      for (final i in items) {
        final d = double.tryParse((i['ctrl'] as TextEditingController).text.trim());
        if (d == null || d <= 0) {
          { setState(() => error = 'Write the dose for ${productById(i['product_id'])?['name'] ?? 'each product'}.'); return; }
        }
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final vid = toI(widget.variety['id']);
      final body = <String, dynamic>{
        'trigger_type': trigger,
        'trigger_days': days,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'tree_age_bracket': seasonal || age.isEmpty ? null : age,
      };
      if (kind == 'pruning') {
        body['activity_type'] = 'pruning';
      } else {
        body['products'] = [
          for (final i in items)
            {'product_id': i['product_id'], 'dose': double.parse((i['ctrl'] as TextEditingController).text.trim())}
        ];
        if (widget.step != null) body['activity_type'] = 'pesticide'; // the server works out the real kind
      }
      int id;
      if (widget.step == null) {
        final created = await AgriApi.post('/agri/spray-schedule-templates', {...body, 'crop_variety_id': vid});
        id = toI(created['id'])!;
      } else {
        id = toI(widget.step!['id'])!;
        await AgriApi.patch('/agri/spray-schedule-templates/$id', body);
      }
      // Put steps back in time order.
      final fresh = numberSteps(await AgriApi.get('/agri/spray-schedule-templates?crop_variety_id=$vid') as List);
      var order = fresh.map((s) => toI(s['id'])!).toList();
      if (trigger == 'DAPREV') {
        order.remove(id);
        order.insert(order.indexOf(afterId!) + 1, id);
      }
      final byId = {for (final s in fresh) toI(s['id']): s};
      final seq = <Map>[];
      for (var i = 0; i < order.length; i++) {
        seq.add({...byId[order[i]]!, 'sequence_order': i + 1});
      }
      final want = chainOrder(numberSteps(seq));
      if (want.join(',') != fresh.map((s) => toI(s['id'])).join(',')) {
        await AgriApi.post('/agri/spray-schedule-templates/reorder', {'crop_variety_id': vid, 'ids': want});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  Future<void> _delete() async {
    final s = widget.step!;
    final follower = widget.steps.where((x) => x['no'] == (s['no'] as int) + 1 && x['trigger_type'] == 'DAPREV');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete step ${s['no']}?'),
        content: Text(
            '${follower.isNotEmpty ? 'Step ${follower.first['no']} counts from this step; it will then count from the step before. ' : ''}Crop cycles already running keep it in their calendar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await AgriApi.delete('/agri/spray-schedule-templates/${s['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final ed = widget.canEdit;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s == null ? 'New step' : 'Step ${s['no']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${widget.variety['crop_name']} · ${widget.variety['name']}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          if (s != null && ed) IconButton(tooltip: 'Delete step', onPressed: saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        if (error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: Text(error!, style: TextStyle(color: Colors.red.shade900)),
          ),
        agLabel('When'),
        Row(children: [
          SizedBox(
            width: 84,
            child: TextField(controller: daysCtrl, enabled: ed, keyboardType: TextInputType.number, decoration: agInput('Days')),
          ),
          const SizedBox(width: 8),
          const Text('days after', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: trigger,
              isExpanded: true,
              decoration: agInput(''),
              items: [
                for (final k in anchorOptions(seasonal, withPrev: followOptions.isNotEmpty))
                  DropdownMenuItem(value: k, child: Text(anchorWords[k]!, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: ed ? (v) => setState(() => trigger = v!) : null,
            ),
          ),
        ]),
        if (trigger == 'DAPREV') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: afterId,
            isExpanded: true,
            decoration: agInput('Which step it follows'),
            items: [
              for (final f in followOptions)
                DropdownMenuItem(
                  value: toI(f['id']),
                  enabled: !takenAfter(f),
                  child: Text('Step ${f['no']} — ${whenText(f, f['no'] as int)}${takenAfter(f) ? ' (taken)' : ''}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: ed ? (v) => setState(() => afterId = v) : null,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          trigger == 'DAPREV'
              ? 'The date is set when that step is marked done in the crop calendar.'
              : seasonal
                  ? 'Counted from the sowing date of each sowing plan.'
                  : 'For orchards, count from flowering, pruning or harvest.',
          style: const TextStyle(fontSize: 12, color: agMuted),
        ),
        if (!seasonal) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: age,
            decoration: agInput('Tree age', helper: 'Use this when young and old trees need a different step.'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All ages')),
              for (final a in agAgeBrackets) DropdownMenuItem(value: a, child: Text('$a years')),
            ],
            onChanged: ed ? (v) => setState(() => age = v ?? '') : null,
          ),
        ],
        const SizedBox(height: 18),
        agLabel('What is done'),
        AgSeg<String>(
          values: const ['products', 'pruning'],
          labels: const ['Apply products', 'Pruning'],
          value: kind,
          onChanged: ed ? (v) => setState(() => kind = v) : null,
        ),
        if (kind == 'products') ...[
          const SizedBox(height: 18),
          Row(children: [
            agLabel('Products in this step'),
            const SizedBox(width: 6),
            if (items.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${items.length} sprayed together (tank mix)', style: const TextStyle(fontSize: 12, color: agMuted)),
              ),
          ]),
          for (var idx = 0; idx < items.length; idx++) _productCard(idx),
          if (ed)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46), foregroundColor: agDark, side: const BorderSide(color: Color(0xFFD5DCCD))),
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: Text(items.isEmpty ? 'Add product' : 'Add product to this spray'),
            ),
        ],
        const SizedBox(height: 18),
        TextField(controller: notesCtrl, enabled: ed, decoration: agInput('Notes (optional)', hint: 'e.g. spray in the evening')),
        const SizedBox(height: 12),
        const Text('Crop cycles already running keep their dates. Product and dose changes show in their calendar for steps not yet done.',
            style: TextStyle(fontSize: 12, color: agMuted)),
      ]),
      bottomNavigationBar: !ed
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: agBorder))),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                      onPressed: saving ? null : _save,
                      icon: Icon(s == null ? Icons.add : Icons.check),
                      label: Text(saving ? 'Saving…' : (s == null ? 'Add step' : 'Save step')),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _productCard(int idx) {
    final it = items[idx];
    final p = productById(it['product_id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(p?['name'] ?? 'Product', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          KindChip(p?['product_type']),
          const Spacer(),
          if (widget.canEdit)
            IconButton(
              tooltip: 'Remove',
              onPressed: () => setState(() => items.removeAt(idx)),
              icon: const Icon(Icons.close, size: 18, color: agMuted),
            ),
        ]),
        Text(p?['preferred_brand_name'] != null ? 'Brand ${p!['preferred_brand_name']} · preferred' : 'No brand yet — add one in Products',
            style: const TextStyle(fontSize: 12.5, color: agMuted)),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: it['ctrl'] as TextEditingController,
              enabled: widget.canEdit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: agInput('Dose'),
            ),
          ),
          const SizedBox(width: 8),
          Text('${p?['unit'] ?? ''} per $perUnit', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}
