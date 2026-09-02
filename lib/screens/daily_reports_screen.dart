// lib/screens/daily_reports_screen.dart
//
// Admin-only screen for generating "Daily Reading Report" PDFs covering
// one or more modules (Tractor / Electricity / Machine). Defaults the
// date range to yesterday (today - 1) since the admin typically reviews
// and reports on the previous day's entries, but allows picking any
// custom range and any combination of modules.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/pdf_download_helper.dart';

class DailyReportsScreen extends StatefulWidget {
  const DailyReportsScreen({super.key});
  @override
  State<DailyReportsScreen> createState() => _DailyReportsScreenState();
}

class _DailyReportsScreenState extends State<DailyReportsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  // Module multi-select — key -> (label, icon, color)
  static const _moduleOptions = [
    {'key': 'tractor', 'label': 'Tractor', 'icon': Icons.agriculture},
    {'key': 'electricity', 'label': 'Electricity', 'icon': Icons.electric_bolt},
    {
      'key': 'machine',
      'label': 'Machine',
      'icon': Icons.precision_manufacturing
    },
  ];

  final Set<String> _selectedModules = {};
  late DateTime _fromDate;
  late DateTime _toDate;

  bool _loadingPreview = false;
  bool _generating = false;
  Map<String, dynamic>? _previewCounts;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default range: yesterday → yesterday (today - 1)
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _toDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  String get _modulesParam => _selectedModules.join(',');
  String get _fromStr => DateFormat('yyyy-MM-dd').format(_fromDate);
  String get _toStr => DateFormat('yyyy-MM-dd').format(_toDate);

  void _toggleModule(String key) {
    setState(() {
      if (_selectedModules.contains(key)) {
        _selectedModules.remove(key);
      } else {
        _selectedModules.add(key);
      }
      _previewCounts = null;
    });
    if (_selectedModules.isNotEmpty) _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (_selectedModules.isEmpty) {
      setState(() => _previewCounts = null);
      return;
    }
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(
        Uri.parse(
            '$baseUrl/daily-reports/preview-count?modules=$_modulesParam&from=$_fromStr&to=$_toStr'),
        headers: h,
      );
      if (res.statusCode == 200) {
        setState(() => _previewCounts = jsonDecode(res.body));
      } else {
        final data = jsonDecode(res.body);
        setState(() => _error = data['error'] ?? 'Failed to load preview');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      setState(() => _loadingPreview = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
    _loadPreview();
  }

  int get _totalEntries {
    if (_previewCounts == null) return 0;
    return (_previewCounts!['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> _generateReport() async {
    if (_selectedModules.isEmpty) {
      setState(
          () => _error = 'Select at least one module to include in the report');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(
        Uri.parse(
            '$baseUrl/daily-reports/generate?modules=$_modulesParam&from=$_fromStr&to=$_toStr'),
        headers: h,
      );

      if (res.statusCode == 200) {
        final filename = 'daily-reading-report_${_fromStr}_to_$_toStr.pdf';
        final result = await savePdfBytes(res.bodyBytes, filename);

        if (!mounted) return;
        if (result.isWeb) {
          // Browser already triggered the download — nothing more to do.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Report downloaded'),
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
        setState(() => _error = data['error'] ?? 'Failed to generate report');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      setState(() => _generating = false);
    }
  }

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
              color: idaGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.picture_as_pdf, color: idaGreen, size: 28),
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
                      text: 'Ida AgriCo Daily Reading Report');
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
        title: const Text('Daily Reports',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Generate a PDF report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Includes previous reading, today\'s reading, the difference and '
            'a grayscale photo for each entry.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 20),

          // ── Module multi-select ───────────────────────────
          const Text('Modules',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _moduleOptions.map((m) {
              final key = m['key'] as String;
              final selected = _selectedModules.contains(key);
              return GestureDetector(
                onTap: () => _toggleModule(key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? idaGreen : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? idaGreen : const Color(0xFFE0E7D8)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(m['icon'] as IconData,
                        size: 16, color: selected ? Colors.white : idaGreen),
                    const SizedBox(width: 6),
                    Text(m['label'] as String,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87)),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // ── Date range ─────────────────────────────────────
          const Text('Date range',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Defaults to yesterday — tap to choose a custom range.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _dateField(
                label: 'From',
                date: _fromDate,
                onTap: () => _pickDate(isFrom: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dateField(
                label: 'To',
                date: _toDate,
                onTap: () => _pickDate(isFrom: false),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Preview ────────────────────────────────────────
          if (_selectedModules.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E7D8)),
              ),
              child: _loadingPreview
                  ? const Center(
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: idaGreen)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(children: [
                            Icon(Icons.insights, size: 16, color: idaGreen),
                            const SizedBox(width: 6),
                            Text(
                                '$_totalEntries entr${_totalEntries == 1 ? "y" : "ies"} will be included',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                          if (_previewCounts?['counts'] != null) ...[
                            const SizedBox(height: 8),
                            ...(_previewCounts!['counts'] as Map)
                                .entries
                                .map((e) => Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '• ${_labelFor(e.key.toString())}: ${e.value} entr${e.value == 1 ? "y" : "ies"}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280)),
                                      ),
                                    )),
                          ],
                        ]),
            ),
            const SizedBox(height: 16),
          ],

          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.red.shade700))),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _generating
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.white),
              label: Text(_generating ? 'Generating…' : 'Generate Report',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: idaGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_selectedModules.isEmpty || _generating)
                  ? null
                  : _generateReport,
            ),
          ),
        ]),
      ),
    );
  }

  String _labelFor(String key) {
    for (final m in _moduleOptions) {
      if (m['key'] == key) return m['label'] as String;
    }
    return key;
  }

  Widget _dateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.calendar_today, size: 14, color: idaGreen),
              const SizedBox(width: 6),
              Text(DateFormat('dd-MMM-yyyy').format(date),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      );
}
