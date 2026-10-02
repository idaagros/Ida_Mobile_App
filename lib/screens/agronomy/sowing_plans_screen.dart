// lib/screens/agronomy/sowing_plans_screen.dart
//
// Sowing plans (Oct 2026, group F) — the phone version of the website's
// Agriculture › Sowing plans: what is sown where, when and on how many
// acres, with the row spacing and the plants per acre / expected yield
// worked out from it.
//  - List: Growing / Done / All, a farm filter and search.
//  - One plan: change acres and spacing (uniform, paired or a repeating
//    line sequence), companion crops grown together, and the line
//    sequence. Finishing or cancelling is done on the crop calendar so
//    its costs and harvest stay together.
//  - New sowing: farm, crop · variety, season, sown on, acres, spacing.
// Web counterpart: src/pages/agri/SowingPlansPage.jsx (+ agronomy/
// IntercropGroupPanel.jsx, agronomy/PatternLinesEditor.jsx).
// API: /agri/sowing-plans (+ /:id/calculations, /:id/intercrop-group,
//      /:id/pattern-lines, /:id/add-intercrop), /farms, /agri/crop-varieties

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../admin/admin_common.dart';
import '../crop_calendar_screen.dart';

const List<String> _units = ['cm', 'in', 'ft'];

String _n(dynamic v) {
  final d = double.tryParse('${v ?? ''}');
  if (d == null) return '';
  return d == d.roundToDouble() ? d.round().toString() : d.toString();
}

