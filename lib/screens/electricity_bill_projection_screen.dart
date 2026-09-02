// lib/screens/electricity_bill_projection_screen.dart
//
// Projects this month's electricity bill from readings so far, using
// the configurable tariff rates. See electricityBillProjection.js on
// the backend for the full reasoning - this screen is a straight
// display of whatever that endpoint returns, plus a settings sheet
// for editing the rates.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ElectricityBillProjectionScreen extends StatefulWidget {
  const ElectricityBillProjectionScreen({super.key});
  @override
  State<ElectricityBillProjectionScreen> createState() => _ElectricityBillProjectionScreenState();
}

class _ElectricityBillProjectionScreenState extends State<ElectricityBillProjectionScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  bool loading = true;
  Map<String, dynamic>? data;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/electricity-bill/projection'), headers: h);
      if (res.statusCode == 200) {
        setState(() => data = jsonDecode(res.body));
      } else {
        setState(() => error = 'Failed to load projection');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _rupees(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v : double.tryParse(v.toString()) ?? 0;
    return '₹${n.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d)\.)'), (m) => ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Electricity Bill Projection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Tariff Settings',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const TariffSettingsScreen()));
              _load();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(12)),
                      child: Text(error!, style: const TextStyle(color: Color(0xFFC0392B), fontSize: 13)),
                    )
                  else if (data != null && data!['available'] == false)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFFEF3DC), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: Color(0xFF92600A)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(data!['reason'] ?? 'Projection not available yet.', style: const TextStyle(fontSize: 13, color: Color(0xFF92600A)))),
                      ]),
                    )
                  else if (data != null) ...[
                    _totalCard(data!),
                    const SizedBox(height: 16),
                    if (data!['cost_of_poor_pf'] != null) _pfCostCard(data!),
                    const SizedBox(height: 16),
                    _breakdownCard(data!),
                    const SizedBox(height: 16),
                    _basisCard(data!),
                    const SizedBox(height: 12),
                    Text(
                      data!['excluded_note'] ?? '',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _totalCard(Map d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: idaDark, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text('PROJECTED BILL — ${d['days_in_month']} DAY MONTH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.7), letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Text(_rupees(d['projected_total']), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Based on ${d['day_of_month']} of ${d['days_in_month']} days · ${d['reading_count']} reading(s) so far', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
      ]),
    );
  }

  Widget _pfCostCard(Map d) {
    final cost = d['cost_of_poor_pf'];
    final pf = d['avg_power_factor'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF5C6C6))),
      child: Row(children: [
        const Icon(Icons.trending_down, color: Color(0xFFC0392B)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Poor power factor is costing you approximately ${_rupees(cost)} this month', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
            if (pf != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('At average PF ${(pf as num).toStringAsFixed(3)}, versus the ideal of 1.0', style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _breakdownCard(Map d) {
    final b = d['breakdown'] as Map;
    Widget row(String label, dynamic value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
            Text(_rupees(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BREAKDOWN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.6)),
        const Divider(height: 18),
        row('Energy charge', b['energy_charge']),
        row('Wheeling charge', b['wheeling_charge']),
        row('FAC', b['fac_charge']),
        row('Demand charge', b['demand_charge']),
        row('Electricity duty', b['electricity_duty']),
      ]),
    );
  }

  Widget _basisCard(Map d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF4F7F2), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Projected: ${d['projected_kwh']} kWh → ${d['projected_kvah']} kVAh (billed unit)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        if (d['pf_note'] != null) ...[
          const SizedBox(height: 4),
          Text(d['pf_note'], style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ],
      ]),
    );
  }
}

class TariffSettingsScreen extends StatefulWidget {
  const TariffSettingsScreen({super.key});
  @override
  State<TariffSettingsScreen> createState() => _TariffSettingsScreenState();
}

class _TariffSettingsScreenState extends State<TariffSettingsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
  }

  bool loading = true;
  bool saving = false;
  String? error;
  final energyCtrl = TextEditingController();
  final wheelingCtrl = TextEditingController();
  final facCtrl = TextEditingController();
  final demandRateCtrl = TextEditingController();
  final contractDemandCtrl = TextEditingController();
  final dutyCtrl = TextEditingController();
  String readingType = 'kwh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/electricity-bill/settings'), headers: h);
      if (res.statusCode == 200) {
        final s = jsonDecode(res.body);
        energyCtrl.text = s['energy_rate_per_unit'].toString();
        wheelingCtrl.text = s['wheeling_rate_per_unit'].toString();
        facCtrl.text = s['fac_rate_per_unit'].toString();
        demandRateCtrl.text = s['demand_rate_per_kva'].toString();
        contractDemandCtrl.text = s['contract_demand_kva'].toString();
        dutyCtrl.text = s['electricity_duty_pct'].toString();
        readingType = s['daily_reading_type'] ?? 'kwh';
      } else {
        setState(() => error = 'Failed to load settings');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() { saving = true; error = null; });
    try {
      final h = await _headers;
      final res = await http.put(
        Uri.parse('$baseUrl/electricity-bill/settings'),
        headers: h,
        body: jsonEncode({
          'energy_rate_per_unit': double.tryParse(energyCtrl.text.trim()),
          'wheeling_rate_per_unit': double.tryParse(wheelingCtrl.text.trim()),
          'fac_rate_per_unit': double.tryParse(facCtrl.text.trim()),
          'demand_rate_per_kva': double.tryParse(demandRateCtrl.text.trim()),
          'contract_demand_kva': double.tryParse(contractDemandCtrl.text.trim()),
          'electricity_duty_pct': double.tryParse(dutyCtrl.text.trim()),
          'daily_reading_type': readingType,
        }),
      );
      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context);
      } else {
        final data = jsonDecode(res.body);
        setState(() => error = data['error'] ?? 'Failed to save');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _rateField(String label, TextEditingController ctrl, {String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Tariff Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Enter these straight from your latest MSEDCL bill — the projection is only as accurate as the rates here.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(10)),
                    child: Text(error!, style: const TextStyle(color: Color(0xFFC0392B), fontSize: 12.5)),
                  ),
                  const SizedBox(height: 16),
                ],
                _rateField('Energy rate', energyCtrl, suffix: '₹/unit'),
                _rateField('Wheeling charge rate', wheelingCtrl, suffix: '₹/unit'),
                _rateField('FAC rate', facCtrl, suffix: '₹/unit'),
                _rateField('Demand charge rate', demandRateCtrl, suffix: '₹/KVA'),
                _rateField('Contract demand', contractDemandCtrl, suffix: 'KVA'),
                _rateField('Electricity duty', dutyCtrl, suffix: '%'),
                const SizedBox(height: 6),
                Text('DAILY READING TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E7D8))),
                  child: Column(children: [
                    RadioListTile<String>(
                      value: 'kwh',
                      groupValue: readingType,
                      onChanged: (v) => setState(() => readingType = v!),
                      title: const Text('kWh (needs PF conversion to bill on kVAh)', style: TextStyle(fontSize: 13)),
                      activeColor: idaGreen,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'kvah',
                      groupValue: readingType,
                      onChanged: (v) => setState(() => readingType = v!),
                      title: const Text('kVAh (already the billed unit, no conversion)', style: TextStyle(fontSize: 13)),
                      activeColor: idaGreen,
                      dense: true,
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: idaGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
    );
  }
}
