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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

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
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List items = [];
  List workers = [];
  bool loading = true;
  // Only populated for cycleType='seasonal' plans with
  // row_arrangement='sequence' - the current pattern-line sequence,
  // for display and as the pre-populated starting point when editing.
  Map<String, dynamic>? mainPlanDetails;
  List patternLines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(
            Uri.parse(
                '$baseUrl/agri/cycles/${widget.cycleType}/${widget.cycleId}/schedule'),
            headers: h),
        http.get(Uri.parse('$baseUrl/farm-workers'), headers: h),
        // Pattern lines only apply to seasonal sowing plans, not
        // orchard cycles - agri_sowing_pattern_lines has no orchard
        // equivalent. Fetching unconditionally for seasonal and
        // simply showing nothing if row_arrangement isn't 'sequence'.
        if (widget.cycleType == 'seasonal')
          http.get(Uri.parse('$baseUrl/agri/sowing-plans/${widget.cycleId}'),
              headers: h),
        if (widget.cycleType == 'seasonal')
          http.get(
              Uri.parse(
                  '$baseUrl/agri/sowing-plans/${widget.cycleId}/pattern-lines'),
              headers: h),
      ]);
      if (results[0].statusCode == 200) items = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) {
        workers = jsonDecode(results[1].body);
        workers.sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }
      if (widget.cycleType == 'seasonal') {
        if (results[2].statusCode == 200) {
          mainPlanDetails = jsonDecode(results[2].body);
        }
        if (results[3].statusCode == 200) {
          patternLines = jsonDecode(results[3].body)['lines'] ?? [];
        }
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
              _showCompleteDialog(item);
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

  Future<void> _showCompleteDialog(Map item) async {
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

    // Brands already on file for this item's compound (item['label']
    // holds the compound name, e.g. "Pendimethalin 38.7% CS" - see
    // SELECT_BASE in cycleScheduleItems.js). Fetched once, before the
    // dialog opens - not the earlier typeahead-as-you-type approach,
    // since the compound is already known here, there's nothing to
    // search for.
    List<Map<String, dynamic>> knownBrands = [];
    if (item['source_type'] == 'spray' || item['source_type'] == 'pruning') {
      try {
        final h = await _headers;
        final res = await http.get(
          Uri.parse(
              '$baseUrl/agri/product-brands/for-compound/${Uri.encodeComponent(item['label'] ?? '')}'),
          headers: h,
        );
        if (res.statusCode == 200) {
          knownBrands = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        }
      } catch (_) {
        // A failed brand lookup shouldn't block marking the spray
        // complete - falls through to manual entry either way.
      }
    }
    // null = manual entry (the productCtrl TextField is shown/used).
    // A real value = one of knownBrands was picked from the dropdown.
    String? selectedBrand = null;

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
                if (knownBrands.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: selectedBrand,
                    decoration: InputDecoration(
                        labelText: 'Brand sprayed',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: [
                      ...knownBrands.map((b) => DropdownMenuItem<String?>(
                          value: b['brand_name'],
                          child: Text(b['brand_name'],
                              overflow: TextOverflow.ellipsis))),
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Other (enter manually)'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() {
                      selectedBrand = v;
                      if (v != null) productCtrl.text = v;
                    }),
                  ),
                  if (selectedBrand == null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: productCtrl,
                      decoration: InputDecoration(
                          labelText: 'Product used',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                  ],
                ] else
                  // No brands on file yet for this compound - straight
                  // to manual entry, same as before this change.
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
                      final h = await _headers;
                      final res = await http.post(
                        Uri.parse('$baseUrl/agri/actual-operations'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({
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
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        _load();
                        _showSnack(loc.agriSaved);
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
                      final h = await _headers;
                      final res = await http.patch(
                        Uri.parse(
                            '$baseUrl/agri/cycle-schedule-items/${item['id']}/skip'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'remarks': remarksCtrl.text.trim().isEmpty
                              ? null
                              : remarksCtrl.text.trim()
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200) {
                        _load();
                        _showSnack(loc.agriSkipAction);
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
                  : Text(loc.agriSkipAction,
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogLaborDialog() {
    final loc = AppLocalizations.of(context)!;
    int? workerId = workers.isNotEmpty ? workers.first['id'] : null;
    DateTime entryDate = DateTime.now();
    String paymentMode = 'daily';
    final activityCtrl = TextEditingController();
    final daysCtrl = TextEditingController();
    final wageCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double computed = 0;
          if (paymentMode == 'daily') {
            computed = (double.tryParse(daysCtrl.text) ?? 0) *
                (double.tryParse(wageCtrl.text) ?? 0);
          } else {
            computed = (double.tryParse(qtyCtrl.text) ?? 0) *
                (double.tryParse(rateCtrl.text) ?? 0);
          }
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(loc.agriLogLabor,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: ctx,
                        initialDate: entryDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now());
                    if (picked != null)
                      setDialogState(() => entryDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: loc.agriOperationDateLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: Text(DateFormat('dd MMM yyyy').format(entryDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: activityCtrl,
                  decoration: InputDecoration(
                      labelText: 'Activity (e.g. weeding, harvesting)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMode,
                  decoration: InputDecoration(
                      labelText: loc.agriPaymentModeLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: [
                    DropdownMenuItem(
                        value: 'daily', child: Text(loc.agriDaily)),
                    DropdownMenuItem(
                        value: 'piece_rate', child: Text(loc.agriPieceRate)),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMode = v!),
                ),
                const SizedBox(height: 12),
                if (paymentMode == 'daily') ...[
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: daysCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: loc.agriDaysWorkedLabel,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onChanged: (_) => setDialogState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: wageCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: loc.agriDailyWageLabel,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onChanged: (_) => setDialogState(() {}))),
                  ]),
                ] else ...[
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: loc.agriQtyHarvestedLabel,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onChanged: (_) => setDialogState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: loc.agriRatePerKgLabel,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onChanged: (_) => setDialogState(() {}))),
                  ]),
                ],
                const SizedBox(height: 10),
                Text(
                    '${loc.agriComputedCostPreview}: ₹${computed.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: idaGreen)),
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
                        if (workerId == null ||
                            activityCtrl.text.trim().isEmpty) return;
                        setDialogState(() => submitting = true);
                        final h = await _headers;
                        final res = await http.post(
                          Uri.parse('$baseUrl/agri/labor-entries'),
                          headers: {...h, 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'cycle_type': widget.cycleType,
                            'cycle_id': widget.cycleId,
                            'worker_id': workerId,
                            'entry_date':
                                DateFormat('yyyy-MM-dd').format(entryDate),
                            'payment_mode': paymentMode,
                            'days_worked':
                                double.tryParse(daysCtrl.text.trim()),
                            'daily_wage_amount':
                                double.tryParse(wageCtrl.text.trim()),
                            'quantity_harvested_kg':
                                double.tryParse(qtyCtrl.text.trim()),
                            'rate_applied_per_kg':
                                double.tryParse(rateCtrl.text.trim()),
                            'activity_type': activityCtrl.text.trim(),
                          }),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (res.statusCode == 201) {
                          _showSnack(loc.agriSaved);
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
                    : Text(loc.save,
                        style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
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

  // Converts a stored cm value back to its originally-entered unit,
  // for pre-populating the edit form with the number the user
  // actually typed rather than a converted cm figure they'd have to
  // mentally convert back.
  double _fromCm(double cm, String unit) {
    switch (unit) {
      case 'in':
        return cm / 2.54;
      case 'ft':
        return cm / 30.48;
      default:
        return cm;
    }
  }

  Future<void> _showEditPatternLinesDialog() async {
    if (patternLines.isEmpty) return;
    // Every distinct crop already appearing in the pattern, derived
    // from the lines themselves - covers both single-crop (Khalla)
    // and intercropped (Tarwale) cases without a separate fetch.
    final Map<int, String> cropOptions = {};
    for (final l in patternLines) {
      cropOptions[l['crop_variety_id']] = l['crop_variety_name'];
    }

    final List<Map<String, dynamic>> editLines = patternLines
        .map((l) => {
              'cropVarietyId': l['crop_variety_id'],
              'gapCtrl': TextEditingController(
                  text: _fromCm(double.parse(l['gap_to_next_cm'].toString()),
                          l['gap_to_next_unit'] ?? 'cm')
                      .toStringAsFixed(2)),
              'unit': l['gap_to_next_unit'] ?? 'cm',
            })
        .toList();
    bool submitting = false;
    final loc = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Sowing Pattern',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  'Enter the gap to the NEXT line, in order (last gap wraps back to line 1):',
                  style:
                      TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 10),
              ...editLines.asMap().entries.map((entry) {
                final i = entry.key;
                final line = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          SizedBox(
                            width: 22,
                            child: Text('${i + 1}.',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                            child: cropOptions.length > 1
                                ? DropdownButtonFormField<int>(
                                    value: line['cropVarietyId'],
                                    isDense: true,
                                    decoration: InputDecoration(
                                        labelText: 'Crop on this line',
                                        isDense: true,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10))),
                                    items: cropOptions.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key,
                                            child: Text(tl(context, e.value),
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) => setDialogState(
                                        () => line['cropVarietyId'] = v),
                                  )
                                // Single-crop pattern (e.g. Khalla) - no
                                // choice to make, just show which crop.
                                : Text(tl(context, cropOptions.values.first),
                                    style: const TextStyle(fontSize: 13)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const SizedBox(width: 22),
                          Expanded(
                            child: TextField(
                              controller: line['gapCtrl'],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: 'Gap to next line',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10))),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _unitDropdown(loc, line['unit'],
                              (v) => setDialogState(() => line['unit'] = v)),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20, color: Colors.red),
                            onPressed: editLines.length <= 2
                                ? null
                                : () =>
                                    setDialogState(() => editLines.removeAt(i)),
                          ),
                        ]),
                      ]),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setDialogState(() => editLines.add({
                        'cropVarietyId': cropOptions.keys.first,
                        'gapCtrl': TextEditingController(),
                        'unit': 'in',
                      })),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
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
                      final linesPayload = editLines
                          .map((l) => {
                                'crop_variety_id': l['cropVarietyId'],
                                'gap_to_next': double.tryParse(
                                    (l['gapCtrl'] as TextEditingController)
                                        .text
                                        .trim()),
                                'gap_to_next_unit': l['unit'],
                              })
                          .toList();
                      final res = await http.post(
                        Uri.parse(
                            '$baseUrl/agri/sowing-plans/${widget.cycleId}/pattern-lines'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({'lines': linesPayload}),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 201) {
                        _showSnack('Pattern updated');
                        await _load();
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

  Future<void> _showAddIntercropDialog() async {
    final loc = AppLocalizations.of(context)!;
    final h = await _headers;
    final res = await http.get(
        Uri.parse('$baseUrl/agri/crop-varieties?crop_type=seasonal'),
        headers: h);
    if (res.statusCode != 200) {
      _showSnack(loc.agriFailedSave, isError: true);
      return;
    }
    final varieties = List<Map<String, dynamic>>.from(jsonDecode(res.body));
    if (varieties.isEmpty) return;

    // Needed for the 'sequence' pattern-lines picker below - each
    // line is EITHER the main plan's crop OR the new companion crop,
    // since intercropping interleaves exactly two.
    final mainPlanRes = await http.get(
        Uri.parse('$baseUrl/agri/sowing-plans/${widget.cycleId}'),
        headers: h);
    if (mainPlanRes.statusCode != 200) {
      _showSnack(loc.agriFailedSave, isError: true);
      return;
    }
    final mainPlan = jsonDecode(mainPlanRes.body);
    final int mainCropVarietyId = mainPlan['crop_variety_id'];
    final String mainCropLabel =
        '${tl(context, mainPlan['crop_variety_name'])} (main crop)';

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
    // 'sequence' mode - a third option alongside the existing
    // width-ratio (uniform-only) calculation this dialog already did.
    // When true, density percentages replace rows_per_cycle/spacing
    // for the AREA calculation (per direct confirmation: NOT physical
    // land-splitting - each crop's own stated % of its normal
    // sole-crop density, percentages can total over 100%).
    bool useSequenceMode = false;
    final mainDensityCtrl = TextEditingController();
    final companionDensityCtrl = TextEditingController();
    final List<Map<String, dynamic>> patternLines = [
      {
        'cropVarietyId': mainCropVarietyId,
        'gapCtrl': TextEditingController(),
        'unit': 'in'
      },
      {
        'cropVarietyId': mainCropVarietyId,
        'gapCtrl': TextEditingController(),
        'unit': 'in'
      },
    ];
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: useSequenceMode,
                    onChanged: (v) => setDialogState(() => useSequenceMode = v),
                    title: const Text('Custom sequence pattern',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'For mixed multi-line patterns like Soybean-Soybean-Soybean-Tur repeating - uses stated density % instead of row-width ratio',
                        style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 8),
                  if (!useSequenceMode) ...[
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
                  ] else ...[
                    // Density %, stated directly (NOT derived from
                    // line-counting) - can total over 100%, since
                    // intercropped crops share land rather than
                    // dividing it. See real_farm_records.sql for the
                    // confirmed Tarwale example (70% + 100% = 170%).
                    Text(mainCropLabel,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF6B7280))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: mainDensityCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              "Main crop's density % of its own sole-crop planting",
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: companionDensityCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText:
                              "Companion crop's density % of its own sole-crop planting",
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                    const SizedBox(height: 16),
                    Text(
                        'Enter the gap to the NEXT line, in order (last gap wraps back to line 1):',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 10),
                    ...patternLines.asMap().entries.map((entry) {
                      final i = entry.key;
                      final line = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                SizedBox(
                                  width: 22,
                                  child: Text('${i + 1}.',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: line['cropVarietyId'],
                                    isDense: true,
                                    decoration: InputDecoration(
                                        labelText: 'Crop on this line',
                                        isDense: true,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10))),
                                    items: [
                                      DropdownMenuItem(
                                          value: mainCropVarietyId,
                                          child: Text(mainCropLabel,
                                              overflow: TextOverflow.ellipsis)),
                                      if (varietyId != null)
                                        DropdownMenuItem(
                                            value: varietyId,
                                            child: Text(
                                                '${tl(context, varieties.firstWhere((v) => v['id'] == varietyId)['crop_name'])} (companion)',
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                    ],
                                    onChanged: (v) => setDialogState(
                                        () => line['cropVarietyId'] = v),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                const SizedBox(width: 22),
                                Expanded(
                                  child: TextField(
                                    controller: line['gapCtrl'],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: 'Gap to next line',
                                        isDense: true,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10))),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _unitDropdown(
                                    loc,
                                    line['unit'],
                                    (v) =>
                                        setDialogState(() => line['unit'] = v)),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20, color: Colors.red),
                                  onPressed: patternLines.length <= 2
                                      ? null
                                      : () => setDialogState(
                                          () => patternLines.removeAt(i)),
                                ),
                              ]),
                            ]),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => patternLines.add({
                              'cropVarietyId': mainCropVarietyId,
                              'gapCtrl': TextEditingController(),
                              'unit': 'in'
                            })),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add line'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                      final h2 = await _headers;
                      final res2 = await http.post(
                        Uri.parse(
                            '$baseUrl/agri/sowing-plans/${widget.cycleId}/add-intercrop'),
                        headers: {...h2, 'Content-Type': 'application/json'},
                        body: jsonEncode({
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
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res2.statusCode == 201) {
                        _showSnack(loc.agriIntercropAddedMsg);
                      } else {
                        final data = jsonDecode(res2.body);
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

  void _showLogHarvestDialog() {
    final loc = AppLocalizations.of(context)!;
    DateTime harvestDate = DateTime.now();
    final qtyCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kg');
    final gradeCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.agriLogHarvest,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: harvestDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (picked != null)
                    setDialogState(() => harvestDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.agriHarvestDateLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(harvestDate)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriTotalYieldLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration: InputDecoration(
                        labelText: loc.agriUnitLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: gradeCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriQualityGradeLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: loc.agriNotesLabel,
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
                      if (qtyCtrl.text.trim().isEmpty) return;
                      setDialogState(() => submitting = true);
                      final h = await _headers;
                      final res = await http.post(
                        Uri.parse('$baseUrl/agri/harvest-records'),
                        headers: {...h, 'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'cycle_type': widget.cycleType,
                          'cycle_id': widget.cycleId,
                          'harvest_date':
                              DateFormat('yyyy-MM-dd').format(harvestDate),
                          'total_yield_qty':
                              double.tryParse(qtyCtrl.text.trim()),
                          'unit': unitCtrl.text.trim(),
                          'quality_grade': gradeCtrl.text.trim().isEmpty
                              ? null
                              : gradeCtrl.text.trim(),
                          'remarks': remarksCtrl.text.trim().isEmpty
                              ? null
                              : remarksCtrl.text.trim(),
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 201) {
                        _showSnack(loc.agriSaved);
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
    final overdue = items.where((i) => i['status'] == 'overdue').toList();
    final upcoming = items
        .where((i) => i['status'] == 'pending' && i['planned_date'] != null)
        .toList();
    final notScheduled = items
        .where((i) => i['status'] == 'pending' && i['planned_date'] == null)
        .toList();
    final done = items.where((i) => i['status'] == 'done').toList();
    final skipped = items.where((i) => i['status'] == 'skipped').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: () => showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.people_outline, color: idaGreen),
                  title: Text(loc.agriLogLabor),
                  onTap: () {
                    Navigator.pop(context);
                    _showLogLaborDialog();
                  }),
              ListTile(
                  leading:
                      const Icon(Icons.agriculture_outlined, color: idaGreen),
                  title: Text(loc.agriLogHarvest),
                  onTap: () {
                    Navigator.pop(context);
                    _showLogHarvestDialog();
                  }),
              if (widget.cycleType == 'seasonal')
                ListTile(
                    leading: const Icon(Icons.grass_outlined, color: idaGreen),
                    title: Text(loc.agriAddIntercropButton),
                    onTap: () {
                      Navigator.pop(context);
                      _showAddIntercropDialog();
                    }),
            ]),
          ),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: Responsive.constrainedContent(
                  context,
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: [
                      if (mainPlanDetails?['row_arrangement'] == 'sequence')
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7ED),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDCE7CE)),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.timeline_outlined,
                                      size: 18, color: idaGreen),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text('Sowing Pattern',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(50, 30)),
                                    onPressed: _showEditPatternLinesDialog,
                                    child: const Text('Edit',
                                        style: TextStyle(fontSize: 12.5)),
                                  ),
                                ]),
                                const SizedBox(height: 8),
                                if (patternLines.isEmpty)
                                  Text(
                                      'No pattern lines entered yet — tap Edit to add them.',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.grey.shade600))
                                else
                                  ...patternLines.asMap().entries.map((e) {
                                    final i = e.key;
                                    final line = e.value;
                                    final isLast = i == patternLines.length - 1;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(
                                          '${i + 1}. ${tl(context, line['crop_variety_name'])}'
                                          '${isLast ? '  →  (wraps to line 1)' : '  →  ${line['gap_to_next_cm']} cm to next'}',
                                          style:
                                              const TextStyle(fontSize: 12.5)),
                                    );
                                  }),
                              ]),
                        ),
                      if (overdue.isNotEmpty)
                        _section(
                            loc.agriOverdueSection,
                            Colors.red,
                            overdue
                                .map((i) => _itemCard(i,
                                    actionable: true, color: Colors.red))
                                .toList()),
                      if (upcoming.isNotEmpty)
                        _section(
                            loc.agriPendingSection,
                            idaGreen,
                            upcoming
                                .map((i) => _itemCard(i,
                                    actionable: true, color: idaGreen))
                                .toList()),
                      if (notScheduled.isNotEmpty)
                        _section(
                            loc.agriNotScheduledSection,
                            Colors.grey,
                            notScheduled
                                .map((i) => _itemCard(i,
                                    actionable: true,
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
                  )),
            ),
    );
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
          if (item['weather_advisory'] != null &&
              item['weather_advisory']['message'] != null)
            _weatherAdvisoryBadge(item['weather_advisory'],
                isOverdue: item['status'] == 'overdue'),
        ]),
      ),
    );
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
