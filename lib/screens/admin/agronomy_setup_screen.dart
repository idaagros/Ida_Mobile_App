// lib/screens/admin/agronomy_setup_screen.dart
//
// Agronomy setup (redesigned Sep 2026 — same model as the web app):
//   Crop plans — per crop variety: growth stages and spray / fertiliser
//                steps. A step says when (N days after sowing / flowering
//                / pruning / harvest, or after another step is done) and
//                which products go into it (several = tank mix) with the
//                dose per acre or per tree.
//   Products   — one list of products, each with a kind, the unit doses
//                are written in and one preferred brand. Steps pick
//                products from here, so the brand comes with them.
// Orchard blocks moved to their own screen (orchard_blocks_screen.dart).
// Editing happens on full screens: agronomy/step_editor_screen.dart,
// stage_editor_screen.dart and product_editor_screen.dart.

import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/responsive.dart';
import '../agronomy/agronomy_common.dart';
import '../agronomy/product_editor_screen.dart';
import '../agronomy/stage_editor_screen.dart';
import '../agronomy/step_editor_screen.dart';

class AgronomySetupScreen extends StatefulWidget {
  const AgronomySetupScreen({super.key});
  @override
  State<AgronomySetupScreen> createState() => _AgronomySetupScreenState();
}

class _AgronomySetupScreenState extends State<AgronomySetupScreen> {
  String section = 'plans';
  String part = 'steps';
  List varieties = [];
  List steps = [];
  List stages = [];
  List products = [];
  int? varietyId;
  bool loading = true;
  bool canEdit = false;
  String? error;
  // products filters
  String q = '';
  String kindFilter = 'all';
  bool needsOnly = false;

