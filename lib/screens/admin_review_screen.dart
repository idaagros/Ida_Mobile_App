// lib/screens/admin_review_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

class AdminReviewScreen extends StatefulWidget {
  // Optional initial status filter — 'pending', 'approved', or 'returned'.
  // Lets the dashboard stat cards deep-link straight into a filtered view.
  final String? initialFilter;
  // Optional initial module tab (0=Electricity, 1=Tractor, 2=Labour,
  // 3=Factory, 4=Machine, 5=Machine PF) - lets the Needs Attention
  // inbox land directly on the right module instead of always opening
  // on Electricity regardless of which item was tapped.
  final int? initialTabIndex;
  const AdminReviewScreen(
      {super.key, this.initialFilter, this.initialTabIndex});
  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen>
    with SingleTickerProviderStateMixin {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  late TabController _tabs;

  List _electricity = [];
  List _tractor = [];
  List _factory = [];
  List _machine = [];
  List _machinePf = [];

  // Per-module counts for the tab badges: {module: {status: {month, lifetime}}}
  Map<String, Map<String, Map<String, int>>> _counts = {};

  bool _loading = true;
  // Default to pending — admin only needs to act on pending records
  late String _filter;

  // Optional date range. When null, the list defaults to the 20 most
  // recent entries for the current filter. When set, it replaces that
  // default view entirely with the full matching range.
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? 'pending';
    _tabs = TabController(
        length: 5, vsync: this, initialIndex: widget.initialTabIndex ?? 0);
    _tabs.addListener(() => setState(() {}));
    _fetchAll();
    _fetchCounts();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    final p = await SharedPreferences.getInstance();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${p.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final h = await _headers;
      // 'all' (used by the dashboard's "Submissions this month" card)
      // fetches every status, filtered to the current month client-side.
      // Otherwise a single status: pending / approved / returned.
      final status = _filter == 'all' ? '' : _filter;

      final fromStr = _fromDate == null
          ? null
          : '${_fromDate!.year.toString().padLeft(4, '0')}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}';
      final toStr = _toDate == null
          ? null
          : '${_toDate!.year.toString().padLeft(4, '0')}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}';

      Future<List> fetchModule(String module,
          {String dateKey = 'reading_date',
          bool supportsStatusFilter = true}) async {
        try {
          final params = <String, String>{};
          // Labour uses a different status model entirely (active/on_leave/
          // resigned/terminated, not pending/approved/returned) — the
          // pending/approved/returned filter chips simply don't apply to
          // it, so always show all labour records regardless of filter.
          if (supportsStatusFilter && status.isNotEmpty)
            params['status'] = status;
          if (fromStr != null) params['from'] = fromStr;
          if (toStr != null) params['to'] = toStr;
          final uri = Uri.parse('$baseUrl/$module')
              .replace(queryParameters: params.isEmpty ? null : params);
          final res = await http.get(uri, headers: h);
          final merged = _parse(res.body);

          if (_filter == 'all' && fromStr == null && toStr == null) {
            // "Submissions this month" — no explicit date range was
            // chosen, so restrict the 'all'-status fetch to the current
            // month client-side.
            final now = DateTime.now();
            return merged.where((r) {
              final raw = r[dateKey];
              if (raw == null) return false;
              final d = DateTime.tryParse(raw.toString());
              return d != null && d.year == now.year && d.month == now.month;
            }).toList();
          }
          return merged;
        } catch (_) {
          return [];
        }
      }

      // Always fetch ALL roles (admin sees everyone) filtered by status
      final results = await Future.wait([
        fetchModule('electricity'),
        fetchModule('tractor'),
        fetchModule('factory', dateKey: 'entry_date'),
        fetchModule('machine'),
        fetchModule('machine-pf'),
      ]);
      setState(() {
        _electricity = results[0];
        _tractor = results[1];
        _factory = results[2];
        _machine = results[3];
        _machinePf = results[4];
      });
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // Fetches pending/approved/returned counts (this month + lifetime) for
  // each module that supports the approval workflow, to show as badges on
  // each tab. Labour doesn't use this status model, so it's skipped.
  Future<void> _fetchCounts() async {
    try {
      final h = await _headers;
      final modules = [
        'electricity',
        'tractor',
        'factory',
        'machine',
        'machine-pf'
      ];
      final results = await Future.wait(modules.map((m) async {
        try {
          final res =
              await http.get(Uri.parse('$baseUrl/$m/counts'), headers: h);
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            return data.map((status, v) => MapEntry(status, {
                  'month': (v['month'] as num?)?.toInt() ?? 0,
                  'lifetime': (v['lifetime'] as num?)?.toInt() ?? 0,
                }));
          }
        } catch (_) {}
        return <String, Map<String, int>>{};
      }));

      if (mounted) {
        setState(() {
          _counts = {
            for (var i = 0; i < modules.length; i++) modules[i]: results[i],
          };
        });
      }
    } catch (e) {
      debugPrint('Counts fetch error: $e');
    }
  }

  List _parse(String body) {
    try {
      if (body.contains('<!DOCTYPE') || body.contains('<html')) return [];
      final d = jsonDecode(body);
      if (d is List) return d;
      if (d is Map && d['data'] is List) return d['data'];
    } catch (_) {}
    return [];
  }

  Future<void> _updateStatus(String module, dynamic id, String status,
      {String? note}) async {
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/$module/$id/status'),
        headers: h,
        body: jsonEncode({
          'status': status,
          if (note != null && note.isNotEmpty) 'admin_note': note,
        }),
      );

      if (res.statusCode == 200) {
        // Remove record from current list immediately (optimistic UI)
        setState(() {
          switch (module) {
            case 'electricity':
              _electricity.removeWhere((r) => r['id'] == id);
              break;
            case 'tractor':
              _tractor.removeWhere((r) => r['id'] == id);
              break;
            case 'factory':
              _factory.removeWhere((r) => r['id'] == id);
              break;
            case 'machine':
              _machine.removeWhere((r) => r['id'] == id);
              break;
            case 'machine-pf':
              _machinePf.removeWhere((r) => r['id'] == id);
              break;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_statusMsg(status)),
            backgroundColor: _statusColor(status),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
        _fetchCounts();
      } else {
        final data = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error'] ?? 'Update failed'),
            backgroundColor: Colors.red.shade700,
          ));
        }
      }
    } catch (e) {
      debugPrint('Update error: $e');
    }
  }

  String _statusMsg(String s) {
    switch (s) {
      case 'approved':
        return '✅ Record approved and saved';
      case 'returned':
        return '↩ Record returned to user for correction';
      default:
        return 'Status updated';
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
        return idaGreen;
      case 'returned':
        return const Color(0xFFF57C00);
      default:
        return Colors.grey;
    }
  }

  void _showReturnDialog(String module, dynamic id) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Return for Correction',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Add a note explaining what needs to be corrected. '
            'The user will see this message.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Reading value seems incorrect, please recheck…',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: idaGreen, width: 1.8),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _updateStatus(module, id, 'returned', note: ctrl.text.trim());
            },
            child: const Text('Return to User'),
          ),
        ],
      ),
    );
  }

  void _showDetail(Map record, String module) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Text(_moduleTitle(module),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              _StatusBadge(record['status'] ?? 'pending'),
            ]),
            const SizedBox(height: 4),
            Text(
              'By ${record['user_name'] ?? record['submitted_by'] ?? 'Unknown'}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const Divider(height: 24),
            ...record.entries
                .where((e) => ![
                      'id',
                      'user_id',
                      'status',
                      'photo_url',
                      'pf_photo_url',
                      'admin_note'
                    ].contains(e.key))
                .map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                width: 140,
                                child: Text(_fieldLabel(e.key),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500))),
                            Expanded(
                                child: Text('${e.value ?? '—'}',
                                    style: const TextStyle(fontSize: 13))),
                          ]),
                    )),
            if (record['admin_note'] != null &&
                record['admin_note'].toString().isNotEmpty) ...[
              const Divider(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: amber.withOpacity(0.4)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(record['admin_note'],
                              style: const TextStyle(fontSize: 13))),
                    ]),
              ),
            ],
            const SizedBox(height: 24),
            if ((record['status'] ?? 'pending') == 'pending') ...[
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Return'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: amber,
                    side: BorderSide(color: amber),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showReturnDialog(module, record['id']);
                  },
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: idaGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _updateStatus(module, record['id'], 'approved');
                  },
                )),
              ]),
            ] else if ((record['status'] ?? '') == 'approved' &&
                ['tractor', 'electricity', 'machine', 'machine-pf']
                    .contains(module)) ...[
              // Approved meter readings are locked for field users, but
              // admin retains the right to fix mistakes after approval.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit (Admin)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A73E8),
                    side: const BorderSide(color: Color(0xFF1A73E8)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _showAdminEditDialog(module, record);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Admin-only: lets an admin correct the meter reading of an already
  // APPROVED record. Field users cannot reach this — approved data is
  // locked for them, but admins retain the right to fix mistakes.
  void _showAdminEditDialog(String module, Map record) {
    final isPf = module == 'machine-pf';
    final fieldKey = isPf ? 'pf_value' : 'meter_reading';
    final fieldLabel = isPf ? 'PF value' : 'Meter reading';
    final readingCtrl =
        TextEditingController(text: record[fieldKey]?.toString() ?? '');
    final notesCtrl =
        TextEditingController(text: record['notes']?.toString() ?? '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit approved record',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'This record is approved. Saving will recalculate the '
                    'difference and keep it approved.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
              ]),
            ),
            TextField(
              controller: readingCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: fieldLabel,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final ok = await _submitAdminEdit(
                        module: module,
                        id: record['id'],
                        meterReading: readingCtrl.text.trim(),
                        notes: notesCtrl.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Record updated'
                              : 'Failed to update record'),
                          backgroundColor: ok ? idaGreen : Colors.red.shade700,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          margin: const EdgeInsets.all(16),
                        ));
                      }
                      if (ok) {
                        _fetchAll();
                        _fetchCounts();
                      }
                    },
              child: saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _submitAdminEdit({
    required String module,
    required dynamic id,
    required String meterReading,
    required String notes,
  }) async {
    try {
      final h = await _headers;
      final fieldKey = module == 'machine-pf' ? 'pf_value' : 'meter_reading';
      final res = await http.put(
        Uri.parse('$baseUrl/$module/$id/admin-edit'),
        headers: h,
        body: jsonEncode({
          fieldKey: meterReading,
          'notes': notes,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('admin-edit error: $e');
      return false;
    }
  }

  String _moduleTitle(String m) {
    switch (m) {
      case 'electricity':
        return 'Electricity Reading';
      case 'tractor':
        return 'Tractor Hours';
      case 'labour':
        return 'Labour Record';
      case 'factory':
        return 'Factory Run Hours';
      case 'machine':
        return 'Machine Hours';
      case 'machine-pf':
        return 'Machine PF Reading';
      default:
        return m;
    }
  }

  String _fieldLabel(String key) =>
      key.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  // Count badge for a module's tab: uses the lifetime count for the
  // CURRENT filter status (pending/approved/returned), falling back to
  // the live list length if counts haven't loaded yet.
  int _badgeCount(String module) {
    final c = _counts[module]?[_filter == 'all' ? 'pending' : _filter];
    if (c != null) return c['lifetime'] ?? 0;
    switch (module) {
      case 'electricity':
        return _electricity.length;
      case 'tractor':
        return _tractor.length;
      case 'factory':
        return _factory.length;
      case 'machine':
        return _machine.length;
      case 'machine-pf':
        return _machinePf.length;
      default:
        return 0;
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: idaGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _fetchAll();
    }
  }

  String _filterLabel(String s) {
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'returned':
        return 'Returned';
      default:
        return s;
    }
  }

  // Small pill showing a status's count this month and lifetime, e.g.
  // "Pending · 3 this month · 12 lifetime". Tapping it switches the
  // filter chip to that status.
  Widget _countBadge({
    required String label,
    required int month,
    required int lifetime,
    required Color color,
    required bool active,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() => _filter = label.toLowerCase() == 'returned'
            ? 'returned'
            : label.toLowerCase());
        _fetchAll();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : const Color(0xFFF4F7F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color : const Color(0xFFE0E7D8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text('$month mo · $lifetime total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 9.5, color: Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }

  List get _currentList {
    switch (_tabs.index) {
      case 0:
        return _electricity;
      case 1:
        return _tractor;
      case 2:
        return _factory;
      case 3:
        return _machine;
      case 4:
        return _machinePf;
      default:
        return [];
    }
  }

  String get _currentModule {
    switch (_tabs.index) {
      case 0:
        return 'electricity';
      case 1:
        return 'tractor';
      case 2:
        return 'factory';
      case 3:
        return 'machine';
      case 4:
        return 'machine-pf';
      default:
        return 'electricity';
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _currentList;
    final module = _currentModule;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
            child: Tooltip(
              message: 'Review Submissions',
              child: Text('Review Submissions',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: amber, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _fetchAll),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Stack(
            children: [
              TabBar(
                controller: _tabs,
                isScrollable: true,
                indicatorColor: amber,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: 'Electricity\n(${_badgeCount('electricity')})'),
                  Tab(text: 'Tractor\n(${_badgeCount('tractor')})'),
                  Tab(text: 'Factory\n(${_badgeCount('factory')})'),
                  Tab(text: 'Machine\n(${_badgeCount('machine')})'),
                  Tab(text: 'Machine PF\n(${_badgeCount('machine-pf')})'),
                ],
              ),
              // Fade indicator on the right edge - the tab bar scrolls
              // (isScrollable: true above), but with no visual cue for
              // that, the extra tabs weren't discoverable at all. This
              // is decorative only (IgnorePointer), so it never blocks
              // taps or the tab bar's own scroll gesture underneath it.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          idaDark.withOpacity(0),
                          idaDark.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(children: [
        // Filter chips — only the 3 statuses admin actually acts on.
        // 'rejected' was removed from the workflow entirely.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in [
                {'v': 'pending', 'l': 'Pending'},
                {'v': 'approved', 'l': 'Approved'},
                {'v': 'returned', 'l': 'Returned to user'},
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f['l']!),
                    selected: _filter == f['v'],
                    onSelected: (_) {
                      setState(() => _filter = f['v']!);
                      _fetchAll();
                    },
                    selectedColor: idaGreen,
                    backgroundColor: const Color(0xFFE8F5E2),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _filter == f['v']
                          ? Colors.white
                          : const Color(0xFF3B6D11),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const Divider(height: 1),

        // Date range — defaults to the 20 most recent entries for the
        // current filter. Picking a range replaces that view entirely
        // with the full matching range.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE0E7D8)),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range, size: 16, color: idaGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fromDate == null
                            ? 'Showing 20 most recent — tap to pick a date range'
                            : '${_fmtDate(_fromDate!)}  →  ${_fmtDate(_toDate!)}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF374151)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (_fromDate != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: 'Clear date range',
                onPressed: () {
                  setState(() {
                    _fromDate = null;
                    _toDate = null;
                  });
                  _fetchAll();
                },
              ),
            ],
          ]),
        ),
        const Divider(height: 1),

        // Count summary for the active module — pending/approved/returned,
        // each showing this month's count and the lifetime total.
        if (module != 'labour')
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(children: [
              for (final s in ['pending', 'approved', 'returned'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _countBadge(
                      label: _filterLabel(s),
                      month: _counts[module]?[s]?['month'] ?? 0,
                      lifetime: _counts[module]?[s]?['lifetime'] ?? 0,
                      color: s == 'pending'
                          ? amber
                          : s == 'approved'
                              ? idaGreen
                              : const Color(0xFFF57C00),
                      active: _filter == s,
                    ),
                  ),
                ),
            ]),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : list.isEmpty
                  ? _EmptyState(filter: _filter)
                  : RefreshIndicator(
                      color: idaGreen,
                      onRefresh: _fetchAll,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _recordGrid(
                            context,
                            list
                                .map((r) => _RecordCard(
                                      record: r,
                                      module: module,
                                      onTap: () =>
                                          _showDetail(Map.from(r), module),
                                      onApprove: () => _updateStatus(
                                          module, r['id'], 'approved'),
                                      onReturn: () =>
                                          _showReturnDialog(module, r['id']),
                                    ))
                                .toList()),
                      ),
                    ),
        ),
      ]),
    );
  }

  // Same reasoning as the grids built for Dashboard, Farm Attendance,
  // and Work Allocation: one column on mobile (unchanged), reflowing
  // to 2-3 columns on wider screens. Unlike those, _RecordCard has no
  // margin of its own - its spacing came entirely from the ListView's
  // separatorBuilder, which this replaces - so runSpacing here
  // actually needs to provide the gap, not stay at 0.
  Widget _recordGrid(BuildContext context, List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final columns = Responsive.gridColumns(context);
    if (columns == 1) {
      return Column(
        children: cards.expand((c) => [c, const SizedBox(height: 10)]).toList()
          ..removeLast(),
      );
    }
    const spacing = 12.0;
    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children:
            cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
      );
    });
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final Map record;
  final String module;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReturn;

  const _RecordCard({
    required this.record,
    required this.module,
    required this.onTap,
    required this.onApprove,
    required this.onReturn,
  });

  static const idaGreen = Color(0xFF3B7A28);
  static const amber = Color(0xFFF5A623);

  String get _title {
    switch (module) {
      case 'electricity':
        return 'Reading: ${record['meter_reading'] ?? '—'} kWh';
      case 'tractor':
        return 'Meter: ${record['meter_reading'] ?? '—'} hrs';
      case 'machine':
        return 'Meter: ${record['meter_reading'] ?? '—'} hrs';
      case 'machine-pf':
        return 'PF: ${record['pf_value'] ?? '—'}';
      case 'labour':
        return record['name'] ?? 'Labour Record';
      case 'factory':
        return 'Run: ${record['entry_date'] ?? record['date'] ?? '—'}';
      default:
        return 'Record #${record['id']}';
    }
  }

  String get _subtitle {
    final by = record['submitted_by'] ?? record['user_name'] ?? '';
    final date = record['reading_date'] ??
        record['entry_date'] ??
        record['date'] ??
        record['created_at'] ??
        '';
    final parts = <String>[];
    if (by.isNotEmpty) parts.add('By $by');
    if (date.isNotEmpty)
      parts.add(date.toString().length > 10
          ? date.toString().substring(0, 10)
          : date.toString());
    return parts.join(' · ');
  }

  String get _status => record['status'] ?? 'pending';
  bool get _isPending => _status == 'pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(_title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600))),
              _StatusBadge(_status),
            ]),
            if (_subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            if (record['admin_note'] != null &&
                record['admin_note'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 14, color: amber),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(record['admin_note'],
                          style: TextStyle(
                              fontSize: 12, color: amber.withOpacity(0.9)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ],
            if (_isPending) ...[
              const SizedBox(height: 12),
              Row(children: [
                _ActionBtn(
                    label: 'Return',
                    color: amber,
                    icon: Icons.undo_rounded,
                    onTap: onReturn),
                const SizedBox(width: 8),
                _ActionBtn(
                    label: 'Approve',
                    color: idaGreen,
                    icon: Icons.check_rounded,
                    onTap: onApprove,
                    filled: true),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _ActionBtn(
      {required this.label,
      required this.color,
      required this.icon,
      required this.onTap,
      this.filled = false});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: filled ? color : color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: filled ? null : Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 14, color: filled ? Colors.white : color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: filled ? Colors.white : color)),
            ]),
          ),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  Color get _bg {
    switch (status) {
      case 'approved':
        return const Color(0xFFE8F5E2);
      case 'rejected':
        return Colors.red.shade50;
      case 'returned':
        return const Color(0xFFFEF3DC);
      default:
        return const Color(0xFFEEF2FF);
    }
  }

  Color get _fg {
    switch (status) {
      case 'approved':
        return const Color(0xFF3B7A28);
      case 'rejected':
        return Colors.red.shade700;
      case 'returned':
        return const Color(0xFFF5A623);
      default:
        return const Color(0xFF4B5EAA);
    }
  }

  String get _label {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'returned':
        return 'Returned';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration:
            BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
        child: Text(_label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _fg)),
      );
}

class _EmptyState extends StatelessWidget {
  final String filter;
  const _EmptyState({required this.filter});

  String get _label {
    switch (filter) {
      case 'all':
        return 'records this month';
      default:
        return '$filter records';
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('No $_label',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54)),
            const SizedBox(height: 6),
            Text('All caught up!',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ]),
        ),
      );
}
