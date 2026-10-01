// lib/screens/crop_cycles_screen.dart
//
// Crop cycles (Sep 2026, group C) — same as the website's Crop cycles:
//  - tiles: crops running, jobs overdue, jobs in the next 7 days, spent
//  - Running / Finished / Cancelled filter with counts, search
//  - each crop shows where it is (farm, size, season), progress (stage,
//    day N of days to harvest), the next job, money spent and harvest
//  - admins see "Work not linked to a crop" — Farm attendance days on
//    farms with more than one crop, to say which crop the work was for
// Tap a crop to open its crop calendar. "+" adds a sowing plan or an
// orchard cycle (POST makes the schedule server-side, then the calendar
// opens).
// API: GET /agri/cycles?state=all, GET /agri/cycles/unassigned-work,
//      POST /agri/cycles/assign-work

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crop_calendar_screen.dart';
import 'agri/cycle_common.dart';
import 'agronomy/agronomy_common.dart' show AgriApi;
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class CropCyclesScreen extends StatefulWidget {
  const CropCyclesScreen({super.key});
  @override
  State<CropCyclesScreen> createState() => _CropCyclesScreenState();
}

class _CropCyclesScreenState extends State<CropCyclesScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static String get baseUrl => AppConfig.apiBaseUrl;

  List cycles = [];
  Map counts = {};
  Map totals = {};
  List unassigned = [];
  String state = 'running';
  String search = '';
  bool isAdmin = false;
  String? loadError;

  List farms = [];
  List seasonalVarieties = [];
  List orchardBlocks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
    };
  }

  Future<void> _loadAll() async {
    if (cycles.isEmpty) setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    isAdmin = prefs.getBool('is_admin') ?? (prefs.getString('role') == 'admin');
    try {
      final d = await AgriApi.get('/agri/cycles?state=all');
      cycles = (d?['cycles'] as List?) ?? [];
      counts = Map.from(d?['counts'] ?? {});
      totals = Map.from(d?['totals'] ?? {});
      loadError = null;
    } catch (e) {
      loadError = '$e';
    }
    if (isAdmin) {
      try {
        final u = await AgriApi.get('/agri/cycles/unassigned-work');
        unassigned = (u?['items'] as List?) ?? [];
      } catch (_) {
        unassigned = [];
      }
    }
    // For the "+" dialogs.
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/crop-varieties'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/orchard-blocks'), headers: h),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) {
        final all = jsonDecode(results[1].body);
        seasonalVarieties =
            all.where((v) => v['crop_type'] == 'seasonal').toList();
      }
      if (results[2].statusCode == 200) {
        orchardBlocks = jsonDecode(results[2].body)['data'] ?? [];
      }
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : idaGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showAddMenu() {
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.grass, color: idaGreen),
            title: Text(loc.agriAddSowingPlan),
            onTap: () {
              Navigator.pop(context);
              if (seasonalVarieties.isEmpty) {
                _showSnack('Add a seasonal crop variety first', isError: true);
                return;
              }
              _showSowingPlanDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.park, color: idaGreen),
            title: Text(loc.agriAddOrchardCycle),
            onTap: () {
              Navigator.pop(context);
              if (orchardBlocks.isEmpty) {
                _showSnack('Add an orchard block first', isError: true);
                return;
              }
              _showOrchardCycleDialog();
            },
          ),
        ]),
      ),
    );
  }

  Widget _unitDropdown(
      AppLocalizations loc, String value, void Function(String) onChanged) {
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
            value: 'cm',
            child: Text(loc.agriUnitCm, style: const TextStyle(fontSize: 13))),
        DropdownMenuItem(
            value: 'ft',
            child: Text(loc.agriUnitFt, style: const TextStyle(fontSize: 13))),
        DropdownMenuItem(
            value: 'in',
            child: Text(loc.agriUnitIn, style: const TextStyle(fontSize: 13))),
      ],
      onChanged: (v) => onChanged(v!),
    );
  }

  void _showSowingPlanDialog() {
    final loc = AppLocalizations.of(context)!;
    int? farmId = farms.isNotEmpty ? farms.first['id'] : null;
    int? varietyId = seasonalVarieties.first['id'];
    String season = 'kharif';
    DateTime sowingDate = DateTime.now();
    final areaCtrl = TextEditingController();
    final rowSpacingCtrl = TextEditingController();
    String rowSpacingUnit = 'cm';
    final plantSpacingCtrl = TextEditingController();
    String plantSpacingUnit = 'cm';
    String rowArrangement = 'uniform';
    final intraPairCtrl = TextEditingController();
    String intraPairUnit = 'cm';
    final interPairCtrl = TextEditingController();
    String interPairUnit = 'cm';
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriAddSowingPlan,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: farmId,
                decoration: InputDecoration(
                    labelText: loc.agriFarmLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: farms
                    .map<DropdownMenuItem<int>>((f) => DropdownMenuItem(
                        value: f['id'], child: Text(tl(context, f['name']))))
                    .toList(),
                onChanged: (v) => setDialogState(() => farmId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: varietyId,
                decoration: InputDecoration(
                    labelText: loc.agriVarietyLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: seasonalVarieties
                    .map<DropdownMenuItem<int>>((v) => DropdownMenuItem(
                        value: v['id'],
                        child: Text(
                            '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}')))
                    .toList(),
                onChanged: (v) => setDialogState(() => varietyId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: season,
                decoration: InputDecoration(
                    labelText: loc.agriSeasonLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: const [
                  DropdownMenuItem(value: 'kharif', child: Text('Kharif')),
                  DropdownMenuItem(value: 'rabi', child: Text('Rabi')),
                  DropdownMenuItem(value: 'summer', child: Text('Summer')),
                ],
                onChanged: (v) => setDialogState(() => season = v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: sowingDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (picked != null) setDialogState(() => sowingDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.agriSowingDateLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(sowingDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.agriAreaSownLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(loc.agriSpacingSectionHeader,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: plantSpacingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriPlantSpacingLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 8),
                _unitDropdown(loc, plantSpacingUnit,
                    (v) => setDialogState(() => plantSpacingUnit = v)),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: rowArrangement,
                decoration: InputDecoration(
                    labelText: loc.agriRowArrangementLabel,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  DropdownMenuItem(
                      value: 'uniform',
                      child: Text(loc.agriArrangementUniform)),
                  DropdownMenuItem(
                      value: 'paired', child: Text(loc.agriArrangementPaired)),
                ],
                onChanged: (v) => setDialogState(() => rowArrangement = v!),
              ),
              const SizedBox(height: 12),
              if (rowArrangement == 'uniform')
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: rowSpacingCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: loc.agriRowSpacingLabel,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _unitDropdown(loc, rowSpacingUnit,
                      (v) => setDialogState(() => rowSpacingUnit = v)),
                ])
              else ...[
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: intraPairCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: loc.agriIntraPairLabel,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _unitDropdown(loc, intraPairUnit,
                      (v) => setDialogState(() => intraPairUnit = v)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: interPairCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: loc.agriInterPairLabel,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _unitDropdown(loc, interPairUnit,
                      (v) => setDialogState(() => interPairUnit = v)),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      final h = await _headers;
                      final res = await http.post(
                        Uri.parse('$baseUrl/agri/sowing-plans'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'farm_id': farmId,
                          'season': season,
                          'crop_variety_id': varietyId,
                          'sowing_date':
                              DateFormat('yyyy-MM-dd').format(sowingDate),
                          'area_sown_acre':
                              double.tryParse(areaCtrl.text.trim()),
                          'plant_to_plant_cm':
                              double.tryParse(plantSpacingCtrl.text.trim()),
                          'plant_to_plant_unit': plantSpacingUnit,
                          'row_arrangement': rowArrangement,
                          if (rowArrangement == 'uniform')
                            'row_to_row_cm':
                                double.tryParse(rowSpacingCtrl.text.trim()),
                          if (rowArrangement == 'uniform')
                            'row_to_row_unit': rowSpacingUnit,
                          if (rowArrangement == 'paired')
                            'intra_pair_distance':
                                double.tryParse(intraPairCtrl.text.trim()),
                          if (rowArrangement == 'paired')
                            'intra_pair_distance_unit': intraPairUnit,
                          if (rowArrangement == 'paired')
                            'inter_pair_distance':
                                double.tryParse(interPairCtrl.text.trim()),
                          if (rowArrangement == 'paired')
                            'inter_pair_distance_unit': interPairUnit,
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 201) {
                        final data = jsonDecode(res.body);
                        _showSnack(loc.agriScheduleGenerated);
                        await _loadAll();
                        if (mounted) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CropCalendarScreen(
                                      cycleType: 'seasonal',
                                      cycleId: data['id'],
                                      title:
                                          '${tl(context, data['crop_variety_name'])} — ${tl(context, data['farm_name'])}')));
                        }
                      } else {
                        final data = jsonDecode(res.body);
                        _showSnack(data['error'] ?? loc.agriFailedSave,
                            isError: true);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrchardCycleDialog() {
    final loc = AppLocalizations.of(context)!;
    int? blockId = orchardBlocks.first['id'];
    int cycleYear = DateTime.now().year;
    final baharCtrl = TextEditingController();
    DateTime? floweringDate;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriAddOrchardCycle,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: blockId,
                decoration: InputDecoration(
                    labelText: loc.agriOrchardBlockLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: orchardBlocks
                    .map<DropdownMenuItem<int>>((b) => DropdownMenuItem(
                        value: b['id'],
                        child: Text(
                            '${tl(context, b['farm_name'])} — ${tl(context, b['crop_variety_name'])}')))
                    .toList(),
                onChanged: (v) => setDialogState(() => blockId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: cycleYear.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: loc.agriCycleYearLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                onChanged: (v) => cycleYear = int.tryParse(v) ?? cycleYear,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baharCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriBaharNameLabel,
                    hintText: 'e.g. ambe, mrig, hasta',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: floweringDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null)
                    setDialogState(() => floweringDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.agriFloweringStartLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(floweringDate != null
                      ? DateFormat('dd MMM yyyy').format(floweringDate!)
                      : '—'),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      final h = await _headers;
                      final res = await http.post(
                        Uri.parse('$baseUrl/agri/orchard-cycles'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'orchard_block_id': blockId,
                          'cycle_year': cycleYear,
                          'bahar_name': baharCtrl.text.trim().isEmpty
                              ? null
                              : baharCtrl.text.trim(),
                          'flowering_start_date': floweringDate != null
                              ? DateFormat('yyyy-MM-dd').format(floweringDate!)
                              : null,
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 201) {
                        final data = jsonDecode(res.body);
                        _showSnack(loc.agriScheduleGenerated);
                        await _loadAll();
                        if (mounted) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CropCalendarScreen(
                                      cycleType: 'orchard',
                                      cycleId: data['id'],
                                      title:
                                          '${tl(context, data['crop_variety_name'])} — ${tl(context, data['farm_name'])}')));
                        }
                      } else {
                        final data = jsonDecode(res.body);
                        _showSnack(data['error'] ?? loc.agriFailedSave,
                            isError: true);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }


  void _openCalendar(String type, dynamic id, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CropCalendarScreen(cycleType: type, cycleId: toInt(id), title: title)),
    ).then((_) => _loadAll());
  }

  Future<void> _showUnassigned() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _UnassignedSheet(items: List.from(unassigned)),
    );
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final q = search.trim().toLowerCase();
    final shown = cycles.where((c) {
      if (c['state'] != state) return false;
      if (q.isEmpty) return true;
      return '${c['crop_name']} ${c['variety_name']} ${c['farm_name']} ${c['season'] ?? ''} ${c['bahar_name'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.agriCyclesTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: idaGreen,
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New crop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _loadAll,
              child: Responsive.constrainedContent(
                context,
                ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  children: [
                    if (loadError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFBE2DF), borderRadius: BorderRadius.circular(10)),
                        child: Text(loadError!, style: const TextStyle(color: cRed)),
                      ),
                    _tiles(),
                    const SizedBox(height: 12),
                    if (isAdmin && unassigned.isNotEmpty) ...[
                      Material(
                        color: const Color(0xFFFFF7EA),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFF3D7A6))),
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded, color: cAmber),
                          title: Text('Work not linked to a crop · ${unassigned.length}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: cAmber, fontSize: 14)),
                          subtitle: const Text('Say which crop each day\'s work was for', style: TextStyle(fontSize: 12.5)),
                          trailing: const Icon(Icons.chevron_right, color: cAmber),
                          onTap: _showUnassigned,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final s in const ['running', 'finished', 'cancelled'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${stateLabel[s]} · ${toInt(counts[s])}'),
                              selected: state == s,
                              selectedColor: const Color(0xFFE3F0DA),
                              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: state == s ? const Color(0xFF2C5E17) : cMuted),
                              onSelected: (_) => setState(() => state = s),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search crop, variety or farm',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cBorder)),
                      ),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 12),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            cycles.isEmpty ? loc.agriNoCyclesYet : q.isNotEmpty ? 'Nothing matches "$search".' : 'No ${stateLabel[state]!.toLowerCase()} crops.',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    for (final c in shown) ...[
                      _card(c),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _tiles() {
    final t = totals;
    Widget tile(String label, String value, String sub, {bool bad = false}) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bad ? const Color(0xFFF1C4BE) : cBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: cMuted, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: bad ? cRed : cDark), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(sub, style: const TextStyle(fontSize: 11.5, color: cMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    final size = [
      if (toInt(t['acres']) > 0 || (double.tryParse('${t['acres']}') ?? 0) > 0) '${t['acres']} acres',
      if (toInt(t['trees']) > 0) '${t['trees']} trees',
    ].join(' · ');
    final hq = double.tryParse('${t['harvest_qtl'] ?? 0}') ?? 0;
    final tiles = [
      tile('Crops running', '${toInt(t['running'])}', size.isEmpty ? '—' : size),
      tile('Jobs overdue', '${toInt(t['overdue'])}',
          toInt(t['overdue']) > 0 ? 'on ${toInt(t['overdue_crops'])} crop${toInt(t['overdue_crops']) == 1 ? '' : 's'}' : 'nothing late',
          bad: toInt(t['overdue']) > 0),
      tile('Jobs next 7 days', '${toInt(t['this_week'])}', 'sprays, fertiliser, pruning'),
      tile('Spent (running)', inr(t['spent']), hq > 0 ? 'Harvested ${qtlText(hq * 100)}' : 'No harvest yet'),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 700 ? 4 : 2;
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in tiles) SizedBox(width: w, child: x)]);
    });
  }

  Widget _card(Map c) {
    final chip = jobsChip(c);
    final nj = nextJobText(c['next_job'] is Map ? c['next_job'] : null);
    final money = Map<String, dynamic>.from(c['money'] ?? {});
    final orchard = c['cycle_type'] == 'orchard';
    final hkg = double.tryParse('${c['harvest_kg'] ?? 0}') ?? 0;
    final per = orchard
        ? (money['per_tree'] != null ? '${inr(money['per_tree'])}/tree' : null)
        : (money['per_acre'] != null ? '${inr(money['per_acre'])}/acre' : null);
    final title = '${tl(context, c['crop_name'] ?? '')} · ${tl(context, c['variety_name'] ?? '')}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openCalendar('${c['cycle_type']}', c['cycle_id'], '$title — ${tl(context, c['farm_name'] ?? '')}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFE3F0DA), borderRadius: BorderRadius.circular(10)),
              child: Icon(orchard ? Icons.park : Icons.grass, color: idaGreen, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(whereText(c), style: const TextStyle(fontSize: 12.5, color: cMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 6),
            Pill(chip.$1, chip.$2, chip.$3),
          ]),
          if (c['state'] == 'cancelled' && c['cancel_reason'] != null) ...[
            const SizedBox(height: 10),
            Text('Cancelled${c['cancelled_at'] != null ? ' ${dayMonth(c['cancelled_at'])}' : ''}: ${c['cancel_reason']}',
                style: const TextStyle(fontSize: 12.5, color: cRed, fontWeight: FontWeight.w600)),
          ],
          if (c['state'] == 'running') ...[
            const SizedBox(height: 12),
            CycleProgress(c),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.event_note, size: 16, color: cMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: nj.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (nj.when.isNotEmpty) TextSpan(text: '  ${nj.when}', style: TextStyle(color: nj.color, fontWeight: FontWeight.w700)),
                  ]),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEEF1EA)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Spent', style: TextStyle(fontSize: 11.5, color: cMuted)),
                Text(inr(money['total']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                if (per != null) Text(per, style: const TextStyle(fontSize: 11.5, color: cMuted)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Harvest', style: TextStyle(fontSize: 11.5, color: cMuted)),
                Text(hkg > 0 ? qtlText(hkg) : '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                if (c['cost_per_qtl'] != null) Text('${inr(c['cost_per_qtl'])}/qtl', style: const TextStyle(fontSize: 11.5, color: cMuted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ]),
      ),
    );
  }
}

