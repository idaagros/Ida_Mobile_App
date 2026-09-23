// lib/screens/notifications_screen.dart
//
// Everything sent to this user (approval requests, returned entries,
// reminders, access requests), newest first — the same list the web
// app's bell shows. Works even if push is off on this phone, since
// notifications are stored on the server. Tap one to open its screen.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/push_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/notifications?limit=100'), headers: await _headers);
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() => items = List<Map<String, dynamic>>.from(d['items'] ?? []));
        PushService.unreadCount.value = (d['unread'] as num?)?.toInt() ?? 0;
      } else {
        setState(() => error = 'Could not load notifications (${res.statusCode})');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await http.patch(Uri.parse('${AppConfig.apiBaseUrl}/notifications/read-all'), headers: await _headers);
    } catch (_) {}
    await _load();
  }

  Future<void> _sendTest() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!PushService.isReady) {
      messenger.showSnackBar(const SnackBar(content: Text('Push is not set up in this app build yet (Firebase config missing).')));
      return;
    }
    await PushService.registerDevice();
    try {
      final res = await http.post(Uri.parse('${AppConfig.apiBaseUrl}/notifications/test'), headers: await _headers);
      final d = jsonDecode(res.body);
      final status = d['result']?['push_status'] ?? '?';
      final err = d['result']?['push_error'];
      messenger.showSnackBar(SnackBar(
        content: Text(status == 'sent'
            ? 'Test sent — it should appear in a few seconds.'
            : 'Test saved, but push status is "$status"${err != null ? ': $err' : ''}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Test failed: $e')));
    }
    await _load();
  }

  void _open(Map<String, dynamic> n) {
    final data = <String, dynamic>{
      ...Map<String, dynamic>.from(n['data'] ?? {}),
      'type': n['type'],
      'module': n['module'],
      'notification_id': n['id'].toString(),
    };
    PushService.markRead(n['id']);
    setState(() => n['read_at'] = DateTime.now().toIso8601String());
    PushService.openRoute((n['route'] ?? '').toString(), data);
  }

  IconData _icon(String? type) {
    switch (type) {
      case 'approval_request':
        return Icons.fact_check_outlined;
      case 'returned':
        return Icons.undo;
      case 'reminder_user':
      case 'reminder_admin':
        return Icons.alarm;
      case 'otp_request':
        return Icons.vpn_key_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _color(String? type) {
    switch (type) {
      case 'returned':
        return Colors.red.shade700;
      case 'reminder_user':
      case 'reminder_admin':
        return Colors.orange.shade800;
      default:
        return idaGreen;
    }
  }

  String _when(dynamic s) {
    final d = DateTime.tryParse(s?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat('h:mm a').format(d);
    return DateFormat('d MMM, h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final unread = items.where((n) => n['read_at'] == null).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        actions: [
          if (unread > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read', style: TextStyle(color: Colors.white))),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'test') _sendTest();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'test', child: Text('Send test notification'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (error != null)
                    Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: TextStyle(color: Colors.red.shade700))),
                  if (items.isEmpty && error == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('No notifications yet', style: TextStyle(color: Colors.grey))),
                    ),
                  ...items.map((n) {
                    final isUnread = n['read_at'] == null;
                    return Material(
                      color: isUnread ? const Color(0xFFEFF5EA) : Colors.white,
                      child: ListTile(
                        onTap: () => _open(n),
                        leading: CircleAvatar(
                          backgroundColor: _color(n['type']).withValues(alpha: 0.12),
                          child: Icon(_icon(n['type']), color: _color(n['type']), size: 20),
                        ),
                        title: Text(n['title']?.toString() ?? '',
                            style: TextStyle(fontSize: 14, fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n['body']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(_when(n['created_at']), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                        isThreeLine: true,
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}
