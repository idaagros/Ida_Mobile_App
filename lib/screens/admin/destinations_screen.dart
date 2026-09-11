// lib/screens/admin/destinations_screen.dart
//
// Admin-managed master list of destinations — used as the dropdown when
// creating an outward register dispatch entry. Simple add/rename/
// activate-deactivate, same shape as parties_screen.dart.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/responsive.dart';
import '../../services/api_service.dart';

class DestinationsScreen extends StatefulWidget {
  const DestinationsScreen({super.key});
  @override
  State<DestinationsScreen> createState() => _DestinationsScreenState();
}

class _DestinationsScreenState extends State<DestinationsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List destinations = [];
  bool loading = true;
  bool canAdd = false;
  bool canUpdate = false;

  @override
  void initState() {
    super.initState();
    ApiService.canAdd('destinations').then((v) {
      if (mounted) setState(() => canAdd = v);
    });
    ApiService.canUpdate('destinations').then((v) {
      if (mounted) setState(() => canUpdate = v);
    });
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res =
          await http.get(Uri.parse('$baseUrl/destinations?all=1'), headers: h);
      if (res.statusCode == 200)
        setState(() => destinations = jsonDecode(res.body));
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _addDestination(String name) async {
    try {
      final h = await _headers;
      final res = await http.post(
        Uri.parse('$baseUrl/destinations'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode == 200) {
        _load();
      } else {
        final data = jsonDecode(res.body);
        _showSnack(data['error'] ?? 'Failed to add destination', isError: true);
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _toggleActive(Map destination) async {
    try {
      final h = await _headers;
      await http.patch(
        Uri.parse('$baseUrl/destinations/${destination['id']}'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode(
            {'is_active': destination['is_active'] == 1 ? false : true}),
      );
      _load();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Manage Destinations',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              backgroundColor: idaGreen,
              onPressed: _showAddDialog,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Responsive.constrainedContent(
          context,
          loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : destinations.isEmpty
                  ? const Center(
                      child: Text('No destinations yet — tap + to add one',
                          style: TextStyle(color: Colors.black54)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: destinations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = destinations[i];
                        final active = p['is_active'] == 1;
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
                            title: Text(p['name'] ?? '',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        active ? Colors.black87 : Colors.grey,
                                    decoration: active
                                        ? null
                                        : TextDecoration.lineThrough)),
                            trailing: Switch(
                              value: active,
                              activeColor: idaGreen,
                              onChanged:
                                  canUpdate ? (_) => _toggleActive(p) : null,
                            ),
                          ),
                        );
                      },
                    )),
    );
  }
}