String _d10(dynamic v) => '${v ?? ''}'.length >= 10 ? '$v'.substring(0, 10) : '';
String _nice(dynamic v) {
  final d = DateTime.tryParse(_d10(v));
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

String spacingText(Map p) {
  String u(dynamic v, dynamic unit) => '${_n(v)} ${unit ?? 'cm'}';
  if (p['row_arrangement'] == 'sequence') return 'Line sequence';
  if (p['row_arrangement'] == 'paired') {
    return p['intra_pair_distance'] != null && p['inter_pair_distance'] != null
        ? 'Paired ${u(p['intra_pair_distance'], p['intra_pair_distance_unit'])} / ${u(p['inter_pair_distance'], p['inter_pair_distance_unit'])}'
        : 'Paired · spacing missing';
  }
  return p['row_to_row_cm'] != null && p['plant_to_plant_cm'] != null
      ? '${u(p['row_to_row_cm'], p['row_to_row_unit'])} × ${u(p['plant_to_plant_cm'], p['plant_to_plant_unit'])}'
      : 'Spacing missing';
}

List<Map<String, dynamic>> _maps(dynamic v) => (v is List ? v : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

class SowingPlansScreen extends StatefulWidget {
  const SowingPlansScreen({super.key});
  @override
  State<SowingPlansScreen> createState() => _SowingPlansScreenState();
}

class _SowingPlansScreenState extends State<SowingPlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _farms = [];
  List<Map<String, dynamic>> _varieties = [];
  final Map<int, Map<String, dynamic>> _calc = {};
  bool _loading = true;
  String? _error;
  String _status = 'active';
  int? _farm;
  String _q = '';
  bool _canAdd = false;
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _canAdd = await ApiService.canAdd('agri');
    _canEdit = await ApiService.canUpdate('agri');
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await AdminApi.get('/agri/sowing-plans?limit=200');
      final f = await AdminApi.get('/farms');
      final v = await AdminApi.get('/agri/crop-varieties');
      final plans = _maps(p is Map ? p['data'] : p);
      final calcs = await Future.wait(plans.map((x) => AdminApi.get('/agri/sowing-plans/${x['id']}/calculations').catchError((_) => null)));
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _farms = _maps(f);
        _varieties = _maps(v);
        _calc.clear();
        for (var i = 0; i < plans.length; i++) {
          final c = calcs[i];
          if (c is Map) _calc[int.tryParse('${plans[i]['id']}') ?? 0] = Map<String, dynamic>.from(c);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _cropOf(Map p) {
    for (final v in _varieties) {
      if ('${v['id']}' == '${p['crop_variety_id']}') return '${v['crop_name'] ?? ''}';
    }
    return '';
  }

  Future<void> _open(Map<String, dynamic>? plan) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SowingPlanScreen(
          plan: plan,
          farms: _farms,
          varieties: _varieties,
          canAdd: _canAdd,
          canEdit: _canEdit,
          initialFarm: _farm,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _plans.where((p) => p['status'] == 'active').length;
    final q = _q.trim().toLowerCase();
    final rows = _plans.where((p) {
      final st = p['status'];
      if (_status == 'active' && st != 'active') return false;
      if (_status == 'done' && st == 'active') return false;
      if (_farm != null && '${p['farm_id']}' != '$_farm') return false;
      if (q.isNotEmpty && !'${p['crop_variety_name']} ${_cropOf(p)} ${p['farm_name']} ${p['season']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => _d10(b['sowing_date']).compareTo(_d10(a['sowing_date'])));
    final acres = _plans.where((p) => p['status'] == 'active').fold<double>(0, (s, p) => s + (double.tryParse('${p['area_sown_acre']}') ?? 0));

    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Sowing plans'),
      floatingActionButton: _canAdd
          ? FloatingActionButton.extended(
              backgroundColor: aGreen,
              foregroundColor: Colors.white,
              onPressed: () => _open(null),
              icon: const Icon(Icons.add),
              label: const Text('New sowing'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          Text('$active growing on ${_n(acres) == '' ? '0' : _n(double.parse(acres.toStringAsFixed(2)))} acres. Plants per acre and the expected yield come from the row spacing.',
              style: const TextStyle(fontSize: 13, color: aMuted)),
          const SizedBox(height: 10),
          AFilterChips<String>(
            value: _status,
            onChanged: (v) => setState(() => _status = v),
            options: [
              ('active', 'Growing', active),
              ('done', 'Done', _plans.length - active),
              ('all', 'All', _plans.length),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _farm,
                isExpanded: true,
                decoration: aInput('Farm'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All farms')),
                  for (final f in _farms) DropdownMenuItem<int?>(value: int.tryParse('${f['id']}'), child: Text('${f['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _farm = v),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(onChanged: (v) => setState(() => _q = v), decoration: aInput('Search', hint: 'Crop, farm or season', suffix: const Icon(Icons.search))),
          const SizedBox(height: 10),
          AErrorBox(_error),
          if (_loading && _plans.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (!_loading && rows.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Text('No sowing plans here.', textAlign: TextAlign.center, style: TextStyle(color: aMuted))),
          if (rows.isNotEmpty) ACard(child: Column(children: [for (var i = 0; i < rows.length; i++) _row(rows[i], i == 0)])),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, bool first) {
    final crop = _cropOf(p);
    final c = _calc[int.tryParse('${p['id']}') ?? 0];
    final sp = spacingText(p);
    final ppa = c?['plants_per_acre'];
    final st = '${p['status']}';
    return InkWell(
      onTap: () => _open(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
        child: Row(children: [
          AAvatar(crop.isEmpty ? '${p['crop_variety_name']}' : crop),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(crop.isEmpty ? '${p['crop_variety_name']}' : '$crop · ${p['crop_variety_name']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: aText)),
              Text('${p['farm_name']} · ${p['area_sown_acre'] != null ? '${_n(p['area_sown_acre'])} ac' : 'acres?'} · sown ${_nice(p['sowing_date'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: aMuted)),
              Text('$sp${ppa != null ? ' · ${_inr.format(ppa)} plants/acre' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: sp.contains('missing') ? const Color(0xFF9E4A19) : aMuted)),
            ]),
          ),
          if (st != 'active') Padding(padding: const EdgeInsets.only(left: 6), child: AChip(st == 'cancelled' ? 'Cancelled' : 'Finished')),
          const Icon(Icons.chevron_right, color: aMuted),
        ]),
      ),
    );
  }
}

// ── One plan (or a new one) ───────────────────────────────────────────
class SowingPlanScreen extends StatefulWidget {
  final Map<String, dynamic>? plan;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> varieties;
  final bool canAdd;
  final bool canEdit;
  final int? initialFarm;
  const SowingPlanScreen({super.key, this.plan, required this.farms, required this.varieties, this.canAdd = false, this.canEdit = false, this.initialFarm});
  @override
  State<SowingPlanScreen> createState() => _SowingPlanScreenState();
}

class _SowingPlanScreenState extends State<SowingPlanScreen> {
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _calc;
  bool _changed = false;
  bool _saving = false;
  String? _error;

  int? _farmId;
  int? _varietyId;
  int? _patternId; // row pattern picked for a new sowing
  List<Map<String, dynamic>> _patterns = [];
  final _season = TextEditingController();
  DateTime _sown = DateTime.now();
  final _acres = TextEditingController();
  String _layout = 'uniform';
  final Map<String, TextEditingController> _d = {for (final k in ['row_to_row_cm', 'plant_to_plant_cm', 'intra_pair_distance', 'inter_pair_distance']) k: TextEditingController()};
  final Map<String, String> _u = {'row_to_row_unit': 'cm', 'plant_to_plant_unit': 'cm', 'intra_pair_distance_unit': 'cm', 'inter_pair_distance_unit': 'cm'};
  String _origKey = '';

  bool get _isNew => _plan == null;
  bool get _mayEdit => _isNew ? widget.canAdd : widget.canEdit;
  List<Map<String, dynamic>> get _seasonal => widget.varieties.where((v) => v['crop_type'] == 'seasonal').toList();

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    _farmId = widget.initialFarm;
    _fill();
  }

  @override
  void dispose() {
    _season.dispose();
    _acres.dispose();
    for (final c in _d.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    final p = _plan;
    if (p != null) {
      _acres.text = _n(p['area_sown_acre']);
      _layout = '${p['row_arrangement'] ?? 'uniform'}';
      for (final k in _d.keys) {
        _d[k]!.text = _n(p[k]);
      }
      for (final k in _u.keys) {
        _u[k] = '${p[k] ?? 'cm'}';
      }
      _loadCalc();
    }
    _origKey = _key();
  }

  String _key() => [_acres.text, _layout, _patternId, ..._d.values.map((c) => c.text), ..._u.values, _farmId, _varietyId, _season.text, _sown.toIso8601String()].join('|');

  Future<void> _loadCalc() async {
    final p = _plan;
    if (p == null) return;
    try {
      final c = await AdminApi.get('/agri/sowing-plans/${p['id']}/calculations');
      if (mounted) setState(() => _calc = c is Map ? Map<String, dynamic>.from(c) : null);
    } catch (_) {}
  }

  Future<void> _reload() async {
    final p = _plan;
    if (p == null) return;
    try {
      final list = await AdminApi.get('/agri/sowing-plans?limit=200');
      final fresh = _maps(list is Map ? list['data'] : list).where((x) => '${x['id']}' == '${p['id']}').toList();
      if (fresh.isNotEmpty && mounted) {
        setState(() => _plan = fresh.first);
        _fill();
        setState(() {});
      }
    } catch (_) {}
  }

  // Row patterns offered for the variety picked in a new sowing.
  Future<void> _loadPatterns() async {
    final id = _varietyId;
    if (id == null) {
      setState(() => _patterns = []);
      return;
    }
    try {
      final r = await AdminApi.get('/agri/sowing-patterns?for_variety=$id');
      if (mounted && _varietyId == id) setState(() => _patterns = _maps(r));
    } catch (_) {
      if (mounted) setState(() => _patterns = []);
    }
  }

  // Picking a pattern fills in the layout and spacing; every field can still be changed.
  void _applyPattern(int? id) {
    final pt = id == null ? null : _patterns.where((x) => '${x['id']}' == '$id').firstOrNull;
    setState(() {
      _patternId = pt == null ? null : id;
      if (pt == null) return;
      _layout = '${pt['row_arrangement'] ?? 'uniform'}';
      for (final k in _d.keys) {
        _d[k]!.text = _n(pt[k]);
      }
      for (final k in _u.keys) {
        _u[k] = _units.contains('${pt[k]}') ? '${pt[k]}' : 'cm';
      }
    });
  }

  Map<String, dynamic> _spacing() => {
        'row_arrangement': _layout,
        for (final k in _d.keys) k: _d[k]!.text.trim().isEmpty ? null : _d[k]!.text.trim(),
        ..._u,
      };

  Future<void> _save() async {
    setState(() => _error = null);
    if (_isNew && (_farmId == null || _varietyId == null || _season.text.trim().isEmpty)) {
      setState(() => _error = 'Pick the farm and variety, and give the season and sowing date.');
      return;
    }
    if (_acres.text.trim().isNotEmpty && !((double.tryParse(_acres.text.trim()) ?? 0) > 0)) {
      setState(() => _error = 'Acres must be more than 0.');
      return;
    }
    setState(() => _saving = true);
    try {
      final acres = _acres.text.trim().isEmpty ? null : _acres.text.trim();
      dynamic saved;
      if (_isNew) {
        saved = await AdminApi.post('/agri/sowing-plans', {
          'farm_id': _farmId,
          'season': _season.text.trim(),
          'crop_variety_id': _varietyId,
          'sowing_date': DateFormat('yyyy-MM-dd').format(_sown),
          'area_sown_acre': acres,
          ..._spacing(),
          if (_patternId != null) 'pattern_id': _patternId,
        });
      } else {
        saved = await AdminApi.put('/agri/sowing-plans/${_plan!['id']}', {'area_sown_acre': acres, ..._spacing()});
      }
      _changed = true;
      if (saved is Map && saved['id'] != null) {
        setState(() => _plan = Map<String, dynamic>.from(saved));
      }
      await _reload();
      if (mounted) showOk(context, 'Saved');
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _cropOf(dynamic varietyId) {
    for (final v in widget.varieties) {
      if ('${v['id']}' == '$varietyId') return '${v['crop_name'] ?? ''}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final p = _plan;
    final crop = p == null ? '' : _cropOf(p['crop_variety_id']);
    final title = p == null ? 'New sowing' : (crop.isEmpty ? '${p['crop_variety_name']}' : '$crop · ${p['crop_variety_name']}');
    final dirty = _key() != _origKey;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: aBg,
        appBar: adminBar(title),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 30), children: [
          if (p != null) ...[_infoGrid(p), const SizedBox(height: 12)],
          ACard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_isNew) ...[
                DropdownButtonFormField<int>(
                  value: _farmId,
                  isExpanded: true,
                  decoration: aInput('Farm'),
                  items: [for (final f in widget.farms) DropdownMenuItem<int>(value: int.tryParse('${f['id']}') ?? 0, child: Text('${f['name']}'))],
                  onChanged: (v) => setState(() => _farmId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _varietyId,
                  isExpanded: true,
                  decoration: aInput('Crop · variety'),
                  items: [for (final v in _seasonal) DropdownMenuItem<int>(value: int.tryParse('${v['id']}') ?? 0, child: Text('${v['crop_name']} · ${v['name']}', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    setState(() {
                      _varietyId = v;
                      _patternId = null;
                      _patterns = [];
                    });
                    _loadPatterns();
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: _season, onChanged: (_) => setState(() {}), decoration: aInput('Season', hint: 'e.g. Kharif 2026')),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _sown, firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) setState(() => _sown = d);
                  },
                  child: InputDecorator(
                    decoration: aInput('Sown on', suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
                    child: Text(DateFormat('d MMM yyyy').format(_sown)),
                  ),
                ),
                const SizedBox(height: 10),
                if (_varietyId != null) ...[
                  DropdownButtonFormField<int?>(
                    value: _patternId,
                    isExpanded: true,
                    decoration: aInput('Row pattern', helper: _patterns.isEmpty ? 'No saved pattern for this crop yet. Add them under Row patterns.' : 'Fills in the layout and spacing below. You can still change them.'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('No pattern — I will set the rows myself', overflow: TextOverflow.ellipsis)),
                      for (final pt in _patterns)
                        DropdownMenuItem<int?>(
                          value: int.tryParse('${pt['id']}'),
                          child: Text('${pt['name']} · ${pt['row_arrangement'] == 'sequence' ? '${_maps(pt['lines']).length} lines' : spacingText(pt)}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _applyPattern,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              TextField(
                controller: _acres,
                enabled: _mayEdit && p?['intercrop_group_id'] == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: aInput('Acres sown', helper: p?['intercrop_group_id'] != null ? 'Worked out from the shared area for crops grown together.' : null),
              ),
              const SizedBox(height: 14),
              const Text('How the rows are laid out', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF3A4833))),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'uniform', label: Text('Uniform')),
                  ButtonSegment(value: 'paired', label: Text('Paired')),
                  ButtonSegment(value: 'sequence', label: Text('Sequence')),
                ],
                selected: {_layout},
                showSelectedIcon: false,
                onSelectionChanged: _mayEdit ? (s) => setState(() => _layout = s.first) : null,
              ),
              const SizedBox(height: 6),
              Text(
                _layout == 'uniform'
                    ? 'The same gap between every row.'
                    : _layout == 'paired'
                        ? 'Rows in pairs: a small gap inside each pair, a wide gap between pairs.'
                        : (_patternId != null ? 'A repeating order of lines. The lines come from the pattern; change them under “Crops grown together” after saving.' : 'A repeating order of lines (one crop or several). Set the lines under “Crops grown together” after saving.'),
                style: const TextStyle(fontSize: 12.5, color: aMuted),
              ),
              if (_layout != 'sequence') ...[
                const SizedBox(height: 10),
                if (_layout == 'paired') ...[
                  _dist('Inside a pair', 'intra_pair_distance', 'intra_pair_distance_unit'),
                  const SizedBox(height: 10),
                  _dist('Between pairs', 'inter_pair_distance', 'inter_pair_distance_unit'),
                ] else
                  _dist('Row to row', 'row_to_row_cm', 'row_to_row_unit'),
                const SizedBox(height: 10),
                _dist('Plant to plant', 'plant_to_plant_cm', 'plant_to_plant_unit'),
              ],
              const SizedBox(height: 10),
              AErrorBox(_error),
              if (_mayEdit) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: aPrimary(),
                  onPressed: _saving || (!dirty && !_isNew) ? null : _save,
                  child: Text(_saving ? 'Saving…' : (_isNew ? 'Add sowing' : 'Save')),
                ),
              ],
            ]),
          ),
          if (p != null) ...[
            const SizedBox(height: 12),
            _IntercropCard(key: ValueKey('ic-${p['id']}-${p['intercrop_group_id']}-${p['rows_per_cycle']}-${p['density_pct_of_solecrop']}'), plan: p, seasonal: _seasonal, canAdd: widget.canAdd, onChanged: () async {
              _changed = true;
              await _reload();
            }),
            const SizedBox(height: 12),
            ACard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Finished or not sown?', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Finish or cancel it on its crop calendar, so its costs and harvest stay together.', style: TextStyle(fontSize: 13, color: aMuted)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: aSecondary(),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Open the crop calendar'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CropCalendarScreen(cycleType: 'seasonal', cycleId: int.tryParse('${p['id']}') ?? 0, title: title)),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _infoGrid(Map<String, dynamic> p) {
    final c = _calc;
    final sown = DateTime.tryParse(_d10(p['sowing_date']));
    final days = sown == null ? '—' : '${DateTime.now().difference(sown).inDays.clamp(0, 99999)}';
    Widget info(String label, String value, [String sub = '']) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(color: const Color(0xFFF6F8F3), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: aMuted)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: aText)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, style: const TextStyle(fontSize: 11.5, color: aMuted)),
            ]),
          ),
        );
    final ppa = c?['plants_per_acre'];
    final total = c?['total_plants'];
    final y = c?['tentative_yield'];
    final st = '${p['status']}';
    return ACard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (st == 'active') const AChip.ok('Growing') else AChip(st == 'cancelled' ? 'Cancelled' : 'Finished'),
          AChip('${p['farm_name']} · ${p['season']}'),
          if (p['pattern_name'] != null) AChip('Row pattern: ${p['pattern_name']}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          info('Sown on', _nice(p['sowing_date'])),
          const SizedBox(width: 8),
          info('Days since sowing', days),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          info('Plants per acre', ppa == null ? '—' : _inr.format(ppa), total != null ? '${_inr.format(total)} in all' : (c?['note'] != null ? 'needs the spacing' : '')),
          const SizedBox(width: 8),
          info('Expected yield', y == null ? '—' : '${_inr.format(double.tryParse('$y') ?? 0)} ${c?['tentative_yield_unit'] ?? ''}', c != null && y == null ? 'set yield per plant on the variety (Crops)' : ''),
        ]),
      ]),
    );
  }

  Widget _dist(String label, String key, String unitKey) => Row(children: [
        Expanded(
          child: TextField(
            controller: _d[key],
            enabled: _mayEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: aInput(label),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: DropdownButtonFormField<String>(
            value: _units.contains(_u[unitKey]) ? _u[unitKey] : 'cm',
            decoration: aInput('Unit'),
            items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: _mayEdit ? (v) => setState(() => _u[unitKey] = v ?? 'cm') : null,
          ),
        ),
      ]);
}

// ── Crops grown together ──────────────────────────────────────────────
class _IntercropCard extends StatefulWidget {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> seasonal;
  final bool canAdd;
  final Future<void> Function() onChanged;
  const _IntercropCard({super.key, required this.plan, required this.seasonal, required this.canAdd, required this.onChanged});
  @override
  State<_IntercropCard> createState() => _IntercropCardState();
}

class _IntercropCardState extends State<_IntercropCard> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = widget.plan;
    try {
      if (p['intercrop_group_id'] != null) {
        final d = await AdminApi.get('/agri/sowing-plans/${p['id']}/intercrop-group');
        _members = _maps(d is Map ? d['members'] : null);
      } else {
        _members = [p];
      }
    } catch (e) {
      _error = errText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddCompanionSheet(plan: widget.plan, seasonal: widget.seasonal),
    );
    if (ok == true) await widget.onChanged();
  }

  Future<void> _lines() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LinesSheet(planId: int.tryParse('${widget.plan['id']}') ?? 0, varieties: widget.seasonal),
    );
    if (ok == true) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return ACard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.eco_outlined, size: 19, color: aText),
          SizedBox(width: 8),
          Text('Crops grown together', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: aText)),
        ]),
        const SizedBox(height: 10),
        if (_loading) const Text('Loading…', style: TextStyle(color: aMuted)),
        for (final m in _members)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: const Color(0xFFF6F8F3), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text('${m['crop_variety_name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              if ('${m['id']}' == '${p['id']}') const Padding(padding: EdgeInsets.only(right: 8), child: AChip('this plan')),
              Text(m['area_sown_acre'] != null ? '${_n(m['area_sown_acre'])} ac' : 'acres pending', style: const TextStyle(color: aMuted)),
            ]),
          ),
        if (!_loading && _members.length <= 1)
          const Text('Grown alone. Add a companion crop if another crop shares these rows.', style: TextStyle(fontSize: 13, color: aMuted)),
        AErrorBox(_error),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (p['row_arrangement'] == 'sequence')
            OutlinedButton.icon(style: aSecondary(), onPressed: _lines, icon: const Icon(Icons.view_week_outlined, size: 18), label: const Text('Line sequence')),
          if (widget.canAdd)
            OutlinedButton.icon(style: aSecondary(), onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Add a companion crop')),
        ]),
      ]),
    );
  }
}

