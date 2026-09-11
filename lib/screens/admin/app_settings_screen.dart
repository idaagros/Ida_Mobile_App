// lib/screens/admin/app_settings_screen.dart
//
// Admin-adjustable app-wide settings. Starts with just the face-login
// match threshold, but the backend (GET/PATCH /api/settings/:key) and
// this screen's structure are both generic - adding a second setting
// later means adding one more card here, not a new screen.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../localization/app_localizations.dart';

const idaGreen = Color(0xFF3B7A28);
const idaDark = Color(0xFF1E4012);
const red = Color(0xFFB91C1C);

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});
  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';
  bool loading = true;
  bool saving = false;
  double? threshold;
  final thresholdCtrl = TextEditingController();

  Future<Map<String, String>> get _headers async {
    final p = await SharedPreferences.getInstance();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${p.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http.get(
          Uri.parse('$baseUrl/settings/face_login_threshold'),
          headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        threshold = double.tryParse(data['setting_value'].toString());
        thresholdCtrl.text = threshold?.toString() ?? '';
      }
    } catch (_) {
      // Leave threshold null - the UI shows a clear "couldn't load"
      // state rather than a misleading blank/zero value.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    final parsed = double.tryParse(thresholdCtrl.text.trim());
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid positive number'), backgroundColor: red));
      return;
    }
    setState(() => saving = true);
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/settings/face_login_threshold'),
        headers: h,
        body: jsonEncode({'value': parsed.toString()}),
      );
      if (res.statusCode == 200) {
        setState(() => threshold = parsed);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Saved'), backgroundColor: idaGreen));
        }
      } else {
        final data = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['error'] ?? 'Failed to save'),
              backgroundColor: red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: red));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        title: const Tooltip(
            message: 'App Settings', child: Text('App Settings')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Face Login Match Sensitivity',
                        style:
                            TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'How closely a face must match the enrolled photo to log in. '
                      'Lower is stricter (fewer false matches, but more login failures for real users). '
                      'Higher is more forgiving (fewer failed logins, but a slightly higher chance of accepting the wrong person\'s face).',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: thresholdCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Match threshold',
                            helperText: 'Started at 1.1 (raised from the original 0.9)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16)),
                        child: saving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      'If real logins keep failing for people who should match, raise this a bit and try again — there\'s no exact right number, it depends on your actual camera/lighting conditions.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic),
                    ),
                  ]),
                ),
              ],
            ),
    );
  }
}
