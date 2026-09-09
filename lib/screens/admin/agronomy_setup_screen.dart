// lib/screens/admin/agronomy_setup_screen.dart
//
// Agronomy Setup: Orchard Blocks + Crop Stage Templates + Spray
// Schedule Templates — grouped together since all three need
// meaningfully more complex forms (trigger_type, day-ranges,
// sequence_order) than the simple name+category masters in
// crop_masters_screen.dart.
//
// Orchard Block's variety picker only shows PERENNIAL varieties
// (matches the backend's own validation — orchard blocks are for
// perennial crops only, mirrored here so the picker itself can't
// offer an invalid choice). Spray Template's dose field dynamically
// shows "per acre" or "per tree" depending on the selected variety's
// crop_type — never both, never neither.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../localization/app_localizations.dart';
import '../../localization/transliterate.dart';
import '../../services/api_service.dart';
import '../../services/responsive.dart';

enum _Tab { orchardBlocks, stageTemplates, sprayTemplates }

class AgronomySetupScreen extends StatefulWidget {
  const AgronomySetupScreen({super.key});
  @override
  State<AgronomySetupScreen> createState() => _AgronomySetupScreenState();
}

class _AgronomySetupScreenState extends State<AgronomySetupScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  static const stageTriggerTypes = ['DAS', 'DAF', 'DAP', 'DAH'];
  static const sprayTriggerTypes = ['DAS', 'DAF', 'DAP', 'DAH', 'DAPREV'];
  static const activityTypes = [
    'fertilizer',
    'pesticide',
    'fungicide',
    'weedicide',
    'pruning'
  ];

  _Tab _tab = _Tab.orchardBlocks;
  List farms = [];
  List varieties = [];
  List orchardBlocks = [];
  List stageTemplates = [];
  List sprayTemplates = [];
  bool loading = true;
  bool _canEditAgri = false;

  List get perennialVarieties =>
      varieties.where((v) => v['crop_type'] == 'perennial').toList();

  @override
  void initState() {
    super.initState();
    _loadAll();
    ApiService.canEdit('agri').then((v) {
      if (mounted) setState(() => _canEditAgri = v);
    });
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
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/crop-varieties'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/orchard-blocks'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/crop-stage-templates'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/spray-schedule-templates'),
            headers: h),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) varieties = jsonDecode(results[1].body);
      if (results[2].statusCode == 200)
        orchardBlocks = jsonDecode(results[2].body);
      if (results[3].statusCode == 200)
        stageTemplates = jsonDecode(results[3].body);
      if (results[4].statusCode == 200)
        sprayTemplates = jsonDecode(results[4].body);
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

  // ── Orchard Block dialog ─────────────────────────────────────────
  void _showOrchardBlockDialog({Map? block}) {
    final loc = AppLocalizations.of(context)!;
    if (perennialVarieties.isEmpty) {
      _showSnack('Add a perennial crop variety first', isError: true);
      return;
    }
    int? farmId =
        block?['farm_id'] ?? (farms.isNotEmpty ? farms.first['id'] : null);
    int? varietyId =
        block?['crop_variety_id'] ?? perennialVarieties.first['id'];
    DateTime plantingDate = block != null
        ? DateTime.tryParse(block['planting_date'] ?? '') ?? DateTime.now()
        : DateTime.now();
    final rowSpacingCtrl =
        TextEditingController(text: block?['row_spacing_m']?.toString() ?? '');
    final plantSpacingCtrl = TextEditingController(
        text: block?['plant_spacing_m']?.toString() ?? '');
    final treesCtrl =
        TextEditingController(text: block?['no_of_trees']?.toString() ?? '');
    final areaCtrl =
        TextEditingController(text: block?['area_acre']?.toString() ?? '');
    String status = block?['status'] ?? 'active';
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              block == null
                  ? loc.agriAddOrchardBlock
                  : loc.agriEditOrchardBlock,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
                onChanged: block == null
                    ? (v) => setDialogState(() => farmId = v)
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: varietyId,
                decoration: InputDecoration(
                    labelText: '${loc.agriVarietyLabel} (${loc.agriPerennial})',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: perennialVarieties
                    .map<DropdownMenuItem<int>>((v) => DropdownMenuItem(
                        value: v['id'],
                        child: Text(
                            '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}')))
                    .toList(),
                onChanged: block == null
                    ? (v) => setDialogState(() => varietyId = v)
                    : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: plantingDate,
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now());
                  if (picked != null)
                    setDialogState(() => plantingDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.agriPlantingDateLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(plantingDate)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: rowSpacingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriRowSpacingLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: plantSpacingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriPlantSpacingLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: treesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: loc.agriNoOfTreesLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: areaCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: loc.agriAreaAcreLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
              if (block != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: InputDecoration(
                      labelText: loc.agriStatusLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'removed', child: Text('Removed')),
                  ],
                  onChanged: (v) => setDialogState(() => status = v!),
                ),
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
                      http.Response res;
                      if (block == null) {
                        res = await http.post(
                          Uri.parse('$baseUrl/agri/orchard-blocks'),
                          headers: {...h, 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'farm_id': farmId,
                            'crop_variety_id': varietyId,
                            'planting_date':
                                DateFormat('yyyy-MM-dd').format(plantingDate),
                            'row_spacing_m':
                                double.tryParse(rowSpacingCtrl.text.trim()),
                            'plant_spacing_m':
                                double.tryParse(plantSpacingCtrl.text.trim()),
                            'no_of_trees': int.tryParse(treesCtrl.text.trim()),
                            'area_acre': double.tryParse(areaCtrl.text.trim()),
                          }),
                        );
                      } else {
                        res = await http.patch(
                          Uri.parse(
                              '$baseUrl/agri/orchard-blocks/${block['id']}'),
                          headers: {...h, 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'row_spacing_m':
                                double.tryParse(rowSpacingCtrl.text.trim()),
                            'plant_spacing_m':
                                double.tryParse(plantSpacingCtrl.text.trim()),
                            'no_of_trees': int.tryParse(treesCtrl.text.trim()),
                            'area_acre': double.tryParse(areaCtrl.text.trim()),
                            'status': status,
                          }),
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        _loadAll();
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

  // ── Stage Template dialog ────────────────────────────────────────
  void _showStageTemplateDialog({Map? template}) {
    final loc = AppLocalizations.of(context)!;
    if (varieties.isEmpty) {
      _showSnack('Add a crop variety first', isError: true);
      return;
    }
    int? varietyId = template?['crop_variety_id'] ?? varieties.first['id'];
    final stageNameCtrl =
        TextEditingController(text: template?['stage_name'] ?? '');
    String triggerType = template?['trigger_type'] ?? stageTriggerTypes.first;
    final daysStartCtrl = TextEditingController(
        text: template?['trigger_days_start']?.toString() ?? '');
    final daysEndCtrl = TextEditingController(
        text: template?['trigger_days_end']?.toString() ?? '');
    final ageBracketCtrl =
        TextEditingController(text: template?['tree_age_bracket'] ?? '');
    final notesCtrl = TextEditingController(text: template?['notes'] ?? '');
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              template == null
                  ? loc.agriAddStageTemplate
                  : loc.agriEditStageTemplate,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: varietyId,
                decoration: InputDecoration(
                    labelText: loc.agriVarietyLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: varieties
                    .map<DropdownMenuItem<int>>((v) => DropdownMenuItem(
                        value: v['id'],
                        child: Text(
                            '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}')))
                    .toList(),
                onChanged: template == null
                    ? (v) => setDialogState(() => varietyId = v)
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stageNameCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriStageNameLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: triggerType,
                decoration: InputDecoration(
                    labelText: loc.agriTriggerTypeLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: stageTriggerTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDialogState(() => triggerType = v!),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: daysStartCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: loc.agriTriggerDaysStartLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: daysEndCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: loc.agriTriggerDaysEndLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: ageBracketCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriTreeAgeBracketLabel,
                    hintText: "e.g. 1-3, 4-6, 7-10, 10+",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
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
                      if (stageNameCtrl.text.trim().isEmpty ||
                          daysStartCtrl.text.trim().isEmpty ||
                          daysEndCtrl.text.trim().isEmpty) return;
                      setDialogState(() => submitting = true);
                      final h = await _headers;
                      final body = jsonEncode({
                        'crop_variety_id': varietyId,
                        'stage_name': stageNameCtrl.text.trim(),
                        'trigger_type': triggerType,
                        'trigger_days_start':
                            int.tryParse(daysStartCtrl.text.trim()),
                        'trigger_days_end':
                            int.tryParse(daysEndCtrl.text.trim()),
                        'tree_age_bracket': ageBracketCtrl.text.trim().isEmpty
                            ? null
                            : ageBracketCtrl.text.trim(),
                        'notes': notesCtrl.text.trim(),
                      });
                      final res = template == null
                          ? await http.post(
                              Uri.parse('$baseUrl/agri/crop-stage-templates'),
                              headers: {
                                ...h,
                                'Content-Type': 'application/json'
                              },
                              body: body)
                          : await http.patch(
                              Uri.parse(
                                  '$baseUrl/agri/crop-stage-templates/${template['id']}'),
                              headers: {
                                ...h,
                                'Content-Type': 'application/json'
                              },
                              body: body);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        _loadAll();
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

  // ── Spray Template dialog ────────────────────────────────────────
  void _showSprayTemplateDialog({Map? template}) {
    final loc = AppLocalizations.of(context)!;
    if (varieties.isEmpty) {
      _showSnack('Add a crop variety first', isError: true);
      return;
    }
    int? varietyId = template?['crop_variety_id'] ?? varieties.first['id'];
    String triggerType = template?['trigger_type'] ?? sprayTriggerTypes.first;
    final daysCtrl = TextEditingController(
        text: template?['trigger_days']?.toString() ?? '');
    String activityType = template?['activity_type'] ?? activityTypes.first;
    final productCtrl =
        TextEditingController(text: template?['product_suggestion'] ?? '');
    final doseCtrl = TextEditingController(
        text: (template?['dose_per_acre'] ?? template?['dose_per_tree'])
                ?.toString() ??
            '');
    final doseUnitCtrl =
        TextEditingController(text: template?['dose_unit'] ?? '');
    final ageBracketCtrl =
        TextEditingController(text: template?['tree_age_bracket'] ?? '');
    final sequenceCtrl = TextEditingController(
        text: template?['sequence_order']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: template?['notes'] ?? '');
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedVariety = varieties
              .firstWhere((v) => v['id'] == varietyId, orElse: () => {});
          final isPerennial = selectedVariety['crop_type'] == 'perennial';
          final isPruning = activityType == 'pruning';

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
                template == null
                    ? loc.agriAddSprayTemplate
                    : loc.agriEditSprayTemplate,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  value: varietyId,
                  decoration: InputDecoration(
                      labelText: loc.agriVarietyLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: varieties
                      .map<DropdownMenuItem<int>>((v) => DropdownMenuItem(
                          value: v['id'],
                          child: Text(
                              '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}')))
                      .toList(),
                  onChanged: template == null
                      ? (v) => setDialogState(() => varietyId = v)
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: triggerType,
                  decoration: InputDecoration(
                      labelText: loc.agriTriggerTypeLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: sprayTriggerTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => triggerType = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: loc.agriTriggerDaysLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: activityType,
                  decoration: InputDecoration(
                      labelText: loc.agriActivityTypeLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: activityTypes
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t[0].toUpperCase() + t.substring(1))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => activityType = v!),
                ),
                if (!isPruning) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: productCtrl,
                    decoration: InputDecoration(
                        labelText: loc.agriProductSuggestionLabel,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: doseCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: isPerennial
                              ? loc.agriDosePerTreeLabel
                              : loc.agriDosePerAcreLabel,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: doseUnitCtrl,
                        decoration: InputDecoration(
                            labelText: loc.agriDoseUnitLabel,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                  ]),
                ],
                if (isPerennial) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: ageBracketCtrl,
                    decoration: InputDecoration(
                        labelText: loc.agriTreeAgeBracketLabel,
                        hintText: "e.g. 1-3, 4-6, 7-10, 10+",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: sequenceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: loc.agriSequenceOrderLabel,
                    helperText: triggerType == 'DAPREV'
                        ? 'DAPREV resolves against sequence_order - 1 for this variety'
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
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
                        if (daysCtrl.text.trim().isEmpty) return;
                        setDialogState(() => submitting = true);
                        final h = await _headers;
                        final dose = double.tryParse(doseCtrl.text.trim());
                        final body = jsonEncode({
                          'crop_variety_id': varietyId,
                          'trigger_type': triggerType,
                          'trigger_days': int.tryParse(daysCtrl.text.trim()),
                          'activity_type': activityType,
                          'product_suggestion': productCtrl.text.trim().isEmpty
                              ? null
                              : productCtrl.text.trim(),
                          'dose_per_acre':
                              !isPruning && !isPerennial ? dose : null,
                          'dose_per_tree':
                              !isPruning && isPerennial ? dose : null,
                          'dose_unit': doseUnitCtrl.text.trim().isEmpty
                              ? null
                              : doseUnitCtrl.text.trim(),
                          'tree_age_bracket': ageBracketCtrl.text.trim().isEmpty
                              ? null
                              : ageBracketCtrl.text.trim(),
                          'sequence_order':
                              int.tryParse(sequenceCtrl.text.trim()),
                          'notes': notesCtrl.text.trim(),
                        });
                        final res = template == null
                            ? await http.post(
                                Uri.parse(
                                    '$baseUrl/agri/spray-schedule-templates'),
                                headers: {
                                  ...h,
                                  'Content-Type': 'application/json'
                                },
                                body: body)
                            : await http.patch(
                                Uri.parse(
                                    '$baseUrl/agri/spray-schedule-templates/${template['id']}'),
                                headers: {
                                  ...h,
                                  'Content-Type': 'application/json'
                                },
                                body: body);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (res.statusCode == 200 || res.statusCode == 201) {
                          _loadAll();
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.agriAgronomySetupTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: !_canEditAgri
          ? null
          : FloatingActionButton(
              backgroundColor: idaGreen,
              onPressed: () {
                switch (_tab) {
                  case _Tab.orchardBlocks:
                    _showOrchardBlockDialog();
                    break;
                  case _Tab.stageTemplates:
                    _showStageTemplateDialog();
                    break;
                  case _Tab.sprayTemplates:
                    _showSprayTemplateDialog();
                    break;
                }
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: Column(children: [
        Container(
          color: idaDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            _segment(loc.agriOrchardBlocksTab, _Tab.orchardBlocks,
                orchardBlocks.length),
            const SizedBox(width: 6),
            _segment(loc.agriStageTemplatesTab, _Tab.stageTemplates,
                stageTemplates.length),
            const SizedBox(width: 6),
            _segment(loc.agriSprayTemplatesTab, _Tab.sprayTemplates,
                sprayTemplates.length),
          ]),
        ),
        Expanded(
            child: Responsive.constrainedContent(
                context,
                loading
                    ? const Center(
                        child: CircularProgressIndicator(color: idaGreen))
                    : _buildList(loc))),
      ]),
    );
  }

  Widget _segment(String label, _Tab tab, int count) {
    final selected = _tab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = tab),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
              color: selected ? idaGreen : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Text('$label ($count)',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations loc) {
    switch (_tab) {
      case _Tab.orchardBlocks:
        return orchardBlocks.isEmpty
            ? _empty(loc.agriNoOrchardBlocksYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: orchardBlocks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final b = orchardBlocks[i];
                  return _row(
                    title:
                        '${tl(context, b['farm_name'])} — ${tl(context, b['crop_variety_name'])}',
                    subtitle:
                        'Planted ${b['planting_date']}${b['no_of_trees'] != null ? ' · ${b['no_of_trees']} trees' : ''} · ${b['status']}',
                    onTap: () => _showOrchardBlockDialog(block: b),
                  );
                },
              );
      case _Tab.stageTemplates:
        return stageTemplates.isEmpty
            ? _empty(loc.agriNoStageTemplatesYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: stageTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = stageTemplates[i];
                  return _row(
                    title:
                        '${tl(context, t['crop_variety_name'])} — ${t['stage_name']}',
                    subtitle:
                        '${t['trigger_type']} ${t['trigger_days_start']}-${t['trigger_days_end']}d${t['tree_age_bracket'] != null ? ' · ${t['tree_age_bracket']}y' : ''}',
                    onTap: () => _showStageTemplateDialog(template: t),
                  );
                },
              );
      case _Tab.sprayTemplates:
        return sprayTemplates.isEmpty
            ? _empty(loc.agriNoSprayTemplatesYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: sprayTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = sprayTemplates[i];
                  final dose = t['dose_per_acre'] ?? t['dose_per_tree'];
                  return _row(
                    title:
                        '${tl(context, t['crop_variety_name'])} — ${t['activity_type']}',
                    subtitle:
                        '${t['trigger_type']} +${t['trigger_days']}d${dose != null ? ' · $dose ${t['dose_unit'] ?? ''}' : ''}${t['sequence_order'] != null ? ' · seq ${t['sequence_order']}' : ''}',
                    onTap: () => _showSprayTemplateDialog(template: t),
                  );
                },
              );
    }
  }

  Widget _row({required String title, String? subtitle, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ],
            ]),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ]),
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Text(text,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      );
}