class _AddCompanionSheet extends StatefulWidget {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> seasonal;
  const _AddCompanionSheet({required this.plan, required this.seasonal});
  @override
  State<_AddCompanionSheet> createState() => _AddCompanionSheetState();
}

class _AddCompanionSheetState extends State<_AddCompanionSheet> {
  late String _mode = widget.plan['row_arrangement'] == 'sequence' ? 'sequence' : 'width';
  int? _variety;
  DateTime _sown = DateTime.now();
  final _shared = TextEditingController();
  final _rows = TextEditingController();
  final _mainRows = TextEditingController();
  final _density = TextEditingController();
  final _mainDensity = TextEditingController();
  bool _saving = false;
  String? _error;

  // The main plan's own share is needed until it is on file.
  bool get _isFirst => _mode == 'sequence' ? widget.plan['density_pct_of_solecrop'] == null : widget.plan['rows_per_cycle'] == null;

  @override
  void dispose() {
    for (final c in [_shared, _rows, _mainRows, _density, _mainDensity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_variety == null || _shared.text.trim().isEmpty) {
      setState(() => _error = 'Pick the companion variety and give the shared acres.');
      return;
    }
    if (_mode == 'width' && (_rows.text.trim().isEmpty || (_isFirst && _mainRows.text.trim().isEmpty))) {
      setState(() => _error = 'Give the rows in each repeat for both crops.');
      return;
    }
    if (_mode == 'sequence' && (_density.text.trim().isEmpty || (_isFirst && _mainDensity.text.trim().isEmpty))) {
      setState(() => _error = 'Give the density % for both crops.');
      return;
    }
    final body = <String, dynamic>{
      'crop_variety_id': _variety,
      'sowing_date': DateFormat('yyyy-MM-dd').format(_sown),
      'shared_physical_area_acre': _shared.text.trim(),
    };
    if (_mode == 'sequence') {
      body['row_arrangement'] = 'sequence';
      body['density_pct_of_solecrop'] = _density.text.trim();
      if (_isFirst) body['main_density_pct_of_solecrop'] = _mainDensity.text.trim();
    } else {
      body['rows_per_cycle'] = _rows.text.trim();
      if (_isFirst) body['main_rows_per_cycle'] = _mainRows.text.trim();
    }
    setState(() => _saving = true);
    try {
      await AdminApi.post('/agri/sowing-plans/${widget.plan['id']}/add-intercrop', body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = '${widget.plan['crop_variety_name']}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add a companion crop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'width', label: Text('By rows')), ButtonSegment(value: 'sequence', label: Text('By density %'))],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _variety,
              isExpanded: true,
              decoration: aInput('Companion crop · variety'),
              items: [for (final v in widget.seasonal) DropdownMenuItem<int>(value: int.tryParse('${v['id']}') ?? 0, child: Text('${v['crop_name']} · ${v['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _variety = v),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _sown, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 60)));
                if (d != null) setState(() => _sown = d);
              },
              child: InputDecorator(decoration: aInput('Sown on', suffix: const Icon(Icons.calendar_today_outlined, size: 18)), child: Text(DateFormat('d MMM yyyy').format(_sown))),
            ),
            const SizedBox(height: 10),
            TextField(controller: _shared, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('Shared acres')),
            const SizedBox(height: 10),
            if (_mode == 'width') ...[
              TextField(controller: _rows, keyboardType: TextInputType.number, decoration: aInput('Companion rows in each repeat')),
              if (_isFirst) ...[const SizedBox(height: 10), TextField(controller: _mainRows, keyboardType: TextInputType.number, decoration: aInput('$main rows in each repeat'))],
            ] else ...[
              TextField(controller: _density, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('Companion density % of a sole crop')),
              if (_isFirst) ...[const SizedBox(height: 10), TextField(controller: _mainDensity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('$main density %'))],
            ],
            const SizedBox(height: 8),
            Text(
              _mode == 'width'
                  ? 'Acres are shared by the rows each crop has in one repeat of the pattern.'
                  : 'Each crop’s density compared with growing it alone (e.g. 5 lines where alone you would sow 7 ≈ 70%). Together they can add up to more than 100%.',
              style: const TextStyle(fontSize: 12.5, color: aMuted),
            ),
            const SizedBox(height: 10),
            AErrorBox(_error),
            const SizedBox(height: 10),
            FilledButton(style: aPrimary(), onPressed: _saving ? null : _save, child: Text(_saving ? 'Adding…' : 'Add companion')),
          ]),
        ),
      ),
    );
  }
}

