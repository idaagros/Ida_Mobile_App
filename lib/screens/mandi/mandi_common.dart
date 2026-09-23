// lib/screens/mandi/mandi_common.dart
//
// Shared bits for the Mandi Prices screens: one small API helper (so the
// three screens don't each repeat headers / JSON / error handling),
// number and date formatting, and the coloured change chip.
// Web counterpart: src/pages/mandi/mandiUtils.jsx.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

const Color mandiGreen = Color(0xFF3B7A28);
const Color mandiDark = Color(0xFF1E4012);
const Color mandiOrange = Color(0xFFF47D1E);
const Color mandiTint = Color(0xFFE3E9DF);
const Color mandiOrangeTint = Color(0xFFF3E2D6);

class MandiApiException implements Exception {
  final String message;
  final int status;
  MandiApiException(this.message, this.status);
  @override
  String toString() => message;
}

class MandiApi {
  static const _base = AppConfig.apiBaseUrl;

  static Future<Map<String, String>> _headers({bool json = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      if (json) 'Content-Type': 'application/json',
    };
  }

  static dynamic _decode(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (body is Map && body['error'] != null)
          ? body['error'].toString()
          : 'Request failed (${res.statusCode})';
      throw MandiApiException(msg, res.statusCode);
    }
    return body;
  }

  static Future<dynamic> get(String path) async {
    final res = await http
        .get(Uri.parse('$_base$path'), headers: await _headers())
        .timeout(const Duration(seconds: 60));
    return _decode(res);
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final res = await http
        .post(Uri.parse('$_base$path'),
            headers: await _headers(json: true), body: jsonEncode(body ?? {}))
        .timeout(const Duration(seconds: 120));
    return _decode(res);
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http
        .patch(Uri.parse('$_base$path'),
            headers: await _headers(json: true), body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return _decode(res);
  }

  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final res = await http
        .put(Uri.parse('$_base$path'),
            headers: await _headers(json: true), body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return _decode(res);
  }

  static Future<dynamic> delete(String path) async {
    final res = await http
        .delete(Uri.parse('$_base$path'), headers: await _headers())
        .timeout(const Duration(seconds: 60));
    return _decode(res);
  }
}

// ── Formatting ───────────────────────────────────────────────────────
double? toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

String rupees(dynamic v) {
  final d = toD(v);
  if (d == null) return '—';
  return '₹${_inr.format(d.round())}';
}

String rupeesK(double v) => '₹${(v / 1000).toStringAsFixed(1)}k';

DateTime? parseDay(dynamic s) {
  if (s == null) return null;
  final str = s.toString();
  if (str.length < 10) return null;
  return DateTime.tryParse(str.substring(0, 10));
}

String shortDate(dynamic s) {
  final d = parseDay(s);
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

String dayMonth(dynamic s) {
  final d = parseDay(s);
  return d == null ? '' : DateFormat('d MMM').format(d);
}

String marketName(Map m) =>
    (m['display_name'] ?? '').toString().isNotEmpty ? m['display_name'].toString() : (m['market'] ?? '').toString();

// ── Widgets ──────────────────────────────────────────────────────────
class ChangeChip extends StatelessWidget {
  final dynamic value;
  final String label;
  const ChangeChip({super.key, required this.value, this.label = ''});

  @override
  Widget build(BuildContext context) {
    final v = toD(value);
    if (v == null) return const SizedBox.shrink();
    final up = v > 0, flat = v == 0;
    final bg = flat ? Colors.grey.shade100 : (up ? mandiTint : Colors.red.shade50);
    final fg = flat ? Colors.grey.shade600 : (up ? mandiGreen : Colors.red.shade700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        '${flat ? '•' : (up ? '▲' : '▼')} ${v.abs().toStringAsFixed(1)}%$label',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class MandiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  const MandiCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8)),
      );
}

class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade200),
            borderRadius: BorderRadius.circular(8)),
        child: Text(message, style: TextStyle(fontSize: 13, color: Colors.red.shade800)),
      );
}