// Farm attendance days on farms with more than one crop: say which crop.
class _UnassignedSheet extends StatefulWidget {
  final List items;
  const _UnassignedSheet({required this.items});
  @override
  State<_UnassignedSheet> createState() => _UnassignedSheetState();
}

class _UnassignedSheetState extends State<_UnassignedSheet> {
  late List items = widget.items;
  final Map<String, String> pick = {};
  String? error;

  String keyOf(Map i) => '${i['date']}|${i['farm_id']}|${i['work_type_id']}';

  Future<void> _assign(Map i) async {
    final v = pick[keyOf(i)];
    if (v == null) return;
    final parts = v.split(':');
    setState(() => error = null);
    try {
      await AgriApi.post('/agri/cycles/assign-work', {
        'date': i['date'], 'farm_id': i['farm_id'], 'work_type_id': i['work_type_id'],
        'cycle_type': parts[0], 'cycle_id': parts[1] == 'x' ? null : int.tryParse(parts[1]),
      });
      setState(() => items = items.where((x) => keyOf(x) != keyOf(i)).toList());
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text('Work not linked to a crop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cDark)),
          const SizedBox(height: 4),
          const Text('Farm attendance on farms with more than one crop. Say which crop each day\'s work was for, so its cost counts on that crop. From now on Farm attendance asks this when the work is given.',
              style: TextStyle(fontSize: 13, color: cMuted)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: cRed))),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('All work is linked. Nothing left.', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final i in items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF1EA)))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${dayMonth(i['date'])} · ${i['farm_name']} · ${i['work_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${i['workers']} workers · ${inr(i['cost'])}', style: const TextStyle(fontSize: 12.5, color: cMuted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: pick[keyOf(i)],
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Which crop?', border: OutlineInputBorder(), isDense: true),
                      items: [
                        for (final o in (i['options'] as List? ?? []))
                          DropdownMenuItem(value: '${o['cycle_type']}:${o['cycle_id']}', child: Text('${o['label']}', overflow: TextOverflow.ellipsis)),
                        const DropdownMenuItem(value: 'none:x', child: Text('General farm work (no crop)')),
                      ],
                      onChanged: (v) => setState(() => pick[keyOf(i)] = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (pick[keyOf(i)] ?? '').isEmpty ? null : () => _assign(i),
                    style: FilledButton.styleFrom(backgroundColor: cGreen, minimumSize: const Size(72, 46)),
                    child: const Text('Save'),
                  ),
                ]),
              ]),
            ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Done')),
        ],
      ),
    );
  }
}
