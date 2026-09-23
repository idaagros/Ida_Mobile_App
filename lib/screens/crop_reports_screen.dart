// lib/screens/crop_reports_screen.dart
//
// Two tabs, matching the two report types built server-side:
//
// Planning — "what's due when" across every farm/crop at once, for
// forward planning. Flexible date range (no hardcoded window), plus
// optional farm/variety/status filters.
//
// Cost & Yield — "slice and dice" cost/labor/yield totals across both
// cycle types, pick any combination of Farm/Crop/Variety/Cycle Type/
// Year to group by. Mirrors Farm Attendance's dynamic report pattern
// exactly (same xlsx download/share flow via pdf_download_helper.dart).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crop_calendar_screen.dart';
import '../services/pdf_download_helper.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class CropReportsScreen extends StatefulWidget {
  const CropReportsScreen({super.key});
  @override
  State<CropReportsScreen> createState() => _CropReportsScreenState();
}

class _CropReportsScreenState extends State<CropReportsScreen>
    with SingleTickerProviderStateMixin {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  late TabController _tabController;
  List farms = [];
  List varieties = [];

  // Planning tab state
  DateTime planFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime planTo = DateTime.now().add(const Duration(days: 30));
  int? planFarmId;
  int? planVarietyId;
  bool showOverdue = true;
  bool showPending = true;
  Map? planningReport;
  bool loadingPlanning = false;

  // Cost & Yield tab state
  DateTime costFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime costTo = DateTime.now();
  final Set<String> groupByDims = {'farm'};
  Map? costReport;
  bool loadingCost = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFilters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadFilters() async {
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/agri/crop-varieties'), headers: h),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) varieties = jsonDecode(results[1].body);
      if (mounted) setState(() {});
      _runPlanningReport();
    } catch (e) {
      debugPrint('Load filters error: $e');
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

  // ── Planning tab ─────────────────────────────────────────────────
  Future<void> _runPlanningReport() async {
    setState(() => loadingPlanning = true);
    try {
      final h = await _headers;
      final statuses = [if (showOverdue) 'overdue', if (showPending) 'pending'];
      final params = {
        'from': DateFormat('yyyy-MM-dd').format(planFrom),
        'to': DateFormat('yyyy-MM-dd').format(planTo),
        'status': statuses.join(','),
        if (planFarmId != null) 'farm_id': planFarmId.toString(),
        if (planVarietyId != null) 'crop_variety_id': planVarietyId.toString(),
      };
      final uri = Uri.parse('$baseUrl/agri/reports/planning')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: h);
      if (res.statusCode == 200) {
        setState(() => planningReport = jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint('Planning report error: $e');
    } finally {
      if (mounted) setState(() => loadingPlanning = false);
    }
  }

  Future<void> _pickPlanDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? planFrom : planTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => isFrom ? planFrom = picked : planTo = picked);
      _runPlanningReport();
    }
  }

  // ── Cost & Yield tab ─────────────────────────────────────────────
  Future<void> _pickCostDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? costFrom : costTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null)
      setState(() => isFrom ? costFrom = picked : costTo = picked);
  }

  Future<void> _generateCostReport() async {
    final loc = AppLocalizations.of(context)!;
    setState(() => loadingCost = true);
    try {
      final h = await _headers;
      final params = {
        'from': DateFormat('yyyy-MM-dd').format(costFrom),
        'to': DateFormat('yyyy-MM-dd').format(costTo),
        'group_by': groupByDims.join(','),
      };
      final uri = Uri.parse('$baseUrl/agri/reports/cost-yield')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: h);
      if (res.statusCode == 200) {
        setState(() => costReport = jsonDecode(res.body));
      } else {
        final data = jsonDecode(res.body);
        _showSnack(data['error'] ?? loc.agriFailedSave, isError: true);
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => loadingCost = false);
    }
  }

  Future<void> _exportCostReportXlsx() async {
    try {
      final h = await _headers;
      final from = DateFormat('yyyy-MM-dd').format(costFrom);
      final to = DateFormat('yyyy-MM-dd').format(costTo);
      final params = {
        'from': from,
        'to': to,
        'group_by': groupByDims.join(','),
        'format': 'xlsx'
      };
      final uri = Uri.parse('$baseUrl/agri/reports/cost-yield')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: h);
      if (res.statusCode == 200) {
        final filename = 'agri-cost-yield-report_${from}_to_$to.xlsx';
        final result = await savePdfBytes(res.bodyBytes, filename);
        if (!mounted) return;
        if (result.isWeb) {
          _showSnack('Report downloaded');
        } else {
          _showResultSheet(result.filePath!, filename);
        }
      } else {
        _showSnack('Failed to export report', isError: true);
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showResultSheet(String filePath, String filename) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: idaGreen.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.grid_on, color: idaGreen, size: 28),
          ),
          const SizedBox(height: 14),
          const Text('Report ready',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(filename,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: idaGreen,
                    side: const BorderSide(color: idaGreen),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () {
                  Navigator.pop(context);
                  Share.shareXFiles([XFile(filePath)],
                      text: 'Ida AgriCo Crop Cost & Yield Report');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: idaGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () {
                  Navigator.pop(context);
                  OpenFilex.open(filePath);
                },
              ),
            ),
          ]),
        ]),
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
        title: Text(loc.agriReportsTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: loc.agriPlanningTab),
            Tab(text: loc.agriCostYieldTab)
          ],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [
        _buildPlanningTab(loc),
        _buildCostYieldTab(loc),
      ]),
    );
  }

  Widget _buildPlanningTab(AppLocalizations loc) {
    final items = planningReport?['items'] as List? ?? [];
    final byFarm = planningReport?['by_farm'] as Map? ?? {};

    return RefreshIndicator(
      color: idaGreen,
      onRefresh: _runPlanningReport,
      child: Responsive.constrainedContent(
          context,
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                    child: _dateChip(loc.agriFromDateLabel, planFrom,
                        () => _pickPlanDate(true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _dateChip(loc.agriToDateLabel, planTo,
                        () => _pickPlanDate(false))),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                value: planFarmId,
                decoration: InputDecoration(
                    labelText: loc.agriFarmLabel,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  DropdownMenuItem(value: null, child: Text(loc.agriAllFarms)),
                  ...farms.map<DropdownMenuItem<int?>>((f) => DropdownMenuItem(
                      value: f['id'], child: Text(tl(context, f['name'])))),
                ],
                onChanged: (v) {
                  setState(() => planFarmId = v);
                  _runPlanningReport();
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                value: planVarietyId,
                decoration: InputDecoration(
                    labelText: loc.agriVarietyLabel,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  DropdownMenuItem(
                      value: null, child: Text(loc.agriAllVarieties)),
                  ...varieties.map<
                      DropdownMenuItem<
                          int?>>((v) => DropdownMenuItem(
                      value: v['id'],
                      child: Text(
                          '${tl(context, v['crop_name'])} — ${tl(context, v['name'])}'))),
                ],
                onChanged: (v) {
                  setState(() => planVarietyId = v);
                  _runPlanningReport();
                },
              ),
              const SizedBox(height: 10),
              Row(children: [
                FilterChip(
                    label: Text(loc.agriOverdueOnly),
                    selected: showOverdue,
                    selectedColor: Colors.red.shade100,
                    onSelected: (v) {
                      setState(() => showOverdue = v);
                      _runPlanningReport();
                    }),
                const SizedBox(width: 8),
                FilterChip(
                    label: Text(loc.agriPendingOnly),
                    selected: showPending,
                    selectedColor: idaGreen.withOpacity(0.2),
                    onSelected: (v) {
                      setState(() => showPending = v);
                      _runPlanningReport();
                    }),
              ]),
              const SizedBox(height: 16),
              if (loadingPlanning)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(color: idaGreen)))
              else if (planningReport != null) ...[
                Row(children: [
                  _statCard(loc.agriTotalItems,
                      '${planningReport!['total_items']}', idaDark),
                  const SizedBox(width: 8),
                  _statCard(loc.agriOverdueOnly,
                      '${planningReport!['overdue_count']}', Colors.red),
                  const SizedBox(width: 8),
                  _statCard(loc.agriPendingOnly,
                      '${planningReport!['pending_count']}', idaGreen),
                ]),
                if (byFarm.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(loc.agriByFarm,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: byFarm.entries.map((e) {
                        final counts = e.value as Map;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E7D8))),
                          child: Text(
                              '${tl(context, e.key)}: ${counts['overdue'] ?? 0} overdue, ${counts['pending'] ?? 0} upcoming',
                              style: const TextStyle(fontSize: 11.5)),
                        );
                      }).toList()),
                ],
                const SizedBox(height: 16),
                if (items.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                          child: Text(loc.agriNoPendingItems,
                              style: TextStyle(color: Colors.grey.shade500))))
                else
                  ...items.map((item) => _planningItemCard(item)),
              ],
            ],
          )),
    );
  }

  Widget _planningItemCard(Map item) {
    final isOverdue = item['status'] == 'overdue';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CropCalendarScreen(
                      cycleType: item['cycle_type'],
                      cycleId: item['cycle_id'],
                      title:
                          '${tl(context, item['crop_variety_name'] ?? '')} — ${tl(context, item['farm_name'] ?? '')}',
                    ))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (isOverdue ? Colors.red : idaGreen).withOpacity(0.3))),
          child: Row(children: [
            Icon(
                item['source_type'] == 'stage'
                    ? Icons.local_florist_outlined
                    : Icons.water_drop_outlined,
                size: 16,
                color: isOverdue ? Colors.red : idaGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        tl(context,
                            item['label'] ?? item['activity_type'] ?? '—'),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                    const SizedBox(height: 3),
                    Text(
                        '${tl(context, item['farm_name'] ?? '')} · ${tl(context, item['crop_variety_name'] ?? '')} · due ${item['planned_date']}',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildCostYieldTab(AppLocalizations loc) {
    final rows = costReport?['rows'] as List? ?? [];
    final dimLabels = costReport?['dimension_labels'] as List? ?? [];

    return Responsive.constrainedContent(
        context,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                  child: _dateChip(loc.agriFromDateLabel, costFrom,
                      () => _pickCostDate(true))),
              const SizedBox(width: 8),
              Expanded(
                  child: _dateChip(
                      loc.agriToDateLabel, costTo, () => _pickCostDate(false))),
            ]),
            const SizedBox(height: 12),
            Text(loc.agriGroupByLabel,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.6)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _dimChip('farm', 'Farm'),
              _dimChip('crop', 'Crop'),
              _dimChip('variety', 'Variety'),
              _dimChip('cycle_type', 'Cycle Type'),
              _dimChip('year', 'Year'),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bar_chart,
                      size: 18, color: Colors.white),
                  label: Text(loc.agriGenerateReport,
                      style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: idaGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: loadingCost ? null : _generateCostReport,
                ),
              ),
              if (costReport != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _exportCostReportXlsx,
                  icon: const Icon(Icons.download, color: idaGreen),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: idaGreen)),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            if (loadingCost)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(color: idaGreen)))
            else if (costReport == null)
              Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                      child: Text(loc.agriNoReportYet,
                          style: TextStyle(color: Colors.grey.shade500))))
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(idaDark),
                  headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                  dataTextStyle: const TextStyle(fontSize: 12),
                  columns: [
                    ...dimLabels
                        .map((d) => DataColumn(label: Text(tl(context, d)))),
                    DataColumn(label: Text(loc.agriInputCostCol)),
                    DataColumn(label: Text(loc.agriLaborCostCol)),
                    DataColumn(label: Text(loc.agriTotalCostCol)),
                    DataColumn(label: Text(loc.agriYieldCol)),
                    DataColumn(label: Text(loc.agriCostPerKgCol)),
                  ],
                  rows: [
                    ...rows.map((r) => DataRow(cells: [
                          ...List.generate(
                              dimLabels.length,
                              (i) => DataCell(Text(
                                  tl(context, '${r['level${i + 1}'] ?? ''}')))),
                          DataCell(Text('₹${r['input_cost']}')),
                          DataCell(Text('₹${r['labor_cost']}')),
                          DataCell(Text('₹${r['total_cost']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                          DataCell(Text('${r['total_yield']}')),
                          DataCell(Text(r['cost_per_kg'] != null
                              ? '₹${r['cost_per_kg']}'
                              : '—')),
                        ])),
                    DataRow(
                      color: WidgetStateProperty.all(idaGreen.withOpacity(0.1)),
                      cells: [
                        DataCell(Text(loc.agriGrandTotal,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        ...List.generate(
                            dimLabels.length > 1 ? dimLabels.length - 1 : 0,
                            (_) => const DataCell(Text(''))),
                        DataCell(Text('₹${costReport!['grand_input_cost']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text('₹${costReport!['grand_labor_cost']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text('₹${costReport!['grand_total_cost']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text('${costReport!['grand_total_yield']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                        const DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ));
  }

  Widget _dimChip(String key, String label) {
    final selected = groupByDims.contains(key);
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: idaGreen.withOpacity(0.2),
      checkmarkColor: idaGreen,
      onSelected: (v) =>
          setState(() => v ? groupByDims.add(key) : groupByDims.remove(key)),
    );
  }

  Widget _dateChip(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(DateFormat('dd MMM yyyy').format(date),
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}
