// lib/screens/otp_approvals_screen.dart
//
// Admin screen for approving Password Manager access requests. When a
// non-admin requests access, a row appears here. Admin taps Approve and
// the 6-digit OTP is displayed prominently — admin then communicates it
// to the user via WhatsApp or phone call. Requests expire after 15 min.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class OtpApprovalsScreen extends StatefulWidget {
  const OtpApprovalsScreen({super.key});
  @override
  State<OtpApprovalsScreen> createState() => _OtpApprovalsScreenState();
}

class _OtpApprovalsScreenState extends State<OtpApprovalsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List _requests = [];
  bool _loading = true;
  // Approved OTPs shown in-session so admin doesn't lose the code on refresh
  final Map<int, String> _approvedOtps = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/passwords/otp/pending'), headers: h);
      if (res.statusCode == 200) setState(() => _requests = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load OTP requests: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map req) async {
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/passwords/otp/${req['id']}/approve'),
        headers: h,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final otpCode = data['otp_code']?.toString() ?? '';
        setState(() => _approvedOtps[req['id']] = otpCode);
        // Show the OTP prominently in a dialog
        _showOtpDialog(req['username']?.toString() ?? 'User', otpCode);
        _load();
      } else {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error'] ?? 'Failed to approve'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reject(Map req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Request?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('Reject OTP request from ${req['username']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final h = await _headers;
    await http.patch(Uri.parse('$baseUrl/passwords/otp/${req['id']}/reject'), headers: h);
    _load();
  }

  void _showOtpDialog(String username, String otp) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.verified_user, color: Color(0xFF3B7A28)),
          const SizedBox(width: 10),
          Text('Approved for $username', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share this OTP with the user (via WhatsApp or call). It expires in 15 minutes.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: idaGreen, width: 2),
            ),
            child: Column(children: [
              const Text('OTP CODE', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(otp, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 10, color: idaDark)),
            ]),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: otp));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP copied to clipboard')));
            },
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.copy, size: 16, color: Color(0xFF1A73E8)),
              SizedBox(width: 6),
              Text('Tap to copy', style: TextStyle(fontSize: 13, color: Color(0xFF1A73E8))),
            ]),
          ),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done — I\'ve shared the OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String? createdAt) {
    if (createdAt == null) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return DateFormat('hh:mm a').format(dt);
  }

  String _expiresIn(String? expiresAt) {
    if (expiresAt == null) return '';
    final dt = DateTime.tryParse(expiresAt);
    if (dt == null) return '';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inMinutes < 1) return 'Expires soon';
    return 'Expires in ${diff.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requests.where((r) => r['status'] == 'pending').toList();
    final others = _requests.where((r) => r['status'] != 'pending').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('OTP Approvals', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: _requests.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Column(children: [
                        Icon(Icons.lock_open, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 14),
                        const Text('No pending OTP requests', style: TextStyle(fontSize: 15, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text('Users requesting password access will appear here',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                    ])
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (pending.isNotEmpty) ...[
                          const Text('PENDING APPROVAL',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF), letterSpacing: 0.6)),
                          const SizedBox(height: 10),
                          ...pending.map((req) => _pendingCard(req)),
                          const SizedBox(height: 20),
                        ],
                        if (others.isNotEmpty) ...[
                          const Text('RECENT (already processed)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF), letterSpacing: 0.6)),
                          const SizedBox(height: 10),
                          ...others.map((req) => _processedCard(req)),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _pendingCard(Map req) {
    final alreadyApproved = _approvedOtps.containsKey(req['id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFFFF3DC),
            child: Text((req['username']?.toString() ?? 'U')[0].toUpperCase(),
                style: const TextStyle(color: Color(0xFFB8860B), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(req['username']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Requesting Password Manager access', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFFFF3DC), borderRadius: BorderRadius.circular(20)),
            child: const Text('Pending', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB8860B))),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(_timeAgo(req['created_at']?.toString()), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(width: 12),
          Icon(Icons.timer_outlined, size: 13, color: Colors.orange.shade400),
          const SizedBox(width: 4),
          Text(_expiresIn(req['expires_at']?.toString()),
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
        ]),

        if (alreadyApproved) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFFF4F7F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: idaGreen)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.verified_user, size: 16, color: idaGreen),
              const SizedBox(width: 8),
              Text('OTP: ${_approvedOtps[req['id']]}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 6, color: idaDark)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: _approvedOtps[req['id']]!)),
                child: const Icon(Icons.copy, size: 16, color: Color(0xFF1A73E8)),
              ),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _reject(req),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _approve(req),
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Approve & Show OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _processedCard(Map req) {
    final isApproved = req['status'] == 'approved';
    final color = isApproved ? const Color(0xFF3B7A28) : const Color(0xFFB23A3A);
    final bg = isApproved ? const Color(0xFFE8F5E2) : const Color(0xFFFDE8E8);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: bg,
            child: Icon(isApproved ? Icons.check : Icons.close, size: 16, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(req['username']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(_timeAgo(req['created_at']?.toString()), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(isApproved ? 'Approved' : 'Rejected', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
