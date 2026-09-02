// lib/screens/admin/users_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/user_model.dart';
import '../../services/api_service.dart';
import 'user_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  List<AppUser> _users = [];
  List<AppUser> _filtered = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final token = await ApiService.getToken();
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/admin/users'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          _users = data.map((u) => AppUser.fromJson(u)).toList();
          _applyFilter();
        });
      } else {
        _showError('Failed to load users (${res.statusCode})');
      }
    } catch (e) {
      _showError('Network error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(AppUser user) async {
    try {
      final token = await ApiService.getToken();
      final res = await http.patch(
        Uri.parse('${ApiService.baseUrl}/api/admin/users/${user.id}/toggle'),
        headers: {
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      if (res.statusCode == 200) {
        _fetchUsers();
        _showSuccess(user.isActive
            ? '${user.displayName} deactivated'
            : '${user.displayName} activated');
      } else {
        _showError('Could not update account status');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _search.isEmpty
          ? List.from(_users)
          : _users
              .where((u) =>
                  u.username.toLowerCase().contains(_search.toLowerCase()) ||
                  u.displayName.toLowerCase().contains(_search.toLowerCase()))
              .toList();
    });
  }

  void _openForm({AppUser? user}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UserFormScreen(existingUser: user)),
    );
    if (saved == true) _fetchUsers();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: idaGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _confirmToggle(AppUser user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text(user.isActive ? 'Deactivate account?' : 'Activate account?'),
        content: Text(user.isActive
            ? '${user.displayName} will not be able to log in until reactivated.'
            : 'Restore login access for ${user.displayName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  user.isActive ? Colors.red.shade600 : const Color(0xFF3B7A28),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _toggleActive(user);
            },
            child: Text(user.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _users.where((u) => u.isActive).length;
    final inactiveCount = _users.where((u) => !u.isActive).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('User Management',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchUsers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: idaGreen,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Add User',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        // Stats strip
        Container(
          color: idaDark,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            _Stat(label: 'Total', count: _users.length, color: Colors.white24),
            const SizedBox(width: 8),
            _Stat(
                label: 'Active',
                count: activeCount,
                color: idaGreen.withOpacity(0.7)),
            const SizedBox(width: 8),
            _Stat(
                label: 'Inactive',
                count: inactiveCount,
                color: Colors.red.shade800.withOpacity(0.5)),
          ]),
        ),

        // Search bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            onChanged: (v) {
              _search = v;
              _applyFilter();
            },
            decoration: InputDecoration(
              hintText: 'Search by username or name…',
              hintStyle: const TextStyle(fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFF4F7F2),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const Divider(height: 1),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : _filtered.isEmpty
                  ? _EmptyState(onAdd: () => _openForm())
                  : RefreshIndicator(
                      color: idaGreen,
                      onRefresh: _fetchUsers,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _UserCard(
                          user: _filtered[i],
                          onEdit: () => _openForm(user: _filtered[i]),
                          onToggle: () => _confirmToggle(_filtered[i]),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Stat({required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  const _UserCard(
      {required this.user, required this.onEdit, required this.onToggle});

  static const idaGreen = Color(0xFF3B7A28);

  @override
  Widget build(BuildContext context) {
    final initials = user.displayName.trim().isNotEmpty
        ? user.displayName
            .trim()
            .split(' ')
            .map((w) => w[0])
            .take(2)
            .join()
            .toUpperCase()
        : user.username.substring(0, 1).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: user.isActive ? Colors.transparent : Colors.red.shade100),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: idaGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: Text(initials,
                    style: const TextStyle(
                        color: idaGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(user.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      if (!user.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Inactive',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.red.shade700)),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.alternate_email_rounded,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(user.username,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ]),
                  ]),
            ),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.edit_outlined,
                    size: 20, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  user.isActive
                      ? Icons.person_off_outlined
                      : Icons.person_outlined,
                  size: 20,
                  color: user.isActive ? Colors.red.shade400 : idaGreen,
                ),
              ),
            ),
          ]),

          // Module chips
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (user.permissions.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...user.permissions.take(4).map((entry) {
                  final mod = kModuleDefinitions.firstWhere(
                      (m) => m['key'] == entry.module,
                      orElse: () => {'label': entry.module});
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: entry.level == 'edit'
                            ? const Color(0xFFE8F5E2)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        entry.level == 'edit'
                            ? '${mod['label']} ✎'
                            : mod['label']!,
                        style: TextStyle(
                            fontSize: 11,
                            color: entry.level == 'edit'
                                ? const Color(0xFF3B6D11)
                                : Colors.grey.shade700)),
                  );
                }),
                if (user.permissions.length > 4)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF4F7F2),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('+${user.permissions.length - 4} more',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            )
          else
            const Text('No modules assigned',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No users yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text('Create staff accounts and assign module access.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B7A28),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add first user'),
            ),
          ]),
        ),
      );
}