class _LinesSheet extends StatefulWidget {
  final int planId;
  final List<Map<String, dynamic>> varieties;
  const _LinesSheet({required this.planId, required this.varieties});
  @override
  State<_LinesSheet> createState() => _LinesSheetState();
}

class _Line {
  int? variety;
  final TextEditingController gap;
  String unit;
  _Line({this.variety, String gapText = '', this.unit = 'cm'}) : gap = TextEditingController(text: gapText);
}

class _LinesSheetState extends State<_LinesSheet> {
  List<_Line> _lines = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.gap.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await AdminApi.get('/agri/sowing-plans/${widget.planId}/pattern-lines');
      final ls = _maps(d is Map ? d['lines'] : null);
      _lines = ls.isEmpty
          ? [_Line()]
          : ls.map((l) => _Line(variety: int.tryParse('${l['crop_variety_id']}'), gapText: _n(l['gap_to_next'] ?? l['gap_to_next_cm']), unit: _units.contains(l['gap_to_next_unit']) ? '${l['gap_to_next_unit']}' : 'cm')).toList();
    } catch (e) {
      _error = errText(e);
      _lines = [_Line()];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_lines.any((l) => l.variety == null || l.gap.text.trim().isEmpty)) {
      setState(() => _error = 'Every line needs a crop and the gap to the next line.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AdminApi.post('/agri/sowing-plans/${widget.planId}/pattern-lines', {
        'lines': [for (final l in _lines) {'crop_variety_id': l.variety, 'gap_to_next': l.gap.text.trim(), 'gap_to_next_unit': l.unit}],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Line sequence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('The repeating order of lines and the gap to each next line. The last gap goes back to line 1.', style: TextStyle(fontSize: 13, color: aMuted)),
            const SizedBox(height: 12),
            if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            for (var i = 0; i < _lines.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFAFBF8), borderRadius: BorderRadius.circular(10), border: Border.all(color: aBorder)),
                child: Column(children: [
                  Row(children: [
                    Text('Line ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_lines.length > 1)
                      IconButton(
                        tooltip: 'Remove line ${i + 1}',
                        icon: const Icon(Icons.delete_outline, color: aRed),
                        onPressed: () => setState(() {
                          _lines[i].gap.dispose();
                          _lines.removeAt(i);
                        }),
                      ),
                  ]),
                  DropdownButtonFormField<int>(
                    value: _lines[i].variety,
                    isExpanded: true,
                    decoration: aInput('Crop'),
                    items: [for (final v in widget.varieties) DropdownMenuItem<int>(value: int.tryParse('${v['id']}') ?? 0, child: Text('${v['crop_name']} · ${v['name']}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _lines[i].variety = v),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _lines[i].gap, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('Gap to the next line'))),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 86,
                      child: DropdownButtonFormField<String>(
                        value: _lines[i].unit,
                        decoration: aInput('Unit'),
                        items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
                        onChanged: (v) => setState(() => _lines[i].unit = v ?? 'cm'),
                      ),
                    ),
                  ]),
                ]),
              ),
            AErrorBox(_error),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(style: aSecondary(), onPressed: () => setState(() => _lines.add(_Line())), icon: const Icon(Icons.add, size: 18), label: const Text('Line')),
              const Spacer(),
              FilledButton(style: aPrimary(), onPressed: _saving || _loading ? null : _save, child: Text(_saving ? 'Saving…' : 'Save sequence')),
            ]),
          ]),
        ),
      ),
    );
  }
}
