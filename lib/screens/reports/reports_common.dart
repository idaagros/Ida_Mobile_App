// lib/screens/reports/reports_common.dart
//
// Shared pieces for the phone Reports screens (Sep 2026, group E):
//  - ReportApi: JSON and file downloads from /api/report-hub (and the two
//    reports with their own layout) with the login token
//  - periods: this week / this month / last month / this year (from
//    1 April) / last year / custom — same as the website
//  - number formats, and the "file ready" sheet (Open / Share)
// Web counterpart: src/pages/ReportsHub.jsx.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../../services/pdf_download_helper.dart';

const Color rGreen = Color(0xFF3B7A28);
const Color rDark = Color(0xFF1E3313);
const Color rMuted = Color(0xFF5F6A58);
const Color rBorder = Color(0xFFE0E7D8);

class ReportApi {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    return {'Authorization': 'Bearer ${prefs.getString('token') ?? ''}'};
  }

  static String _error(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      if (d is Map && d['error'] != null) return d['error'].toString();
    } catch (_) {}
    return 'Something went wrong (${res.statusCode})';
  }

  static Future<dynamic> get(String path) async {
    final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: await _headers()).timeout(const Duration(seconds: 90));
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception(_error(res));
    return jsonDecode(res.body);
  }

  // Downloads a file and shows Open / Share (or "downloaded" on web).
  static Future<void> download(BuildContext context, String path, String filename) async {
    final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: await _headers()).timeout(const Duration(seconds: 180));
    if (res.statusCode != 200) throw Exception(_error(res));
    final saved = await savePdfBytes(res.bodyBytes, filename);
    if (!context.mounted) return;
    if (saved.isWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloaded'), backgroundColor: rGreen));
      return;
    }
    await showFileReady(context, saved.filePath!, filename);
  }
}

Future<void> showFileReady(BuildContext context, String filePath, String filename) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle, color: rGreen, size: 22),
            SizedBox(width: 10),
            Text('File ready', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(filename, style: const TextStyle(fontSize: 12, color: rMuted)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(filePath);
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
                style: OutlinedButton.styleFrom(foregroundColor: rGreen, minimumSize: const Size.fromHeight(46)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(filePath)]);
                },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share'),
                style: FilledButton.styleFrom(backgroundColor: rGreen, minimumSize: const Size.fromHeight(46)),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

// ── Periods ───────────────────────────────────────────────────────────
const List<(String, String)> periodPresets = [
  ('week', 'This week'), ('month', 'This month'), ('last_month', 'Last month'),
  ('year', 'This year'), ('last_year', 'Last year'), ('custom', 'Custom'),
];

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String niceDate(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? s : DateFormat('d MMM yyyy').format(d);
}

// [from, to] as YYYY-MM-DD. "This year" = the financial year from 1 April.
(String, String) periodOf(String preset, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final fy = n.month >= 4 ? n.year : n.year - 1;
  switch (preset) {
    case 'week':
      return (ymd(n.subtract(Duration(days: n.weekday - 1))), ymd(n));
    case 'last_month':
      return (ymd(DateTime(n.year, n.month - 1, 1)), ymd(DateTime(n.year, n.month, 0)));
    case 'year':
      return ('$fy-04-01', ymd(n));
    case 'last_year':
      return ('${fy - 1}-04-01', '$fy-03-31');
    default:
      return (ymd(DateTime(n.year, n.month, 1)), ymd(n));
  }
}

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');
String fmtFigure(dynamic v, String? fmt) {
  if (v == null) return '—';
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null || n.isNaN || n.isInfinite) return '—';
  switch (fmt) {
    case 'money':
      return '${n < 0 ? '−' : ''}₹${_inr.format(n.abs().round())}';
    case 'int':
      return _inr.format(n.round());
    case 'pct':
      return '${n > 0 ? '+' : ''}${n.toStringAsFixed(1)}%';
    case 'dec1':
      return _trim(n, 1);
    case 'dec3':
      return _trim(n, 3);
    default:
      return _trim(n, 2);
  }
}

String _trim(double n, int dp) {
  final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: dp);
  var s = f.format(n);
  if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

IconData reportIcon(String? key) {
  switch (key) {
    case 'truck':
      return Icons.local_shipping_outlined;
    case 'bolt':
      return Icons.bolt;
    case 'clock':
      return Icons.schedule;
    case 'alert':
      return Icons.warning_amber_rounded;
    case 'check':
      return Icons.build_circle_outlined;
    case 'users':
      return Icons.groups_outlined;
    case 'sprout':
      return Icons.grass;
    case 'cal':
      return Icons.event_note;
    case 'spray':
      return Icons.water_drop_outlined;
    case 'basket':
      return Icons.shopping_basket_outlined;
    case 'tractor':
      return Icons.agriculture;
    case 'drop':
      return Icons.local_gas_station_outlined;
    case 'rupee':
      return Icons.receipt_long_outlined;
    default:
      return Icons.description_outlined;
  }
}
