// lib/screens/crop_calendar_screen.dart
//
// The "planned vs actual" timeline for one cycle (sowing plan or
// orchard cycle). Sections, in order:
//   OVERDUE      - status='overdue'
//   UPCOMING     - status='pending', planned_date known
//   NOT YET SCHEDULED - status='pending', planned_date=null (DAPREV
//                  items waiting on a predecessor's actual_date —
//                  real rows, just not due in a meaningful sense yet)
//   DONE         - status='done', shows delay vs planned
//   SKIPPED      - status='skipped', shows remarks
//
// Tapping any actionable item (overdue/pending, scheduled or not)
// opens a sheet: Mark Complete (asks when it was actually done,
// pre-fills product/dose from the template, calls POST
// actual-operations with schedule_item_id — this is what triggers
// the cascade) or Skip (asks for optional remarks, calls PATCH
// .../skip). Skip is available even on Not Yet Scheduled items —
// deciding not to do something doesn't require knowing when it
// would've been due.
//
// Sep 2026 (group C): summary tiles (stage, jobs, inputs, labour,
// harvest in quintals, spent), Jobs / Labour / Harvest tabs, Record
// labour and Record harvest (kg) sheets from agri/cycle_common.dart,
// and the ⋮ menu: Mark finished, Cancel (admin, reason needed), Make
// running again (admin). A finished or cancelled crop shows a banner.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../services/responsive.dart';

import 'agronomy/agronomy_common.dart' show fmtQty, trimNum, toD, KindChip, SmallChip, mainKind, AgriApi;
import 'agronomy/record_spray_screen.dart';
import 'agri/cycle_common.dart';
class CropCalendarScreen extends StatefulWidget {
  final String cycleType; // 'seasonal' | 'orchard'
  final int cycleId;
  final String title;
  const CropCalendarScreen(
      {super.key,
      required this.cycleType,
      required this.cycleId,
      required this.title});

  @override
  State<CropCalendarScreen> createState() => _CropCalendarScreenState();
}

