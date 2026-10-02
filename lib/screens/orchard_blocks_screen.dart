// lib/screens/orchard_blocks_screen.dart
//
// Orchard blocks (moved out of Agronomy setup in Sep 2026 — they are
// farm records, not setup; the web app has them under Agriculture too).
// Same list and add/edit dialog as before. The variety picker only
// shows PERENNIAL varieties (matches the backend's own validation).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../services/responsive.dart';

class OrchardBlocksScreen extends StatefulWidget {
  const OrchardBlocksScreen({super.key});
  @override
  State<OrchardBlocksScreen> createState() => _OrchardBlocksScreenState();
}

class _OrchardBlocksScreenState extends State<OrchardBlocksScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  List farms = [];
  List varieties = [];
  List orchardBlocks = [];
  bool loading = true;
  bool _canAddAgri = false;

  List get perennialVarieties =>
      varieties.where((v) => v['crop_type'] == 'perennial').toList();

  @override
  void initState() {
    super.initState();
    _loadAll();
    ApiService.canAdd('agri').then((v) {
      if (mounted) setState(() => _canAddAgri = v);
    });
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        Api.get('/farms'),
        Api.get('/agri/crop-varieties'),
        Api.get('/agri/orchard-blocks'),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) varieties = jsonDecode(results[1].body);
      if (results[2].statusCode == 200) orchardBlocks = jsonDecode(results[2].body);
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
                      http.Response res;
                      if (block == null) {
                        res = await Api.post(
                          '/agri/orchard-blocks',
                          body: {
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
                          },
                        );
                      } else {
                        res = await Api.patch(
                          '/agri/orchard-blocks/${block['id']}',
                          body: {
                            'row_spacing_m':
                                double.tryParse(rowSpacingCtrl.text.trim()),
                            'plant_spacing_m':
                                double.tryParse(plantSpacingCtrl.text.trim()),
                            'no_of_trees': int.tryParse(treesCtrl.text.trim()),
                            'area_acre': double.tryParse(areaCtrl.text.trim()),
                            'status': status,
                          },
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (res.statusCode == 200 || res.statusCode == 201) {
                        _loadAll();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.agriOrchardBlocksTab,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: !_canAddAgri
          ? null
          : FloatingActionButton(
              backgroundColor: idaGreen,
              onPressed: () => _showOrchardBlockDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: Responsive.constrainedContent(
          context,
          loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : orchardBlocks.isEmpty
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
                    )),
    );
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
