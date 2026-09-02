// lib/screens/password_screen.dart
//
// Password Manager — categorised credential store.
// Admin: full access immediately.
// Non-admin: must complete the OTP flow (request → wait for admin
//   approval → enter 6-digit code) before any entry is shown.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';
  static const primaryColor = Color(0xFF1565C0); // matching the CCA blue

  List _categories = [];
  bool _loading = true;
  bool _isAdmin = false;

  // Non-admins must pass the OTP gate before any category can be opened.
  // Once granted in a session, this stays true until the screen is disposed.
  bool _otpGranted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    if (token.isNotEmpty) {
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
          _isAdmin = payload['is_admin'] == true;
        }
      } catch (_) {}
    }
    if (_isAdmin) setState(() => _otpGranted = true);
    await _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/passwords/categories'),
          headers: h);
      if (res.statusCode == 200)
        setState(() => _categories = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load categories: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  IconData _icon(String? code) {
    final map = {
      '59640': Icons.vpn_key,
      '58835': Icons.lock,
      '57399': Icons.account_balance,
      '58356': Icons.credit_card,
      '57680': Icons.business,
      '57421': Icons.computer,
      '57704': Icons.email,
      '59203': Icons.receipt_long,
    };
    return map[code] ?? Icons.vpn_key;
  }

  List<Color> _colors(String? val) {
    try {
      final base = Color(int.parse(val ?? '4279757248'));
      return [base, Color.lerp(base, Colors.black, 0.2)!];
    } catch (_) {
      return [primaryColor, const Color(0xFF0D47A1)];
    }
  }

  // ── OTP Gate ─────────────────────────────────────────────────────────────
  // Called when a non-admin taps a category. Navigates to the OTP flow
  // and only opens the category if access is granted.
  Future<bool> _requestOtpAccess() async {
    if (_isAdmin) return true;
    if (_otpGranted) return true;

    // Request OTP from backend
    final h = await _headers;
    final res = await http.post(Uri.parse('$baseUrl/passwords/otp/request'),
        headers: h);
    if (!mounted) return false;
    if (res.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to request OTP'), backgroundColor: Colors.red));
      return false;
    }
    final data = jsonDecode(res.body);
    if (data['skip'] == true) {
      setState(() => _otpGranted = true);
      return true;
    }

    final requestId = data['requestId'];
    final granted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => OtpWaitScreen(
              requestId: requestId, baseUrl: baseUrl, headers: () => _headers)),
    );
    if (granted == true) {
      setState(() => _otpGranted = true);
      return true;
    }
    return false;
  }

  // ── Category management ────────────────────────────────────────────────
  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    IconData selectedIcon = Icons.vpn_key;
    Color selectedColor = primaryColor;

    final icons = [
      Icons.vpn_key,
      Icons.lock,
      Icons.account_balance,
      Icons.credit_card,
      Icons.business,
      Icons.computer,
      Icons.email,
      Icons.receipt_long
    ];
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
      const Color(0xFFD32F2F),
      const Color(0xFFF57C00),
      const Color(0xFF7B1FA2),
      const Color(0xFF0097A7),
      const Color(0xFF512DA8),
      const Color(0xFFC2185B)
    ];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Category',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Category Name *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Icon',
                    style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: icons.map((ic) {
                  final sel = selectedIcon == ic;
                  return GestureDetector(
                    onTap: () => setS(() => selectedIcon = ic),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: sel
                              ? selectedColor.withOpacity(0.2)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: sel ? selectedColor : Colors.transparent,
                              width: 2)),
                      child: Icon(ic, color: sel ? selectedColor : Colors.grey),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Color',
                    style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((c) {
                  final sel = selectedColor == c;
                  return GestureDetector(
                    onTap: () => setS(() => selectedColor = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: sel ? Colors.black : Colors.transparent,
                              width: 3)),
                      child: sel
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList()),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: selectedColor),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final h = await _headers;
                final res =
                    await http.post(Uri.parse('$baseUrl/passwords/categories'),
                        headers: h,
                        body: jsonEncode({
                          'name': nameCtrl.text.trim(),
                          'icon_code': selectedIcon.codePoint.toString(),
                          'color_val': selectedColor.value.toString()
                        }));
                if (!mounted) return;
                Navigator.pop(ctx);
                if (res.statusCode == 200)
                  _loadCategories();
                else
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(jsonDecode(res.body)['error'] ?? 'Failed'),
                      backgroundColor: Colors.red));
              },
              child:
                  const Text('CREATE', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCategory(Map cat) async {
    if ((cat['entry_count'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Delete all entries first.'),
          backgroundColor: Colors.red));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${cat['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    final h = await _headers;
    await http.delete(Uri.parse('$baseUrl/passwords/categories/${cat['id']}'),
        headers: h);
    _loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Password Manager',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (!_isAdmin && _otpGranted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_user, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Verified',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : _categories.isEmpty
              ? const Center(
                  child: Text('No categories yet.',
                      style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                      childAspectRatio: 1.1),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final catColors = _colors(cat['color_val']?.toString());
                    final catIcon = _icon(cat['icon_code']?.toString());
                    final count = cat['entry_count'] ?? 0;
                    return InkWell(
                      onTap: () async {
                        final granted = await _requestOtpAccess();
                        if (granted && mounted) {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _PasswordCategoryScreen(
                                  category: cat,
                                  baseUrl: baseUrl,
                                  headers: () => _headers,
                                  colors: catColors,
                                  icon: catIcon,
                                  isAdmin: _isAdmin,
                                ),
                              ));
                          _loadCategories();
                        }
                      },
                      onLongPress:
                          _isAdmin ? () => _confirmDeleteCategory(cat) : null,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: catColors,
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: catColors[0].withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Stack(children: [
                          Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Icon(catIcon, color: Colors.white, size: 36),
                                const SizedBox(height: 8),
                                Text(cat['name'] ?? '',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    textAlign: TextAlign.center),
                                Text(
                                    '$count ${count == 1 ? 'entry' : 'entries'}',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 11)),
                              ])),
                          if (!_isAdmin && !_otpGranted)
                            Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(Icons.lock,
                                    size: 16,
                                    color: Colors.white.withOpacity(0.7))),
                        ]),
                      ),
                    );
                  },
                ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              backgroundColor: primaryColor,
              onPressed: _showAddCategoryDialog,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

