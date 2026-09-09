// lib/screens/admin/user_form_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/user_model.dart';
import '../../services/api_service.dart';
import '../../services/responsive.dart';

class UserFormScreen extends StatefulWidget {
  final AppUser? existingUser;
  const UserFormScreen({super.key, this.existingUser});
  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isActive = true;
  bool _obscurePass = true;
  bool _saving = false;
  // module key -> 'view' | 'edit'. Absent = no access.
  Map<String, String> _perms = {};

  bool get _isEdit => widget.existingUser != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final u = widget.existingUser!;
      _nameCtrl.text = u.displayName;
      _userCtrl.text = u.username;
      _isActive = u.isActive;
      _perms = {for (final p in u.permissions) p.module: p.level};
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_perms.isEmpty) {
      _showError('Assign at least one module before saving.');
      return;
    }

    setState(() => _saving = true);
    try {
      final token = await ApiService.getToken();
      final body = <String, dynamic>{
        'display_name': _nameCtrl.text.trim(),
        'username': _userCtrl.text.trim(),
        'is_active': _isActive,
        'permissions': _perms.entries
            .map((e) => {'module': e.key, 'level': e.value})
            .toList(),
        if (!_isEdit || _passCtrl.text.isNotEmpty) 'password': _passCtrl.text,
      };

      final uri = _isEdit
          ? Uri.parse(
              '${ApiService.baseUrl}/api/admin/users/${widget.existingUser!.id}')
          : Uri.parse('${ApiService.baseUrl}/api/admin/users');

      final res = _isEdit
          ? await http.put(uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
              body: jsonEncode(body))
          : await http.post(uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                'ngrok-skip-browser-warning': 'true',
              },
              body: jsonEncode(body));

      setState(() => _saving = false);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? 'User updated' : 'User created'),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
          Navigator.pop(context, true);
        }
      } else {
        final result = jsonDecode(res.body);
        _showError(result['error'] ?? 'Something went wrong');
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError('Error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Text(_isEdit ? 'Edit User' : 'Add User',
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      body: Responsive.constrainedContent(
          context,
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              children: [
                // ── Account details ──────────────────────────────────────
                _SectionLabel(
                    icon: Icons.person_outline, label: 'Account Details'),
                const SizedBox(height: 12),
                _Card(
                    child: Column(children: [
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        _deco(label: 'Full name', icon: Icons.badge_outlined),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Full name is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _userCtrl,
                    autocorrect: false,
                    // Lock username in edit mode — changing it could break sessions
                    readOnly: _isEdit,
                    decoration: _deco(
                      label: 'Username',
                      icon: Icons.alternate_email_rounded,
                    ).copyWith(
                      helperText: _isEdit
                          ? 'Username cannot be changed after creation'
                          : 'Used to log in to the app',
                      filled: true,
                      fillColor: _isEdit
                          ? const Color(0xFFF0F0F0)
                          : const Color(0xFFF7FAF5),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Username is required';
                      if (v.contains(' ')) return 'No spaces allowed';
                      if (v.length < 3) return 'At least 3 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    decoration: _deco(
                      label: _isEdit
                          ? 'New password (leave blank to keep)'
                          : 'Password',
                      icon: Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (!_isEdit && (v == null || v.isEmpty)) {
                        return 'Password is required';
                      }
                      if (v != null && v.isNotEmpty && v.length < 6) {
                        return 'Minimum 6 characters';
                      }
                      return null;
                    },
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account active',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              Text('Inactive users cannot log in',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ]),
                      ),
                      Switch.adaptive(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeColor: idaGreen,
                      ),
                    ]),
                  ],
                ])),

                // ── Module access ────────────────────────────────────────
                const SizedBox(height: 24),
                _SectionLabel(
                    icon: Icons.apps_outlined, label: 'Module Access'),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12, left: 2),
                  child: Text(
                    'Select the modules this user can see and use.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
                _Card(
                    child: Column(children: [
                  // Select all / none quick actions
                  Row(children: [
                    Text(
                        '${_perms.length} of ${kModuleDefinitions.length} selected',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey)),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: idaGreen,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () => setState(() => _perms = {
                            for (final m in kModuleDefinitions)
                              m['key']!: 'view',
                          }),
                      child: const Text('Select all (view)',
                          style: TextStyle(fontSize: 13)),
                    ),
                    const Text(' · ', style: TextStyle(color: Colors.grey)),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () => setState(() => _perms.clear()),
                      child: const Text('None', style: TextStyle(fontSize: 13)),
                    ),
                  ]),
                  const Divider(height: 20),

                  // Module rows — 3-way: no access / view / edit.
                  ...kModuleDefinitions.map((mod) {
                    final level = _perms[mod['key']]; // null | 'view' | 'edit'
                    return _ModuleRow(
                      mod: mod,
                      level: level,
                      onChanged: (newLevel) => setState(() {
                        if (newLevel == null) {
                          _perms.remove(mod['key']!);
                        } else {
                          _perms[mod['key']!] = newLevel;
                        }
                      }),
                    );
                  }),
                ])),

                const SizedBox(height: 28),

                // ── Save ─────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: idaGreen,
                      disabledBackgroundColor: idaGreen.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(
                            _isEdit ? 'Save Changes' : 'Create User',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          )),
    );
  }

  InputDecoration _deco({required String label, required IconData icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE8D8))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE8D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B7A28), width: 1.8)),
        filled: true,
        fillColor: const Color(0xFFF7FAF5),
      );
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF3B7A28)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B7A28),
                letterSpacing: 0.2)),
      ]);
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: child,
      );
}

// Module icon lookup (avoids Icon import issues with string keys)
IconData _moduleIcon(String key) {
  switch (key) {
    case 'electricity':
      return Icons.electric_bolt_outlined;
    case 'tractor':
      return Icons.agriculture_outlined;
    case 'labour':
      return Icons.people_outline;
    case 'factory':
      return Icons.factory_outlined;
    case 'daily_report':
      return Icons.assignment_outlined;
    case 'reports_analytics':
      return Icons.bar_chart_outlined;
    case 'payroll':
      return Icons.payments_outlined;
    case 'farm_attendance':
      return Icons.groups_outlined;
    case 'transport':
      return Icons.local_shipping_outlined;
    case 'passwords':
      return Icons.vpn_key_outlined;
    default:
      return Icons.extension_outlined;
  }
}

class _ModuleRow extends StatelessWidget {
  final Map<String, String> mod;
  final String? level; // null | 'view' | 'edit'
  final ValueChanged<String?> onChanged;
  const _ModuleRow(
      {required this.mod, required this.level, required this.onChanged});

  static const idaGreen = Color(0xFF3B7A28);

  @override
  Widget build(BuildContext context) {
    final enabled = level != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: enabled ? idaGreen.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _moduleIcon(mod['key']!),
              size: 18,
              color: enabled ? idaGreen : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(mod['label']!,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: enabled ? Colors.black87 : Colors.grey)),
                Text(mod['description']!,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ])),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 50),
          child: Wrap(spacing: 6, children: [
            _levelChip(context, 'No access', null),
            _levelChip(context, 'View', 'view'),
            _levelChip(context, 'Add / Edit', 'edit'),
          ]),
        ),
      ]),
    );
  }

  Widget _levelChip(BuildContext context, String label, String? value) {
    final selected = level == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: value == 'edit' ? idaGreen : idaGreen.withOpacity(0.35),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
      onSelected: (_) => onChanged(value),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