class _CropCalendarScreenState extends State<CropCalendarScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  List items = [];
  List workers = [];
  bool loading = true;
  // Sep 2026 (group C): summary, labour and harvest tabs.
  Map? sum;
  Map? labour;
  List harvest = [];
  String tab = 'jobs';
  bool isAdmin = false;
  // Crop planning ('agri') levels - the same rules the server applies:
  // record = Add, correct = Update, delete = Delete, finish = Update,
  // cancel / restore a cycle = Reopen (admin always has all of them).
  bool mayAddAgri = false;
  bool mayUpdateAgri = false;
  bool mayDeleteAgri = false;
  bool mayReopenAgri = false;
  bool get mayOpenEntry => mayUpdateAgri || mayDeleteAgri;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (items.isEmpty) setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    isAdmin = prefs.getBool('is_admin') ?? (prefs.getString('role') == 'admin');
    mayAddAgri = await ApiService.canAdd('agri');
    mayUpdateAgri = await ApiService.canUpdate('agri');
    mayDeleteAgri = await ApiService.canDelete('agri');
    mayReopenAgri = await ApiService.canReopen('agri');
    final base = '/agri/cycles/${widget.cycleType}/${widget.cycleId}';
    try {
      final results = await Future.wait([
        Api.get('$base/schedule'),
        Api.get('/farm-workers'),
      ]);
      if (results[0].statusCode == 200) {
        final d = jsonDecode(results[0].body);
        items = d is List ? d : (d?['data'] ?? []);
      }
      if (results[1].statusCode == 200) {
        workers = jsonDecode(results[1].body);
        workers.sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
    // Summary, labour and harvest (Sep 2026).
    await Future.wait([
      AgriApi.get(base).then((v) => sum = v is Map ? v : null).catchError((_) => null),
      AgriApi.get('$base/labour').then((v) => labour = v is Map ? v : null).catchError((_) => null),
      AgriApi.get('/agri/harvest-records?cycle_type=${widget.cycleType}&cycle_id=${widget.cycleId}&limit=200')
          .then((v) => harvest = (v is Map ? v['data'] : v) as List? ?? [])
          .catchError((_) => <dynamic>[]),
    ]);
    if (mounted) setState(() => loading = false);
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

  Map? _predecessorOf(Map item) {
    final seq = item['sequence_order'];
    if (seq == null) return null;
    try {
      return items.firstWhere(
          (i) => i['sequence_order'] == seq - 1 && i['source_type'] != 'stage');
    } catch (_) {
      return null;
    }
  }

  void _showActionSheet(Map item) {
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(tl(context, item['label'] ?? ''),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: idaGreen),
            title: Text(loc.agriMarkComplete),
            onTap: () {
              Navigator.pop(context);
              _markDone(item);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.orange),
            title: Text(loc.agriSkipAction),
            onTap: () {
              Navigator.pop(context);
              _showSkipDialog(item);
            },
          ),
        ]),
      ),
    );
  }

  // Step number of a spray / pruning item, in plan order.
  int? _stepNo(Map item) {
    final list = items.where((i) => i['source_type'] != 'stage').toList()
      ..sort((a, b) => ((a['sequence_order'] ?? 0) as num).compareTo((b['sequence_order'] ?? 0) as num));
    final i = list.indexWhere((x) => x['id'] == item['id']);
    return i < 0 ? null : i + 1;
  }

  // Spray steps with products from the Products list open the full
  // "Mark done" screen (brand used, recommended vs actual per product);
  // everything else keeps the short dialog.
  Future<void> _markDone(Map item) async {
    final prods = (item['products'] as List?) ?? [];
    if (item['source_type'] == 'spray' && prods.isNotEmpty) {
      final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => RecordSprayScreen(
                  item: item, stepNo: _stepNo(item), cycleType: widget.cycleType, cycleId: widget.cycleId, workers: workers)));
      if (saved == true) {
        _load();
        if (mounted) _showSnack(AppLocalizations.of(context)!.agriSaved);
      }
      return;
    }
    _showCompleteDialog(item);
  }

  void _showCompleteDialog(Map item) {
    final loc = AppLocalizations.of(context)!;
    DateTime operationDate = DateTime.now();
    final productCtrl = TextEditingController(text: item['label'] ?? '');
    final dose = widget.cycleType == 'seasonal'
        ? item['dose_per_acre']
        : item['dose_per_tree'];
    final doseCtrl = TextEditingController(text: dose?.toString() ?? '');
    final doseUnitCtrl = TextEditingController(text: item['dose_unit'] ?? '');
    final costCtrl = TextEditingController();
    int? workerId;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriMarkComplete,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: operationDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (picked != null)
                    setDialogState(() => operationDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.agriOperationDateLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(operationDate)),
                ),
              ),
              if (item['source_type'] != 'stage') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: productCtrl,
                  decoration: InputDecoration(
                      labelText: 'Product used',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: doseCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Dose applied',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: doseUnitCtrl,
                      decoration: InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.agriCostLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: workerId,
                decoration: InputDecoration(
                    labelText: loc.agriWorkerLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: workers
                    .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                        value: w['id'], child: Text(tl(context, w['name']))))
                    .toList(),
                onChanged: (v) => setDialogState(() => workerId = v),
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
                      final res = await Api.post(
                        '/agri/actual-operations',
                        body: {
                          'cycle_type': widget.cycleType,
                          'cycle_id': widget.cycleId,
                          'operation_date':
                              DateFormat('yyyy-MM-dd').format(operationDate),
                          'activity_type':
                              item['activity_type'] ?? item['source_type'],
                          'product_used': productCtrl.text.trim().isEmpty
                              ? null
                              : productCtrl.text.trim(),
                          'dose_applied': double.tryParse(doseCtrl.text.trim()),
                          'dose_unit': doseUnitCtrl.text.trim().isEmpty
                              ? null
                              : doseUnitCtrl.text.trim(),
                          'cost': double.tryParse(costCtrl.text.trim()) ?? 0,
                          'worker_id': workerId,
                          'schedule_item_id': item['id'],
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        _load();
                        _showSnack(loc.agriSaved);
                      } else {
                        _showSnack(Api.responseError(res), isError: true);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.agriMarkComplete,
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSkipDialog(Map item) {
    final loc = AppLocalizations.of(context)!;
    final remarksCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriSkipAction,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: TextField(
            controller: remarksCtrl,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: loc.agriSkipRemarksLabel,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      final res = await Api.patch(
                        '/agri/cycle-schedule-items/${item['id']}/skip',
                        body: {
                          'remarks': remarksCtrl.text.trim().isEmpty
                              ? null
                              : remarksCtrl.text.trim()
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200) {
                        _load();
                        _showSnack(loc.agriSkipAction);
                      } else {
                        _showSnack(Api.responseError(res), isError: true);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.agriSkipAction,
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
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

  Future<void> _showAddIntercropDialog() async {
    final loc = AppLocalizations.of(context)!;
    final res = await Api.get('/agri/crop-varieties?crop_type=seasonal');
    if (res.statusCode != 200) {
      _showSnack(loc.agriFailedSave, isError: true);
      return;
    }
    final varieties = List<Map<String, dynamic>>.from(jsonDecode(res.body));
    if (varieties.isEmpty) return;
    if (!mounted) return;

    int? varietyId = varieties.first['id'];
    DateTime sowingDate = DateTime.now();
    final mainRowsCtrl = TextEditingController();
    final intercropRowsCtrl = TextEditingController();
    final rowSpacingCtrl = TextEditingController();
    String rowSpacingUnit = 'cm';
    final plantSpacingCtrl = TextEditingController();
    String plantSpacingUnit = 'cm';
    final sharedAreaCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriAddIntercropTitle,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.agriIntercropHint,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: varietyId,
                    decoration: InputDecoration(
                        labelText: loc.agriIntercropVarietyLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: varieties
                        .map<DropdownMenuItem<int>>((v) => DropdownMenuItem(
                            value: v['id'],
                            child: Text(
                                '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}')))
                        .toList(),
                    onChanged: (v) => setDialogState(() => varietyId = v),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: ctx,
                          initialDate: sowingDate,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 30)));
                      if (picked != null)
                        setDialogState(() => sowingDate = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                          labelText: loc.agriSowingDateLabel,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: Text(DateFormat('dd MMM yyyy').format(sowingDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: mainRowsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: loc.agriMainRowsPerCycleLabel,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: intercropRowsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: loc.agriIntercropRowsPerCycleLabel,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: rowSpacingCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: plantSpacingCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                  TextField(
                    controller: sharedAreaCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriSharedAreaLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
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
                      final res2 = await Api.post(
                        '/agri/sowing-plans/${widget.cycleId}/add-intercrop',
                        body: {
                          'crop_variety_id': varietyId,
                          'sowing_date':
                              DateFormat('yyyy-MM-dd').format(sowingDate),
                          'main_rows_per_cycle':
                              int.tryParse(mainRowsCtrl.text.trim()),
                          'rows_per_cycle':
                              int.tryParse(intercropRowsCtrl.text.trim()),
                          'row_to_row_cm':
                              double.tryParse(rowSpacingCtrl.text.trim()),
                          'row_to_row_unit': rowSpacingUnit,
                          'plant_to_plant_cm':
                              double.tryParse(plantSpacingCtrl.text.trim()),
                          'plant_to_plant_unit': plantSpacingUnit,
                          'shared_physical_area_acre':
                              double.tryParse(sharedAreaCtrl.text.trim()),
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res2.statusCode == 201) {
                        _showSnack(loc.agriIntercropAddedMsg);
                      } else {
                        _showSnack(Api.responseError(res2), isError: true);
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

  Future<void> _changeState(String action, String done) async {
    try {
      await AgriApi.post('/agri/cycles/${widget.cycleType}/${widget.cycleId}/$action', {});
      _showSnack(done);
      _load();
    } catch (e) {
      _showSnack(Api.errorText(e), isError: true);
    }
  }

  Future<void> _menu(String v) async {
    final s = sum;
    if (s == null) return;
    final name = '${s['crop_name'] ?? 'This crop'} on ${s['farm_name'] ?? ''}';
    if (v == 'intercrop') {
      _showAddIntercropDialog();
    } else if (v == 'finish') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Mark $name as finished?'),
          content: const Text('Its records stay. It moves to the Finished list and its cost per quintal is worked out.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: cGreen), child: const Text('Mark finished')),
          ],
        ),
      );
      if (ok == true) _changeState('finish', '$name marked finished.');
    } else if (v == 'cancel') {
      final ok = await showCancelCycleSheet(context, s);
      if (ok == true) {
        _showSnack('$name cancelled. Its records are kept.');
        _load();
      }
    } else if (v == 'restore') {
      _changeState('restore', '$name is running again.');
    }
  }

  Future<void> _labour([Map? row]) async {
    if (sum == null) return;
    final ok = await showLabourSheet(context, cycle: sum!, entry: row, canDelete: mayDeleteAgri, canSave: row == null || mayUpdateAgri);
    if (ok == true) {
      setState(() => tab = 'labour');
      _load();
    }
  }

  Future<void> _harvest([Map? row]) async {
    if (sum == null) return;
    final ok = await showHarvestSheet(context, cycle: sum!, record: row, canDelete: mayDeleteAgri, canSave: row == null || mayUpdateAgri);
    if (ok == true) {
      setState(() => tab = 'harvest');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final overdue = items.where((i) => i['status'] == 'overdue').toList();
    final upcoming = items
        .where((i) => i['status'] == 'pending' && i['planned_date'] != null)
        .toList();
    final notScheduled = items
        .where((i) => i['status'] == 'pending' && i['planned_date'] == null)
        .toList();
    final done = items.where((i) => i['status'] == 'done').toList();
    final skipped = items.where((i) => i['status'] == 'skipped').toList();
    final s = sum;
    final st = '${s?['state'] ?? 'running'}';
    final labourRows = (labour?['rows'] as List?) ?? [];
    final jobCount = items.where((i) => i['source_type'] != 'stage').length;

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
        actions: [
          if (s != null)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (widget.cycleType == 'seasonal' && st == 'running' && mayAddAgri)
                  PopupMenuItem(value: 'intercrop', child: Text(loc.agriAddIntercropButton)),
                if (st == 'running' && mayUpdateAgri) const PopupMenuItem(value: 'finish', child: Text('Mark finished')),
                if (st == 'running' && mayReopenAgri)
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel this cycle', style: TextStyle(color: cRed))),
                if (st != 'running' && mayReopenAgri) const PopupMenuItem(value: 'restore', child: Text('Make running again')),
              ],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: Responsive.constrainedContent(
                  context,
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      if (s != null && st != 'running')
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: st == 'cancelled' ? const Color(0xFFFDF1EF) : const Color(0xFFF6F8F3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: st == 'cancelled' ? const Color(0xFFF0C4BE) : cBorder),
                          ),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: '${stateLabel[st]}. ', style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (st == 'cancelled') TextSpan(text: 'Reason: ${s['cancel_reason'] ?? '—'}. '),
                            TextSpan(text: 'Its records are kept.${mayReopenAgri ? ' It can be made running again from the ⋮ menu.' : ''}'),
                          ]), style: const TextStyle(fontSize: 13.5)),
                        ),
                      if (s != null) ...[
                        _tiles(s),
                        const SizedBox(height: 12),
                      ],
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'jobs', label: Text('Jobs $jobCount', style: const TextStyle(fontSize: 13))),
                          ButtonSegment(value: 'labour', label: Text('Labour ${labourRows.length}', style: const TextStyle(fontSize: 13))),
                          ButtonSegment(value: 'harvest', label: Text('Harvest ${harvest.length}', style: const TextStyle(fontSize: 13))),
                        ],
                        selected: {tab},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) => setState(() => tab = v.first),
                      ),
                      if (s != null && st != 'cancelled' && mayAddAgri) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _harvest(),
                              icon: const Icon(Icons.shopping_basket_outlined, size: 18),
                              label: const Text('Record harvest'),
                              style: OutlinedButton.styleFrom(foregroundColor: cDark, minimumSize: const Size.fromHeight(44)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _labour(),
                              icon: const Icon(Icons.people_outline, size: 18),
                              label: const Text('Record labour'),
                              style: OutlinedButton.styleFrom(foregroundColor: cDark, minimumSize: const Size.fromHeight(44)),
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 14),
                      if (tab == 'labour') _labourTab(labourRows),
                      if (tab == 'harvest') _harvestTab(),
                      if (tab == 'jobs') ...[
                        if (overdue.isNotEmpty)
                          _section(
                              loc.agriOverdueSection,
                              Colors.red,
                              overdue
                                  .map((i) => _itemCard(i,
                                      actionable: st == 'running', color: Colors.red))
                                  .toList()),
                        if (upcoming.isNotEmpty)
                          _section(
                              loc.agriPendingSection,
                              idaGreen,
                              upcoming
                                  .map((i) => _itemCard(i,
                                      actionable: st == 'running', color: idaGreen))
                                  .toList()),
                        if (notScheduled.isNotEmpty)
                          _section(
                              loc.agriNotScheduledSection,
                              Colors.grey,
                              notScheduled
                                  .map((i) => _itemCard(i,
                                      actionable: st == 'running',
                                      color: Colors.grey,
                                      notScheduled: true))
                                  .toList()),
                        if (done.isNotEmpty)
                          _section(
                              loc.agriDoneSection,
                              idaGreen,
                              done
                                  .map((i) => _itemCard(i,
                                      actionable: false, color: idaGreen))
                                  .toList()),
                        if (skipped.isNotEmpty)
                          _section(
                              loc.agriSkippedSection,
                              Colors.grey,
                              skipped
                                  .map((i) => _itemCard(i,
                                      actionable: false, color: Colors.grey))
                                  .toList()),
                        if (items.isEmpty)
                          Padding(
                              padding: const EdgeInsets.all(40),
                              child: Center(
                                  child: Text('No schedule items',
                                      style: TextStyle(
                                          color: Colors.grey.shade500)))),
                      ],
                    ],
                  )),
            ),
    );
  }

  Widget _tiles(Map s) {
    final jobs = Map<String, dynamic>.from(s['jobs'] ?? {});
    final money = Map<String, dynamic>.from(s['money'] ?? {});
    final hkg = double.tryParse('${s['harvest_kg'] ?? 0}') ?? 0;
    final day = s['day'];
    Widget tile(String label, String value, String sub, {bool bad = false}) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bad ? const Color(0xFFF1C4BE) : cBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: cMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: bad ? cRed : cDark), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(sub, style: const TextStyle(fontSize: 11.5, color: cMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    final nextStage = s['next_stage'] is Map ? s['next_stage'] : null;
    final tiles = [
      tile('Stage', '${(s['stage'] is Map ? s['stage']['name'] : null) ?? '—'}',
          day != null ? 'Day $day${toInt(s['days_to_harvest']) > 0 ? ' of ${s['days_to_harvest']}' : ''}' : ''),
      tile('Jobs', '${toInt(jobs['done'])} done',
          toInt(jobs['overdue']) > 0 ? '${jobs['overdue']} overdue · ${toInt(jobs['coming'])} coming' : '${toInt(jobs['coming'])} coming',
          bad: toInt(jobs['overdue']) > 0),
      tile('Inputs', inr(money['inputs']), 'sprays, fertiliser'),
      tile('Labour', inr(money['labour']), labour != null ? '${toInt(labour!['worker_days'])} worker-days from attendance' : ''),
      tile('Harvest', hkg > 0 ? qtlText(hkg) : 'None yet',
          s['cost_per_qtl'] != null
              ? '${inr(s['cost_per_qtl'])} a quintal'
              : nextStage != null ? '${nextStage['name']} ~${dayMonth(nextStage['date'])}' : ''),
      tile('Spent', inr(money['total']),
          money['per_acre'] != null ? '${inr(money['per_acre'])} an acre' : money['per_tree'] != null ? '${inr(money['per_tree'])} a tree' : ''),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 700 ? 3 : 2;
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in tiles) SizedBox(width: w, child: x)]);
    });
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cBorder)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cBorder)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: cMuted, fontSize: 13.5)),
      );

  static const _paid = {'piece_rate': 'By kg', 'contract': 'Fixed amount', 'daily': 'By the day'};

  Widget _labourTab(List rows) {
    if (labour == null) return _empty('Could not load labour. Pull down to try again.');
    if (rows.isEmpty) {
      return _empty('No labour yet. Daily workers show here once Farm attendance gives them work on this crop; record picking or contract work with Record labour.');
    }
    return _card([
      for (final r in rows)
        InkWell(
          onTap: r['source'] == 'entry' && mayOpenEntry ? () => _labour(Map.from(r)) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1EA)))),
            child: Row(children: [
              SizedBox(width: 52, child: Text(dayMonth(r['date']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${r['work']} · ${r['source'] == 'attendance' ? '${r['workers']} worker${toInt(r['workers']) == 1 ? '' : 's'}' : '${r['who'] ?? ''}${r['workers_count'] != null ? ' (${r['workers_count']} people)' : ''}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    r['source'] == 'attendance'
                        ? 'Farm attendance${r['allocation_status'] != null && r['allocation_status'] != 'approved' ? ' · waiting for approval' : ''}'
                        : r['payment_mode'] == 'piece_rate'
                            ? '${_paid['piece_rate']} · ${kgText(r['quantity_harvested_kg'])} × ${inr(r['rate_applied_per_kg'])}'
                            : r['payment_mode'] == 'daily'
                                ? '${_paid['daily']} · ${r['days_worked']} × ${inr(r['daily_wage_amount'])}'
                                : '${_paid['contract']}',
                    style: const TextStyle(fontSize: 12, color: cMuted),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Text(inr(r['cost']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ]),
          ),
        ),
      Container(
        color: const Color(0xFFFAFBF8),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Total', style: TextStyle(fontWeight: FontWeight.w800)),
              if (toInt(labour!['from_attendance']) > 0)
                TextSpan(text: ' · ${inr(labour!['from_attendance'])} from Farm attendance', style: const TextStyle(color: cMuted, fontSize: 12.5)),
            ])),
          ),
          Text(inr(labour!['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      ),
      if (mayOpenEntry)
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Text('Tap a piece-rate or contract entry to correct or delete it. Attendance work is changed in Farm attendance.', style: TextStyle(fontSize: 12, color: cMuted)),
        ),
    ]);
  }

  Widget _harvestTab() {
    if (harvest.isEmpty) return _empty('No harvest recorded yet.');
    final total = harvest.fold<double>(0, (a, r) => a + (double.tryParse('${r['quantity_kg'] ?? 0}') ?? 0));
    return _card([
      for (final r in harvest)
        InkWell(
          onTap: mayOpenEntry ? () => _harvest(Map.from(r)) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1EA)))),
            child: Row(children: [
              SizedBox(width: 52, child: Text(dayMonth(r['harvest_date']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kgText(r['quantity_kg']), style: const TextStyle(fontSize: 13.5)),
                  Text(
                    [if ('${r['quality_grade'] ?? ''}'.isNotEmpty) 'Grade ${r['quality_grade']}', if ('${r['remarks'] ?? ''}'.isNotEmpty) '${r['remarks']}'].join(' · '),
                    style: const TextStyle(fontSize: 12, color: cMuted), maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              Text(qtlText(r['quantity_kg']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
          ),
        ),
      Container(
        color: const Color(0xFFFAFBF8),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
          Text('${kgText(total)}  ·  ', style: const TextStyle(color: cMuted)),
          Text(qtlText(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      ),
      if (mayOpenEntry)
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Text('Tap a record to correct or delete it.', style: TextStyle(fontSize: 12, color: cMuted)),
        ),
    ]);
  }

  Widget _section(String title, Color color, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _itemCard(Map item,
      {required bool actionable,
      required Color color,
      bool notScheduled = false}) {
    final loc = AppLocalizations.of(context)!;
    final predecessor = notScheduled ? _predecessorOf(item) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
      child: InkWell(
        onTap: actionable ? () => _showActionSheet(item) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                item['source_type'] == 'stage'
                    ? Icons.local_florist_outlined
                    : Icons.water_drop_outlined,
                size: 16,
                color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tl(context, item['label'] ?? ''),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1)),
            if (item['status'] == 'done' && item['delay_days'] != null)
              Text(
                item['delay_days'] > 0
                    ? '+${item['delay_days']} ${loc.agriDelayDays}'
                    : item['delay_days'] < 0
                        ? '${-item['delay_days']} ${loc.agriEarlyDays}'
                        : loc.agriOnTime,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: item['delay_days'] > 0 ? Colors.orange : idaGreen),
              ),
          ]),
          const SizedBox(height: 4),
          if (notScheduled)
            Text(
              predecessor != null
                  ? '${loc.agriWaitingOn}: ${tl(context, predecessor['label'] ?? '')}'
                  : loc.agriNotScheduledSection,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic),
            )
          else if (item['status'] == 'done')
            Text(
                'Planned ${item['planned_date']} · Done ${item['actual_date']}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))
          else if (item['status'] == 'skipped')
            Text(item['remarks'] ?? '—',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic))
          else
            Text('Due ${item['planned_date']}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ..._productLines(item),
          if (item['weather_advisory'] != null &&
              item['weather_advisory']['message'] != null)
            _weatherAdvisoryBadge(item['weather_advisory'],
                isOverdue: item['status'] == 'overdue'),
        ]),
      ),
    );
  }

  // Products of a spray step with the recommended quantity for this
  // field, or — once done — what was recorded (actual of recommended).
  List<Widget> _productLines(Map item) {
    final perTree = item['basis'] == 'tree';
    final rec = item['recorded'] as Map?;
    final prods = (item['products'] as List?) ?? [];
    final out = <Widget>[];
    if (rec != null && ((rec['products'] as List?) ?? []).isNotEmpty) {
      final area = rec['area_covered_acre'] != null
          ? ' · ${trimNum(toD(rec['area_covered_acre']))} acres'
          : rec['trees_covered'] != null
              ? ' · ${rec['trees_covered']} trees'
              : '';
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text('Recorded$area', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
      ));
      for (final p in rec['products'] as List) {
        final r = toD(p['recommended_qty']);
        final a = toD(p['actual_qty']) ?? 0;
        final pct = r != null && r > 0 ? (a - r) / r * 100 : null;
        out.add(Row(children: [
          Expanded(
            child: Text('${p['name']}${p['brand_name'] != null ? ' · ${p['brand_name']}' : ''}',
                style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          Text('${fmtQty(a, p['unit'] ?? 'ml')} of ${fmtQty(r, p['unit'] ?? 'ml')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (pct != null && pct.abs() >= 0.5) ...[
            const SizedBox(width: 6),
            SmallChip('${pct.abs().round()}% ${pct > 0 ? 'more' : 'less'}',
                bg: pct > 0 ? const Color(0xFFFDE6D2) : const Color(0xFFDDE9F7),
                fg: pct > 0 ? const Color(0xFF8C3F06) : const Color(0xFF1D4D86)),
          ],
        ]));
      }
      return out;
    }
    if (item['source_type'] != 'spray' || prods.isEmpty) return out;
    out.add(Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(spacing: 4, children: [
        KindChip(mainKind({...item, 'products': prods})),
        if (prods.length > 1) const SmallChip('Tank mix'),
      ]),
    ));
    for (final p in prods) {
      out.add(Row(children: [
        Expanded(
          child: Text('${p['name']} · ${p['preferred_brand_name'] ?? 'no brand'}',
              style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        ),
        Text('${trimNum(toD(p['dose']), 3)} ${p['unit']}/${perTree ? 'tree' : 'acre'} → ${fmtQty(toD(p['recommended_qty']), p['unit'] ?? 'ml')}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]));
    }
    return out;
  }

  Widget _weatherAdvisoryBadge(Map advisory, {required bool isOverdue}) {
    final status = advisory['status'] as String?;
    final favorable = status == 'favorable';
    // Overdue + rain coming gets the most attention-grabbing treatment
    // of the three states - it's the one situation that's both urgent
    // AND working against you, per the explicit design decision that
    // this deserves a more urgent tone than upcoming-with-rain.
    final urgent = !favorable && isOverdue;
    final bg = favorable
        ? const Color(0xFFE8F5E2)
        : (urgent ? const Color(0xFFFDE8E8) : const Color(0xFFFEF3DC));
    final fg = favorable
        ? idaGreen
        : (urgent ? const Color(0xFFC0392B) : const Color(0xFF92600A));
    final icon =
        favorable ? Icons.wb_sunny_outlined : Icons.water_drop_outlined;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(advisory['message'],
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
          ),
        ]),
      ),
    );
  }
}
