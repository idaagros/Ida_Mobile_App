// lib/screens/crop_cycles_screen.dart
//
// Entry point into the transaction side of Crop Planning: lists every
// sowing plan (seasonal) and orchard cycle (perennial) across all
// farms, newest first. Tap one to open its Crop Calendar. "+" creates
// either type — POST for both auto-generates the schedule server-side
// (see agriScheduleService.js), which is why creation here always
// navigates straight into the calendar afterward rather than just
// closing a dialog.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crop_calendar_screen.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';

class CropCyclesScreen extends StatefulWidget {
  const CropCyclesScreen({super.key});
  @override
  State<CropCyclesScreen> createState() => _CropCyclesScreenState();
}

class _CropCyclesScreenState extends State<CropCyclesScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List sowingPlans = [];
  List orchardCycles = [];
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
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/agri/sowing-plans'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/orchard-cycles'), headers: h),
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/crop-varieties'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/orchard-blocks'), headers: h),
      ]);
      if (results[0].statusCode == 200)
        sowingPlans = jsonDecode(results[0].body)['data'] ?? [];
      if (results[1].statusCode == 200)
        orchardCycles = jsonDecode(results[1].body)['data'] ?? [];
      if (results[2].statusCode == 200) farms = jsonDecode(results[2].body);
      if (results[3].statusCode == 200) {
        final all = jsonDecode(results[3].body);
        seasonalVarieties =
            all.where((v) => v['crop_type'] == 'seasonal').toList();
      }
      if (results[4].statusCode == 200)
        orchardBlocks = jsonDecode(results[4].body)['data'] ?? [];
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final combined = [
      ...sowingPlans
          .map((p) => {...p, '_type': 'seasonal', '_date': p['sowing_date']}),
      ...orchardCycles.map((c) => {
            ...c,
            '_type': 'orchard',
            '_date': c['flowering_start_date'] ?? '${c['cycle_year']}-01-01'
          }),
    ]..sort((a, b) => (b['_date'] ?? '').compareTo(a['_date'] ?? ''));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.agriCyclesTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: _showAddMenu,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _loadAll,
              child: combined.isEmpty
                  ? ListView(children: [
                      Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                              child: Text(loc.agriNoCyclesYet,
                                  style:
                                      TextStyle(color: Colors.grey.shade500))))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: combined.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = combined[i];
                        final isSeasonal = c['_type'] == 'seasonal';
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CropCalendarScreen(
                                      cycleType: c['_type'],
                                      cycleId: c['id'],
                                      title:
                                          '${tl(context, c['crop_variety_name'])} — ${tl(context, c['farm_name'])}',
                                    )),
                          ).then((_) => _loadAll()),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0xFFE0E7D8))),
                            child: Row(children: [
                              Icon(isSeasonal ? Icons.grass : Icons.park,
                                  color: idaGreen, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${tl(context, c['crop_variety_name'])} — ${tl(context, c['farm_name'])}',
                                          style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1),
                                      const SizedBox(height: 3),
                                      Text(
                                        isSeasonal
                                            ? '${c['season']} · sown ${c['sowing_date']}'
                                            : 'Cycle ${c['cycle_year']}${c['bahar_name'] != null ? ' · ${c['bahar_name']}' : ''}',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600),
                                      ),
                                    ]),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.grey, size: 20),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