// ── OTP Wait Screen ─────────────────────────────────────────────────────────
// User lands here after submitting an OTP request. Polls every 3 seconds.
// When the admin approves, the status flips to 'approved' and the OTP
// entry field appears.
class OtpWaitScreen extends StatefulWidget {
  final int requestId;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  const OtpWaitScreen(
      {super.key,
      required this.requestId,
      required this.baseUrl,
      required this.headers});
  @override
  State<OtpWaitScreen> createState() => _OtpWaitScreenState();
}

class _OtpWaitScreenState extends State<OtpWaitScreen> {
  static const primaryColor = Color(0xFF1565C0);
  String _status = 'pending';
  final _otpCtrl = TextEditingController();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    while (mounted && (_status == 'pending')) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final h = await widget.headers();
        final res = await http.get(
            Uri.parse(
                '${widget.baseUrl}/passwords/otp/status/${widget.requestId}'),
            headers: h);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          setState(() => _status = data['status'] ?? 'pending');
        }
      } catch (_) {}
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      final h = await widget.headers();
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/passwords/otp/verify'),
        headers: h,
        body: jsonEncode(
            {'requestId': widget.requestId, 'code': _otpCtrl.text.trim()}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error'] ?? 'Invalid OTP'),
            backgroundColor: Colors.red));
        setState(() => _verifying = false);
      }
    } catch (e) {
      setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _status == 'approved';
    final expired = _status == 'expired';
    return Scaffold(
      appBar: AppBar(
          title: const Text('Verify Access'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
              approved
                  ? Icons.verified_user
                  : expired
                      ? Icons.timer_off
                      : Icons.lock_clock,
              size: 80,
              color: approved
                  ? Colors.green
                  : expired
                      ? Colors.red
                      : Colors.orange),
          const SizedBox(height: 20),
          Text(
            expired
                ? 'Request Expired'
                : approved
                    ? 'Approved! Enter OTP below'
                    : 'Waiting for Admin Approval...',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (!approved && !expired)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                  'The admin will approve your request and give you the OTP code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ),
          if (!approved && !expired) ...[
            const SizedBox(height: 24),
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.orange)),
          ],
          if (expired)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go Back & Try Again'),
              ),
            ),
          if (approved) ...[
            const SizedBox(height: 30),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(
                  fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '______',
                counterText: '',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: _verifying ? null : _verify,
                child: _verifying
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : const Text('VERIFY & UNLOCK',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Per-category entry screen ─────────────────────────────────────────────
class _PasswordCategoryScreen extends StatefulWidget {
  final Map category;
  final String baseUrl;
  final Future<Map<String, String>> Function() headers;
  final List<Color> colors;
  final IconData icon;
  final bool isAdmin;
  const _PasswordCategoryScreen(
      {required this.category,
      required this.baseUrl,
      required this.headers,
      required this.colors,
      required this.icon,
      required this.isAdmin});
  @override
  State<_PasswordCategoryScreen> createState() =>
      _PasswordCategoryScreenState();
}

class _PasswordCategoryScreenState extends State<_PasswordCategoryScreen> {
  List _entries = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final h = await widget.headers();
      final res = await http.get(
          Uri.parse(
              '${widget.baseUrl}/passwords/entries?category_id=${widget.category['id']}'),
          headers: h);
      if (res.statusCode == 200)
        setState(() => _entries = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load entries: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showDetails(Map entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 20),
                Row(children: [
                  CircleAvatar(
                      backgroundColor: widget.colors[0].withOpacity(0.1),
                      child: Icon(widget.icon, color: widget.colors[0])),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Text(entry['service_name'] ?? '',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: widget.colors[0]))),
                  if (widget.isAdmin) ...[
                    IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditDialog(entry);
                        }),
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteEntry(entry);
                        }),
                  ],
                ]),
                const Divider(height: 28),
                _detailRow('Company', entry['company'], Icons.business, false),
                _detailRow('Provider', entry['provider'], Icons.hub, false),
                _detailRow('User ID', entry['username'], Icons.person, true),
                _detailRow('Password', entry['password'], Icons.lock, true,
                    isPassword: true),
                _detailRow('URL', entry['url'], Icons.link, true, isUrl: true),
                _detailRow('Remarks', entry['remarks'], Icons.notes, false),
                const SizedBox(height: 24),
              ])),
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic val, IconData icon, bool canCopy,
      {bool isPassword = false, bool isUrl = false}) {
    final value =
        (val == null || val.toString().isEmpty) ? null : val.toString();
    if (value == null) return const SizedBox.shrink();
    return StatefulBuilder(
      builder: (ctx, setS) {
        bool obscured = isPassword;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  isUrl
                      ? GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(value.startsWith('http')
                                ? value
                                : 'https://$value');
                            if (await canLaunchUrl(uri))
                              launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                          },
                          child: Text(value,
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w500)))
                      : isPassword
                          ? Row(children: [
                              Text(obscured ? '••••••••' : value,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                  onTap: () => setS(() => obscured = !obscured),
                                  child: Icon(
                                      obscured
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      size: 16,
                                      color: Colors.grey)),
                            ])
                          : Text(value,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                ])),
            if (canCopy)
              IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$label copied')));
                  }),
          ]),
        );
      },
    );
  }

  void _showEditDialog(Map? entry) {
    final isEdit = entry != null;
    final companyCtrl = TextEditingController(text: entry?['company'] ?? '');
    final serviceCtrl =
        TextEditingController(text: entry?['service_name'] ?? '');
    final userCtrl = TextEditingController(text: entry?['username'] ?? '');
    final passCtrl = TextEditingController(text: entry?['password'] ?? '');
    final urlCtrl = TextEditingController(text: entry?['url'] ?? '');
    final remarkCtrl = TextEditingController(text: entry?['remarks'] ?? '');
    String? provider = entry?['provider'];

    const providers = [
      'Google',
      'Bank',
      'GST Portal',
      'Microsoft',
      'Social Media',
      'Payment Gateway',
      'Email Service',
      'Cloud Storage',
      'E-commerce',
      'Accounting Software',
      'Government Portal',
      'Other'
    ];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isEdit ? 'Edit Entry' : 'Add Entry',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(companyCtrl, 'Company'),
            _field(serviceCtrl, 'Service Name *'),
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  value: provider,
                  hint: const Text('Service Provider'),
                  decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.hub)),
                  items: providers
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setS(() => provider = v),
                )),
            _field(userCtrl, 'User ID', prefixIcon: Icons.person),
            _field(passCtrl, 'Password *', isPassword: true),
            _field(urlCtrl, 'URL',
                keyboardType: TextInputType.url, prefixIcon: Icons.link),
            _field(remarkCtrl, 'Remarks', maxLines: 2),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: widget.colors[0]),
              onPressed: () async {
                if (serviceCtrl.text.trim().isEmpty ||
                    passCtrl.text.trim().isEmpty) return;
                final h = await widget.headers();
                final body = jsonEncode({
                  'category_id': widget.category['id'],
                  'service_name': serviceCtrl.text.trim(),
                  'company': companyCtrl.text.trim(),
                  'provider': provider,
                  'username': userCtrl.text.trim(),
                  'password': passCtrl.text.trim(),
                  'url': urlCtrl.text.trim(),
                  'remarks': remarkCtrl.text.trim()
                });
                if (isEdit) {
                  await http.put(
                      Uri.parse(
                          '${widget.baseUrl}/passwords/entries/${entry!['id']}'),
                      headers: h,
                      body: body);
                } else {
                  await http.post(
                      Uri.parse('${widget.baseUrl}/passwords/entries'),
                      headers: h,
                      body: body);
                }
                if (!mounted) return;
                Navigator.pop(ctx);
                _load();
              },
              child: Text(isEdit ? 'UPDATE' : 'SAVE',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEntry(Map entry) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Delete "${entry['service_name']}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.white))),
              ],
            ));
    if (confirm != true) return;
    final h = await widget.headers();
    await http.delete(
        Uri.parse('${widget.baseUrl}/passwords/entries/${entry['id']}'),
        headers: h);
    _load();
  }

  Widget _field(TextEditingController ctrl, String label,
          {bool isPassword = false,
          TextInputType? keyboardType,
          IconData? prefixIcon,
          int maxLines = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: ctrl,
            obscureText: isPassword,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null),
          ));

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.colors[0];
    final filtered = _entries.where((e) {
      final s = _search.toLowerCase();
      return (e['service_name'] ?? '').toString().toLowerCase().contains(s) ||
          (e['company'] ?? '').toString().toLowerCase().contains(s) ||
          (e['username'] ?? '').toString().toLowerCase().contains(s);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.category['name'] ?? ''),
      ),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search entries...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            )),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const Center(
                      child: Text('No entries yet',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: themeColor.withOpacity(0.1),
                                child: Icon(widget.icon,
                                    color: themeColor, size: 20)),
                            title: Text(e['service_name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${e['username'] != null ? 'User: ${e['username']}' : ''}${e['company'] != null ? '\n${e['company']}' : ''}',
                                style: const TextStyle(fontSize: 12)),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 14),
                            onTap: () => _showDetails(e),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              backgroundColor: themeColor,
              onPressed: () => _showEditDialog(null),
              child: const Icon(Icons.add, color: Colors.white))
          : null,
    );
  }
}
