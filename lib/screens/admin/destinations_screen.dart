// lib/screens/admin/destinations_screen.dart
//
// Admin-managed master list of destinations — used as the dropdown when
// creating an outward register dispatch entry. Simple add/rename/
// activate-deactivate, same shape as parties_screen.dart.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/responsive.dart';
import '../../localization/app_localizations.dart';
import '../../services/api_client.dart';
import 'admin_common.dart' show AChip, MasterLifecycle, MasterStatusToggle, isRowActive, usedCountOf;

class DestinationsScreen extends StatefulWidget {
  const DestinationsScreen({super.key});
  @override
  State<DestinationsScreen> createState() => _DestinationsScreenState();
}

class _DestinationsScreenState extends State<DestinationsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  List destinations = [];
  bool loading = true;
  // Active / Inactive switch above the list (default Active)
  bool showInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await Api.get('/destinations?all=1');
      if (res.statusCode == 200 && mounted)
        setState(() => destinations = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _addDestination(String name) async {
    try {
      final res = await Api.post(
        '/destinations',
        body: {'name': name},
      );
      if (res.statusCode == 200) {
        _load();
      } else {
        _showSnack(Api.responseError(res), isError: true);
      }
    } catch (e) {
      _showSnack('Error: ${Api.errorText(e)}', isError: true);
    }
  }

  Future<void> _toggleActive(Map destination) async {
    try {
      await Api.patch(
        '/destinations/${destination['id']}',
        body: {'is_active': !isRowActive(destination)},
      );
      _load();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  Future<void> _rename(Map row, String name) async {
    try {
      final res = await Api.patch('/destinations/${row['id']}', body: {'name': name});
      if (res.statusCode == 200) {
        _load();
      } else {
        _showSnack(Api.responseError(res), isError: true);
      }
    } catch (e) {
      _showSnack('Error: ${Api.errorText(e)}', isError: true);
    }
  }

  void _showEditDialog(Map row) {
    final loc = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: '${row['name'] ?? ''}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.miEditDestination,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: 'Destination name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            MasterLifecycle(
              path: '/destinations/${row['id']}',
              module: 'destinations',
              itemName: '${row['name'] ?? ''}',
              isActive: isRowActive(row),
              usedCount: usedCountOf(row),
              onDone: (msg) {
                Navigator.pop(ctx);
                _showSnack(msg);
                _load();
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.cancel, style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              if (name != '${row['name'] ?? ''}') _rename(row, name);
            },
            child: Text(loc.save, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : idaGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Destination',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Destination name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _addDestination(ctrl.text.trim());
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final shown = destinations.where((r) => isRowActive(r) != showInactive).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Manage Destinations',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: MasterStatusToggle(
              showInactive: showInactive,
              activeCount: destinations.where(isRowActive).length,
              inactiveCount: destinations.where((r) => !isRowActive(r)).length,
              onChanged: (v) => setState(() => showInactive = v),
            ),
          ),
        ),
        Expanded(
            child: Responsive.constrainedContent(
          context,
          loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : shown.isEmpty
                  ? Center(
                      child: Text(
                          destinations.isEmpty
                              ? 'No destinations yet — tap + to add one'
                              : (showInactive ? loc.miNoneInactive : loc.miNoneActive),
                          style: const TextStyle(color: Colors.black54)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = shown[i];
                        final active = isRowActive(p);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE0E7D8)),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => _showEditDialog(p),
                            title: Text(p['name'] ?? '',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        active ? Colors.black87 : Colors.grey,
                                    decoration: active
                                        ? null
                                        : TextDecoration.lineThrough)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (!active) AChip(loc.miInactive),
                              const SizedBox(width: 6),
                              Switch(
                                value: active,
                                activeColor: idaGreen,
                                onChanged: (_) => _toggleActive(p),
                              ),
                            ]),
                          ),
                        );
                      },
                    )),
        ),
      ]),
    );
  }
}
