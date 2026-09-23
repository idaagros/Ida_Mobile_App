// lib/screens/reading_reminder_settings_screen.dart
//
// Two time thresholds for the missing-reading nudge in the Needs
// Attention inbox: before user_reminder_time, a missing reading isn't
// flagged at all. After it, users with edit access to that specific
// module see it. After admin_reminder_time, admins see it too - a
// real escalation, not admins seeing everything immediately.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class ReadingReminderSettingsScreen extends StatefulWidget {
  const ReadingReminderSettingsScreen({super.key});
  @override
  State<ReadingReminderSettingsScreen> createState() =>
      _ReadingReminderSettingsScreenState();
}

class _ReadingReminderSettingsScreenState
    extends State<ReadingReminderSettingsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

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
  TimeOfDay userTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay adminTime = const TimeOfDay(hour: 14, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay _parseTime(String raw) {
    final parts = raw.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatForApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http
          .get(Uri.parse('$baseUrl/reading-reminder-settings'), headers: h);
      if (res.statusCode == 200) {
        final s = jsonDecode(res.body);
        setState(() {
          userTime = _parseTime(s['user_reminder_time']);
          adminTime = _parseTime(s['admin_reminder_time']);
        });
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
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.put(
        Uri.parse('$baseUrl/reading-reminder-settings'),
        headers: h,
        body: jsonEncode({
          'user_reminder_time': _formatForApi(userTime),
          'admin_reminder_time': _formatForApi(adminTime),
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

  Future<void> _pickTime(bool isUser) async {
    final picked = await showTimePicker(
        context: context, initialTime: isUser ? userTime : adminTime);
    if (picked != null) {
      setState(() {
        if (isUser) {
          userTime = picked;
        } else {
          adminTime = picked;
        }
      });
    }
  }

  Widget _timeRow(
      String title, String description, TimeOfDay time, bool isUser) {
    return InkWell(
      onTap: () => _pickTime(isUser),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: idaDark)),
              const SizedBox(height: 3),
              Text(description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF4F7F2),
                borderRadius: BorderRadius.circular(8)),
            child: Text(time.format(context),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: idaGreen)),
          ),
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
        title: const Text('Reminder Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : Responsive.constrainedContent(
              context,
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Applies to Electricity, Machine, Machine PF, and Tractor readings — checked against yesterday\'s expected reading, every day.',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFDE8E8),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(error!,
                          style: const TextStyle(
                              color: Color(0xFFC0392B), fontSize: 12.5)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _timeRow(
                    'Remind users',
                    'A missing reading appears for anyone with edit access to that screen, starting at this time.',
                    userTime,
                    true,
                  ),
                  const SizedBox(height: 12),
                  _timeRow(
                    'Escalate to admins',
                    'If still missing, it also appears for admins, starting at this time.',
                    adminTime,
                    false,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: idaGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: saving ? null : _save,
                      child: saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              )),
    );
  }
}
