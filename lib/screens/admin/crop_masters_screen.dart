// lib/screens/admin/crop_masters_screen.dart
//
// Crop Masters: Crops + Varieties, the two simplest agri masters —
// plain name+category forms, no trigger/day-range logic. Mirrors
// farm_masters_screen.dart's tabbed pattern.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../localization/transliterate.dart';
import '../../services/api_service.dart';
import '../../services/api_client.dart';
import '../../services/responsive.dart';
import 'admin_common.dart' show AChip, MasterLifecycle, MasterStatusToggle, isRowActive, usedCountOf;

enum _Tab { crops, varieties }

class CropMastersScreen extends StatefulWidget {
  const CropMastersScreen({super.key});
  @override
  State<CropMastersScreen> createState() => _CropMastersScreenState();
}

class _CropMastersScreenState extends State<CropMastersScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  _Tab _tab = _Tab.crops;
  List crops = [];
  List varieties = [];
  bool loading = true;
  bool _canAddAgri = false;
  // Active / Inactive switch above the lists (default Active)
  bool showInactive = false;

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
        Api.get('/agri/crops?all=1'),
        Api.get('/agri/crop-varieties?all=1'),
      ]);
      if (results[0].statusCode == 200) crops = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) varieties = jsonDecode(results[1].body);
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

  void _showCropDialog({Map? crop}) {
    final loc = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: crop?['name'] ?? '');
    final categoryCtrl = TextEditingController(text: crop?['category'] ?? '');
    String cropType = crop?['crop_type'] ?? 'seasonal';
    bool submitting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(crop == null ? loc.agriAddCrop : loc.agriEditCrop,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                  labelText: loc.agriCropNameLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryCtrl,
              decoration: InputDecoration(
                  labelText: loc.agriCategoryLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cropType,
              decoration: InputDecoration(
                  labelText: loc.agriCropTypeLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
              items: [
                DropdownMenuItem(
                    value: 'seasonal', child: Text(loc.agriSeasonal)),
                DropdownMenuItem(
                    value: 'perennial', child: Text(loc.agriPerennial)),
              ],
              onChanged: (v) => setDialogState(() => cropType = v!),
            ),
            if (crop != null)
              MasterLifecycle(
                path: '/agri/crops/${crop['id']}',
                module: 'agri',
                itemName: '${crop['name'] ?? ''}',
                isActive: isRowActive(crop),
                usedCount: usedCountOf(crop),
                onDone: (msg) {
                  Navigator.pop(ctx);
                  _showSnack(msg);
                  _loadAll();
                },
              ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: submitting
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setDialogState(() => submitting = true);
                      final body = {
                        'name': nameCtrl.text.trim(),
                        'category': categoryCtrl.text.trim(),
                        'crop_type': cropType
                      };
                      final res = crop == null
                          ? await Api.post('/agri/crops', body: body)
                          : await Api.patch('/agri/crops/${crop['id']}',
                              body: body);
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

  // Crops that can be picked for a new variety
  List _activeCrops() => crops.where(isRowActive).toList();

  // Rows of [all] for the chosen Active / Inactive view
  List _shown(List all) => all.where((r) => isRowActive(r) != showInactive).toList();

  void _showVarietyDialog({Map? variety}) {
    final loc = AppLocalizations.of(context)!;
    int? cropId =
        variety?['crop_id'] ?? (_activeCrops().isNotEmpty ? _activeCrops().first['id'] : null);
    final nameCtrl = TextEditingController(text: variety?['name'] ?? '');
    final notesCtrl =
        TextEditingController(text: variety?['source_notes'] ?? '');
    final maturityCtrl = TextEditingController(
        text: variety?['maturity_days']?.toString() ?? '');
    final yieldCtrl = TextEditingController(
        text: variety?['std_yield_per_plant']?.toString() ?? '');
    final yieldUnitCtrl =
        TextEditingController(text: variety?['std_yield_unit'] ?? '');
    bool submitting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              variety == null ? loc.agriAddVariety : loc.agriEditVariety,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: crops.any((c) => c['id'] == cropId) ? cropId : null,
                decoration: InputDecoration(
                    labelText: loc.agriCropNameLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                // new variety: active crops only; editing: the crop is fixed
                items: crops
                    .where((c) => isRowActive(c) || c['id'] == cropId)
                    .map<DropdownMenuItem<int>>((c) => DropdownMenuItem(
                        value: c['id'], child: Text(tl(context, c['name']))))
                    .toList(),
                onChanged: variety == null
                    ? (v) => setDialogState(() => cropId = v)
                    : null, // crop_id fixed once created
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriVarietyNameLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: loc.agriSourceNotesLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maturityCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: loc.agriMaturityDaysLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: yieldCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.agriStdYieldLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: yieldUnitCtrl,
                decoration: InputDecoration(
                    labelText: loc.agriYieldUnitLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              if (variety != null)
                MasterLifecycle(
                path: '/agri/crop-varieties/${variety['id']}',
                module: 'agri',
                itemName: '${variety['name'] ?? ''}',
                isActive: isRowActive(variety),
                usedCount: usedCountOf(variety),
                onDone: (msg) {
                  Navigator.pop(ctx);
                  _showSnack(msg);
                  _loadAll();
                },
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
                      if (cropId == null || nameCtrl.text.trim().isEmpty)
                        return;
                      setDialogState(() => submitting = true);
                      final body = {
                        'crop_id': cropId,
                        'name': nameCtrl.text.trim(),
                        'source_notes': notesCtrl.text.trim(),
                        'maturity_days': int.tryParse(maturityCtrl.text.trim()),
                        'std_yield_per_plant':
                            double.tryParse(yieldCtrl.text.trim()),
                        'std_yield_unit': yieldUnitCtrl.text.trim(),
                      };
                      final res = variety == null
                          ? await Api.post('/agri/crop-varieties', body: body)
                          : await Api.patch(
                              '/agri/crop-varieties/${variety['id']}',
                              body: body);
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
        title: Text(loc.agriCropMastersTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: !_canAddAgri
          ? null
          : FloatingActionButton(
              backgroundColor: idaGreen,
              onPressed: () {
                if (_tab == _Tab.crops) {
                  _showCropDialog();
                } else {
                  if (_activeCrops().isEmpty) {
                    _showSnack('Add a crop first', isError: true);
                    return;
                  }
                  _showVarietyDialog();
                }
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: Column(children: [
        Container(
          color: idaDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(children: [
            _segment(loc.agriCropsTab, _Tab.crops, _shown(crops).length),
            const SizedBox(width: 8),
            _segment(loc.agriVarietiesTab, _Tab.varieties, _shown(varieties).length),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: MasterStatusToggle(
              showInactive: showInactive,
              activeCount: (_tab == _Tab.crops ? crops : varieties).where(isRowActive).length,
              inactiveCount: (_tab == _Tab.crops ? crops : varieties).where((r) => !isRowActive(r)).length,
              onChanged: (v) => setState(() => showInactive = v),
            ),
          ),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: selected ? idaGreen : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Text('$label ($count)',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations loc) {
    switch (_tab) {
      case _Tab.crops:
        final shownCrops = _shown(crops);
        return shownCrops.isEmpty
            ? _empty(crops.isEmpty ? loc.agriNoCropsYet : (showInactive ? loc.miNoneInactive : loc.miNoneActive))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: shownCrops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = shownCrops[i];
                  return _row(
                    active: isRowActive(c),
                    title: tl(context, c['name'] ?? ''),
                    subtitle:
                        '${c['crop_type'] == 'seasonal' ? loc.agriSeasonal : loc.agriPerennial}${c['category'] != null ? ' · ${c['category']}' : ''}',
                    onTap: () => _showCropDialog(crop: c),
                  );
                },
              );
      case _Tab.varieties:
        final shownVarieties = _shown(varieties);
        return shownVarieties.isEmpty
            ? _empty(varieties.isEmpty ? loc.agriNoVarietiesYet : (showInactive ? loc.miNoneInactive : loc.miNoneActive))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: shownVarieties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final v = shownVarieties[i];
                  return _row(
                    active: isRowActive(v),
                    cropInactive: v['crop_is_active'] == 0 || v['crop_is_active'] == false,
                    title: tl(context, v['name'] ?? ''),
                    subtitle:
                        '${tl(context, v['crop_name'])}${v['maturity_days'] != null ? ' · ${v['maturity_days']}d' : ''}',
                    onTap: () => _showVarietyDialog(variety: v),
                  );
                },
              );
    }
  }

  Widget _row(
      {required String title,
      String? subtitle,
      VoidCallback? onTap,
      bool active = true,
      bool cropInactive = false}) {
    final loc = AppLocalizations.of(context)!;
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
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.black87 : Colors.grey),
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
          if (cropInactive && active) ...[
            AChip.wait(loc.miCropInactive),
            const SizedBox(width: 6),
          ],
          if (!active) ...[
            AChip(loc.miInactive),
            const SizedBox(width: 6),
          ],
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
