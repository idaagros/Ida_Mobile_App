// lib/screens/farm_tractor_work_screen.dart
//
// The daily flow: pick a date, assign a tractor to a farm for a work
// type (Step 1 — hour_start logged, entry becomes "in progress"),
// then later mark it complete (Step 2 — hour_end and/or quantity
// logged). Billing is resolved entirely at completion time: if the
// work type has more than one valid billing option (e.g. Trolley:
// per trip or per day), the server tells us so and this screen shows
// a choice — it never guesses, and never asks at assignment time,
// since the job's actual shape often isn't known until it's done.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin/farm_tractor_master_screen.dart';
import 'farm_tractor_diesel_screen.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';

class FarmTractorWorkScreen extends StatefulWidget {
  const FarmTractorWorkScreen({super.key});
  @override
  State<FarmTractorWorkScreen> createState() => _FarmTractorWorkScreenState();
}

class _FarmTractorWorkScreenState extends State<FarmTractorWorkScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  DateTime selectedDate = DateTime.now();
  List tractors = [];
  List farms = [];
  List workTypes = [];
  List entries = [];
  bool loadingMasters = true;
  bool loadingEntries = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> _init() async {
    await _loadMasters();
    await _loadEntries();
  }

  Future<void> _loadMasters() async {
    setState(() => loadingMasters = true);
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/farm-tractor/tractors'), headers: h),
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/work-types?applies_to=tractor'),
            headers: h),
      ]);
      if (results[0].statusCode == 200) tractors = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) farms = jsonDecode(results[1].body);
      if (results[2].statusCode == 200) workTypes = jsonDecode(results[2].body);
    } catch (e) {
      debugPrint('Load masters error: $e');
    } finally {
      if (mounted) setState(() => loadingMasters = false);
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      loadingEntries = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(
          Uri.parse('$baseUrl/farm-tractor/work-entries?date=$_dateStr'),
          headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => entries = data['data'] ?? []);
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loadingEntries = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      await _loadEntries();
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

  void _showAssignDialog() {
    final loc = AppLocalizations.of(context)!;
    int? tractorId = tractors.isNotEmpty ? tractors.first['id'] : null;
    int? farmId = farms.isNotEmpty ? farms.first['id'] : null;
    int? workTypeId = workTypes.isNotEmpty ? workTypes.first['id'] : null;
    final hourStartCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(loc.ftAssignWork,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  value: tractorId,
                  decoration: InputDecoration(
                      labelText: loc.ftTractorLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: tractors
                      .map<DropdownMenuItem<int>>((t) => DropdownMenuItem(
                          value: t['id'], child: Text(tl(context, t['name']))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => tractorId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: farmId,
                  decoration: InputDecoration(
                      labelText: loc.ftFarmLabel,
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
                  value: workTypeId,
                  decoration: InputDecoration(
                      labelText: loc.ftWorkTypeLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: workTypes
                      .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                          value: w['id'], child: Text(tl(context, w['name']))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => workTypeId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hourStartCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: loc.ftHourStartLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                      labelText: loc.ftNotesLabel,
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
                onPressed: () async {
                  if (tractorId == null ||
                      farmId == null ||
                      workTypeId == null) {
                    _showSnack(loc.ftSelectRequired, isError: true);
                    return;
                  }
                  final h = await _headers;
                  final res = await http.post(
                    Uri.parse('$baseUrl/farm-tractor/work-entries'),
                    headers: {...h, 'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'tractor_id': tractorId,
                      'farm_id': farmId,
                      'work_type_id': workTypeId,
                      'work_date': _dateStr,
                      'hour_start': double.tryParse(hourStartCtrl.text.trim()),
                      'notes': notesCtrl.text.trim(),
                    }),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (res.statusCode == 201) {
                    _loadEntries();
                    _showSnack(loc.ftWorkAssigned);
                  } else {
                    final data = jsonDecode(res.body);
                    _showSnack(data['error'] ?? loc.ftFailedAssign,
                        isError: true);
                  }
                },
                child: Text(loc.ftAssignWork,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // Handles the full completion flow, including the billing-choice
  // step ONLY when the server tells us it's genuinely ambiguous — the
  // common case (a work type with one billing option) never shows
  // this extra step at all.
  void _showCompleteDialog(Map entry) {
    final loc = AppLocalizations.of(context)!;
    final hourEndCtrl = TextEditingController();
    final quantityCtrl = TextEditingController();
    List<String>?
        billingOptions; // null until the server tells us it's ambiguous
    String? chosenUnit;
    bool submitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> attemptComplete() async {
            setDialogState(() {
              submitting = true;
              dialogError = null;
            });
            final h = await _headers;
            final body = <String, dynamic>{
              'hour_end': double.tryParse(hourEndCtrl.text.trim()),
            };
            if (chosenUnit != null) {
              body['billing_unit'] = chosenUnit;
              if (chosenUnit != 'hour')
                body['quantity'] = double.tryParse(quantityCtrl.text.trim());
            } else if (quantityCtrl.text.trim().isNotEmpty) {
              // billing_unit not yet known, but a quantity was already
              // entered from a prior attempt's follow-up field
              body['quantity'] = double.tryParse(quantityCtrl.text.trim());
            }
            final res = await http.patch(
              Uri.parse(
                  '$baseUrl/farm-tractor/work-entries/${entry['id']}/complete'),
              headers: {...h, 'Content-Type': 'application/json'},
              body: jsonEncode(body),
            );
            final data = jsonDecode(res.body);
            if (res.statusCode == 200) {
              if (ctx.mounted) Navigator.pop(ctx);
              _loadEntries();
              _showSnack(loc.ftWorkCompleted);
            } else if (res.statusCode == 409 &&
                data['available_billing_units'] != null) {
              // Genuinely ambiguous — show the choice, don't guess.
              setDialogState(() {
                billingOptions =
                    List<String>.from(data['available_billing_units']);
                submitting = false;
              });
            } else {
              setDialogState(() {
                dialogError = data['error'] ?? loc.ftFailedComplete;
                submitting = false;
              });
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
                '${loc.ftCompleteButton} — ${tl(context, entry['work_type_name'])}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${tl(context, entry['tractor_name'])} · ${tl(context, entry['farm_name'])}',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: hourEndCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.ftHourMeterEndLabel,
                        helperText: entry['hour_start'] != null
                            ? '${loc.ftStartedAt} ${entry['hour_start']}'
                            : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (billingOptions != null) ...[
                      const SizedBox(height: 16),
                      Text(loc.ftBillingChoiceTitle,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ...billingOptions!.map((unit) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                                '${loc.ftBillingUnitLabel} ${unit[0].toUpperCase()}${unit.substring(1)}'),
                            value: unit,
                            groupValue: chosenUnit,
                            activeColor: idaGreen,
                            onChanged: (v) =>
                                setDialogState(() => chosenUnit = v),
                          )),
                      if (chosenUnit != null && chosenUnit != 'hour') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: quantityCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: '${loc.ftQuantityLabel} ($chosenUnit)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10))),
                        ),
                      ],
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(dialogError!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12.5)),
                    ],
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed:
                    submitting || (billingOptions != null && chosenUnit == null)
                        ? null
                        : attemptComplete,
                child: submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(loc.ftCompleteButton,
                        style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final inProgress =
        entries.where((e) => e['status'] == 'in_progress').toList();
    final completed = entries.where((e) => e['status'] == 'completed').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.ftScreenTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_gas_station_outlined),
            tooltip: loc.ftDieselLogTooltip,
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FarmTractorDieselScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: loc.ftSetupTooltip,
            onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FarmTractorMasterScreen()))
                .then((_) => _loadMasters()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: idaGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            Text(loc.ftAssignWork, style: const TextStyle(color: Colors.white)),
        onPressed: (tractors.isEmpty || farms.isEmpty || workTypes.isEmpty)
            ? null
            : _showAssignDialog,
      ),
      body: loadingMasters
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: () async {
                await _loadMasters();
                await _loadEntries();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E7D8))),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 18, color: idaGreen),
                        const SizedBox(width: 10),
                        Text(
                            DateFormat('EEEE, dd MMM yyyy')
                                .format(selectedDate),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: idaDark)),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_outlined,
                            size: 18, color: Colors.grey),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (loadingEntries)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(color: idaGreen)))
                  else ...[
                    if (inProgress.isNotEmpty) ...[
                      Text(loc.ftInProgress,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 8),
                      ...inProgress.map(
                          (e) => _entryCard(e, inProgress: true, loc: loc)),
                      const SizedBox(height: 16),
                    ],
                    Text(loc.ftCompleted,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    if (completed.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E7D8))),
                        child: Text(loc.ftNoCompletedWork,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                      )
                    else
                      ...completed.map(
                          (e) => _entryCard(e, inProgress: false, loc: loc)),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _entryCard(Map e,
      {required bool inProgress, required AppLocalizations loc}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                inProgress ? Colors.orange.shade200 : const Color(0xFFE0E7D8)),
      ),
      child: InkWell(
        onTap: inProgress ? () => _showCompleteDialog(e) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.agriculture, color: idaGreen, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tl(context, e['tractor_name'] ?? ''),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1)),
            if (inProgress)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(loc.ftTapToComplete,
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.orange,
                        fontWeight: FontWeight.w700)),
              )
            else
              Text('₹${e['computed_cost'] ?? '—'}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: idaGreen)),
          ]),
          const SizedBox(height: 6),
          Text(
              '${tl(context, e['farm_name'])} · ${tl(context, e['work_type_name'])}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          if (!inProgress) ...[
            const SizedBox(height: 4),
            Text(
              e['billing_unit'] == 'hour'
                  ? '${e['total_hours']} hours × ₹${e['rate_applied']}'
                  : '${e['quantity']} ${e['billing_unit']} × ₹${e['rate_applied']}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ] else if (e['hour_start'] != null) ...[
            const SizedBox(height: 4),
            Text('${loc.ftStartedAt} ${e['hour_start']}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ],
        ]),
      ),
    );
  }
}
