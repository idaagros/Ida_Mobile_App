// lib/screens/admin/farm_tractor_master_screen.dart
//
// Admin setup for the Farm Tractor module: the fleet (tractors), and
// rates (tractor + work type + billing unit combination). Work types
// themselves are NOT managed here — they're the shared work_types
// list also used by Farm Attendance (see farm_masters_screen.dart's
// Work Types tab); this screen just fetches them filtered to
// applies_to=tractor.
//
// billing_unit lives on the RATE, not the work type — one work type
// (e.g. "Trolley/Transport") can have more than one rate row with
// different billing units (per trip, per day).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../localization/app_localizations.dart';
import '../../localization/transliterate.dart';
import '../../services/responsive.dart';
import '../../services/api_service.dart';

enum _Tab { tractors, rateCard }

class FarmTractorMasterScreen extends StatefulWidget {
  const FarmTractorMasterScreen({super.key});
  @override
  State<FarmTractorMasterScreen> createState() =>
      _FarmTractorMasterScreenState();
}

class _FarmTractorMasterScreenState extends State<FarmTractorMasterScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  _Tab _tab = _Tab.tractors;
  List tractors = [];
  List workTypes = [];
  List rateCard = [];
  bool loading = true;
  bool canAdd = false;
  bool canUpdate = false;

  static const billingUnits = ['hour', 'acre', 'bag', 'trip', 'day'];

  @override
  void initState() {
    super.initState();
    ApiService.canAdd('farm_tractor').then((v) {
      if (mounted) setState(() => canAdd = v);
    });
    ApiService.canUpdate('farm_tractor').then((v) {
      if (mounted) setState(() => canUpdate = v);
    });
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
        http.get(Uri.parse('$baseUrl/farm-tractor/tractors?all=1'), headers: h),
        http.get(Uri.parse('$baseUrl/work-types?applies_to=tractor'),
            headers: h),
        http.get(Uri.parse('$baseUrl/farm-tractor/rate-card'), headers: h),
      ]);
      if (results[0].statusCode == 200) tractors = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) workTypes = jsonDecode(results[1].body);
      if (results[2].statusCode == 200) rateCard = jsonDecode(results[2].body);
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

  void _showTractorDialog({Map? tractor}) {
    final loc = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: tractor?['name'] ?? '');
    final regCtrl =
        TextEditingController(text: tractor?['registration_number'] ?? '');
    final hpCtrl =
        TextEditingController(text: tractor?['hp']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tractor == null ? loc.ftAddTractor : loc.ftEditTractor,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
                labelText: loc.ftTractorNameLabel,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: regCtrl,
            decoration: InputDecoration(
                labelText: loc.ftRegistrationLabel,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hpCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: loc.ftHpLabel,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final h = await _headers;
              final body = jsonEncode({
                'name': nameCtrl.text.trim(),
                'registration_number': regCtrl.text.trim(),
                'hp': double.tryParse(hpCtrl.text.trim())
              });
              final res = tractor == null
                  ? await http.post(Uri.parse('$baseUrl/farm-tractor/tractors'),
                      headers: {...h, 'Content-Type': 'application/json'},
                      body: body)
                  : await http.patch(
                      Uri.parse(
                          '$baseUrl/farm-tractor/tractors/${tractor['id']}'),
                      headers: {...h, 'Content-Type': 'application/json'},
                      body: body);
              if (ctx.mounted) Navigator.pop(ctx);
              if (res.statusCode == 200 || res.statusCode == 201) {
                _loadAll();
                _showSnack(
                    tractor == null ? loc.ftAddTractor : loc.ftEditTractor);
              } else {
                _showSnack(loc.ftFailedAssign, isError: true);
              }
            },
            child: Text(loc.save, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRateDialog() {
    final loc = AppLocalizations.of(context)!;
    int? tractorId = tractors.isNotEmpty ? tractors.first['id'] : null;
    int? workTypeId = workTypes.isNotEmpty ? workTypes.first['id'] : null;
    String billingUnit = billingUnits.first;
    final rateCtrl = TextEditingController();
    DateTime effectiveFrom = DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.ftSetRate,
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
              DropdownButtonFormField<String>(
                value: billingUnit,
                decoration: InputDecoration(
                    labelText: loc.ftBillingUnitLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: billingUnits
                    .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u[0].toUpperCase() + u.substring(1))))
                    .toList(),
                onChanged: (v) => setDialogState(() => billingUnit = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.ftRateLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: effectiveFrom,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (picked != null)
                    setDialogState(() => effectiveFrom = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.ftEffectiveFromLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(effectiveFrom)),
                ),
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
                    workTypeId == null ||
                    rateCtrl.text.trim().isEmpty) return;
                final h = await _headers;
                final res = await http.post(
                  Uri.parse('$baseUrl/farm-tractor/rate-card'),
                  headers: {...h, 'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'tractor_id': tractorId,
                    'work_type_id': workTypeId,
                    'billing_unit': billingUnit,
                    'rate': double.tryParse(rateCtrl.text.trim()),
                    'effective_from':
                        DateFormat('yyyy-MM-dd').format(effectiveFrom),
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (res.statusCode == 201) {
                  _loadAll();
                  _showSnack(loc.ftSetRate);
                } else {
                  final data = jsonDecode(res.body);
                  _showSnack(data['error'] ?? loc.ftFailedAssign,
                      isError: true);
                }
              },
              child:
                  Text(loc.save, style: const TextStyle(color: Colors.white)),
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
        title: Text(loc.ftSetupTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: !canAdd
          ? null
          : FloatingActionButton(
              backgroundColor: idaGreen,
              onPressed: () {
                switch (_tab) {
                  case _Tab.tractors:
                    _showTractorDialog();
                    break;
                  case _Tab.rateCard:
                    _showRateDialog();
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
            _segment(loc.ftTractorsTab, _Tab.tractors, tractors.length),
            const SizedBox(width: 8),
            _segment(loc.ftRatesTab, _Tab.rateCard, rateCard.length),
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
      case _Tab.tractors:
        return tractors.isEmpty
            ? _empty(loc.ftNoTractorsYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: tractors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = tractors[i];
                  return _row(
                    title: tl(context, t['name'] ?? ''),
                    subtitle: [
                      if (t['registration_number'] != null)
                        t['registration_number'],
                      if (t['hp'] != null) '${t['hp']} HP'
                    ].join(' · '),
                    onTap:
                        canUpdate ? () => _showTractorDialog(tractor: t) : null,
                  );
                },
              );
      case _Tab.rateCard:
        return rateCard.isEmpty
            ? _empty(loc.ftNoRatesYet)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: rateCard.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = rateCard[i];
                  return _row(
                    title:
                        '${tl(context, r['tractor_name'])} — ${tl(context, r['work_type_name'])}',
                    subtitle:
                        '₹${r['rate']} per ${r['billing_unit']} · from ${r['effective_from']}',
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
