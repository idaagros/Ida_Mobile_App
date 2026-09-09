// lib/screens/attendance_report_screen.dart
//
// Two report generators for Farm Attendance, on one screen:
//
// 1. Worker Wage Report — Excel download matching the reference
//    layout: one row per worker, one column-group per date (Days /
//    Amount / Farm / Work Type), a running total-for-worker column,
//    and a Grand Total row.
//
// 2. Dynamic Report (slice & dice) — pick up to 3 grouping levels, in
//    order, from Farm / Worker / Work Type, over a date range. Any
//    level left as "None" is simply skipped — leaving all three as
//    None returns one overall total. Shown inline as a table, with an
//    Export to Excel option.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/pdf_download_helper.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});
  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

const _dimOptions = [
  {'key': null, 'label': 'None'},
  {'key': 'farm', 'label': 'Farm'},
  {'key': 'worker', 'label': 'Worker'},
  {'key': 'work_type', 'label': 'Work Type'},
  {'key': 'gender', 'label': 'Gender'},
];

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  // ── Report 1: Worker Wage Report ────────────────────────────
  DateTime _wageFrom = DateTime.now().subtract(const Duration(days: 6));
  DateTime _wageTo = DateTime.now();
  bool _generatingWageReport = false;
  String? _wageError;

  // ── Report 1b: Worker Wage Report, Male/Female split ─────────
  DateTime _genderSplitFrom = DateTime.now().subtract(const Duration(days: 6));
  DateTime _genderSplitTo = DateTime.now();
  bool _generatingGenderSplitReport = false;
  String? _genderSplitError;

  // ── Report 2: Dynamic Report ────────────────────────────────
  DateTime _dynFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _dynTo = DateTime.now();
  String? _level1;
  String? _level2;
  String? _level3;
  bool _loadingDynamic = false;
  bool _exportingDynamic = false;
  String? _dynError;
  Map<String, dynamic>? _dynResult;

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ── Report 1 actions ─────────────────────────────────────────
  Future<void> _pickWageDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _wageFrom : _wageTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _wageFrom = picked;
          if (_wageFrom.isAfter(_wageTo)) _wageTo = _wageFrom;
        } else {
          _wageTo = picked;
          if (_wageTo.isBefore(_wageFrom)) _wageFrom = _wageTo;
        }
      });
    }
  }

  Future<void> _generateWageReport() async {
    setState(() {
      _generatingWageReport = true;
      _wageError = null;
    });
    try {
      final h = await _headers;
      final from = _fmt(_wageFrom);
      final to = _fmt(_wageTo);
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/report?from=$from&to=$to'),
        headers: h,
      );
      if (res.statusCode == 200) {
        final filename = 'attendance-report_${from}_to_$to.xlsx';
        final result = await savePdfBytes(res.bodyBytes, filename);
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        if (result.isWeb) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.faReportDownloaded),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        } else {
          await _showResultSheet(result.filePath!, filename);
        }
      } else {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body);
        } catch (_) {}
        final serverMsg = data['error'] as String?;
        setState(() => _wageError = serverMsg ??
            'Server returned ${res.statusCode}: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}');
      }
    } catch (e) {
      setState(() => _wageError = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _generatingWageReport = false);
    }
  }

  // ── Report 1b actions ─────────────────────────────────────────
  Future<void> _pickGenderSplitDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _genderSplitFrom : _genderSplitTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _genderSplitFrom = picked;
          if (_genderSplitFrom.isAfter(_genderSplitTo))
            _genderSplitTo = _genderSplitFrom;
        } else {
          _genderSplitTo = picked;
          if (_genderSplitTo.isBefore(_genderSplitFrom))
            _genderSplitFrom = _genderSplitTo;
        }
      });
    }
  }

  Future<void> _generateGenderSplitReport() async {
    setState(() {
      _generatingGenderSplitReport = true;
      _genderSplitError = null;
    });
    try {
      final h = await _headers;
      final from = _fmt(_genderSplitFrom);
      final to = _fmt(_genderSplitTo);
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/report-gender-split?from=$from&to=$to'),
        headers: h,
      );
      if (res.statusCode == 200) {
        final filename = 'attendance-report-gender-split_${from}_to_$to.xlsx';
        final result = await savePdfBytes(res.bodyBytes, filename);
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        if (result.isWeb) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.faReportDownloaded),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        } else {
          await _showResultSheet(result.filePath!, filename);
        }
      } else {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body);
        } catch (_) {}
        final serverMsg = data['error'] as String?;
        setState(() => _genderSplitError = serverMsg ??
            'Server returned ${res.statusCode}: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}');
      }
    } catch (e) {
      setState(() => _genderSplitError = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _generatingGenderSplitReport = false);
    }
  }

  // ── Report 2 actions ─────────────────────────────────────────
  Future<void> _pickDynDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dynFrom : _dynTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dynFrom = picked;
          if (_dynFrom.isAfter(_dynTo)) _dynTo = _dynFrom;
        } else {
          _dynTo = picked;
          if (_dynTo.isBefore(_dynFrom)) _dynFrom = _dynTo;
        }
      });
    }
  }

  String get _groupByParam =>
      [_level1, _level2, _level3].where((l) => l != null).join(',');

  Future<void> _runDynamicReport() async {
    setState(() {
      _loadingDynamic = true;
      _dynError = null;
    });
    try {
      final h = await _headers;
      final from = _fmt(_dynFrom);
      final to = _fmt(_dynTo);
      final groupBy = _groupByParam;
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/dynamic-report?from=$from&to=$to'
            '${groupBy.isNotEmpty ? '&group_by=$groupBy' : ''}'),
        headers: h,
      );
      if (res.statusCode == 200) {
        setState(() => _dynResult = jsonDecode(res.body));
      } else {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body);
        } catch (_) {}
        final serverMsg = data['error'] as String?;
        setState(() => _dynError = serverMsg ??
            'Server returned ${res.statusCode}: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}');
      }
    } catch (e) {
      setState(() => _dynError = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _loadingDynamic = false);
    }
  }

  Future<void> _exportDynamicReport() async {
    setState(() {
      _exportingDynamic = true;
      _dynError = null;
    });
    try {
      final h = await _headers;
      final from = _fmt(_dynFrom);
      final to = _fmt(_dynTo);
      final groupBy = _groupByParam;
      final res = await http.get(
        Uri.parse('$baseUrl/attendance/dynamic-report?from=$from&to=$to'
            '${groupBy.isNotEmpty ? '&group_by=$groupBy' : ''}&format=xlsx'),
        headers: h,
      );
      if (res.statusCode == 200) {
        final filename = 'attendance-dynamic-report_${from}_to_$to.xlsx';
        final result = await savePdfBytes(res.bodyBytes, filename);
        if (!mounted) return;
        final loc = AppLocalizations.of(context)!;
        if (result.isWeb) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.faReportDownloaded),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        } else {
          await _showResultSheet(result.filePath!, filename);
        }
      } else {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body);
        } catch (_) {}
        final serverMsg = data['error'] as String?;
        setState(() => _dynError = serverMsg ??
            'Server returned ${res.statusCode}: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}');
      }
    } catch (e) {
      setState(() => _dynError = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _exportingDynamic = false);
    }
  }

  // Same Open/Share bottom sheet pattern already used correctly in
  // daily_reports_screen.dart and outward_register_report_screen.dart —
  // this screen was missing it, which is why a generated report
  // previously just said "Saved: filename.xlsx" with no way to actually
  // reach it: savePdfBytes() writes to the app's private temp/cache
  // directory (via path_provider's getTemporaryDirectory()), which
  // isn't visible in any file manager or Downloads app. Opening the
  // file directly (or sharing it) is what actually gets it somewhere
  // the user can use it, rather than just naming a path they can't browse to.
  Future<void> _showResultSheet(String filePath, String filename) async {
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Share.shareXFiles([XFile(filePath)],
                      text: 'Ida AgriCo Attendance Report');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new,
                    size: 18, color: Colors.white),
                label: const Text('Open',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: idaGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(AppLocalizations.of(context)!.faReportsTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Responsive.constrainedContent(
          context,
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _wageReportCard(),
              const SizedBox(height: 24),
              _genderSplitReportCard(),
              const SizedBox(height: 24),
              _dynamicReportCard(),
            ],
          )),
    );
  }

  // ── UI: Report 1 card ────────────────────────────────────────
  Widget _wageReportCard() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loc.faWorkerWageReportTitle,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: idaDark)),
        const SizedBox(height: 4),
        Text(
          loc.faWorkerWageReportDesc,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _dateField(
                  loc.faFrom, _wageFrom, () => _pickWageDate(isFrom: true))),
          const SizedBox(width: 10),
          Expanded(
              child: _dateField(
                  loc.faTo, _wageTo, () => _pickWageDate(isFrom: false))),
        ]),
        if (_wageError != null) ...[
          const SizedBox(height: 10),
          Text(_wageError!,
              style: const TextStyle(color: Colors.red, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _generatingWageReport
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.grid_on, color: Colors.white, size: 18),
            label: Text(
                _generatingWageReport
                    ? loc.faGenerating
                    : loc.faGenerateExcelReport,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: idaGreen,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _generatingWageReport ? null : _generateWageReport,
          ),
        ),
      ]),
    );
  }

  // ── UI: Report 1b card ───────────────────────────────────────
  Widget _genderSplitReportCard() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loc.faGenderSplitReportTitle,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: idaDark)),
        const SizedBox(height: 4),
        Text(
          loc.faGenderSplitReportDesc,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _dateField(loc.faFrom, _genderSplitFrom,
                  () => _pickGenderSplitDate(isFrom: true))),
          const SizedBox(width: 10),
          Expanded(
              child: _dateField(loc.faTo, _genderSplitTo,
                  () => _pickGenderSplitDate(isFrom: false))),
        ]),
        if (_genderSplitError != null) ...[
          const SizedBox(height: 10),
          Text(_genderSplitError!,
              style: const TextStyle(color: Colors.red, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _generatingGenderSplitReport
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.grid_on, color: Colors.white, size: 18),
            label: Text(
                _generatingGenderSplitReport
                    ? loc.faGenerating
                    : loc.faGenerateExcelReport,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: idaGreen,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _generatingGenderSplitReport
                ? null
                : _generateGenderSplitReport,
          ),
        ),
      ]),
    );
  }

  // ── UI: Report 2 card ────────────────────────────────────────
  Widget _dynamicReportCard() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E7D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loc.faDynamicReportTitle,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: idaDark)),
        const SizedBox(height: 4),
        Text(
          loc.faDynamicReportDesc,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _dateField(
                  loc.faFrom, _dynFrom, () => _pickDynDate(isFrom: true))),
          const SizedBox(width: 10),
          Expanded(
              child: _dateField(
                  loc.faTo, _dynTo, () => _pickDynDate(isFrom: false))),
        ]),
        const SizedBox(height: 12),
        _levelDropdown(loc.faSelection1, _level1,
            exclude: const [],
            onChanged: (v) => setState(() {
                  _level1 = v;
                  if (_level2 == v) _level2 = null;
                  if (_level3 == v) _level3 = null;
                })),
        const SizedBox(height: 10),
        _levelDropdown(loc.faSelection2, _level2,
            exclude: [if (_level1 != null) _level1!],
            onChanged: (v) => setState(() {
                  _level2 = v;
                  if (_level3 == v) _level3 = null;
                })),
        const SizedBox(height: 10),
        _levelDropdown(loc.faSelection3, _level3,
            exclude: [
              if (_level1 != null) _level1!,
              if (_level2 != null) _level2!
            ],
            onChanged: (v) => setState(() => _level3 = v)),
        if (_dynError != null) ...[
          const SizedBox(height: 10),
          Text(_dynError!,
              style: const TextStyle(color: Colors.red, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: _loadingDynamic
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.filter_alt_outlined,
                      color: Colors.white, size: 18),
              label: Text(_loadingDynamic ? loc.faGenerating : loc.faGenerate,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: idaGreen,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loadingDynamic ? null : _runDynamicReport,
            ),
          ),
          if (_dynResult != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: _exportingDynamic
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: idaGreen))
                    : const Icon(Icons.download_outlined,
                        size: 18, color: idaGreen),
                label: Text(
                    _exportingDynamic ? loc.faExporting : loc.faExportToExcel,
                    style: const TextStyle(
                        color: idaGreen, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: idaGreen,
                  side: const BorderSide(color: idaGreen),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _exportingDynamic ? null : _exportDynamicReport,
              ),
            ),
          ],
        ]),
        if (_dynResult != null) ...[
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _dynamicResultTable(),
        ],
      ]),
    );
  }

  String _dimLabel(AppLocalizations loc, String? key) {
    switch (key) {
      case 'farm':
        return loc.faFarm;
      case 'worker':
        return loc.faWorker;
      case 'work_type':
        return loc.faWorkType;
      case 'gender':
        return loc.faGender;
      default:
        return loc.faNone;
    }
  }

  Widget _dynamicResultTable() {
    final loc = AppLocalizations.of(context)!;
    final result = _dynResult!;
    final groupBy = List<String>.from(result['group_by'] ?? []);
    final dims = groupBy.map((k) => _dimLabel(loc, k)).toList();
    final rows = List<Map<String, dynamic>>.from(result['rows'] ?? []);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(loc.faNoEntriesRange,
            style: const TextStyle(color: Colors.black54, fontSize: 13)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F7F2)),
        columns: [
          ...dims.map((d) => DataColumn(
              label: Text(d,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5)))),
          DataColumn(
              label: Text(loc.faTotalDaysCol,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5))),
          DataColumn(
              label: Text(loc.faTotalWageCol,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5))),
          DataColumn(
              label: Text(loc.faEntriesCol,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
        rows: [
          ...rows.map((r) => DataRow(cells: [
                ...List.generate(dims.length, (i) {
                  final raw = r['level${i + 1}']?.toString() ?? '';
                  final isNameDim =
                      i < groupBy.length && groupBy[i] != 'gender';
                  return DataCell(Text(isNameDim ? tl(context, raw) : raw,
                      style: const TextStyle(fontSize: 12.5)));
                }),
                DataCell(Text(r['total_days'].toString(),
                    style: const TextStyle(fontSize: 12.5))),
                DataCell(Text('₹${r['total_wage']}',
                    style: const TextStyle(fontSize: 12.5))),
                DataCell(Text(r['entries'].toString(),
                    style: const TextStyle(fontSize: 12.5))),
              ])),
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFE8F5E2)),
            cells: [
              ...List.generate(
                  dims.length,
                  (i) => DataCell(Text(i == 0 ? loc.faGrandTotal : '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: idaGreen)))),
              DataCell(Text('${result['grand_total_days']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: idaGreen))),
              DataCell(Text('₹${result['grand_total_wage']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: idaGreen))),
              DataCell(Text('${result['grand_entries']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: idaGreen))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E7D8)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.calendar_today, size: 14, color: idaGreen),
            const SizedBox(width: 6),
            Text(DateFormat('dd MMM yyyy').format(value),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: idaDark)),
          ]),
        ]),
      ),
    );
  }

  Widget _levelDropdown(String label, String? value,
      {required List<String> exclude,
      required ValueChanged<String?> onChanged}) {
    final loc = AppLocalizations.of(context)!;
    final options = _dimOptions
        .where((o) => o['key'] == null || !exclude.contains(o['key']))
        .toList();
    return DropdownButtonFormField<String?>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: idaGreen, width: 1.5)),
      ),
      items: options
          .map<DropdownMenuItem<String?>>((o) => DropdownMenuItem(
              value: o['key'],
              child: Text(_dimLabel(loc, o['key']),
                  style: const TextStyle(fontSize: 13))))
          .toList(),
      onChanged: onChanged,
    );
  }
}