  @override
  void initState() {
    super.initState();
    ApiService.canEdit('agri').then((v) {
      if (mounted) setState(() => canEdit = v);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        AgriApi.get('/agri/crop-varieties'),
        AgriApi.get('/agri/spray-schedule-templates'),
        AgriApi.get('/agri/crop-stage-templates'),
        AgriApi.get('/agri/products'),
      ]);
      if (!mounted) return;
      setState(() {
        varieties = r[0] as List;
        steps = r[1] as List;
        stages = r[2] as List;
        products = r[3] as List;
        varietyId ??= varieties.isNotEmpty ? toI(varieties.first['id']) : null;
        error = null;
        loading = false;
      });
      _fixOrder();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Map? get variety {
    for (final v in varieties) {
      if (toI(v['id']) == varietyId) return v as Map;
    }
    return null;
  }

  bool get seasonal => variety?['crop_type'] != 'perennial';
  List<Map> get vSteps => numberSteps(steps.where((s) => toI(s['crop_variety_id']) == varietyId).toList());
  List<Map> get vStages {
    final l = stages.where((s) => toI(s['crop_variety_id']) == varietyId).map((s) => s as Map).toList();
    l.sort((a, b) => (toI(a['trigger_days_start']) ?? 0).compareTo(toI(b['trigger_days_start']) ?? 0));
    return l;
  }

  // Steps saved by older app versions can be out of time order; put them
  // in order (keeping "after step N" steps right behind step N).
  Future<void> _fixOrder() async {
    if (!canEdit || varietyId == null) return;
    final numbered = vSteps;
    if (numbered.isEmpty) return;
    final want = chainOrder(numbered);
    if (want.join(',') == numbered.map((s) => toI(s['id'])).join(',')) return;
    try {
      await AgriApi.post('/agri/spray-schedule-templates/reorder', {'crop_variety_id': varietyId, 'ids': want});
      final fresh = await AgriApi.get('/agri/spray-schedule-templates');
      if (mounted) setState(() => steps = fresh as List);
    } catch (_) {}
  }

  Future<void> _openStep(Map? step) async {
    if (variety == null) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StepEditorScreen(variety: variety!, steps: vSteps, step: step, products: products, canEdit: canEdit)));
    _load();
  }

  Future<void> _openStage(Map? stage) async {
    if (variety == null) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => StageEditorScreen(variety: variety!, stage: stage, steps: vSteps, canEdit: canEdit)));
    _load();
  }

  Future<void> _openProduct(Map? product) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductEditorScreen(product: product, canEdit: canEdit)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final needsCount = products.where((p) => p['needs_check'] == true).length;
    return Scaffold(
      backgroundColor: agBg,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.agriAgronomySetupTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: !canEdit
          ? null
          : FloatingActionButton.extended(
              backgroundColor: agGreen,
              foregroundColor: Colors.white,
              onPressed: () => section == 'products' ? _openProduct(null) : (part == 'steps' ? _openStep(null) : _openStage(null)),
              icon: const Icon(Icons.add),
              label: Text(section == 'products' ? 'Add product' : (part == 'steps' ? 'Add step' : 'Add stage')),
            ),
      body: Column(children: [
        Container(
          color: agDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            _topTab('Crop plans (${varieties.length})', 'plans'),
            const SizedBox(width: 6),
            _topTab('Products (${products.length})${needsCount > 0 ? ' · $needsCount to check' : ''}', 'products'),
          ]),
        ),
        Expanded(
          child: Responsive.constrainedContent(
            context,
            loading
                ? const Center(child: CircularProgressIndicator(color: agGreen))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: section == 'plans' ? _plans() : _products(needsCount),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _topTab(String label, String key) {
    final on = section == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => section = key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: on ? agGreen : Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _errorBox() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
        child: Text(error!, style: TextStyle(color: Colors.red.shade900)),
      );

  // ── Crop plans ─────────────────────────────────────────────────────
  Widget _plans() {
    final v = variety;
    final numbered = vSteps;
    final st = vStages;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      if (error != null) _errorBox(),
      if (varieties.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Add a crop variety in Crop masters to start a plan.', textAlign: TextAlign.center, style: TextStyle(color: agMuted)),
        ),
      if (varieties.isNotEmpty)
        DropdownButtonFormField<int>(
          value: varietyId,
          isExpanded: true,
          decoration: agInput('Crop variety'),
          items: [
            for (final x in varieties)
              DropdownMenuItem(
                value: toI(x['id']),
                child: Text('${x['crop_name']} · ${x['name']} (${x['crop_type'] == 'perennial' ? 'orchard' : 'seasonal'})',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            setState(() => varietyId = id);
            _fixOrder();
          },
        ),
      if (v != null) ...[
        const SizedBox(height: 10),
        Text(
          '${seasonal ? 'Seasonal — days count from the sowing date' : 'Orchard — days count from flowering, pruning or harvest'}${v['maturity_days'] != null ? ' · about ${v['maturity_days']} days to harvest' : ''}',
          style: const TextStyle(fontSize: 12.5, color: agMuted),
        ),
        const SizedBox(height: 12),
        AgSeg<String>(
          values: const ['steps', 'stages'],
          labels: ['Spray & fertiliser (${numbered.length})', 'Growth stages (${st.length})'],
          value: part,
          onChanged: (p) => setState(() => part = p),
        ),
        const SizedBox(height: 12),
        _timeline(v, numbered, st),
        const SizedBox(height: 12),
        if (part == 'steps') ...[
          for (final s in numbered) _stepCard(s, st),
          if (numbered.isEmpty) _emptyText('No steps yet for ${v['name']}.'),
        ] else ...[
          for (final g in st) _stageCard(g, numbered),
          if (st.isEmpty) _emptyText('No growth stages yet for ${v['name']}.'),
        ],
      ],
    ]);
  }

  Widget _emptyText(String t) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: agMuted)),
      );

  static const _shades = [
    Color(0xFFE8F1DF), Color(0xFFD7E9C7), Color(0xFFC5DEB0), Color(0xFFFBE7C6), Color(0xFFF6D9B4), Color(0xFFEDDCC8), Color(0xFFE3E8F3)
  ];

  Widget _timeline(Map v, List<Map> numbered, List<Map> st) {
    final anchor = seasonal ? 'DAS' : 'DAF';
    final tlStages = st.where((g) => g['trigger_type'] == anchor).toList();
    final tlSteps = numbered.where((s) => s['est'] != null).toList();
    var span = (toI(v['maturity_days']) ?? 0).toDouble();
    for (final g in tlStages) {
      span = span < (toI(g['trigger_days_end']) ?? 0) ? (toI(g['trigger_days_end']) ?? 0).toDouble() : span;
    }
    for (final s in tlSteps) {
      span = span < (s['est'] as int) ? (s['est'] as int).toDouble() : span;
    }
    if (!seasonal) span += 10;
    if (span <= 0) span = 120;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
      child: Column(children: [
        LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          if (!w.isFinite || w < 60) return const SizedBox(height: 42);
          double x(num d) => (d.clamp(0, span).toDouble() / span) * w;
          return SizedBox(
            height: 42,
            child: Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < tlStages.length; i++)
                Positioned(
                  left: x(toI(tlStages[i]['trigger_days_start']) ?? 0),
                  width: (x(toI(tlStages[i]['trigger_days_end']) ?? 0) - x(toI(tlStages[i]['trigger_days_start']) ?? 0) - 2).clamp(2.0, w).toDouble(),
                  top: 0,
                  height: 12,
                  child: Container(decoration: BoxDecoration(color: _shades[i % 7], borderRadius: BorderRadius.circular(4))),
                ),
              for (final s in tlSteps)
                Positioned(
                  left: (x(s['est'] as int) - 10).clamp(0.0, w - 20).toDouble(),
                  top: 18,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => part = 'steps');
                      _openStep(s);
                    },
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: agKinds[mainKind(s)]?.dot ?? agGreen,
                      child: Text('${s['no']}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]),
          );
        }),
        Row(children: [
          Text(seasonal ? 'Sowing (day 0)' : 'Flowering (day 0)', style: const TextStyle(fontSize: 11, color: agMuted)),
          const Spacer(),
          Text('Day ${span.round()}', style: const TextStyle(fontSize: 11, color: agMuted)),
        ]),
      ]),
    );
  }

  Widget _stepCard(Map s, List<Map> st) {
    final prods = (s['products'] as List?) ?? [];
    final kinds = s['activity_type'] == 'pruning' ? ['pruning'] : prods.map((p) => p['product_type']).where((k) => k != null).toSet().toList();
    String sub = '';
    if (s['trigger_type'] == 'DAPREV' && s['est'] != null) {
      sub = 'about day ${s['est']}';
    } else if (s['est'] != null) {
      for (final g in st) {
        if ((s['est'] as int) >= (toI(g['trigger_days_start']) ?? 0) && (s['est'] as int) <= (toI(g['trigger_days_end']) ?? 0)) {
          sub = g['stage_name'];
          break;
        }
      }
    }
    if (s['tree_age_bracket'] != null) sub = '${sub.isEmpty ? '' : '$sub · '}trees ${s['tree_age_bracket']} yrs';
    final unitPer = seasonal ? 'acre' : 'tree';
    return InkWell(
      onTap: () => _openStep(s),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 14,
              backgroundColor: agDark,
              child: Text('${s['no']}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(whenText(s, s['no'] as int), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: agMuted)),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final k in kinds) KindChip(k),
                if (prods.length > 1) const SmallChip('Tank mix'),
              ]),
              const SizedBox(height: 6),
              for (final p in prods)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: p['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: '  ${p['preferred_brand_name'] ?? 'no brand'}', style: const TextStyle(color: agMuted)),
                        ]),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text('${trimNum(toD(p['dose']), 3)} ${p['unit']}/$unitPer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
              if (s['activity_type'] == 'pruning') const Text('Pruning', style: TextStyle(color: agMuted)),
              if (s['activity_type'] != 'pruning' && prods.isEmpty)
                Text('${s['product_suggestion'] ?? 'No product'} — open to pick from Products',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A4D00))),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _stageCard(Map g, List<Map> numbered) {
    final i = vStages.indexOf(g);
    final a = toI(g['trigger_days_start']) ?? 0;
    final b = toI(g['trigger_days_end']) ?? 0;
    final inside = numbered.where((s) => s['est'] != null && (s['est'] as int) >= a && (s['est'] as int) <= b).toList();
    return InkWell(
      onTap: () => _openStage(g),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
        child: Row(children: [
          Container(width: 10, height: 36, decoration: BoxDecoration(color: _shades[(i < 0 ? 0 : i) % 7], borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g['stage_name'] ?? '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              Text('Day $a–$b after ${anchorWords[g['trigger_type']] ?? ''}', style: const TextStyle(fontSize: 12, color: agMuted)),
              if (inside.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 4, children: [
                    for (final s in inside)
                      CircleAvatar(
                          radius: 10,
                          backgroundColor: agKinds[mainKind(s)]?.dot ?? agGreen,
                          child: Text('${s['no']}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800))),
                  ]),
                ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }

  // ── Products ───────────────────────────────────────────────────────
  Widget _products(int needsCount) {
    final s = q.trim().toLowerCase();
    final list = products.where((p) {
      if (kindFilter != 'all' && p['product_type'] != kindFilter) return false;
      if (needsOnly && p['needs_check'] != true) return false;
      if (s.isEmpty) return true;
      final brands = (p['brands'] as List?) ?? [];
      return p['name'].toString().toLowerCase().contains(s) || brands.any((b) => b['brand_name'].toString().toLowerCase().contains(s));
    }).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      if (error != null) _errorBox(),
      TextField(
        decoration: agInput('Find a product or brand').copyWith(prefixIcon: const Icon(Icons.search)),
        onChanged: (v) => setState(() => q = v),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (needsCount > 0) ...[
            FilterChip(
              label: Text('Needs checking $needsCount'),
              selected: needsOnly,
              selectedColor: const Color(0xFFFCEFD2),
              onSelected: (v) => setState(() => needsOnly = v),
            ),
            const SizedBox(width: 6),
          ],
          for (final k in ['all', ...agKindKeys]) ...[
            ChoiceChip(
              label: Text(k == 'all' ? 'All' : agKinds[k]!.label),
              selected: kindFilter == k,
              selectedColor: agDark,
              labelStyle: TextStyle(color: kindFilter == k ? Colors.white : const Color(0xFF3A4833), fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => kindFilter = k),
            ),
            const SizedBox(width: 6),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      if (list.isEmpty) _emptyText(products.isEmpty ? 'No products yet.' : 'No product matches these filters.'),
      for (final p in list)
        InkWell(
          onTap: () => _openProduct(p as Map),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(p['name'], style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                    if (p['needs_check'] == true) ...[
                      const SizedBox(width: 6),
                      const SmallChip('Check', bg: Color(0xFFFCEFD2), fg: Color(0xFF7A4D00)),
                    ],
                    if (p['is_active'] == false) ...[
                      const SizedBox(width: 6),
                      const SmallChip('Off', bg: Color(0xFFECEEE8)),
                    ],
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [
                    KindChip(p['product_type']),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p['unit']} · ${p['preferred_brand_name'] ?? 'no brand'}${((p['brands'] as List?)?.length ?? 0) > 1 ? ' +${(p['brands'] as List).length - 1}' : ''} · ${toI(p['used_in_steps']) == 0 ? 'not in a plan' : '${p['used_in_steps']} step(s)'}',
                        style: const TextStyle(fontSize: 12, color: agMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ]),
          ),
        ),
    ]);
  }
}
