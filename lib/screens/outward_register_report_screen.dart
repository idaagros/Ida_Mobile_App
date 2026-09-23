// lib/screens/outward_register_report_screen.dart
//
// Admin report download for the Outward Sales Register: pick a date
// range, choose Excel or PDF, optionally restrict to fully-approved
// records only.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/pdf_download_helper.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class OutwardRegisterReportScreen extends StatefulWidget {
  const OutwardRegisterReportScreen({super.key});
  @override
  State<OutwardRegisterReportScreen> createState() =>
      _OutwardRegisterReportScreenState();
}

class _OutwardRegisterReportScreenState
    extends State<OutwardRegisterReportScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  DateTime fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime toDate = DateTime.now();
  bool approvedOnly = false;
  bool generating = false;
  String? errorMessage;

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? fromDate : toDate,
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
        fromDate = picked;
        if (toDate.isBefore(fromDate)) toDate = fromDate;
      } else {
        toDate = picked;
        if (fromDate.isAfter(toDate)) fromDate = toDate;
      }
    });
  }

  Future<void> _generate(String format) async {
    setState(() {
      generating = true;
      errorMessage = null;
    });
    try {
      final h = await _headers;
      final fromStr = DateFormat('yyyy-MM-dd').format(fromDate);
      final toStr = DateFormat('yyyy-MM-dd').format(toDate);
      final url = '$baseUrl/outward-register/report'
          '?from=$fromStr&to=$toStr&format=$format&approved_only=${approvedOnly ? '1' : '0'}';
      final res = await http.get(Uri.parse(url), headers: h);

      if (res.statusCode == 200) {
        final filename = 'outward_register_${fromStr}_to_${toStr}'
            '${approvedOnly ? '_approved' : ''}.$format';
        final result = await savePdfBytes(res.bodyBytes, filename);

        if (!mounted) return;
        if (result.isWeb) {
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
        setState(
            () => errorMessage = data['error'] ?? 'Failed to generate report');
      }
    } catch (e) {
      setState(() => errorMessage = 'Error: $e');
    } finally {
      setState(() => generating = false);
    }
  }

  Future<void> _showResultSheet(String filePath, String filename) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle, color: idaGreen, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Report ready',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(filename,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        OpenFilex.open(filePath);
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: idaGreen,
                        side: const BorderSide(color: idaGreen),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Share.shareXFiles([XFile(filePath)]);
                      },
                      icon: const Icon(Icons.share,
                          size: 18, color: Colors.white),
                      label: const Text('Share',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: idaGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ]),
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
        title: const Text('Outward Register Report',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Responsive.constrainedContent(
          context,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE0E7D8)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DATE RANGE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9CA3AF),
                              letterSpacing: 0.6)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _dateTile('From', fromDate,
                                () => _pickDate(isFrom: true))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _dateTile(
                                'To', toDate, () => _pickDate(isFrom: false))),
                      ]),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: approvedOnly,
                        activeColor: idaGreen,
                        onChanged: (v) => setState(() => approvedOnly = v),
                        title: const Text('Fully approved records only',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          approvedOnly
                              ? 'Only records where every section is approved'
                              : 'All records — partial/pending shown with status badges',
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFF9CA3AF)),
                        ),
                      ),
                    ]),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200)),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(errorMessage!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.red.shade700))),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              const Text('DOWNLOAD AS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.6)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: generating ? null : () => _generate('xlsx'),
                      icon: generating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.grid_on,
                              color: Colors.white, size: 18),
                      label: const Text('Excel (.xlsx)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: idaGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: generating ? null : () => _generate('pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: idaGreen,
                        side: const BorderSide(color: idaGreen),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ]),
            ]),
          )),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E7D8)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today, size: 14, color: idaGreen),
            const SizedBox(width: 6),
            Text(DateFormat('dd MMM yyyy').format(date),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}
