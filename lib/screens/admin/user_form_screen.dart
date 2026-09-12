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
  bool _isAdmin = false;
  bool _obscurePass = true;
  bool _saving = false;
  // module key -> set of granted levels ('view'/'add'/'update'/'delete').
  // Absent or empty set = no access. A module can hold multiple levels
  // at once (e.g. {'view','add'} = can see and create, but not edit
  // or delete existing records) - confirmed directly as the target
  // granularity everywhere, not just a single view-or-edit choice.
  Map<String, Set<String>> _perms = {};
  // "module::scope" -> granted (e.g. "outward_register::bhada"). Only
  // 'update' is meaningful for a section grant (see kSectionedModules),
  // so a presence-only Set is enough - no need for a level per entry.
  Set<String> _sectionPerms = {};

  bool get _isEdit => widget.existingUser != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final u = widget.existingUser!;
      _nameCtrl.text = u.displayName;
      _userCtrl.text = u.username;
      _isActive = u.isActive;
      _isAdmin = u.isAdmin;
      // Group by module, since a user can now hold multiple
      // {module, level} entries for the same module (one per granted
      // level) - a plain map keyed by module would silently drop all
      // but the last one.
      _perms = {};
      _sectionPerms = {};
      for (final p in u.permissions) {
        if (p.scope != null) {
          // Scoped entries are tracked separately - they don't count
          // toward the whole-module toggles above, which only reflect
          // unscoped ("applies everywhere") grants.
          _sectionPerms.add('${p.module}::${p.scope}');
          continue;
        }
        // Backward compatibility with the old combined 'edit' level:
        // expand it into all three mutation levels, matching exactly
        // what the backend's _hasLevel already does - someone with
        // old-format 'edit' access keeps seeing add+update+delete
        // checked, not silently losing two of the three.
        final levels =
            p.level == 'edit' ? ['add', 'update', 'delete'] : [p.level];
        _perms.putIfAbsent(p.module, () => {}).addAll(levels);
      }
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
        'is_admin': _isAdmin,
        'permissions': [
          ..._perms.entries.expand(
              (e) => e.value.map((level) => {'module': e.key, 'level': level})),
          ..._sectionPerms.map((key) {
            final parts = key.split('::');
            return {'module': parts[0], 'scope': parts[1], 'level': 'update'};
          }),
        ],
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
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Admin',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            Text(
                                'Full access to everything, including managing other users. Module access below is ignored for admins.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ]),
                    ),
                    Switch.adaptive(
                      value: _isAdmin,
                      onChanged: (v) => setState(() => _isAdmin = v),
                      activeColor: Colors.red.shade700,
                    ),
                  ]),
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
                              m['key']!: {'view'},
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

                  // Module rows — 4 independent toggles: view / add /
                  // update / delete. Each can be on or off separately.
                  // Modules with sections (see kSectionedModules) also
                  // get an expandable per-section grant list.
                  ...kModuleDefinitions.map((mod) {
                    final levels = _perms[mod['key']] ?? {};
                    final sections = kSectionedModules[mod['key']];
                    return _ModuleRow(
                      mod: mod,
                      levels: levels,
                      onToggle: (level, isOn) => setState(() {
                        final current =
                            Set<String>.from(_perms[mod['key']] ?? {});
                        if (isOn) {
                          current.add(level);
                        } else {
                          current.remove(level);
                        }
                        if (current.isEmpty) {
                          _perms.remove(mod['key']!);
                        } else {
                          _perms[mod['key']!] = current;
                        }
                      }),
                      sections: sections,
                      sectionGranted: (sectionKey) =>
                          _sectionPerms.contains('${mod['key']}::$sectionKey'),
                      onToggleSection: (sectionKey, isOn) => setState(() {
                        final key = '${mod['key']}::$sectionKey';
                        if (isOn) {
                          _sectionPerms.add(key);
                        } else {
                          _sectionPerms.remove(key);
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
  final Set<String>
      levels; // subset of {'view','add','update','delete','approve'}
  final void Function(String level, bool isOn) onToggle;
  // Present only for modules with sections (kSectionedModules) - null
  // for every other module, which renders no section list at all.
  final List<Map<String, String>>? sections;
  final bool Function(String sectionKey)? sectionGranted;
  final void Function(String sectionKey, bool isOn)? onToggleSection;
  const _ModuleRow({
    required this.mod,
    required this.levels,
    required this.onToggle,
    this.sections,
    this.sectionGranted,
    this.onToggleSection,
  });

  static const idaGreen = Color(0xFF3B7A28);

  @override
  Widget build(BuildContext context) {
    final enabled = levels.isNotEmpty;
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
          child: Builder(builder: (context) {
            // Not every module supports every level (e.g. electricity
            // has no delete route at all) - only show chips for levels
            // this module's backend actually has wired up, so granting
            // one never looks like it did something when it can't.
            final supported = moduleSupportedLevels(mod['key']!);
            return Wrap(spacing: 6, children: [
              if (supported.contains('view'))
                _levelToggle(context, 'View', 'view'),
              if (supported.contains('add'))
                _levelToggle(context, 'Add', 'add'),
              if (supported.contains('update'))
                _levelToggle(context, 'Update', 'update'),
              if (supported.contains('delete'))
                _levelToggle(context, 'Delete', 'delete'),
              if (supported.contains('approve'))
                _levelToggle(context, 'Approve', 'approve'),
            ]);
          }),
        ),
        if (sections != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Or grant update access to specific sections only, instead of the whole module:',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sections!.map((s) {
                        final granted = sectionGranted!(s['key']!);
                        return FilterChip(
                          label: Text(s['label']!,
                              style: const TextStyle(fontSize: 11.5)),
                          selected: granted,
                          selectedColor: idaGreen,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                              color: granted ? Colors.white : Colors.black87),
                          onSelected: (isOn) =>
                              onToggleSection!(s['key']!, isOn),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _levelToggle(BuildContext context, String label, String value) {
    final selected = levels.contains(value);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: value == 'delete'
          ? Colors.red.shade400
          : value == 'approve'
              ? Colors.blue.shade600
              : idaGreen,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
      onSelected: (isOn) => onToggle(value, isOn),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
