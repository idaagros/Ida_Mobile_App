// lib/screens/agronomy/sowing_patterns_screen.dart
//
// Row patterns (Oct 2026) — the phone version of the website's
// Agriculture › Row patterns. A pattern is a named way of laying out
// rows for a crop, e.g. "Soybean 30 in uniform" or "Soybean paired
// 2.5 in". Pick one when you add a sowing and its spacing (and, for a
// line sequence, its lines) fill in. The plan keeps its own copy, so
// changing a pattern later never changes plans already made.
//  - List: In use / Archived / All, a crop filter and search.
//  - One pattern: name, crop, optional variety, layout (uniform, paired
//    or line sequence), spacing or lines, archive / bring back.
// Web counterpart: src/pages/agri/SowingPatternsPage.jsx.
// API: /agri/sowing-patterns, /agri/crops, /agri/crop-varieties

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../admin/admin_common.dart';
import 'sowing_plans_screen.dart' show spacingText;

const List<String> _pUnits = ['cm', 'in', 'ft'];

String _pn(dynamic v) {
  final d = double.tryParse('${v ?? ''}');
  if (d == null) return '';
  return d == d.roundToDouble() ? d.round().toString() : d.toString();
}

List<Map<String, dynamic>> _pmaps(dynamic v) => (v is List ? v : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

String _patternSummary(Map p) {
  if (p['row_arrangement'] == 'sequence') {
    final ls = _pmaps(p['lines']);
    if (ls.isEmpty) return 'No lines yet';
    return '${ls.length} line${ls.length == 1 ? '' : 's'}: ${ls.map((l) => '${_pn(l['gap_to_next'])} ${l['gap_to_next_unit']}').join(' · ')}';
  }
  return spacingText(p);
}

class SowingPatternsScreen extends StatefulWidget {
  const SowingPatternsScreen({super.key});
  @override
  State<SowingPatternsScreen> createState() => _SowingPatternsScreenState();
}

class _SowingPatternsScreenState extends State<SowingPatternsScreen> {
  List<Map<String, dynamic>> _patterns = [];
  List<Map<String, dynamic>> _crops = [];
  List<Map<String, dynamic>> _varieties = [];
  bool _loading = true;
  String? _error;
  String _status = 'active';
  int? _crop;
  String _q = '';
  bool _canAdd = false;
  bool _canEdit = false;
  bool _canDelete = false; // Archive = DELETE on the server; Bring back = update

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _canAdd = await ApiService.canAdd('agri');
    _canEdit = await ApiService.canUpdate('agri');
    _canDelete = await ApiService.canDelete('agri');
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await AdminApi.get('/agri/sowing-patterns?all=1');
      final c = await AdminApi.get('/agri/crops');
      final v = await AdminApi.get('/agri/crop-varieties');
      if (!mounted) return;
      setState(() {
        _patterns = _pmaps(p);
        _crops = _pmaps(c).where((x) => x['crop_type'] == 'seasonal').toList();
        _varieties = _pmaps(v).where((x) => x['crop_type'] == 'seasonal').toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isOn(Map p) => '${p['is_active']}' == '1' || p['is_active'] == true;

  Future<void> _open(Map<String, dynamic>? pattern) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SowingPatternScreen(
          pattern: pattern,
          crops: _crops,
          varieties: _varieties,
          canAdd: _canAdd,
          canEdit: _canEdit,
          canDelete: _canDelete,
          initialCrop: _crop,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final on = _patterns.where(_isOn).length;
    final q = _q.trim().toLowerCase();
    final rows = _patterns.where((p) {
      final active = _isOn(p);
      if (_status == 'active' && !active) return false;
      if (_status == 'archived' && active) return false;
      if (_crop != null && '${p['crop_id']}' != '$_crop') return false;
      if (q.isNotEmpty && !'${p['name']} ${p['crop_name']} ${p['variety_name'] ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) => '${a['crop_name']} ${a['name']}'.toLowerCase().compareTo('${b['crop_name']} ${b['name']}'.toLowerCase()));

    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Row patterns'),
      floatingActionButton: _canAdd
          ? FloatingActionButton.extended(
              backgroundColor: aGreen,
              foregroundColor: Colors.white,
              onPressed: () => _open(null),
              icon: const Icon(Icons.add),
              label: const Text('New pattern'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          const Text('Named ways of laying out rows for a crop. Pick one when you add a sowing and its spacing fills in.', style: TextStyle(fontSize: 13, color: aMuted)),
          const SizedBox(height: 10),
          AFilterChips<String>(
            value: _status,
            onChanged: (v) => setState(() => _status = v),
            options: [
              ('active', 'In use', on),
              ('archived', 'Archived', _patterns.length - on),
              ('all', 'All', _patterns.length),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            value: _crop,
            isExpanded: true,
            decoration: aInput('Crop'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All crops')),
              for (final c in _crops) DropdownMenuItem<int?>(value: int.tryParse('${c['id']}'), child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _crop = v),
          ),
          const SizedBox(height: 10),
          TextField(onChanged: (v) => setState(() => _q = v), decoration: aInput('Search', hint: 'Pattern or crop', suffix: const Icon(Icons.search))),
          const SizedBox(height: 10),
          AErrorBox(_error),
          if (_loading && _patterns.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (!_loading && rows.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Text('No row patterns here yet.', textAlign: TextAlign.center, style: TextStyle(color: aMuted))),
          if (rows.isNotEmpty) ACard(child: Column(children: [for (var i = 0; i < rows.length; i++) _row(rows[i], i == 0)])),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, bool first) {
    final used = int.tryParse('${p['used_count']}') ?? 0;
    return InkWell(
      onTap: () => _open(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
        child: Row(children: [
          AAvatar('${p['crop_name']}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: aText)),
              Text('${p['crop_name']}${p['variety_name'] != null ? ' · ${p['variety_name']}' : ' · any variety'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: aMuted)),
              Text('${_patternSummary(p)}${used > 0 ? ' · used in $used plan${used == 1 ? '' : 's'}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: aMuted)),
            ]),
          ),
          if (!_isOn(p)) const Padding(padding: EdgeInsets.only(left: 6), child: AChip('Archived')),
          const Icon(Icons.chevron_right, color: aMuted),
        ]),
      ),
    );
  }
}

// ── One pattern (or a new one) ───────────────────────────────────────
class _PLine {
  int? variety;
  final TextEditingController gap;
  String unit;
  _PLine({this.variety, String gapText = '', this.unit = 'cm'}) : gap = TextEditingController(text: gapText);
}

class SowingPatternScreen extends StatefulWidget {
  final Map<String, dynamic>? pattern;
  final List<Map<String, dynamic>> crops;
  final List<Map<String, dynamic>> varieties;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final int? initialCrop;
  const SowingPatternScreen({super.key, this.pattern, required this.crops, required this.varieties, this.canAdd = false, this.canEdit = false, this.canDelete = false, this.initialCrop});
  @override
  State<SowingPatternScreen> createState() => _SowingPatternScreenState();
}

class _SowingPatternScreenState extends State<SowingPatternScreen> {
  Map<String, dynamic>? _pattern;
  bool _changed = false;
  bool _saving = false;
  String? _error;

  final _name = TextEditingController();
  int? _cropId;
  int? _varietyId;
  String _layout = 'uniform';
  final Map<String, TextEditingController> _d = {for (final k in ['row_to_row_cm', 'plant_to_plant_cm', 'intra_pair_distance', 'inter_pair_distance']) k: TextEditingController()};
  final Map<String, String> _u = {'row_to_row_unit': 'cm', 'plant_to_plant_unit': 'cm', 'intra_pair_distance_unit': 'cm', 'inter_pair_distance_unit': 'cm'};
  List<_PLine> _lines = [_PLine()];
  String _origKey = '';

  bool get _isNew => _pattern == null;
  bool get _mayEdit => _isNew ? widget.canAdd : widget.canEdit;
  bool get _isOn => _pattern == null || '${_pattern!['is_active']}' == '1' || _pattern!['is_active'] == true;
  List<Map<String, dynamic>> get _cropVarieties => widget.varieties.where((v) => '${v['crop_id']}' == '$_cropId').toList();

  @override
  void initState() {
    super.initState();
    _pattern = widget.pattern;
    _cropId = widget.initialCrop;
    _fill();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _d.values) {
      c.dispose();
    }
    for (final l in _lines) {
      l.gap.dispose();
    }
    super.dispose();
  }

  void _fill() {
    final p = _pattern;
    if (p != null) {
      _name.text = '${p['name']}';
      _cropId = int.tryParse('${p['crop_id']}');
      _varietyId = p['crop_variety_id'] == null ? null : int.tryParse('${p['crop_variety_id']}');
      _layout = '${p['row_arrangement'] ?? 'uniform'}';
      for (final k in _d.keys) {
        _d[k]!.text = _pn(p[k]);
      }
      for (final k in _u.keys) {
        _u[k] = _pUnits.contains('${p[k]}') ? '${p[k]}' : 'cm';
      }
      for (final l in _lines) {
        l.gap.dispose();
      }
      final ls = _pmaps(p['lines']);
      _lines = ls.isEmpty
          ? [_PLine()]
          : ls.map((l) => _PLine(variety: int.tryParse('${l['crop_variety_id']}'), gapText: _pn(l['gap_to_next']), unit: _pUnits.contains('${l['gap_to_next_unit']}') ? '${l['gap_to_next_unit']}' : 'cm')).toList();
    }
    _origKey = _key();
  }

  String _key() => [_name.text, _cropId, _varietyId, _layout, ..._d.values.map((c) => c.text), ..._u.values, ..._lines.map((l) => '${l.variety}:${l.gap.text}:${l.unit}')].join('|');

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the pattern a name.');
      return;
    }
    if (_cropId == null) {
      setState(() => _error = 'Pick the crop this pattern is for.');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'crop_id': _cropId,
        'crop_variety_id': _varietyId,
        'row_arrangement': _layout,
        for (final k in _d.keys) k: _d[k]!.text.trim().isEmpty ? null : _d[k]!.text.trim(),
        ..._u,
        if (_layout == 'sequence') 'lines': [for (final l in _lines) {'crop_variety_id': l.variety, 'gap_to_next': l.gap.text.trim(), 'gap_to_next_unit': l.unit}],
      };
      final dynamic saved = _isNew ? await AdminApi.post('/agri/sowing-patterns', body) : await AdminApi.put('/agri/sowing-patterns/${_pattern!['id']}', body);
      _changed = true;
      if (saved is Map) {
        setState(() {
          _pattern = Map<String, dynamic>.from(saved);
          _fill();
        });
      }
      if (mounted) showOk(context, 'Saved');
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setActive(bool on) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (on) {
        final dynamic saved = await AdminApi.put('/agri/sowing-patterns/${_pattern!['id']}', {'is_active': true});
        if (saved is Map) _pattern = Map<String, dynamic>.from(saved);
      } else {
        await AdminApi.delete('/agri/sowing-patterns/${_pattern!['id']}');
        _pattern = {..._pattern!, 'is_active': 0};
      }
      _changed = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            value: _pUnits.contains(_u[unitKey]) ? _u[unitKey] : 'cm',
            decoration: aInput('Unit'),
            items: [for (final u in _pUnits) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: _mayEdit ? (v) => setState(() => _u[unitKey] = v ?? 'cm') : null,
          ),
        ),
      ]);

  Widget _lineCard(int i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFAFBF8), borderRadius: BorderRadius.circular(10), border: Border.all(color: aBorder)),
        child: Column(children: [
          Row(children: [
            Text('Line ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (_lines.length > 1 && _mayEdit)
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
            onChanged: _mayEdit ? (v) => setState(() => _lines[i].variety = v) : null,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lines[i].gap,
                enabled: _mayEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: aInput('Gap to the next line'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: DropdownButtonFormField<String>(
                value: _lines[i].unit,
                decoration: aInput('Unit'),
                items: [for (final u in _pUnits) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: _mayEdit ? (v) => setState(() => _lines[i].unit = v ?? 'cm') : null,
              ),
            ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _pattern;
    final dirty = _key() != _origKey;
    final used = int.tryParse('${p?['used_count']}') ?? 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: aBg,
        appBar: adminBar(p == null ? 'New row pattern' : '${p['name']}'),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 30), children: [
          ACard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p != null) ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (_isOn) const AChip.ok('In use') else const AChip('Archived'),
                  AChip('${p['crop_name']}${p['variety_name'] != null ? ' · ${p['variety_name']}' : ''}'),
                ]),
                const SizedBox(height: 12),
              ],
              TextField(controller: _name, enabled: _mayEdit, onChanged: (_) => setState(() {}), decoration: aInput('Name', hint: 'e.g. Soybean 30 in uniform')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _cropId,
                isExpanded: true,
                decoration: aInput('Crop'),
                items: [for (final c in widget.crops) DropdownMenuItem<int>(value: int.tryParse('${c['id']}') ?? 0, child: Text('${c['name']}', overflow: TextOverflow.ellipsis))],
                onChanged: _mayEdit
                    ? (v) => setState(() {
                          _cropId = v;
                          _varietyId = null;
                        })
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                value: _varietyId,
                isExpanded: true,
                decoration: aInput('Variety', helper: 'Leave on “Any variety” to offer it for every variety of the crop.'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Any variety')),
                  for (final v in _cropVarieties) DropdownMenuItem<int?>(value: int.tryParse('${v['id']}'), child: Text('${v['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _mayEdit && _cropId != null ? (v) => setState(() => _varietyId = v) : null,
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
                        : 'A repeating order of lines (one crop or several), each with the gap to the next. The last gap goes back to line 1.',
                style: const TextStyle(fontSize: 12.5, color: aMuted),
              ),
              const SizedBox(height: 10),
              if (_layout == 'uniform') ...[
                _dist('Row to row', 'row_to_row_cm', 'row_to_row_unit'),
                const SizedBox(height: 10),
                _dist('Plant to plant', 'plant_to_plant_cm', 'plant_to_plant_unit'),
              ],
              if (_layout == 'paired') ...[
                _dist('Inside a pair', 'intra_pair_distance', 'intra_pair_distance_unit'),
                const SizedBox(height: 10),
                _dist('Between pairs', 'inter_pair_distance', 'inter_pair_distance_unit'),
                const SizedBox(height: 10),
                _dist('Plant to plant', 'plant_to_plant_cm', 'plant_to_plant_unit'),
              ],
              if (_layout == 'sequence') ...[
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                if (_mayEdit)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(style: aSecondary(), onPressed: () => setState(() => _lines.add(_PLine())), icon: const Icon(Icons.add, size: 18), label: const Text('Line')),
                  ),
                const SizedBox(height: 6),
                const Text('If the lines use more than one crop, add the other crops as companions on the sowing plan after it is made.', style: TextStyle(fontSize: 12.5, color: aMuted)),
              ],
              if (p != null) ...[
                const SizedBox(height: 10),
                Text(used > 0 ? 'Used in $used sowing plan${used == 1 ? '' : 's'}. Changing it does not change them.' : 'Not used in any sowing plan yet.', style: const TextStyle(fontSize: 13, color: aMuted)),
              ],
              const SizedBox(height: 10),
              AErrorBox(_error),
              if (_mayEdit) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: aPrimary(),
                  onPressed: _saving || (!dirty && !_isNew) ? null : _save,
                  child: Text(_saving ? 'Saving…' : (_isNew ? 'Add pattern' : 'Save')),
                ),
              ],
            ]),
          ),
          if (p != null && (_isOn ? widget.canDelete : widget.canEdit)) ...[
            const SizedBox(height: 12),
            ACard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_isOn ? 'Not used any more?' : 'Use it again?', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_isOn ? 'Archive it. Sowing plans made with it stay as they are.' : 'Bring it back to the list.', style: const TextStyle(fontSize: 13, color: aMuted)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: aSecondary(fg: _isOn ? aRed : const Color(0xFF2B3A24)),
                  icon: Icon(_isOn ? Icons.archive_outlined : Icons.unarchive_outlined, size: 18),
                  label: Text(_isOn ? 'Archive' : 'Bring back'),
                  onPressed: _saving ? null : () => _setActive(!_isOn),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
